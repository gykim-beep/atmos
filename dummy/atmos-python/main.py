"""
Atmos Mixer Pro — 방탈출 전용 멀티채널 오디오 믹서
Phase 2: 유선 LAN OSC 수신 · 독점적 룸 배타 제어 시퀀스

하네스 규칙: pathlib · 허용 종속성만 · config.json 단일 진실 · 스레드 분리 · main.py 단독 실행
"""

import json
import os
import platform
import sys
import threading
import time
import uuid
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from pathlib import Path
from tkinter import filedialog

import customtkinter as ctk
import numpy as np
import sounddevice as sd
import soundfile as sf
from pythonosc import dispatcher as osc_dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer

# ═══════════════════════════════════════════════════════════════════════════════
# 경로 상수
# ═══════════════════════════════════════════════════════════════════════════════
BASE_DIR = Path(__file__).parent.resolve()
CONFIG_PATH = BASE_DIR / "config.json"

DEFAULT_SR = 48_000
DEFAULT_BLOCK_SIZE = 512
FADE_SECS = 0.3
DUCK_GAIN = 0.30
UNDUCK_FADE_SECS = 0.3


def _ts() -> str:
    return datetime.now().strftime("%H:%M:%S")


# ═══════════════════════════════════════════════════════════════════════════════
# 설정 읽기/쓰기 (단일 진실 공급원)
# ═══════════════════════════════════════════════════════════════════════════════
def load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH, encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "audio_device": {},
        "osc": {"host": "0.0.0.0", "port": 8000},
        "timeline": {"active_room_id": 1, "unlocked_through": 1},
        "rooms": [],
    }


def save_config(cfg: dict) -> None:
    save_config_to_path(cfg, CONFIG_PATH)


def load_config_from_path(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("JSON 루트가 객체(dict)가 아닙니다.")
    return normalize_preset_config(data)


def save_config_to_path(cfg: dict, path: Path) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)


ATMOS_SCHEMA_VERSION = "1.17"


def resolve_audio_path(file_str: str, asset_base: Path | None = None) -> Path:
    """저장된 경로를 Mac/Windows에서 재해석 (절대·상대·프리셋 기준)"""
    if not file_str:
        return Path()
    raw = Path(file_str)
    bases = [asset_base, BASE_DIR, Path.home()]
    candidates: list[Path] = []
    if raw.is_absolute():
        candidates.append(raw)
    for base in bases:
        if base is None:
            continue
        candidates.append(base / raw)
        if raw.name:
            candidates.append(base / raw.name)
    seen: set[str] = set()
    for candidate in candidates:
        key = str(candidate)
        if key in seen:
            continue
        seen.add(key)
        try:
            resolved = candidate.expanduser().resolve()
            if resolved.exists():
                return resolved
        except OSError:
            continue
    return raw.expanduser()


def normalize_preset_config(cfg: dict) -> dict:
    """불러오기 전 JSON 구조 정규화 — 룸 순서·필수 키 보장"""
    cfg = dict(cfg)
    cfg.setdefault("atmos_schema", ATMOS_SCHEMA_VERSION)
    cfg.setdefault("timeline", {"active_room_id": 1, "unlocked_through": 1})
    cfg.setdefault("osc", {"host": "0.0.0.0", "port": 8000})
    cfg.setdefault("audio_device", {})
    ad = cfg["audio_device"]
    if "output_port_labels" in ad and isinstance(ad["output_port_labels"], list):
        ad["output_port_labels"] = [str(x) for x in ad["output_port_labels"]]
    tl = cfg["timeline"]
    if "active_room_id" not in tl:
        tl["active_room_id"] = int(tl.get("unlocked_through", 1))
    tl["unlocked_through"] = int(tl.get("active_room_id", tl.get("unlocked_through", 1)))
    rooms = list(cfg.get("rooms") or [])
    rooms.sort(
        key=lambda r: (
            int(r.get("order_index", r.get("id", 0))),
            int(r.get("id", 0)),
        )
    )
    for idx, room in enumerate(rooms):
        room.setdefault("order_index", idx)
        room.setdefault("id", idx + 1)
        room.setdefault("name", f"🚪 룸 {room['id']}")
        room.setdefault("master_volume", 1.0)
        room.setdefault("osc_clear", "")
        tracks = list(room.get("tracks") or [])
        for t_idx, track in enumerate(tracks):
            track.setdefault("order_index", t_idx)
            track.setdefault("volume", 0.75)
            track.setdefault("volume_percent", int(float(track["volume"]) * 100))
            track.setdefault("loop", bool(track.get("is_bgm", False)))
            track.setdefault("is_bgm", track["loop"])
            track.setdefault("output_ch", 0)
            track.setdefault("osc_play", track.get("osc_address", ""))
            track.setdefault("osc_stop", "")
            track.setdefault("custom_name", Path(track.get("file", "트랙")).stem)
        room["tracks"] = tracks
    cfg["rooms"] = rooms
    cfg["room_count"] = len(rooms)
    return cfg


# ═══════════════════════════════════════════════════════════════════════════════
# 프로 오디오 장치 스캔 (ASIO / Core Audio 전용)
# ═══════════════════════════════════════════════════════════════════════════════
_VIRTUAL_NAME_KEYWORDS = (
    "loopback",
    "loop back",
    "stereo mix",
    "virtual",
    "vb-audio",
    "vb audio",
    "cable input",
    "cable output",
    "what u hear",
    "monitor of",
    "microsoft sound mapper",
    "primary sound",
    "secondary sound",
    "wave mapper",
)

_BLOCKED_HOSTAPI_KEYWORDS = (
    "mme",
    "wdm-ks",
    "wdm ks",
    "directsound",
    "wasapi",
)


def _platform_requires_hostapi() -> str | None:
    """허용할 Host API 식별 키워드 (소문자). None이면 프로 필터만 적용."""
    if sys.platform == "win32":
        return "asio"
    if sys.platform == "darwin":
        return "core audio"
    return None


def _is_virtual_device_name(name: str) -> bool:
    lower = name.lower()
    return any(k in lower for k in _VIRTUAL_NAME_KEYWORDS)


def _hostapi_allowed(hostapi_idx: int, hostapis: list) -> bool:
    api_name = hostapis[hostapi_idx]["name"]
    lower = api_name.lower()
    required = _platform_requires_hostapi()
    if required:
        if required not in lower:
            return False
    else:
        if any(bad in lower for bad in _BLOCKED_HOSTAPI_KEYWORDS):
            return False
    return True


def scan_pro_audio_devices(hotplug_reset: bool = False) -> dict[str, int]:
    """
    Windows: ASIO Host API 장치만
    macOS: Core Audio Host API 장치만
    가상 루프백·MME/WDM 등은 제외
    반환: {표시 라벨: PortAudio 장치 인덱스}
    """
    if hotplug_reset and hasattr(sd, "_terminate") and hasattr(sd, "_initialize"):
        sd._terminate()
        sd._initialize()

    hostapis = sd.query_hostapis()
    required = _platform_requires_hostapi()
    result: dict[str, int] = {}

    for idx, dev in enumerate(sd.query_devices()):
        max_out = int(dev.get("max_output_channels", 0))
        if max_out <= 0:
            continue

        hostapi_idx = int(dev["hostapi"])
        if not _hostapi_allowed(hostapi_idx, hostapis):
            continue

        dev_name = str(dev["name"])
        if _is_virtual_device_name(dev_name):
            continue

        api_name = hostapis[hostapi_idx]["name"]
        sr = int(dev.get("default_samplerate", DEFAULT_SR))
        lbl = f"{api_name}: {dev_name} [출력 {max_out}ch / {sr}Hz]"
        result[lbl] = idx

    return result


def get_device_output_channels(device_idx: int) -> int:
    info = sd.query_devices(device_idx)
    return max(int(info.get("max_output_channels", 0)), 1)


OSC_MATCH_SLOP_NS = 100_000  # 0.1ms — 주소 대조·디스패치 허용 상한 (나노초)


def normalize_osc_address(address: str) -> str:
    """OSC 주소 정규화 — 공백 제거·대소문자·슬래시 경로 그대로 유지 (정확 일치)"""
    return str(address or "").strip()


def osc_addresses_equal(a: str, b: str) -> bool:
    return normalize_osc_address(a) == normalize_osc_address(b)


class OSCActionKind(Enum):
    ROOM_CLEAR = "room_clear"
    TRACK_PLAY = "track_play"
    TRACK_STOP = "track_stop"


@dataclass(frozen=True)
class OSCBinding:
    kind: OSCActionKind
    room_id: int
    track_id: str | None = None


class OSCAddressRegistry:
    """환경설정 OSC 주소 → (룸·트랙) 액션 — O(1) 정확 일치 대조"""

    def __init__(self):
        self._by_address: dict[str, OSCBinding] = {}

    def clear(self):
        self._by_address.clear()

    def register(self, address: str, binding: OSCBinding) -> bool:
        key = normalize_osc_address(address)
        if not key:
            return False
        self._by_address[key] = binding
        return True

    def lookup(self, address: str) -> OSCBinding | None:
        return self._by_address.get(normalize_osc_address(address))

    def match_latency_ns(self, address: str) -> tuple[OSCBinding | None, int]:
        """수신 주소 대조 소요 시간 (나노초) — 0.1ms 이내 목표"""
        t0 = time.perf_counter_ns()
        hit = self.lookup(address)
        elapsed = time.perf_counter_ns() - t0
        return hit, elapsed


class ExclusiveRoomGate:
    """독점 활성 룸 — 테마 시작·룸 클리어 시퀀스 단일 진실"""

    def __init__(self, room_ids: list[int] | None = None):
        ids = sorted({int(r) for r in (room_ids or []) if int(r) > 0})
        self._room_ids = ids
        self._active_room_id = ids[0] if ids else 0

    @property
    def active_room_id(self) -> int:
        return self._active_room_id

    @property
    def room_ids(self) -> list[int]:
        return list(self._room_ids)

    def set_room_ids(self, room_ids: list[int]):
        self._room_ids = sorted({int(r) for r in room_ids if int(r) > 0})
        if self._active_room_id not in self._room_ids and self._room_ids:
            self._active_room_id = self._room_ids[0]

    def set_active_room(self, room_id: int):
        self._active_room_id = max(0, int(room_id))

    def theme_start(self) -> int:
        """전체 정지 후 1번 룸만 독점 활성"""
        if 1 in self._room_ids:
            self._active_room_id = 1
        elif self._room_ids:
            self._active_room_id = self._room_ids[0]
        else:
            self._active_room_id = 0
        return self._active_room_id

    def on_room_clear(self, room_id: int) -> tuple[bool, int]:
        """활성 룸 클리어만 허용 → 다음 룸 독점 (없으면 0=전체 차단)"""
        if room_id != self._active_room_id:
            return False, self._active_room_id
        next_id = room_id + 1
        if next_id in self._room_ids:
            self._active_room_id = next_id
        else:
            self._active_room_id = 0
        return True, self._active_room_id

    def allows_room_osc(self, room_id: int) -> bool:
        return room_id == self._active_room_id and self._active_room_id > 0


def build_osc_registry_from_rooms(rooms: list) -> OSCAddressRegistry:
    """RoomPanel·설정 dict 양쪽에서 레지스트리 구축"""
    reg = OSCAddressRegistry()
    for room in rooms:
        if hasattr(room, "room_id"):
            rid = int(room.room_id)
            clear_addr = str(getattr(room, "osc_clear", "") or "")
            cards = list(getattr(room, "_cards", []) or [])
        else:
            rid = int(room.get("id", 0))
            clear_addr = str(room.get("osc_clear", "") or "")
            cards = []
            for t in room.get("tracks") or []:
                cards.append(t)
        if clear_addr.strip():
            reg.register(
                clear_addr,
                OSCBinding(OSCActionKind.ROOM_CLEAR, rid),
            )
        for item in cards:
            if hasattr(item, "osc_play"):
                play_a = str(item.osc_play or "")
                stop_a = str(item.osc_stop or "")
                tid = str(item.track_id)
            else:
                play_a = str(item.get("osc_play", item.get("osc_address", "")) or "")
                stop_a = str(item.get("osc_stop", "") or "")
                tid = str(item.get("track_id", ""))
            if play_a.strip():
                reg.register(
                    play_a,
                    OSCBinding(OSCActionKind.TRACK_PLAY, rid, tid or None),
                )
            if stop_a.strip():
                reg.register(
                    stop_a,
                    OSCBinding(OSCActionKind.TRACK_STOP, rid, tid or None),
                )
    return reg


def parse_track_room_id(track_id: str) -> int:
    """트랙 ID에서 룸 번호 추출 (예: r2_t1_abc → 2)"""
    if track_id.startswith("r") and "_" in track_id:
        try:
            return int(track_id[1 : track_id.index("_")])
        except ValueError:
            pass
    return 1


# ═══════════════════════════════════════════════════════════════════════════════
# 메인 스크롤 — 마우스 휠·맥 트랙패드(Tk9 TouchpadScroll) 전역 연동
# ═══════════════════════════════════════════════════════════════════════════════
TOUCHPAD_ACC_THRESHOLD = 2


def _is_mac() -> bool:
    return platform.system() == "Darwin"


def _is_widget_descendant(widget, ancestor) -> bool:
    w = widget
    while w is not None:
        if w == ancestor:
            return True
        try:
            w = w.master
        except Exception:
            break
    return False


def _parse_touchpad_pixels(tk_root, event) -> tuple[int, int]:
    """Tk 9 TouchpadScroll — Δx, Δy 픽셀 분해 (TIP 684)"""
    try:
        packed = int(getattr(event, "delta", 0) or 0)
        if packed == 0:
            return (0, 0)
        result = tk_root.call("tk::PreciseScrollDeltas", packed)
        return (int(result[0]), int(result[1]))
    except Exception:
        return (0, 0)


def _parse_wheel_deltas(event) -> tuple[int, int]:
    """물리 마우스 휠 → (수직 units, 수평 units)"""
    raw = int(getattr(event, "delta", 0) or 0)
    if raw != 0:
        if _is_mac():
            units = -raw
        else:
            units = int(-1 * (raw / 40))
            if units == 0:
                units = -1 if raw > 0 else 1
        state = int(getattr(event, "state", 0) or 0)
        if state & 0x0001:
            return (0, units)
        return (units, 0)
    num = getattr(event, "num", 0)
    if num == 4:
        return (-3, 0)
    if num == 5:
        return (3, 0)
    return (0, 0)


class AtmosScrollableFrame(ctk.CTkScrollableFrame):
    """
    CTkScrollableFrame 확장:
    - 가로 프레임에서 xview_scroll 정상 동작 (CTk 기본 버그 보정)
    - Tk 9 맥 트랙패드 TouchpadScroll 픽셀 누적 스크롤
    """

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._tp_acc_x = 0.0
        self._tp_acc_y = 0.0

    def _pull_touchpad_acc(self, attr: str) -> int:
        acc = getattr(self, attr)
        units = 0
        while abs(acc) >= TOUCHPAD_ACC_THRESHOLD:
            if acc > 0:
                units += 1
                acc -= TOUCHPAD_ACC_THRESHOLD
            else:
                units -= 1
                acc += TOUCHPAD_ACC_THRESHOLD
        setattr(self, attr, acc)
        return units

    def apply_touchpad(self, dx: int, dy: int) -> bool:
        """트랙패드 픽셀 delta → 스크롤 적용"""
        if dx == 0 and dy == 0:
            return False
        canvas = self._parent_canvas
        self._tp_acc_x -= dx
        self._tp_acc_y -= dy
        scrolled = False
        if self._orientation == "horizontal":
            step = self._pull_touchpad_acc("_tp_acc_x")
            if step == 0:
                step = self._pull_touchpad_acc("_tp_acc_y")
            if step and canvas.xview() != (0.0, 1.0):
                canvas.xview_scroll(step, "units")
                scrolled = True
        else:
            step = self._pull_touchpad_acc("_tp_acc_y")
            if step == 0 and abs(dx) > abs(dy):
                step = self._pull_touchpad_acc("_tp_acc_x")
            if step and canvas.yview() != (0.0, 1.0):
                canvas.yview_scroll(step, "units")
                scrolled = True
        return scrolled

    def apply_mouse_wheel(self, vert: int, horiz: int) -> bool:
        """물리 마우스 휠 → 방향에 맞게 스크롤"""
        canvas = self._parent_canvas
        if self._orientation == "horizontal":
            step = horiz if horiz else vert
            if step and canvas.xview() != (0.0, 1.0):
                canvas.xview_scroll(step, "units")
                return True
        else:
            step = vert if vert else horiz
            if step and canvas.yview() != (0.0, 1.0):
                canvas.yview_scroll(step, "units")
                return True
        return False

    def _mouse_wheel_all(self, event):
        """CTk 기본 bind_all 중복 방지 — 전역/위젯 핸들러가 처리"""
        return


def bind_mousewheel_to_scroll(scroll_frame: AtmosScrollableFrame, root_widget) -> None:
    """Windows/Linux 물리 마우스 휠 — 위젯 트리 재귀 바인딩"""
    if _is_mac():
        return
    try:
        orientation = scroll_frame.cget("orientation")
    except Exception:
        orientation = "vertical"
    is_horizontal = orientation == "horizontal"

    def _on_mousewheel(event):
        vert, horiz = _parse_wheel_deltas(event)
        scroll_frame.apply_mouse_wheel(vert, horiz)

    def _bind_widget(widget):
        try:
            widget.bind("<MouseWheel>", _on_mousewheel, add="+")
            widget.bind("<Shift-MouseWheel>", _on_mousewheel, add="+")
            widget.bind("<Button-4>", _on_mousewheel, add="+")
            widget.bind("<Button-5>", _on_mousewheel, add="+")
        except Exception:
            pass

    def _bind_tree(widget):
        _bind_widget(widget)
        for child in widget.winfo_children():
            _bind_tree(child)

    _bind_tree(scroll_frame)
    if root_widget is not scroll_frame:
        _bind_tree(root_widget)
    for attr in ("_parent_canvas", "_scrollbar"):
        try:
            _bind_widget(getattr(scroll_frame, attr))
        except Exception:
            pass


# ═══════════════════════════════════════════════════════════════════════════════
# 오디오 엔진
# ═══════════════════════════════════════════════════════════════════════════════
class TrackState:
    def __init__(
        self,
        track_id: str,
        audio_data: np.ndarray,
        sample_rate: int,
        output_ch: int,
        volume: float,
        loop: bool,
        is_bgm: bool,
        on_finish=None,
    ):
        self.id = track_id
        self.audio_data = audio_data
        self.sample_rate = sample_rate
        self.output_ch = output_ch
        self.volume = volume
        self.room_volume = 1.0
        self.loop = loop
        self.is_bgm = is_bgm
        self.on_finish = on_finish
        self.active = False
        self.position = 0
        self.duck_gain = 1.0
        self._duck_target = 1.0
        self._duck_start_gain = 1.0
        self._duck_fade_total = 0
        self._duck_fade_left = 0
        self.play_fade_gain = 0.0
        self.play_fade_target = 0.0
        self.play_fade_start = 0.0
        self.play_fade_total = 0
        self.play_fade_left = 0


class AudioEngine:
    def __init__(self, log_cb):
        self._log = log_cb
        self._lock = threading.RLock()
        self._tracks: dict[str, TrackState] = {}
        self._stream: sd.OutputStream | None = None
        self._device_idx: int | None = None
        self._num_ch = 2
        self._sample_rate = DEFAULT_SR
        self._sfx_active = 0
        self._muted = False
        self._active_room_id = 1
        self._output_port_labels: list[str] = ["Output 1"]

    def set_active_room(self, room_id: int):
        """독점 활성 룸 ID — 오직 이 룸만 오디오 출력 허용"""
        with self._lock:
            self._active_room_id = max(0, room_id)

    def get_active_room(self) -> int:
        with self._lock:
            return self._active_room_id

    def set_unlocked_through(self, room_limit: int):
        """하위 호환 — active_room_id와 동기화"""
        self.set_active_room(room_limit)

    def _is_track_audible(self, track_id: str) -> bool:
        rid = parse_track_room_id(track_id)
        with self._lock:
            return rid == self._active_room_id and self._active_room_id > 0

    def configure_device_params(self, device_idx: int) -> tuple[int, int]:
        """장치 파라미터만 갱신 (스트림 재시작 없음 — UI 스레드 안전)"""
        info = sd.query_devices(device_idx)
        max_out = int(info["max_output_channels"])
        max_in = int(info["max_input_channels"])
        sr = int(info.get("default_samplerate", DEFAULT_SR))
        with self._lock:
            self._device_idx = device_idx
            self._num_ch = max(max_out, 1)
            self._sample_rate = sr
        return max_in, max_out

    def reinitialize_device(self, device_idx: int | None = None) -> tuple[int, int]:
        """
        스트림 종료 후 재시작 — 반드시 백그라운드 스레드에서 호출.
        UI 데드락 방지용.
        """
        with self._lock:
            idx = device_idx if device_idx is not None else self._device_idx
        if idx is None:
            return 0, self._num_ch
        max_in, max_out = self.configure_device_params(idx)
        self._restart_stream()
        return max_in, max_out

    def _restart_stream(self):
        self._stop_stream()
        if self._device_idx is None:
            return
        try:
            self._stream = sd.OutputStream(
                device=self._device_idx,
                samplerate=self._sample_rate,
                channels=self._num_ch,
                dtype="float32",
                blocksize=DEFAULT_BLOCK_SIZE,
                callback=self._callback,
            )
            self._stream.start()
            self._log(f"[엔진] 스트림 시작 — {self._num_ch}ch @ {self._sample_rate:,}Hz")
        except Exception as exc:
            self._log(f"[오류] 스트림 시작 실패: {exc}")

    def _stop_stream(self, force: bool = False):
        stream = self._stream
        self._stream = None
        if stream is None:
            return
        try:
            if force:
                stream.abort()
            else:
                stream.stop()
        except Exception:
            try:
                stream.abort()
            except Exception:
                pass
        try:
            stream.close()
        except Exception:
            pass

    def _callback(self, outdata: np.ndarray, frames: int, time_info, status):
        outdata.fill(0.0)
        if self._muted:
            return

        with self._lock:
            newly_finished_sfx: list[str] = []
            for tid, t in self._tracks.items():
                if not t.active or t.output_ch >= self._num_ch:
                    continue
                if not self._is_track_audible(tid):
                    continue

                # 더킹 복구 페이드 (0.3초 선형)
                if t._duck_fade_left > 0:
                    adv = min(frames, t._duck_fade_left)
                    t._duck_fade_left -= adv
                    progress = (
                        1.0 - (t._duck_fade_left / t._duck_fade_total)
                        if t._duck_fade_total > 0
                        else 1.0
                    )
                    t.duck_gain = t._duck_start_gain + (t._duck_target - t._duck_start_gain) * progress
                    if t._duck_fade_left <= 0:
                        t.duck_gain = t._duck_target

                # 재생 페이드 인/아웃 (0.3초 선형)
                if t.play_fade_left > 0:
                    adv = min(frames, t.play_fade_left)
                    t.play_fade_left -= adv
                    progress = (
                        1.0 - (t.play_fade_left / t.play_fade_total)
                        if t.play_fade_total > 0
                        else 1.0
                    )
                    t.play_fade_gain = t.play_fade_start + (t.play_fade_target - t.play_fade_start) * progress
                    if t.play_fade_left <= 0:
                        t.play_fade_gain = t.play_fade_target
                        if t.play_fade_target <= 0.0:
                            t.active = False
                            t.position = 0
                            if not t.is_bgm:
                                newly_finished_sfx.append(tid)
                            if t.on_finish:
                                t.on_finish()
                            continue

                data_len = len(t.audio_data)
                end = t.position + frames
                chunk = np.zeros(frames, dtype=np.float32)

                if end <= data_len:
                    chunk[:] = t.audio_data[t.position:end]
                    t.position = end
                    if end == data_len:
                        if t.loop:
                            t.position = 0
                        else:
                            t.active = False
                            t.position = 0
                            if not t.is_bgm:
                                newly_finished_sfx.append(tid)
                            if t.on_finish:
                                t.on_finish()
                else:
                    avail = data_len - t.position
                    if avail > 0:
                        chunk[:avail] = t.audio_data[t.position:]
                    if t.loop:
                        need = frames - avail
                        chunk[avail:] = t.audio_data[:need]
                        t.position = need
                    else:
                        t.active = False
                        t.position = 0
                        if not t.is_bgm:
                            newly_finished_sfx.append(tid)
                        if t.on_finish:
                            t.on_finish()

                # 효과음 재생 중 배경음 즉시 더킹 (0.3 가중치)
                duck = t.duck_gain
                if t.is_bgm and self._sfx_active > 0:
                    duck = DUCK_GAIN

                gain = t.volume * duck * t.room_volume * t.play_fade_gain
                outdata[:, t.output_ch] += chunk * gain

            if newly_finished_sfx:
                self._sfx_active = max(0, self._sfx_active - len(newly_finished_sfx))
                if self._sfx_active == 0:
                    self._start_unduck()

    def _apply_duck(self):
        """효과음 시작 시 배경음 즉시 더킹"""
        for t in self._tracks.values():
            if t.is_bgm and t.active:
                t.duck_gain = DUCK_GAIN
                t._duck_target = DUCK_GAIN
                t._duck_fade_left = 0

    def _start_unduck(self):
        fade_samples = int(self._sample_rate * UNDUCK_FADE_SECS)
        for t in self._tracks.values():
            if t.is_bgm and t.active and t.duck_gain < 1.0:
                t._duck_target = 1.0
                t._duck_fade_total = fade_samples
                t._duck_fade_left = fade_samples
                t._duck_start_gain = t.duck_gain
        self._log(f"[엔진] 배경음 복구 페이드인 시작 ({UNDUCK_FADE_SECS}초)")

    def add_track(self, state: TrackState):
        with self._lock:
            self._tracks[state.id] = state

    def play(self, track_id: str):
        with self._lock:
            t = self._tracks.get(track_id)
            if not t:
                return
            if not self._is_track_audible(track_id):
                return
            fade_samples = int(self._sample_rate * FADE_SECS)
            was_active = t.active
            t.active = True
            t.play_fade_target = 1.0
            t.play_fade_total = fade_samples
            t.play_fade_left = fade_samples
            if not was_active:
                t.position = 0
                t.play_fade_gain = 0.0
                t.play_fade_start = 0.0
                if not t.is_bgm and not t.loop:
                    self._sfx_active += 1
                    self._apply_duck()
            else:
                t.play_fade_start = t.play_fade_gain

    def stop(self, track_id: str):
        with self._lock:
            t = self._tracks.get(track_id)
            if not t or not t.active or t.play_fade_target == 0.0:
                return
            fade_samples = int(self._sample_rate * FADE_SECS)
            t.play_fade_target = 0.0
            t.play_fade_total = fade_samples
            t.play_fade_left = fade_samples
            t.play_fade_start = t.play_fade_gain
            was_sfx = not t.is_bgm and not t.loop
            if was_sfx:
                self._sfx_active = max(0, self._sfx_active - 1)
                if self._sfx_active == 0:
                    self._start_unduck()

    def panic(self):
        with self._lock:
            self._muted = True
            for t in self._tracks.values():
                t.active = False
                t.position = 0
                t.duck_gain = 1.0
                t._duck_target = 1.0
                t._duck_fade_left = 0
                t.play_fade_gain = 0.0
                t.play_fade_target = 0.0
                t.play_fade_left = 0
            self._sfx_active = 0

    def unmute(self):
        with self._lock:
            self._muted = False

    def remove_track(self, track_id: str):
        with self._lock:
            self._tracks.pop(track_id, None)

    def update_room_volume(self, room_id: int, r_vol: float):
        prefix = f"r{room_id}_"
        with self._lock:
            for tid, t in self._tracks.items():
                if tid.startswith(prefix):
                    t.room_volume = r_vol

    def reset(self):
        self._muted = False
        self.panic()
        self.unmute()

    def update_volume(self, tid: str, vol: float):
        with self._lock:
            t = self._tracks.get(tid)
            if t:
                t.volume = vol

    def update_loop(self, tid: str, loop: bool):
        with self._lock:
            t = self._tracks.get(tid)
            if t:
                t.loop = loop

    def update_output_ch(self, tid: str, ch: int):
        with self._lock:
            t = self._tracks.get(tid)
            if t:
                t.output_ch = ch

    def update_is_bgm(self, tid: str, is_bgm: bool):
        with self._lock:
            t = self._tracks.get(tid)
            if t:
                t.is_bgm = is_bgm

    def get_num_channels(self) -> int:
        return self._num_ch

    def set_output_port_labels(self, labels: list[str]):
        with self._lock:
            self._output_port_labels = list(labels) if labels else ["Output 1"]

    def get_output_port_labels(self) -> list[str]:
        with self._lock:
            return list(self._output_port_labels)

    def get_output_port_display_name(self, channel_index: int) -> str:
        with self._lock:
            labels = self._output_port_labels
            if not labels:
                return _fallback_output_port_name(channel_index)
            idx = max(0, min(channel_index, len(labels) - 1))
            return labels[idx]

    def shutdown(self):
        """종료 시 오디오 스트림 즉시 중단 및 자원 해제"""
        self._muted = True
        with self._lock:
            self._sfx_active = 0
            for t in self._tracks.values():
                t.active = False
                t.play_fade_gain = 0.0
                t.play_fade_target = 0.0
                t.play_fade_left = 0
        self._stop_stream(force=True)


# ═══════════════════════════════════════════════════════════════════════════════
# OSC 수신 스레드
# ═══════════════════════════════════════════════════════════════════════════════
class OSCReceiver:
    """아두이노 이더넷 쉴드 UDP OSC — 전용 데몬 스레드에서 수신"""

    def __init__(self, host: str, port: int, log_cb, trigger_cb):
        self._host = host
        self._port = port
        self._log = log_cb
        self._trigger = trigger_cb
        self._thread: threading.Thread | None = None
        self._server: BlockingOSCUDPServer | None = None
        self._running = False

    def start(self):
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True, name="OSC-LAN-수신")
        self._thread.start()

    def stop(self, wait: bool = True):
        self._running = False
        server = self._server
        self._server = None
        if server:
            try:
                server.shutdown()
            except Exception:
                pass
            try:
                server.server_close()
            except Exception:
                pass
        thread = self._thread
        if wait and thread and thread.is_alive() and threading.current_thread() is not thread:
            thread.join(timeout=0.15)
        self._thread = None

    def _run(self):
        disp = osc_dispatcher.Dispatcher()
        disp.set_default_handler(self._on_message)
        try:
            self._server = BlockingOSCUDPServer((self._host, self._port), disp)
            self._log(
                f"[OSC/LAN] 전용 수신 스레드 가동 — udp://{self._host}:{self._port}"
            )
            while self._running:
                self._server.handle_request(timeout=0.2)
        except Exception as exc:
            if self._running:
                self._log(f"[오류] OSC 서버 실패: {exc}")

    def _on_message(self, address, *args):
        recv_ns = time.perf_counter_ns()
        self._trigger(address, args, recv_ns)


# ═══════════════════════════════════════════════════════════════════════════════
# 트랙 카드
# ═══════════════════════════════════════════════════════════════════════════════
class TrackCard(ctk.CTkFrame):
    def __init__(
        self,
        parent,
        file_path: Path,
        track_id: str,
        engine: AudioEngine,
        num_channels: int,
        log_cb,
        save_cb,
        delete_cb,
        accent: str,
        locked: bool = False,
        track_cfg: dict | None = None,
        **kwargs,
    ):
        super().__init__(parent, **kwargs)
        self.file_path = Path(file_path)
        self.track_id = track_id
        self.engine = engine
        self.log_cb = log_cb
        self.save_cb = save_cb
        self.delete_cb = delete_cb
        self.accent = accent
        self._playing = False
        self._pending_delete = False
        self._locked = locked
        self._pending_cfg = dict(track_cfg) if track_cfg else None

        if track_cfg:
            vol = float(track_cfg.get("volume", 0.75))
            loop = bool(track_cfg.get("loop", track_cfg.get("is_bgm", False)))
            name = str(track_cfg.get("custom_name", self.file_path.stem))
            self.output_ch = int(track_cfg.get("output_ch", 0))
            self.osc_play = str(track_cfg.get("osc_play", track_cfg.get("osc_address", "")))
            self.osc_stop = str(track_cfg.get("osc_stop", ""))
        else:
            vol = 0.75
            loop = False
            name = self.file_path.stem
            self.output_ch = 0
            self.osc_play = ""
            self.osc_stop = ""

        self._name_var = ctk.StringVar(value=name)
        self._vol_var = ctk.DoubleVar(value=vol)
        self._loop_var = ctk.BooleanVar(value=loop)

        self._build_ui()
        self._apply_track_cfg_to_ui(self._pending_cfg)
        self._load_audio_async()
        if locked:
            self._apply_locked_style()

    def _build_ui(self):
        self.configure(fg_color="#161628", corner_radius=8)

        # 우측 상단 삭제 버튼 (고정 크기 빨간 X)
        self.delete_btn = ctk.CTkButton(
            self,
            text="X",
            width=24,
            height=24,
            font=ctk.CTkFont(size=13, weight="bold"),
            fg_color="#CC0000",
            hover_color="#990000",
            text_color="#FFFFFF",
            corner_radius=4,
            command=self._on_delete,
        )
        self.delete_btn.place(relx=1.0, x=-6, y=6, anchor="ne")

        top = ctk.CTkFrame(self, fg_color="transparent")
        top.pack(fill="x", padx=10, pady=(10, 4))

        self.play_btn = ctk.CTkButton(
            top,
            text="▶",
            width=34,
            height=28,
            font=ctk.CTkFont(size=13),
            fg_color="#1E6B22",
            hover_color="#0F3D12",
            corner_radius=6,
            command=self._toggle_play,
        )
        self.play_btn.pack(side="left", padx=(0, 6))

        self.name_entry = ctk.CTkEntry(
            top,
            textvariable=self._name_var,
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color="#C8C8E8",
            fg_color="#1A1A30",
            border_width=1,
            border_color="#333355",
            height=28,
        )
        self.name_entry.pack(side="left", fill="x", expand=True, padx=(0, 28))
        self.name_entry.bind("<FocusOut>", lambda e: self.save_cb())
        self.name_entry.bind("<Return>", lambda e: self.name_entry.focus_set())

        mid = ctk.CTkFrame(self, fg_color="transparent")
        mid.pack(fill="x", padx=10, pady=(2, 4))

        ctk.CTkLabel(
            mid,
            text="볼륨",
            font=ctk.CTkFont(size=10),
            text_color="#888888",
            width=32,
        ).pack(side="left", padx=(0, 4))

        self.vol_slider = ctk.CTkSlider(
            mid,
            from_=0,
            to=1,
            variable=self._vol_var,
            height=14,
            button_color=self.accent,
            progress_color=self.accent,
            command=self._on_vol,
        )
        self.vol_slider.pack(side="left", fill="x", expand=True, padx=(0, 4))

        self.vol_pct = ctk.CTkLabel(
            mid, text="75%", width=36, font=ctk.CTkFont(size=10), text_color="#AAAAAA"
        )
        self.vol_pct.pack(side="left")

        bot = ctk.CTkFrame(self, fg_color="transparent")
        bot.pack(fill="x", padx=10, pady=(2, 10))

        self.loop_sw = ctk.CTkSwitch(
            bot,
            text="🔄 무한 루프",
            variable=self._loop_var,
            font=ctk.CTkFont(size=11, weight="bold"),
            switch_width=36,
            switch_height=18,
            button_color=self.accent,
            progress_color=self.accent,
            command=self._on_loop,
        )
        self.loop_sw.pack(side="left")

        self.output_lbl = ctk.CTkLabel(
            bot,
            text="🔌 Output 1",
            font=ctk.CTkFont(size=10, weight="bold"),
            text_color="#6688AA",
        )
        self.output_lbl.pack(side="right", padx=(8, 0))

    def refresh_output_label(self):
        name = self.engine.get_output_port_display_name(self.output_ch)
        self.output_lbl.configure(text=f"🔌 {name}")

    def _apply_locked_style(self):
        self.configure(fg_color="#121218")
        for w in (self.play_btn, self.name_entry, self.vol_slider, self.loop_sw, self.delete_btn):
            try:
                w.configure(state="disabled")
            except Exception:
                pass

    def set_locked(self, locked: bool):
        self._locked = locked
        state = "disabled" if locked else "normal"
        for w in (self.play_btn, self.name_entry, self.vol_slider, self.loop_sw, self.delete_btn):
            try:
                w.configure(state=state)
            except Exception:
                pass
        self.configure(fg_color="#121218" if locked else "#161628")

    def set_output_channel(self, ch: int, num_ch: int | None = None):
        max_ch = num_ch if num_ch is not None else self.engine.get_num_channels()
        self.output_ch = max(0, min(ch, max(max_ch, 1) - 1))
        self.engine.update_output_ch(self.track_id, self.output_ch)
        self.refresh_output_label()

    def _apply_track_cfg_to_ui(self, cfg: dict | None):
        if not cfg:
            return
        if "custom_name" in cfg:
            self._name_var.set(str(cfg["custom_name"]))
        vol = float(cfg.get("volume", self._vol_var.get()))
        self._vol_var.set(vol)
        self.vol_slider.set(vol)
        self.vol_pct.configure(text=f"{int(vol * 100)}%")
        loop = bool(cfg.get("loop", cfg.get("is_bgm", False)))
        self._loop_var.set(loop)
        self.osc_play = str(cfg.get("osc_play", cfg.get("osc_address", self.osc_play)))
        self.osc_stop = str(cfg.get("osc_stop", self.osc_stop))
        self.set_output_channel(int(cfg.get("output_ch", self.output_ch)))
        self.refresh_output_label()

    def sync_to_engine(self) -> bool:
        """UI 값 → 오디오 엔진 (불러오기 후 재동기화용)"""
        with self.engine._lock:
            if self.track_id not in self.engine._tracks:
                return False
        vol = float(self._vol_var.get())
        loop = bool(self._loop_var.get())
        self.engine.update_volume(self.track_id, vol)
        self.engine.update_loop(self.track_id, loop)
        self.engine.update_is_bgm(self.track_id, loop)
        self.engine.update_output_ch(self.track_id, self.output_ch)
        return True

    def _safe_ui(self, fn):
        """종료 중·위젯 파괴 후 메인 루프 콜백 스케줄 방지"""
        try:
            if not self.winfo_exists():
                return
            self.after(0, fn)
        except Exception:
            pass

    def _load_audio_async(self):
        threading.Thread(target=self._load_audio_worker, daemon=True, name="오디오로드").start()

    def _load_audio_worker(self):
        try:
            if not self.file_path.exists():
                self._safe_ui(lambda: self.log_cb(f"[오류] 파일 없음: {self.file_path}"))
                return
            data, sr = sf.read(str(self.file_path), dtype="float32", always_2d=True)
            mono = data.mean(axis=1).astype(np.float32)
            vol = float(self._vol_var.get())
            loop = bool(self._loop_var.get())
            is_bgm = loop
            state = TrackState(
                self.track_id,
                mono,
                sr,
                self.output_ch,
                vol,
                loop,
                is_bgm,
                on_finish=self._on_track_finish,
            )
            self.engine.add_track(state)
            self._safe_ui(self.sync_to_engine)
            self._safe_ui(
                lambda: self.log_cb(f"[트랙 로드 완료] {self._name_var.get()}")
            )
        except Exception as exc:
            self._safe_ui(
                lambda: self.log_cb(f"[오류] 파일 로드 실패: {self.file_path.name} — {exc}")
            )

    def _on_delete(self):
        if self._locked:
            return
        self.delete_btn.configure(state="disabled")
        self._pending_delete = True
        if self._playing:
            self.engine.stop(self.track_id)
            self.log_cb(f"[{self._name_var.get()}] 삭제 중 (0.3초 페이드아웃)")
        else:
            self._finalize_delete()

    def _finalize_delete(self):
        self.engine.remove_track(self.track_id)
        self.log_cb(f"[{self._name_var.get()}] 트랙 삭제 완료")
        if self.delete_cb:
            self.delete_cb(self)
        self.destroy()

    def _on_track_finish(self):
        def _reset_ui():
            if self._pending_delete:
                self._finalize_delete()
                return
            self._playing = False
            self.play_btn.configure(text="▶", fg_color="#1E6B22", hover_color="#0F3D12")

        self._safe_ui(_reset_ui)

    def _toggle_play(self):
        if self._locked:
            return
        if self._playing:
            self.engine.stop(self.track_id)
            self.play_btn.configure(text="▶", fg_color="#1E6B22", hover_color="#0F3D12")
            self._playing = False
        else:
            self.engine.play(self.track_id)
            self.play_btn.configure(text="⏹", fg_color="#8B0000", hover_color="#5C0000")
            self._playing = True

    def _on_vol(self, val):
        self.vol_pct.configure(text=f"{int(float(val) * 100)}%")
        self.engine.update_volume(self.track_id, float(val))
        self.save_cb()

    def _on_loop(self):
        loop = self._loop_var.get()
        self.engine.update_loop(self.track_id, loop)
        self.engine.update_is_bgm(self.track_id, loop)
        self.save_cb()

    def force_stop_ui(self):
        self._playing = False
        self.play_btn.configure(text="▶", fg_color="#1E6B22", hover_color="#0F3D12")

    def start_bgm_playback(self):
        """시퀀스 자동 재생 — 엔진 직접 트리거 (원클릭 지연 제거)"""
        if self._locked or not self._loop_var.get():
            return False
        self.engine.play(self.track_id)
        self._playing = True
        self.play_btn.configure(text="⏹", fg_color="#8B0000", hover_color="#5C0000")
        return True

    def play_bgm(self):
        return self.start_bgm_playback()

    def stop_bgm(self):
        if self._playing:
            self._toggle_play()

    def get_bgm_cards(self):
        return [self] if self._loop_var.get() else []

    def get_config(self) -> dict:
        vol = round(float(self._vol_var.get()), 3)
        return {
            "track_id": self.track_id,
            "file": str(self.file_path.resolve()),
            "custom_name": self._name_var.get().strip(),
            "osc_play": self.osc_play.strip(),
            "osc_stop": self.osc_stop.strip(),
            "volume": vol,
            "volume_percent": int(vol * 100),
            "loop": bool(self._loop_var.get()),
            "is_bgm": bool(self._loop_var.get()),
            "output_ch": int(self.output_ch),
        }

    def restore_config(self, cfg: dict):
        self._apply_track_cfg_to_ui(cfg)
        self.sync_to_engine()


# ═══════════════════════════════════════════════════════════════════════════════
# 룸 패널
# ═══════════════════════════════════════════════════════════════════════════════
class RoomPanel(ctk.CTkFrame):
    def __init__(
        self,
        parent,
        room_id: int,
        room_name: str,
        engine: AudioEngine,
        log_cb,
        save_cb,
        clear_cb,
        delete_cb,
        accent: str,
        **kwargs,
    ):
        super().__init__(parent, **kwargs)
        self.room_id = room_id
        self.room_name = room_name
        self.engine = engine
        self.log_cb = log_cb
        self.save_cb = save_cb
        self.clear_cb = clear_cb
        self.delete_cb = delete_cb
        self.accent = accent
        self.osc_clear = ""
        self._cards: list[TrackCard] = []
        self._seq = 0
        self._locked = False
        self._master_vol_var = ctk.DoubleVar(value=1.0)
        self._build()

    def _build(self):
        self.configure(fg_color="#0E0E1C", corner_radius=10, width=350)
        self.pack_propagate(False)

        hdr = ctk.CTkFrame(self, fg_color="transparent")
        hdr.pack(fill="x", padx=8, pady=(10, 2))

        self.title_lbl = ctk.CTkLabel(
            hdr,
            text=self.room_name,
            font=ctk.CTkFont(size=15, weight="bold"),
            text_color=self.accent,
        )
        self.title_lbl.pack(side="left")

        self.delete_room_btn = ctk.CTkButton(
            hdr,
            text="❌",
            width=28,
            height=28,
            font=ctk.CTkFont(size=12),
            fg_color="#3A1520",
            hover_color="#5C0000",
            corner_radius=6,
            command=self._on_delete_room,
        )
        self.delete_room_btn.pack(side="right", padx=(4, 0))

        vol_frame = ctk.CTkFrame(hdr, fg_color="transparent")
        vol_frame.pack(side="right")
        ctk.CTkLabel(
            vol_frame,
            text="룸 마스터",
            font=ctk.CTkFont(size=10),
            text_color="#888888",
        ).pack(side="left", padx=(0, 4))
        self.master_slider = ctk.CTkSlider(
            vol_frame,
            from_=0,
            to=1,
            variable=self._master_vol_var,
            width=90,
            height=12,
            button_color=self.accent,
            progress_color=self.accent,
            command=self._on_master_vol,
        )
        self.master_slider.pack(side="left")

        ctk.CTkFrame(self, height=2, fg_color=self.accent, corner_radius=0).pack(
            fill="x", padx=8, pady=(0, 6)
        )

        btn_row = ctk.CTkFrame(self, fg_color="transparent")
        btn_row.pack(fill="x", padx=8, pady=(0, 6))

        self.add_btn = ctk.CTkButton(
            btn_row,
            text="➕ 오디오 파일 추가",
            font=ctk.CTkFont(size=11),
            height=32,
            fg_color=self.accent,
            hover_color="#2A2A4A",
            corner_radius=8,
            command=self._open_file_dialog,
        )
        self.add_btn.pack(side="left", fill="x", expand=True, padx=(0, 4))

        self.clear_btn = ctk.CTkButton(
            btn_row,
            text="룸 클리어",
            font=ctk.CTkFont(size=11, weight="bold"),
            width=90,
            height=32,
            fg_color="#5C4A00",
            hover_color="#7A6200",
            corner_radius=8,
            command=self._on_clear,
        )
        self.clear_btn.pack(side="right")

        self.lock_badge = ctk.CTkLabel(
            self,
            text="🔒 잠금 — 이전 룸을 클리어하세요",
            font=ctk.CTkFont(size=10),
            text_color="#666688",
            fg_color="#1A1A28",
            corner_radius=6,
            height=24,
        )

        self.scroll = AtmosScrollableFrame(self, fg_color="transparent", corner_radius=0)
        self.scroll.pack(fill="both", expand=True, padx=4, pady=4)

    def _on_master_vol(self, val):
        self.engine.update_room_volume(self.room_id, float(val))
        self.save_cb()

    def _open_file_dialog(self):
        paths = filedialog.askopenfilenames(
            title=f"{self.room_name} — 오디오 선택",
            filetypes=[("WAV", "*.wav"), ("모든 파일", "*.*")],
        )
        for p in paths:
            self._create_card(Path(p))

    def _on_clear(self):
        if self._locked:
            self.log_cb(f"[{self.room_name}] 잠금 상태 — 클리어 무시됨")
            return
        self.clear_cb(self)

    def _on_delete_room(self):
        if self.delete_cb:
            self.delete_cb(self)

    def _create_card(self, file_path: Path, track_cfg: dict | None = None) -> TrackCard:
        if track_cfg and track_cfg.get("track_id"):
            tid = str(track_cfg["track_id"])
            try:
                seq_part = tid.split("_")[1]
                if seq_part.startswith("t"):
                    self._seq = max(self._seq, int(seq_part[1:]))
            except (IndexError, ValueError):
                pass
        else:
            self._seq += 1
            tid = f"r{self.room_id}_t{self._seq}_{uuid.uuid4().hex[:6]}"
        card = TrackCard(
            self.scroll,
            file_path=file_path,
            track_id=tid,
            engine=self.engine,
            num_channels=self.engine.get_num_channels(),
            log_cb=self.log_cb,
            save_cb=self.save_cb,
            delete_cb=self._on_card_deleted,
            accent=self.accent,
            locked=self._locked,
            track_cfg=track_cfg,
        )
        card.pack(fill="x", padx=4, pady=3)
        self._cards.append(card)
        card.refresh_output_label()
        self.log_cb(f"[{self.room_name}] 트랙 추가: {card._name_var.get()}")
        self.save_cb()
        self.after(500, lambda: self.engine.update_room_volume(self.room_id, self._master_vol_var.get()))
        return card

    def _on_card_deleted(self, card: TrackCard):
        if card in self._cards:
            self._cards.remove(card)
        self.save_cb()

    def set_locked(self, locked: bool):
        self._locked = locked
        if locked:
            for c in self._cards:
                if c._playing:
                    c.engine.stop(c.track_id)
                    c.force_stop_ui()
            self.lock_badge.pack(fill="x", padx=8, pady=(0, 4))
            self.scroll.pack(fill="both", expand=True, padx=4, pady=4)
            self.configure(fg_color="#0A0A12")
            self.title_lbl.configure(text_color="#555566")
        else:
            self.lock_badge.pack_forget()
            self.scroll.pack(fill="both", expand=True, padx=4, pady=4)
            self.configure(fg_color="#0E0E1C")
            self.title_lbl.configure(text_color=self.accent)
        self.add_btn.configure(state="normal")
        self.clear_btn.configure(state="disabled" if locked else "normal")
        self.master_slider.configure(state="disabled" if locked else "normal")
        self.delete_room_btn.configure(state="normal")
        for c in self._cards:
            c.set_locked(locked)

    def update_channels(self, num_ch: int):
        for c in self._cards:
            c.set_output_channel(c.output_ch, num_ch)
            c.refresh_output_label()

    def force_stop_all(self):
        for c in self._cards:
            if c._playing:
                c.engine.stop(c.track_id)
            c.force_stop_ui()

    def get_bgm_cards(self) -> list[TrackCard]:
        result = []
        for c in self._cards:
            result.extend(c.get_bgm_cards())
        return result

    def get_config(self, order_index: int = 0) -> dict:
        m_vol = round(float(self._master_vol_var.get()), 3)
        return {
            "id": self.room_id,
            "order_index": order_index,
            "name": self.room_name,
            "master_volume": m_vol,
            "master_volume_percent": int(m_vol * 100),
            "osc_clear": self.osc_clear.strip(),
            "tracks": [c.get_config() for c in self._cards],
        }

    def load_from_config(self, room_data: dict, asset_base: Path | None = None):
        self.osc_clear = str(room_data.get("osc_clear", ""))
        m_vol = float(room_data.get("master_volume", 1.0))
        self._master_vol_var.set(m_vol)
        self.master_slider.set(m_vol)
        self.engine.update_room_volume(self.room_id, m_vol)
        base = asset_base or BASE_DIR
        tracks = sorted(
            room_data.get("tracks", []),
            key=lambda t: int(t.get("order_index", 0)),
        )
        for track_cfg in tracks:
            fp = resolve_audio_path(str(track_cfg.get("file", "")), base)
            if fp.exists():
                self._create_card(fp, track_cfg=track_cfg)
            else:
                self.log_cb(f"[경고] 파일 없음: {track_cfg.get('file')} (해석: {fp})")


# ═══════════════════════════════════════════════════════════════════════════════
# 환경설정 팝업 (탭 분리)
# ═══════════════════════════════════════════════════════════════════════════════
class SettingsDialog(ctk.CTkToplevel):
    def __init__(self, parent, app: "AtmosMixerApp"):
        super().__init__(parent)
        self.app = app
        self.title("⚙️ 환경설정")
        self.geometry("720x560")
        self.configure(fg_color="#0E0E1C")
        self.transient(parent)
        self.grab_set()

        ctk.CTkLabel(
            self,
            text="오디오 아웃풋 · 아두이노 신호 매핑",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color="#CCCCFF",
        ).pack(padx=16, pady=(14, 6), anchor="w")

        if app.engine._device_idx is not None:
            app.refresh_output_port_labels(app.engine._device_idx, log=False)
        self._num_ch = max(app.engine.get_num_channels(), 1)
        self._ch_labels = app.get_output_menu_labels()

        self.tabview = ctk.CTkTabview(self, fg_color="#08080F", segmented_button_fg_color="#1A1A30")
        self.tabview.pack(fill="both", expand=True, padx=16, pady=8)
        self.tab_out = self.tabview.add("오디오 아웃풋")
        self.tab_osc = self.tabview.add("아두이노 신호")

        self.scroll_out = AtmosScrollableFrame(self.tab_out, fg_color="transparent", corner_radius=0)
        self.scroll_out.pack(fill="both", expand=True, padx=4, pady=4)
        self.scroll_osc = AtmosScrollableFrame(self.tab_osc, fg_color="transparent", corner_radius=0)
        self.scroll_osc.pack(fill="both", expand=True, padx=4, pady=4)

        self._route_rows: list[tuple[TrackCard, ctk.StringVar]] = []
        self._osc_rows: list[tuple[TrackCard, ctk.StringVar, ctk.StringVar]] = []
        self._room_clear_rows: list[tuple[RoomPanel, ctk.StringVar]] = []
        self._render_all_tabs()

        osc_cfg = app._cfg.get("osc", {})
        bottom = ctk.CTkFrame(self, fg_color="transparent")
        bottom.pack(fill="x", padx=16, pady=(0, 4))
        ctk.CTkLabel(
            bottom,
            text=f"OSC 수신 포트  ·  물리 출력 {self._num_ch}ch (에이블톤 I/O 명칭)",
            font=ctk.CTkFont(size=10),
            text_color="#666688",
        ).pack(side="left")
        self._port_var = ctk.StringVar(value=str(osc_cfg.get("port", 8000)))
        ctk.CTkEntry(bottom, textvariable=self._port_var, width=72, height=28).pack(
            side="right", padx=(8, 0)
        )

        ctk.CTkButton(
            self,
            text="저장 및 닫기",
            font=ctk.CTkFont(size=13, weight="bold"),
            height=40,
            fg_color="#1565C0",
            hover_color="#0D3E8A",
            command=self._save_close,
        ).pack(fill="x", padx=16, pady=(8, 16))
        self.protocol("WM_DELETE_WINDOW", self._on_dialog_close)
        self.after(50, self._bind_settings_scroll)

    def _on_dialog_close(self):
        try:
            self.grab_release()
        except Exception:
            pass
        self.destroy()

    def _bind_settings_scroll(self):
        self.app._register_scroll_frame(self.scroll_out)
        self.app._register_scroll_frame(self.scroll_osc)
        bind_mousewheel_to_scroll(self.scroll_out, self.scroll_out)
        bind_mousewheel_to_scroll(self.scroll_osc, self.scroll_osc)

    def _render_all_tabs(self):
        for w in self.scroll_out.winfo_children():
            w.destroy()
        for w in self.scroll_osc.winfo_children():
            w.destroy()
        self._route_rows.clear()
        self._osc_rows.clear()
        self._room_clear_rows.clear()

        if not any(room._cards for room in self.app._rooms):
            ctk.CTkLabel(
                self.scroll_out,
                text="등록된 트랙이 없습니다. 메인 화면에서 오디오를 추가하세요.",
                font=ctk.CTkFont(size=11),
                text_color="#555566",
            ).pack(padx=12, pady=20)
        else:
            for room in self.app._rooms:
                self._room_header(self.scroll_out, room)
                if not room._cards:
                    ctk.CTkLabel(
                        self.scroll_out,
                        text="  (트랙 없음)",
                        font=ctk.CTkFont(size=10),
                        text_color="#555566",
                    ).pack(anchor="w", padx=12, pady=(0, 6))
                    continue
                for card in room._cards:
                    self._add_output_row(card, room.accent)

        if not self.app._rooms:
            ctk.CTkLabel(
                self.scroll_osc,
                text="생성된 룸이 없습니다. 메인 화면에서 룸을 추가하세요.",
                font=ctk.CTkFont(size=11),
                text_color="#555566",
            ).pack(padx=12, pady=20)
        else:
            for room in self.app._rooms:
                self._room_header(self.scroll_osc, room)
                self._add_room_clear_row(room)
                if not room._cards:
                    ctk.CTkLabel(
                        self.scroll_osc,
                        text="  (트랙 없음)",
                        font=ctk.CTkFont(size=10),
                        text_color="#555566",
                    ).pack(anchor="w", padx=12, pady=(0, 6))
                    continue
                for card in room._cards:
                    self._add_osc_row(card)

    def _add_room_clear_row(self, room: RoomPanel):
        """룸 제목 바로 아래 — 룸 클리어 아두이노 신호 입력"""
        box = ctk.CTkFrame(self.scroll_osc, fg_color="#0A0A18", corner_radius=6)
        box.pack(fill="x", padx=8, pady=(0, 8))
        ctk.CTkLabel(
            box,
            text="룸 클리어 아두이노 신호",
            font=ctk.CTkFont(size=10, weight="bold"),
            text_color="#AA9944",
        ).pack(anchor="w", padx=10, pady=(8, 2))
        clear_var = ctk.StringVar(value=room.osc_clear or "")
        ctk.CTkEntry(
            box,
            textvariable=clear_var,
            placeholder_text=f"/room{room.room_id}/clear",
            height=28,
        ).pack(fill="x", padx=10, pady=(0, 10))
        self._room_clear_rows.append((room, clear_var))

    @staticmethod
    def _room_header(parent, room: RoomPanel):
        ctk.CTkLabel(
            parent,
            text=room.room_name,
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color=room.accent,
        ).pack(anchor="w", padx=8, pady=(12, 4))

    def _add_output_row(self, card: TrackCard, accent: str):
        row = ctk.CTkFrame(self.scroll_out, fg_color="#12122A", corner_radius=6)
        row.pack(fill="x", padx=4, pady=3)
        ctk.CTkLabel(
            row,
            text=card._name_var.get(),
            font=ctk.CTkFont(size=11),
            width=200,
            anchor="w",
        ).pack(side="left", padx=10, pady=8)
        ch_idx = min(card.output_ch, max(len(self._ch_labels) - 1, 0))
        route_var = ctk.StringVar(value=self._ch_labels[ch_idx] if self._ch_labels else "1: Output 1")

        def _on_route_change(choice: str):
            ch = parse_ableton_port_label(choice, self._ch_labels)
            card.set_output_channel(ch, self._num_ch)
            card.refresh_output_label()

        ctk.CTkOptionMenu(
            row,
            variable=route_var,
            values=self._ch_labels,
            width=200,
            height=28,
            font=ctk.CTkFont(size=11),
            fg_color="#1E1E38",
            button_color=accent,
            button_hover_color="#333355",
            command=_on_route_change,
        ).pack(side="right", padx=10, pady=8)
        self._route_rows.append((card, route_var))

    def _add_osc_row(self, card: TrackCard):
        row = ctk.CTkFrame(self.scroll_osc, fg_color="#12122A", corner_radius=6)
        row.pack(fill="x", padx=4, pady=3)

        name_col = ctk.CTkFrame(row, fg_color="transparent")
        name_col.pack(side="left", padx=10, pady=8)
        ctk.CTkLabel(
            name_col,
            text=card._name_var.get(),
            font=ctk.CTkFont(size=11, weight="bold"),
            anchor="w",
        ).pack(anchor="w")

        fields = ctk.CTkFrame(row, fg_color="transparent")
        fields.pack(side="right", padx=8, pady=6)

        play_var = ctk.StringVar(value=card.osc_play or "")
        stop_var = ctk.StringVar(value=card.osc_stop or "")

        play_col = ctk.CTkFrame(fields, fg_color="transparent")
        play_col.pack(side="left", padx=4)
        ctk.CTkLabel(
            play_col, text="재생 신호", font=ctk.CTkFont(size=9), text_color="#88AA88"
        ).pack(anchor="w")
        ctk.CTkEntry(
            play_col,
            textvariable=play_var,
            placeholder_text=f"/room/card/play",
            width=180,
            height=28,
        ).pack()

        stop_col = ctk.CTkFrame(fields, fg_color="transparent")
        stop_col.pack(side="left", padx=4)
        ctk.CTkLabel(
            stop_col, text="정지 신호", font=ctk.CTkFont(size=9), text_color="#AA8888"
        ).pack(anchor="w")
        ctk.CTkEntry(
            stop_col,
            textvariable=stop_var,
            placeholder_text="/room/card/stop",
            width=180,
            height=28,
        ).pack()

        self._osc_rows.append((card, play_var, stop_var))

    @staticmethod
    def _parse_output_label(label: str, menu_labels: list[str] | None = None) -> int:
        return parse_ableton_port_label(label, menu_labels)

    def _save_close(self):
        # ① 메모리·config.json 반영 (가벼운 작업만 UI 스레드에서 수행)
        route_updates = [
            (card, self._parse_output_label(route_var.get(), self._ch_labels), self._num_ch)
            for card, route_var in self._route_rows
        ]
        osc_updates = [
            (card, play_var.get().strip(), stop_var.get().strip())
            for card, play_var, stop_var in self._osc_rows
        ]
        port_str = self._port_var.get()

        for card, ch, num_ch in route_updates:
            card.set_output_channel(ch, num_ch)
        for card, play, stop in osc_updates:
            card.osc_play = play
            card.osc_stop = stop
        for room, clear_var in self._room_clear_rows:
            room.osc_clear = clear_var.get().strip()

        try:
            port = int(port_str)
            self.app._cfg.setdefault("osc", {})["port"] = port
            self.app._cfg["osc"]["host"] = self.app._cfg.get("osc", {}).get("host", "0.0.0.0")
        except ValueError:
            pass

        num_ch = self._num_ch
        self.app._sync_cfg_from_ui()
        self.app._rebuild_osc_registry()
        save_config(self.app._cfg)

        # ② 팝업 즉시 닫기 (grab 해제 후 destroy — 렉·데드락 원천 차단)
        try:
            self.grab_release()
        except Exception:
            pass
        self.destroy()

        # ③ 오디오·OSC 재초기화는 백그라운드에서 (UI는 즉시 조작 가능)
        self.app._after_settings_saved(num_ch)


# ═══════════════════════════════════════════════════════════════════════════════
# 메인 앱
# ═══════════════════════════════════════════════════════════════════════════════
class AtmosMixerApp(ctk.CTk):
    ROOM_COLORS = ["#4A90D9", "#9B68EE", "#50C878", "#D94A70", "#D9B84A", "#4AD9B8"]

    def __init__(self):
        super().__init__()
        self._cfg = load_config()
        self.engine = AudioEngine(log_cb=self.append_log)
        self._rooms: list[RoomPanel] = []
        self._scroll_frames: list[AtmosScrollableFrame] = []
        self._dev_map: dict[str, int] = {}
        self._active_room_id = int(
            self._cfg.get("timeline", {}).get(
                "active_room_id",
                self._cfg.get("timeline", {}).get("unlocked_through", 1),
            )
        )
        self._unlocked_through = self._active_room_id  # 하위 호환 별칭
        self._room_gate = ExclusiveRoomGate()
        self._osc_registry = OSCAddressRegistry()
        self._osc: OSCReceiver | None = None
        self._osc_debounce_cache: dict[str, float] = {}
        self._loaded_preset_path: Path | None = None
        self._import_asset_base: Path = BASE_DIR
        self._shutting_down = False
        saved_ports = self._cfg.get("audio_device", {}).get("output_port_labels") or ["Output 1"]
        self._output_port_labels: list[str] = [str(x) for x in saved_ports]
        self.engine.set_output_port_labels(self._output_port_labels)

        self._setup_window()
        self._build_header()
        self._build_room_area()
        self._build_log_area()

        self._init_devices()
        self._restore_rooms()
        self._sync_track_output_labels()
        self._room_gate.set_room_ids([r.room_id for r in self._rooms])
        self._room_gate.set_active_room(self._active_room_id)
        self._rebuild_osc_registry()
        self.engine.set_active_room(self._active_room_id)
        self._apply_room_locks()
        self._refresh_main_scroll_wheel()
        self._install_global_scroll()
        self._start_osc()
        self._startup_log()
        self.protocol("WM_DELETE_WINDOW", self.on_closing)

    def _setup_window(self):
        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("blue")
        self.title("🎛  Atmos Mixer Pro — 방탈출 멀티채널 오디오 믹서")
        self.geometry("1400x860")
        self.minsize(1100, 720)
        self.configure(fg_color="#08080F")

    def _build_header(self):
        hdr = ctk.CTkFrame(self, height=90, fg_color="#0E0E1C", corner_radius=0)
        hdr.pack(fill="x", side="top")
        hdr.pack_propagate(False)

        title_blk = ctk.CTkFrame(hdr, fg_color="transparent")
        title_blk.pack(side="left", padx=18, pady=8, fill="y")
        ctk.CTkLabel(
            title_blk,
            text="🎛  Atmos Mixer Pro",
            font=ctk.CTkFont(size=22, weight="bold"),
            text_color="#FFFFFF",
        ).pack(anchor="w")
        ctk.CTkLabel(
            title_blk,
            text="시퀀스 제어형 멀티채널 오디오 믹서",
            font=ctk.CTkFont(size=10),
            text_color="#4A4A6A",
        ).pack(anchor="w")

        btn_blk = ctk.CTkFrame(hdr, fg_color="transparent")
        btn_blk.pack(side="left", padx=12, pady=18, fill="y")
        self._mk_hdr_btn(btn_blk, "테마 시작", "#1565C0", "#0D3E8A", self._start_theme).pack(
            side="left", padx=3
        )
        self._mk_hdr_btn(btn_blk, "비상 정지", "#B71C1C", "#7F0000", self._panic_stop).pack(
            side="left", padx=3
        )
        self._mk_hdr_btn(btn_blk, "시스템 리셋", "#37474F", "#1C2A30", self._system_reset).pack(
            side="left", padx=3
        )
        self._mk_hdr_btn(btn_blk, "➕ 룸 추가", "#2E7D32", "#1B5E20", self._add_room).pack(
            side="left", padx=3
        )
        self._mk_hdr_btn(btn_blk, "⚙️ 환경설정", "#455A64", "#263238", self._open_settings).pack(
            side="left", padx=3
        )

        file_blk = ctk.CTkFrame(hdr, fg_color="transparent")
        file_blk.pack(side="left", padx=(4, 8), pady=18, fill="y")
        self._mk_hdr_btn(
            file_blk, "💾 설정보내기", "#6A1B9A", "#4A148C", self._export_settings, width=118
        ).pack(side="left", padx=3)
        self._mk_hdr_btn(
            file_blk, "📂 설정 불러오기", "#00838F", "#006064", self._import_settings, width=118
        ).pack(side="left", padx=3)

        dev_blk = ctk.CTkFrame(hdr, fg_color="transparent")
        dev_blk.pack(side="right", padx=18, pady=12, fill="y")

        dev_lbl_frame = ctk.CTkFrame(dev_blk, fg_color="transparent")
        dev_lbl_frame.pack(fill="x", anchor="w")
        ctk.CTkLabel(
            dev_lbl_frame,
            text="🔌 출력 오디오 기기",
            font=ctk.CTkFont(size=10),
            text_color="#666688",
        ).pack(side="left")
        ctk.CTkButton(
            dev_lbl_frame,
            text="🔄 스캔",
            width=56,
            height=20,
            font=ctk.CTkFont(size=10),
            fg_color="#2A2A4A",
            hover_color="#3A3A5A",
            corner_radius=6,
            command=lambda: self._init_devices(hotplug=True, bind=False),
        ).pack(side="left", padx=(8, 0))

        self._dev_var = ctk.StringVar(value="기기 감지 중...")
        self.dev_menu = ctk.CTkOptionMenu(
            dev_blk,
            variable=self._dev_var,
            values=["기기 감지 중..."],
            width=300,
            height=34,
            font=ctk.CTkFont(size=11),
            fg_color="#181830",
            button_color="#4A90D9",
            command=self._on_device_select,
        )
        self.dev_menu.pack(anchor="w", pady=(4, 0))

        self.ch_label = ctk.CTkLabel(
            dev_blk,
            text="채널: 감지 중",
            font=ctk.CTkFont(family="Menlo", size=10),
            text_color="#445566",
        )
        self.ch_label.pack(anchor="w")

    @staticmethod
    def _mk_hdr_btn(parent, text, fg, hover, cmd, width: int = 108):
        return ctk.CTkButton(
            parent,
            text=text,
            font=ctk.CTkFont(size=12, weight="bold"),
            fg_color=fg,
            hover_color=hover,
            width=width,
            height=48,
            corner_radius=10,
            command=cmd,
        )

    def _build_room_area(self):
        self.room_scroll = AtmosScrollableFrame(
            self,
            fg_color="#08080F",
            corner_radius=0,
            orientation="horizontal",
        )
        self.room_scroll.pack(fill="both", expand=True, padx=8, pady=6)
        self._register_scroll_frame(self.room_scroll)
        self.rooms_container = ctk.CTkFrame(self.room_scroll, fg_color="transparent")
        self.rooms_container.pack(fill="both", expand=True, anchor="nw")

    def _sync_room_heights(self):
        """룸 패널이 세로 공간을 가득 채우도록 높이 동기화"""
        try:
            ch = self.room_scroll.winfo_height()
            if ch < 120:
                ch = self.room_scroll._parent_canvas.winfo_height()
            if ch > 120:
                for room in self._rooms:
                    room.configure(height=ch - 12)
        except Exception:
            pass

    def _register_scroll_frame(self, frame: AtmosScrollableFrame):
        if frame not in self._scroll_frames:
            self._scroll_frames.append(frame)

    def _refresh_main_scroll_wheel(self):
        self._sync_room_heights()
        bind_mousewheel_to_scroll(self.room_scroll, self.room_scroll)
        bind_mousewheel_to_scroll(self.room_scroll, self.rooms_container)
        for room in self._rooms:
            self._register_scroll_frame(room.scroll)
            bind_mousewheel_to_scroll(self.room_scroll, room)
            try:
                bind_mousewheel_to_scroll(room.scroll, room.scroll)
            except Exception:
                pass
        self.room_scroll.bind("<Configure>", lambda _e: self._sync_room_heights(), add="+")

    def _find_scroll_frame_at(self, x_root: int, y_root: int) -> AtmosScrollableFrame | None:
        """포인터 아래 가장 안쪽 스크롤 프레임 탐색 (마스터 체인 상향)"""
        w = self.winfo_containing(x_root, y_root)
        cur = w
        while cur is not None:
            for sf in self._scroll_frames:
                if cur == sf:
                    return sf
            try:
                cur = cur.master
            except Exception:
                break
        return None

    def _global_touchpad(self, event):
        """Tk 9 TouchpadScroll — 맥·윈도우 트랙패드 전역 라우팅"""
        dx, dy = _parse_touchpad_pixels(self.tk, event)
        if dx == 0 and dy == 0:
            return
        target = self._find_scroll_frame_at(event.x_root, event.y_root)
        if target and target.apply_touchpad(dx, dy):
            return
        self.room_scroll.apply_touchpad(dx, dy)

    def _global_mousewheel(self, event):
        """물리 마우스 휠 — 맥 포함 전역 라우팅 (CTk 기본 MouseWheel 보조)"""
        vert, horiz = _parse_wheel_deltas(event)
        if vert == 0 and horiz == 0:
            return
        target = self._find_scroll_frame_at(event.x_root, event.y_root)
        if target and target.apply_mouse_wheel(vert, horiz):
            return
        self.room_scroll.apply_mouse_wheel(vert, horiz)

    def _install_global_scroll(self):
        """트랙패드(TouchpadScroll) + 마우스휠 전역 바인딩"""
        if getattr(self, "_global_scroll_installed", False):
            return
        self.bind_all("<TouchpadScroll>", self._global_touchpad, add="+")
        if _is_mac():
            self.bind_all("<MouseWheel>", self._global_mousewheel, add="+")
            self.bind_all("<Shift-MouseWheel>", self._global_mousewheel, add="+")
        self._global_scroll_installed = True
        tk_ver = self.tk.call("info", "patchlevel")
        self.append_log(f"[UI] 전역 스크롤 바인딩 활성화 (Tk {tk_ver}, TouchpadScroll+MouseWheel)")

    def _build_log_area(self):
        log_outer = ctk.CTkFrame(self, fg_color="#030306", corner_radius=0, height=155)
        log_outer.pack(fill="x", side="bottom")
        log_outer.pack_propagate(False)
        hdr = ctk.CTkFrame(log_outer, fg_color="transparent")
        hdr.pack(fill="x", padx=10, pady=(6, 0))
        ctk.CTkLabel(
            hdr,
            text="📋 시스템 로그",
            font=ctk.CTkFont(family="Menlo", size=11, weight="bold"),
            text_color="#303050",
        ).pack(side="left")
        ctk.CTkButton(
            hdr,
            text="지우기",
            font=ctk.CTkFont(size=10),
            width=64,
            height=22,
            fg_color="#181830",
            hover_color="#252545",
            command=self._clear_log,
        ).pack(side="right")
        self.log_box = ctk.CTkTextbox(
            log_outer,
            font=ctk.CTkFont(family="Menlo", size=11),
            fg_color="#000000",
            text_color="#22DD88",
            corner_radius=0,
            state="disabled",
            wrap="word",
        )
        self.log_box.pack(fill="both", expand=True, pady=(4, 0))

    def get_output_menu_labels(self) -> list[str]:
        labels = self._output_port_labels or ["Output 1"]
        return [format_ableton_port_label(i, name) for i, name in enumerate(labels)]

    def refresh_output_port_labels(self, device_idx: int | None = None, log: bool = True):
        """하드웨어 포트 이름 재스캔 → 엔진·UI·config 동기화"""
        idx = device_idx if device_idx is not None else self.engine._device_idx
        if idx is None:
            self._output_port_labels = ["Output 1"]
        else:
            self._output_port_labels = query_hardware_output_port_labels(idx)
        self.engine.set_output_port_labels(self._output_port_labels)
        self._cfg.setdefault("audio_device", {})["output_port_labels"] = list(self._output_port_labels)
        if log:
            dev_name = "미연결"
            if idx is not None:
                try:
                    dev_name = str(sd.query_devices(idx)["name"])
                except Exception:
                    pass
            self.append_log(f"[포트] {dev_name} — 물리 출력 {len(self._output_port_labels)}ch 감지:")
            for i, name in enumerate(self._output_port_labels):
                self.append_log(f"  · CH{i + 1}: {name}")
        self._sync_track_output_labels()

    def _sync_track_output_labels(self):
        for room in self._rooms:
            for card in room._cards:
                card.refresh_output_label()

    def _on_device_select(self, label: str):
        self._init_devices(hotplug=True, bind=False)
        if label in self._dev_map:
            self._dev_var.set(label)
        self._bind_device_async(self._dev_var.get())

    def _init_devices(self, hotplug: bool = False, bind: bool = True):
        try:
            if hotplug:
                self.append_log("[오디오] 프로 오디오 장치 스캔 중 (ASIO/Core Audio)...")

            output_devs = scan_pro_audio_devices(hotplug_reset=hotplug)
            platform_hint = "ASIO" if sys.platform == "win32" else "Core Audio"

            if not output_devs:
                self.dev_menu.configure(values=[f"⚠ {platform_hint} 출력 기기 없음"])
                self._dev_var.set(f"⚠ {platform_hint} 출력 기기 없음")
                if hotplug:
                    self.append_log(
                        f"[오디오] {platform_hint} 장치를 찾지 못했습니다. "
                        "드라이버 설치 및 케이블 연결을 확인하세요."
                    )
                return

            self._dev_map = output_devs
            labels = list(output_devs.keys())
            self.dev_menu.configure(values=labels)

            saved_name = self._cfg.get("audio_device", {}).get("name", "")
            chosen = labels[0]
            curr = self._dev_var.get()
            if hotplug and curr in labels:
                chosen = curr
            else:
                for lbl in labels:
                    if saved_name and saved_name in lbl:
                        chosen = lbl
                        break

            self._dev_var.set(chosen)
            if bind:
                self._bind_device_async(chosen)

            if hotplug:
                self.append_log(
                    f"[오디오] {platform_hint} 기준 스캔 완료 — {len(labels)}개 장치"
                )
        except Exception as exc:
            self.append_log(f"[오류] 기기 스캔 실패: {exc}")

    def _bind_device_async(self, label: str):
        idx = self._dev_map.get(label)
        if idx is None:
            return

        self.ch_label.configure(text="출력 연결 중...", text_color="#AA8800")
        self.append_log(f"[오디오] 백그라운드 연결 시작: {label}")

        def worker():
            try:
                max_in, max_out = self.engine.reinitialize_device(idx)
                info = sd.query_devices(idx)
                hostapis = sd.query_hostapis()
                api_name = hostapis[int(info["hostapi"])]["name"]

                def on_ui():
                    self.refresh_output_port_labels(idx, log=True)
                    self.ch_label.configure(
                        text=f"출력 {max_out}ch · {self._output_port_labels[0] if self._output_port_labels else '—'}",
                        text_color="#4499BB",
                    )
                    self.append_log(
                        f"[오디오] 연결 완료 — {api_name}: {info['name']} · 물리 출력 {max_out}ch"
                    )
                    for room in self._rooms:
                        room.update_channels(max_out)
                    self._cfg.setdefault("audio_device", {})
                    self._cfg["audio_device"].update(
                        {
                            "name": str(info["name"]),
                            "hostapi": api_name,
                            "index": idx,
                            "output_channels": max_out,
                            "output_port_labels": list(self._output_port_labels),
                        }
                    )
                    self._save_cfg()

                self._safe_after(0, on_ui)
            except Exception as exc:
                self._safe_after(
                    0,
                    lambda: self.append_log(f"[오류] 기기 바인딩 실패: {exc}"),
                )

        threading.Thread(target=worker, daemon=True, name="오디오장치연결").start()

    def _after_settings_saved(self, num_ch: int):
        """환경설정 닫힌 직후 — UI 스레드에서 호출, 무거운 작업은 백그라운드"""
        self.append_log(
            f"[환경설정] 저장 완료 (물리 출력 {num_ch}ch) — 백그라운드 오디오 재연결 중..."
        )
        device_idx = self.engine._device_idx

        def audio_worker():
            try:
                if device_idx is not None:
                    _mi, max_out = self.engine.reinitialize_device(device_idx)
                    self._safe_after(
                        0,
                        lambda: self._on_audio_reinit_done(max_out, "환경설정 적용"),
                    )
                else:
                    self._safe_after(
                        0,
                        lambda: self.append_log("[엔진] 연결된 장치 없음 — 재연결 생략"),
                    )
            except Exception as exc:
                self._safe_after(
                    0,
                    lambda: self.append_log(f"[오류] 백그라운드 오디오 재연결 실패: {exc}"),
                )

        def osc_worker():
            try:
                if self._osc:
                    self._osc.stop()
                osc_cfg = self._cfg.get("osc", {})
                host = osc_cfg.get("host", "0.0.0.0")
                port = int(osc_cfg.get("port", 8000))
                self._osc = OSCReceiver(host, port, self.append_log, self._on_osc_trigger)
                self._osc.start()
                self._safe_after(0, lambda: self.append_log("[OSC] 백그라운드 서버 재시작 완료"))
            except Exception as exc:
                self._safe_after(
                    0,
                    lambda: self.append_log(f"[오류] OSC 재시작 실패: {exc}"),
                )

        threading.Thread(target=audio_worker, daemon=True, name="설정후오디오재연결").start()
        threading.Thread(target=osc_worker, daemon=True, name="설정후OSC재시작").start()

    def _on_audio_reinit_done(self, max_out: int, reason: str):
        if self.engine._device_idx is not None:
            self.refresh_output_port_labels(self.engine._device_idx, log=False)
        for room in self._rooms:
            room.update_channels(max_out)
        port_hint = self._output_port_labels[0] if self._output_port_labels else "—"
        self.ch_label.configure(
            text=f"출력 {max_out}ch · {port_hint}", text_color="#4499BB"
        )
        self.append_log(f"[엔진] {reason} — 물리 출력 {max_out}ch 재연결 완료 (UI 정상)")
        if self.engine._device_idx is not None:
            self.append_log("[포트] 현재 활성 출력 포트:")
            for i, name in enumerate(self._output_port_labels):
                self.append_log(f"  · CH{i + 1}: {name}")

    def _create_room_panel(self, room_data: dict | None = None) -> RoomPanel:
        if room_data:
            room_id = int(room_data.get("id", len(self._rooms) + 1))
            name = str(room_data.get("name", f"🚪 룸 {room_id}"))
        else:
            room_id = len(self._rooms) + 1
            name = f"🚪 룸 {room_id}"
        color = self.ROOM_COLORS[(max(room_id, 1) - 1) % len(self.ROOM_COLORS)]
        panel = RoomPanel(
            self.rooms_container,
            room_id=room_id,
            room_name=name,
            engine=self.engine,
            log_cb=self.append_log,
            save_cb=self._save_cfg,
            clear_cb=self._on_room_clear,
            delete_cb=self._on_room_delete,
            accent=color,
        )
        panel.pack(side="left", fill="both", expand=True, padx=5, pady=4)
        self._rooms.append(panel)
        locked = room_id != self._active_room_id
        panel.set_locked(locked)
        if room_data:
            panel.load_from_config(room_data, asset_base=self._import_asset_base)
        return panel

    def _add_room(self):
        panel = self._create_room_panel()
        self._room_gate.set_room_ids([r.room_id for r in self._rooms])
        self._rebuild_osc_registry()
        self._refresh_main_scroll_wheel()
        self.append_log(f"[룸 추가] {panel.room_name}")
        self._save_cfg()

    def _on_room_delete(self, room: RoomPanel):
        self.append_log(f"[{room.room_name}] 룸 삭제 — 오디오 정지 및 리소스 해제")
        room.force_stop_all()
        for card in list(room._cards):
            self.engine.remove_track(card.track_id)
            try:
                card.destroy()
            except Exception:
                pass
        room._cards.clear()
        room.destroy()
        if room in self._rooms:
            self._rooms.remove(room)
        self._room_gate.set_room_ids([r.room_id for r in self._rooms])
        self._rebuild_osc_registry()
        self._save_cfg()
        self._refresh_main_scroll_wheel()
        self.append_log(f"[{room.room_name}] 삭제 완료 — 레이아웃 재정렬됨")

    def _sync_timeline_cfg(self):
        self._unlocked_through = self._active_room_id
        self._room_gate.set_active_room(self._active_room_id)
        self._cfg.setdefault("timeline", {})["active_room_id"] = self._active_room_id
        self._cfg["timeline"]["unlocked_through"] = self._active_room_id

    def _rebuild_osc_registry(self):
        self._osc_registry = build_osc_registry_from_rooms(self._rooms)

    def _play_room_bgm(self, room: RoomPanel | None) -> int:
        if not room:
            return 0
        count = 0
        for card in room.get_bgm_cards():
            if card.start_bgm_playback():
                count += 1
        return count

    def _apply_room_locks(self):
        self._active_room_id = self._room_gate.active_room_id
        self.engine.set_active_room(self._active_room_id)
        for room in self._rooms:
            is_active = room.room_id == self._active_room_id
            if not is_active:
                room.force_stop_all()
            room.set_locked(not is_active)

    def _on_room_clear(self, room: RoomPanel):
        accepted, next_id = self._room_gate.on_room_clear(room.room_id)
        if not accepted:
            self.append_log(
                f"[{room.room_name}] 비활성 — 클리어 무시 (활성 룸: {self._active_room_id})"
            )
            return
        self.append_log(f"[{room.room_name}] 룸 클리어 — 독점 전환 원스톱")
        room.force_stop_all()
        next_room = next((r for r in self._rooms if r.room_id == next_id), None)
        self._active_room_id = next_id
        if not next_room:
            self.append_log("[인터록] 다음 룸 없음 — 전체 출력 차단")
        self._sync_timeline_cfg()
        self._apply_room_locks()
        self.update_idletasks()
        count = self._play_room_bgm(next_room) if next_room else 0
        self._save_cfg()
        if next_room:
            if count:
                self.append_log(
                    f"[{next_room.room_name}] 독점 활성 — 배경음 {count}개 즉시 페이드인"
                )
            else:
                self.append_log(f"[{next_room.room_name}] 독점 활성 — 배경음 없음")

    def _start_theme(self):
        self.engine.unmute()
        self.append_log("[테마 시작] 전체 정지 → 룸 1 독점 활성화")
        for room in self._rooms:
            room.force_stop_all()
        self._active_room_id = self._room_gate.theme_start()
        self._sync_timeline_cfg()
        self._apply_room_locks()
        self.update_idletasks()
        room1 = next((r for r in self._rooms if r.room_id == 1), None)
        if not room1:
            self.append_log("[테마 시작] 1번 룸이 없습니다.")
            self._save_cfg()
            return
        count = self._play_room_bgm(room1)
        self._save_cfg()
        self.append_log(
            f"[테마 시작] 룸 1 배경음 {count}개 즉시 재생 (타 룸 완전 차단)"
            if count
            else "[테마 시작] 1번 룸에 루프(배경음) 트랙 없음"
        )

    def _panic_stop(self):
        self.engine.panic()
        for room in self._rooms:
            room.force_stop_all()
        self.append_log("🚨 [비상 정지] 모든 채널 즉시 정지 및 뮤트")

    def _system_reset(self):
        self.engine.reset()
        for room in self._rooms:
            room.force_stop_all()
        self._active_room_id = self._room_gate.theme_start()
        self._sync_timeline_cfg()
        self._apply_room_locks()
        self._save_cfg()
        self.append_log("↺ [시스템 리셋] 룸 1 독점 활성 — 나머지 차단")

    def _open_settings(self):
        SettingsDialog(self, self)

    def _start_osc(self):
        osc_cfg = self._cfg.get("osc", {})
        host = osc_cfg.get("host", "0.0.0.0")
        port = int(osc_cfg.get("port", 8000))
        self._osc = OSCReceiver(host, port, self.append_log, self._on_osc_trigger)
        self._osc.start()

    def _restart_osc(self):
        if self._osc:
            self._osc.stop()
        self._start_osc()

    def _on_osc_trigger(self, address: str, args, recv_ns: int = 0):
        if self._shutting_down:
            return

        # 1. 아두이노 센서 Release(0) 신호 무시 로직
        if args and isinstance(args[0], (int, float)):
            if args[0] <= 0:  # 센서가 꺼질 때의 신호는 무시
                return
                
        # 2. 하드웨어 바운싱 방지 (예: 250ms 이내 동일 주소 무시)
        now = time.time()
        last_time = self._osc_debounce_cache.get(address, 0)
        if now - last_time < 0.25:
            return  # 쿨타임 중 중복 패킷 버림
        self._osc_debounce_cache[address] = now

        def _handle():
            if self._shutting_down:
                return
            binding, match_ns = self._osc_registry.match_latency_ns(address)
            if binding is None:
                self.append_log(f"[OSC] 매핑 없음: {normalize_osc_address(address)}")
                return
            if match_ns > OSC_MATCH_SLOP_NS:
                self.append_log(
                    f"[OSC] 주소 대조 {match_ns / 1_000_000:.4f}ms "
                    f"(목표 ≤0.1ms) — {address}"
                )

            if binding.kind is OSCActionKind.ROOM_CLEAR:
                room = next((r for r in self._rooms if r.room_id == binding.room_id), None)
                if not room:
                    return
                if not self._room_gate.allows_room_osc(binding.room_id):
                    self.append_log(
                        f"[OSC 클리어] 무시 — 잠금 룸 {binding.room_id} "
                        f"(활성 {self._active_room_id})"
                    )
                    return
                self.append_log(f"[OSC 클리어] {address} → {room.room_name}")
                self._on_room_clear(room)
                return

            if not self._room_gate.allows_room_osc(binding.room_id):
                self.append_log(
                    f"[OSC] 잠금 룸 {binding.room_id} 신호 차단: {address} "
                    f"(활성 {self._active_room_id})"
                )
                return

            room = next((r for r in self._rooms if r.room_id == binding.room_id), None)
            if not room:
                return
            card = next(
                (c for c in room._cards if c.track_id == binding.track_id),
                None,
            )
            if not card:
                return
            if binding.kind is OSCActionKind.TRACK_PLAY:
                if not card._playing:
                    card._toggle_play()
                    self.append_log(
                        f"[OSC 재생] {address} → [{room.room_name}] {card._name_var.get()}"
                    )
            elif binding.kind is OSCActionKind.TRACK_STOP:
                if card._playing:
                    card._toggle_play()
                    self.append_log(
                        f"[OSC 정지] {address} → [{room.room_name}] {card._name_var.get()}"
                    )

        if threading.current_thread() is threading.main_thread():
            _handle()
        else:
            try:
                self._safe_after(0, _handle)
            except Exception:
                pass

    def _safe_after(self, delay_ms: int, callback):
        """종료 중 백그라운드 스레드의 after() 호출 차단"""
        if self._shutting_down:
            return
        try:
            self.after(delay_ms, callback)
        except Exception:
            pass

    def append_log(self, msg: str):
        if self._shutting_down:
            return

        def _write():
            if self._shutting_down:
                return
            self.log_box.configure(state="normal")
            self.log_box.insert("end", f"[{_ts()}] {msg}\n")
            self.log_box.see("end")
            self.log_box.configure(state="disabled")

        if threading.current_thread() is threading.main_thread():
            _write()
        else:
            try:
                self._safe_after(0, _write)
            except Exception:
                pass

    def _clear_log(self):
        self.log_box.configure(state="normal")
        self.log_box.delete("1.0", "end")
        self.log_box.configure(state="disabled")

    def _build_full_snapshot(self) -> dict:
        """화면에 표시된 실시간 UI 값을 역추적하여 완전한 JSON 스냅샷 생성"""
        rooms = []
        for idx, room in enumerate(self._rooms):
            rooms.append(room.get_config(order_index=idx))
        snapshot = {
            "atmos_schema": ATMOS_SCHEMA_VERSION,
            "room_count": len(rooms),
            "timeline": {
                "active_room_id": self._active_room_id,
                "unlocked_through": self._active_room_id,
            },
            "osc": dict(self._cfg.get("osc", {"host": "0.0.0.0", "port": 8000})),
            "audio_device": dict(self._cfg.get("audio_device", {})),
            "rooms": rooms,
        }
        if self._loaded_preset_path:
            snapshot["loaded_preset"] = str(self._loaded_preset_path)
        return snapshot

    def _sync_cfg_from_ui(self):
        self._cfg = self._build_full_snapshot()

    def _save_cfg(self):
        try:
            self._sync_cfg_from_ui()
            self._rebuild_osc_registry()
            save_config(self._cfg)
        except Exception as exc:
            self.append_log(f"[오류] 설정 저장 실패: {exc}")

    def _clear_engine_tracks(self):
        with self.engine._lock:
            self.engine._tracks.clear()
        self.engine._sfx_active = 0

    def _clear_all_rooms(self):
        self.engine.panic()
        self._clear_engine_tracks()
        for room in list(self._rooms):
            room.force_stop_all()
            for card in list(room._cards):
                self.engine.remove_track(card.track_id)
                try:
                    card.destroy()
                except Exception:
                    pass
            room._cards.clear()
            try:
                room.destroy()
            except Exception:
                pass
        self._rooms.clear()

    def _restore_rooms(self):
        saved = self._cfg.get("rooms", [])
        if not saved:
            self._add_room()
            return
        for room_data in saved:
            self._create_room_panel(room_data)
        self._refresh_main_scroll_wheel()

    def _export_settings(self):
        path = filedialog.asksaveasfilename(
            title="설정보내기 — Save As",
            defaultextension=".json",
            filetypes=[("JSON 설정 파일", "*.json"), ("모든 파일", "*.*")],
            initialdir=str(BASE_DIR),
            initialfile="공포테마_세팅.json",
        )
        if not path:
            return
        export_path = Path(path)
        cfg_snapshot = self._build_full_snapshot()
        cfg_snapshot.setdefault("atmos_preset", {})["exported_at"] = datetime.now().isoformat(
            timespec="seconds"
        )
        cfg_snapshot["atmos_preset"]["source"] = "ui_snapshot"
        self.append_log(f"[보내기] UI 역추적 저장 중: {export_path.name}")

        def worker():
            try:
                save_config_to_path(cfg_snapshot, export_path)
                self._safe_after(
                    0,
                    lambda: self.append_log(
                        f"[보내기] 완료 — 룸 {len(cfg_snapshot.get('rooms', []))}개, "
                        f"트랙 {sum(len(r.get('tracks', [])) for r in cfg_snapshot.get('rooms', []))}개 "
                        f"→ {export_path}"
                    ),
                )
            except Exception as exc:
                self._safe_after(0, lambda: self.append_log(f"[오류]보내기 실패: {exc}"))

        threading.Thread(target=worker, daemon=True, name="설정보내기").start()

    def _import_settings(self):
        path = filedialog.askopenfilename(
            title="설정 불러오기 — Load File",
            filetypes=[("JSON 설정 파일", "*.json"), ("모든 파일", "*.*")],
            initialdir=str(BASE_DIR),
        )
        if not path:
            return
        import_path = Path(path)
        self.append_log(f"[불러오기] 파일 읽는 중: {import_path.name}")

        def read_worker():
            try:
                cfg = load_config_from_path(import_path)
                self._safe_after(0, lambda: self._apply_imported_config(cfg, import_path))
            except Exception as exc:
                self._safe_after(0, lambda: self.append_log(f"[오류] 불러오기 실패: {exc}"))

        threading.Thread(target=read_worker, daemon=True, name="설정불러오기").start()

    def _apply_imported_config(self, cfg: dict, import_path: Path):
        self.append_log(f"[불러오기] 대시보드 재건축 시작: {import_path.name}")
        self.update_idletasks()
        self._clear_all_rooms()
        self._import_asset_base = import_path.parent.resolve()
        cfg = normalize_preset_config(cfg)
        self._cfg = cfg
        self._loaded_preset_path = import_path
        self._active_room_id = int(
            cfg.get("timeline", {}).get(
                "active_room_id",
                cfg.get("timeline", {}).get("unlocked_through", 1),
            )
        )
        self._unlocked_through = self._active_room_id
        if cfg.get("osc"):
            self._cfg["osc"] = dict(cfg["osc"])
        if cfg.get("audio_device"):
            self._cfg["audio_device"] = dict(cfg["audio_device"])
        self._restore_rooms()
        self._room_gate.set_room_ids([r.room_id for r in self._rooms])
        self._room_gate.set_active_room(self._active_room_id)
        self._rebuild_osc_registry()
        self.engine.set_active_room(self._active_room_id)
        self._apply_room_locks()
        self._refresh_main_scroll_wheel()
        room_count = len(self._rooms)
        track_count = sum(len(r._cards) for r in self._rooms)
        self.append_log(
            f"[불러오기] UI 복구 — 룸 {room_count}개, 트랙 {track_count}개 "
            f"(순서·이름·볼륨·루프·OSC·아웃풋 반영)"
        )
        self._schedule_post_import_sync()
        self._after_import_reboot(cfg)

    def _schedule_post_import_sync(self, attempt: int = 0):
        """오디오 비동기 로드 완료 후 엔진·UI 1:1 재동기화 (최대 6초)"""
        pending = 0
        synced = 0
        for room in self._rooms:
            self.engine.update_room_volume(room.room_id, float(room._master_vol_var.get()))
            for card in room._cards:
                if card.sync_to_engine():
                    synced += 1
                else:
                    pending += 1
        if pending > 0 and attempt < 20:
            self._safe_after(300, lambda: self._schedule_post_import_sync(attempt + 1))
            return
        self._refresh_main_scroll_wheel()
        self._sync_track_output_labels()
        self.append_log(
            f"[불러오기] 엔진 동기화 완료 — 트랙 {synced}개 바인딩 "
            f"(대기 {pending}개)"
        )

    def _after_import_reboot(self, cfg: dict):
        saved_dev = cfg.get("audio_device", {})
        device_idx = saved_dev.get("index")

        def audio_worker():
            try:
                if device_idx is not None:
                    try:
                        sd.query_devices(device_idx)
                        self.engine.reinitialize_device(int(device_idx))
                    except Exception:
                        with self.engine._lock:
                            cur = self.engine._device_idx
                        if cur is not None:
                            self.engine.reinitialize_device(cur)
                elif self.engine._device_idx is not None:
                    self.engine.reinitialize_device(self.engine._device_idx)
                max_out = self.engine.get_num_channels()
                self._safe_after(0, lambda: self._on_import_audio_done(max_out, saved_dev, cfg))
            except Exception as exc:
                self._safe_after(
                    0, lambda: self.append_log(f"[오류] 불러오기 후 오디오 리부팅 실패: {exc}")
                )

        def osc_worker():
            try:
                if self._osc:
                    self._osc.stop()
                osc_cfg = cfg.get("osc", {})
                host = osc_cfg.get("host", "0.0.0.0")
                port = int(osc_cfg.get("port", 8000))
                self._osc = OSCReceiver(host, port, self.append_log, self._on_osc_trigger)
                self._osc.start()
                self._safe_after(0, lambda: self.append_log("[OSC] 불러오기 후 서버 재시작 완료"))
            except Exception as exc:
                self._safe_after(0, lambda: self.append_log(f"[오류] OSC 재시작 실패: {exc}"))

        def save_worker():
            try:
                save_config(self._cfg)
                self._safe_after(
                    0,
                    lambda: self.append_log(
                        f"[불러오기] 기본 설정({CONFIG_PATH.name})에도 동기화 저장됨"
                    ),
                )
            except Exception as exc:
                self._safe_after(
                    0, lambda: self.append_log(f"[경고] config.json 동기화 실패: {exc}")
                )

        threading.Thread(target=audio_worker, daemon=True, name="불러오기오디오").start()
        threading.Thread(target=osc_worker, daemon=True, name="불러오기OSC").start()
        threading.Thread(target=save_worker, daemon=True, name="불러오기저장").start()

    def _on_import_audio_done(self, max_out: int, saved_dev: dict, cfg: dict):
        if self.engine._device_idx is not None:
            self.refresh_output_port_labels(self.engine._device_idx, log=True)
        else:
            saved_labels = saved_dev.get("output_port_labels")
            if saved_labels:
                self._output_port_labels = [str(x) for x in saved_labels]
                self.engine.set_output_port_labels(self._output_port_labels)
        for room in self._rooms:
            room.update_channels(max_out)
        self._init_devices(hotplug=False, bind=False)
        dev_name = saved_dev.get("name", "")
        if dev_name:
            for lbl in self._dev_map:
                if dev_name in lbl:
                    self._dev_var.set(lbl)
                    break
        port_hint = self._output_port_labels[0] if self._output_port_labels else "—"
        self.ch_label.configure(
            text=f"출력 {max_out}ch · {port_hint}", text_color="#4499BB"
        )
        self._schedule_post_import_sync()
        self._refresh_main_scroll_wheel()
        self.append_log(
            f"[불러오기] 오디오 엔진 리부팅 완료 — 물리 출력 {max_out}ch (UI 조작 가능)"
        )

    def _startup_log(self):
        osc_port = int(self._cfg.get("osc", {}).get("port", 8000))
        for m in [
            "=" * 60,
            "  Atmos Mixer Pro — Phase 2 (유선 LAN OSC · 독점 룸 게이팅)",
            f"  기본 설정: {CONFIG_PATH}",
            f"  OSC 수신: udp://0.0.0.0:{osc_port} (전용 스레드)",
            f"  활성 룸(독점): {self._active_room_id}",
            "  [테마 시작] 전체 Stop → 룸1 독점+BGM | [룸 클리어 OSC] 다음 룸",
            "  잠금 룸: OSC·콜백 단계 100% 뮤트",
            "=" * 60,
        ]:
            self.append_log(m)

    def on_closing(self):
        """Graceful Shutdown — 블로킹 없이 즉시 프로세스 종료"""
        if self._shutting_down:
            os._exit(0)
        self._shutting_down = True

        try:
            if self._osc:
                self._osc.stop(wait=False)
                self._osc = None
        except Exception:
            pass

        try:
            self.engine._muted = True
            self.engine._stop_stream(force=True)
        except Exception:
            pass

        try:
            self._save_cfg()
        except Exception:
            pass

        os._exit(0)

    def _on_close(self):
        """하위 호환 — on_closing 위임"""
        self.on_closing()


@dataclass
class OscVerifyResult:
    name: str
    passed: bool
    detail: str


def _verify_audio_callback_interlock() -> OscVerifyResult:
    """잠금 룸 트랙은 콜백에서 출력 0 — 활성 룸만 믹스"""
    engine = AudioEngine(lambda _m: None)
    engine._num_ch = 2
    engine.set_active_room(1)
    sample = np.ones(256, dtype=np.float32) * 0.8
    st1 = TrackState("r1_t9_a", sample, DEFAULT_SR, 0, 1.0, True, True)
    st2 = TrackState("r2_t9_b", sample, DEFAULT_SR, 0, 1.0, True, True)
    for st in (st1, st2):
        st.active = True
        st.play_fade_gain = 1.0
        engine.add_track(st)
    out = np.zeros((128, 2), dtype=np.float32)
    engine._callback(out, 128, None, None)
    peak_both = float(np.max(np.abs(out[:, 0])))
    st1.active = False
    out_locked = np.zeros((128, 2), dtype=np.float32)
    engine._callback(out_locked, 128, None, None)
    peak_r2_while_r1 = float(np.max(np.abs(out_locked[:, 0])))
    st1.active = True
    st2.active = False
    out_r1 = np.zeros((128, 2), dtype=np.float32)
    engine._callback(out_r1, 128, None, None)
    peak_r1_only = float(np.max(np.abs(out_r1[:, 0])))
    ok = (
        peak_both > 0.01
        and peak_r2_while_r1 < 0.001
        and peak_r1_only > 0.01
    )
    return OscVerifyResult(
        "오디오 콜백 인터록 (활성 룸만 출력)",
        ok,
        f"룸1+2={peak_both:.4f}, 룸2잠금={peak_r2_while_r1:.6f}, 룸1만={peak_r1_only:.4f}",
    )


def _verify_osc_address_registry() -> list[OscVerifyResult]:
    rooms = [
        {
            "id": 1,
            "osc_clear": "/room1/clear",
            "tracks": [
                {
                    "track_id": "r1_t1_x",
                    "osc_play": "/room1/bgm/play",
                    "osc_stop": "/room1/bgm/stop",
                },
            ],
        },
        {
            "id": 2,
            "osc_clear": "/room2/clear",
            "tracks": [
                {
                    "track_id": "r2_t1_y",
                    "osc_play": "/room2/bgm/play",
                    "osc_stop": "",
                },
            ],
        },
    ]
    reg = build_osc_registry_from_rooms(rooms)
    results: list[OscVerifyResult] = []
    hit, ns = reg.match_latency_ns("/room1/clear")
    results.append(
        OscVerifyResult(
            "룸 클리어 주소 정확 일치",
            hit is not None and hit.kind is OSCActionKind.ROOM_CLEAR and hit.room_id == 1,
            f"lookup {ns}ns, kind={hit.kind if hit else None}",
        )
    )
    results.append(
        OscVerifyResult(
            "주소 대조 ≤0.1ms",
            ns <= OSC_MATCH_SLOP_NS,
            f"{ns / 1_000_000:.4f}ms",
        )
    )
    wrong_case = reg.lookup("/room1/Clear")
    wrong_room = reg.lookup("/room9/clear")
    results.append(
        OscVerifyResult(
            "오등록 주소·대소문자 거부",
            wrong_case is None and wrong_room is None,
            "대소문자·미등록 경로 미매칭 (수신 공백은 strip 후 일치)",
        )
    )
    play = reg.lookup("/room2/bgm/play")
    results.append(
        OscVerifyResult(
            "트랙 재생 주소 매핑",
            play is not None and play.room_id == 2 and play.track_id == "r2_t1_y",
            str(play),
        )
    )
    return results


def _verify_exclusive_room_sequence() -> list[OscVerifyResult]:
    gate = ExclusiveRoomGate([1, 2, 3, 4])
    results: list[OscVerifyResult] = []
    gate.theme_start()
    results.append(
        OscVerifyResult(
            "테마 시작 → 룸 1 독점",
            gate.active_room_id == 1,
            f"active={gate.active_room_id}",
        )
    )
    ignored, still = gate.on_room_clear(2)
    results.append(
        OscVerifyResult(
            "1번 구동 중 2번 클리어 신호 무시",
            not ignored and still == 1,
            f"accepted={ignored}, active={still}",
        )
    )
    ok, nxt = gate.on_room_clear(1)
    results.append(
        OscVerifyResult(
            "1번 클리어 단일 신호 → 2번 독점",
            ok and nxt == 2,
            f"next={nxt}",
        )
    )
    results.append(
        OscVerifyResult(
            "2번 활성 시 1번 트랙 OSC 차단",
            gate.allows_room_osc(2) and not gate.allows_room_osc(1),
            f"allows_r1={gate.allows_room_osc(1)}, allows_r2={gate.allows_room_osc(2)}",
        )
    )
    return results


def _dispatch_virtual_osc_clear(
    address: str,
    reg: OSCAddressRegistry,
    gate: ExclusiveRoomGate,
) -> tuple[str, int, int, int]:
    """수신 스레드와 동일 경로로 가상 OSC 클리어 패킷 처리"""
    binding, match_ns = reg.match_latency_ns(address)
    if not binding or binding.kind is not OSCActionKind.ROOM_CLEAR:
        return address, match_ns, gate.active_room_id, gate.active_room_id
    before = gate.active_room_id
    if gate.allows_room_osc(binding.room_id):
        gate.on_room_clear(binding.room_id)
    return address, match_ns, before, gate.active_room_id


def _verify_virtual_osc_room_sequence() -> OscVerifyResult:
    """가상 OSC 패킷 — 레지스트리·게이트·단일 신호 룸 전환"""
    gate = ExclusiveRoomGate([1, 2])
    reg = build_osc_registry_from_rooms(
        [
            {"id": 1, "osc_clear": "/sim/room1/clear", "tracks": []},
            {"id": 2, "osc_clear": "/sim/room2/clear", "tracks": []},
        ]
    )
    gate.theme_start()
    t2 = _dispatch_virtual_osc_clear("/sim/room2/clear", reg, gate)
    t1 = _dispatch_virtual_osc_clear("/sim/room1/clear", reg, gate)
    r2_ignored = t2[2] == 1 and t2[3] == 1
    r1_switch = t1[2] == 1 and t1[3] == 2
    fast = t1[1] <= OSC_MATCH_SLOP_NS and t2[1] <= OSC_MATCH_SLOP_NS
    detail = f"room2={t2[2]}→{t2[3]}ns={t2[1]}, room1={t1[2]}→{t1[3]}ns={t1[1]}"
    return OscVerifyResult(
        "가상 OSC 룸 전환 (2번 무시→1번 클리어→2번)",
        r2_ignored and r1_switch and gate.active_room_id == 2 and fast,
        detail,
    )


def run_osc_gating_verification() -> bool:
    """Phase 2 자율 검증 — 콘솔 보고 후 전체 통과 여부 반환"""
    all_results: list[OscVerifyResult] = []
    all_results.extend(_verify_osc_address_registry())
    all_results.extend(_verify_exclusive_room_sequence())
    all_results.append(_verify_audio_callback_interlock())
    all_results.append(_verify_virtual_osc_room_sequence())

    print("\n" + "=" * 60)
    print("  Atmos Mixer Pro — Phase 2 OSC·독점 게이팅 자율 검증")
    print("=" * 60)
    passed = 0
    for r in all_results:
        mark = "PASS" if r.passed else "FAIL"
        if r.passed:
            passed += 1
        print(f"  [{mark}] {r.name}")
        print(f"         {r.detail}")
    total = len(all_results)
    ok = passed == total
    print("-" * 60)
    print(f"  결과: {passed}/{total} 통과 — {'전체 성공' if ok else '일부 실패'}")
    print("=" * 60 + "\n")
    return ok


def main():
    if "--verify-osc" in sys.argv:
        sys.exit(0 if run_osc_gating_verification() else 1)
    app = AtmosMixerApp()
    app.mainloop()


if __name__ == "__main__":
    main()
