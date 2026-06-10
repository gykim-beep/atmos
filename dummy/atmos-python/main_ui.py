"""
ARTMOS Immersive Audio System - Main Dashboard UI
역할: 시각적 대시보드 껍데기만 구축 (오디오/센서 기능 없음)
작성 규칙:
  - pathlib 사용 (경로 독립성)
  - config.json 단일 진실 공급원
  - UI 스레드 분리 (메인 스레드만)
  - customtkinter 전용
"""

import json
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

import customtkinter as ctk

# ── 경로 독립성: 스크립트 기준 절대 경로 ──────────────────────────────────────
BASE_DIR = Path(__file__).parent.resolve()
CONFIG_PATH = BASE_DIR / "config.json"


# ── config.json 로드 ───────────────────────────────────────────────────────────
def load_config() -> dict:
    if not CONFIG_PATH.exists():
        print(f"[ERROR] config.json 을 찾을 수 없습니다: {CONFIG_PATH}")
        sys.exit(1)
    with open(CONFIG_PATH, encoding="utf-8") as f:
        return json.load(f)


# ── 타임스탬프 헬퍼 ────────────────────────────────────────────────────────────
def ts() -> str:
    return datetime.now().strftime("%H:%M:%S")


# ══════════════════════════════════════════════════════════════════════════════
# RoomPanel : 개별 방 패널 위젯
# ══════════════════════════════════════════════════════════════════════════════
class RoomPanel(ctk.CTkFrame):
    def __init__(self, parent, room_cfg: dict, log_callback, **kwargs):
        super().__init__(parent, **kwargs)

        self.room_cfg = room_cfg
        self.log_callback = log_callback
        accent = room_cfg.get("color_accent", "#4A90D9")

        # ── 상단 컬러 바 (구분선 역할) ─────────────────────────────────────────
        ctk.CTkFrame(
            self, height=4, fg_color=accent, corner_radius=0
        ).pack(fill="x", pady=(0, 0))

        # ── 방 제목 ────────────────────────────────────────────────────────────
        ctk.CTkLabel(
            self,
            text=room_cfg["label"],
            font=ctk.CTkFont(family="AppleGothic", size=16, weight="bold"),
            text_color=accent,
        ).pack(pady=(14, 2), padx=16, anchor="w")

        # ── 현재 BGM 이름 ──────────────────────────────────────────────────────
        bgm_frame = ctk.CTkFrame(self, fg_color="#1C1C2E", corner_radius=8)
        bgm_frame.pack(fill="x", padx=16, pady=(4, 8))

        ctk.CTkLabel(
            bgm_frame,
            text="▶  현재 BGM",
            font=ctk.CTkFont(size=10),
            text_color="#888888",
        ).pack(anchor="w", padx=10, pady=(6, 0))

        self.bgm_label = ctk.CTkLabel(
            bgm_frame,
            text=room_cfg.get("current_bgm", "대기 중..."),
            font=ctk.CTkFont(family="AppleGothic", size=13, weight="bold"),
            text_color="#FFFFFF",
            wraplength=220,
            anchor="w",
            justify="left",
        )
        self.bgm_label.pack(anchor="w", padx=10, pady=(2, 8))

        # ── 볼륨 슬라이더 ──────────────────────────────────────────────────────
        vol_row = ctk.CTkFrame(self, fg_color="transparent")
        vol_row.pack(fill="x", padx=16, pady=(0, 4))

        ctk.CTkLabel(
            vol_row,
            text="🔊  볼륨",
            font=ctk.CTkFont(size=11),
            text_color="#AAAAAA",
        ).pack(side="left")

        self.vol_value_label = ctk.CTkLabel(
            vol_row,
            text=f"{room_cfg.get('default_volume', 75)}",
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color=accent,
            width=32,
        )
        self.vol_value_label.pack(side="right")

        self.volume_slider = ctk.CTkSlider(
            self,
            from_=0,
            to=100,
            number_of_steps=100,
            button_color=accent,
            button_hover_color=accent,
            progress_color=accent,
            command=self._on_volume_change,
        )
        self.volume_slider.set(room_cfg.get("default_volume", 75))
        self.volume_slider.pack(fill="x", padx=16, pady=(0, 10))

        # ── OSC 큐 수신 내역 ────────────────────────────────────────────────────
        ctk.CTkLabel(
            self,
            text="📡  최근 OSC 수신 내역",
            font=ctk.CTkFont(size=10),
            text_color="#888888",
        ).pack(anchor="w", padx=16)

        self.osc_log = ctk.CTkTextbox(
            self,
            height=140,
            font=ctk.CTkFont(family="Menlo", size=10),
            fg_color="#0D0D1A",
            text_color="#00FF88",
            corner_radius=8,
            wrap="word",
            state="disabled",
        )
        self.osc_log.pack(fill="x", padx=16, pady=(4, 14))

        # ── 상태 인디케이터 ────────────────────────────────────────────────────
        status_row = ctk.CTkFrame(self, fg_color="transparent")
        status_row.pack(fill="x", padx=16, pady=(0, 12))

        self.status_dot = ctk.CTkLabel(
            status_row,
            text="●",
            font=ctk.CTkFont(size=12),
            text_color="#555555",
        )
        self.status_dot.pack(side="left")

        self.status_label = ctk.CTkLabel(
            status_row,
            text="대기 중",
            font=ctk.CTkFont(size=10),
            text_color="#666666",
        )
        self.status_label.pack(side="left", padx=(4, 0))

    # ── 콜백: 볼륨 슬라이더 변경 ───────────────────────────────────────────────
    def _on_volume_change(self, value: float):
        val = int(value)
        self.vol_value_label.configure(text=str(val))
        room_id = self.room_cfg["id"]
        self.log_callback(f"[룸 {room_id}] 볼륨 → {val}")

    # ── 공개 API: OSC 메시지 추가 ──────────────────────────────────────────────
    def append_osc(self, message: str):
        self.osc_log.configure(state="normal")
        self.osc_log.insert("end", f"[{ts()}] {message}\n")
        self.osc_log.see("end")
        self.osc_log.configure(state="disabled")

    # ── 공개 API: BGM 이름 갱신 ────────────────────────────────────────────────
    def set_bgm(self, name: str):
        self.bgm_label.configure(text=name)

    # ── 공개 API: 상태 인디케이터 갱신 ────────────────────────────────────────
    def set_status(self, text: str, color: str = "#555555"):
        self.status_dot.configure(text_color=color)
        self.status_label.configure(text=text)


# ══════════════════════════════════════════════════════════════════════════════
# ArtmosApp : 메인 애플리케이션
# ══════════════════════════════════════════════════════════════════════════════
class ArtmosApp(ctk.CTk):
    def __init__(self, cfg: dict):
        super().__init__()

        self.cfg = cfg
        self._panic_active = False
        self._room_panels: list[RoomPanel] = []

        self._setup_window()
        self._build_header()
        self._build_rooms()
        self._build_log()
        self._startup_log()

    # ── 창 기본 설정 ────────────────────────────────────────────────────────────
    def _setup_window(self):
        app_cfg = self.cfg["app"]
        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("blue")

        self.title(app_cfg["title"])
        w = app_cfg["window_width"]
        h = app_cfg["window_height"]
        self.geometry(f"{w}x{h}")
        self.minsize(1000, 700)
        self.configure(fg_color="#0A0A14")

        # 창 중앙 배치
        self.update_idletasks()
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        x = (sw - w) // 2
        y = (sh - h) // 2
        self.geometry(f"{w}x{h}+{x}+{y}")

    # ── 헤더 영역 ────────────────────────────────────────────────────────────────
    def _build_header(self):
        header = ctk.CTkFrame(
            self, height=70, fg_color="#12121F", corner_radius=0
        )
        header.pack(fill="x", side="top")
        header.pack_propagate(False)

        # 타이틀
        title_block = ctk.CTkFrame(header, fg_color="transparent")
        title_block.pack(side="left", padx=20, pady=10)

        ctk.CTkLabel(
            title_block,
            text="🎧  ARTMOS",
            font=ctk.CTkFont(family="AppleGothic", size=22, weight="bold"),
            text_color="#FFFFFF",
        ).pack(anchor="w")

        ctk.CTkLabel(
            title_block,
            text="Immersive Audio System  ·  B2B Escape Room Engine",
            font=ctk.CTkFont(size=10),
            text_color="#666699",
        ).pack(anchor="w")

        # 상태 표시 (OSC / Audio Engine)
        status_block = ctk.CTkFrame(header, fg_color="transparent")
        status_block.pack(side="left", padx=30, pady=10)

        osc_cfg = self.cfg["osc"]
        audio_cfg = self.cfg["audio_engine"]

        self.osc_status_label = ctk.CTkLabel(
            status_block,
            text=f"📡  OSC  {osc_cfg['host']}:{osc_cfg['port']}  —  {osc_cfg['status']}",
            font=ctk.CTkFont(family="Menlo", size=11),
            text_color="#FFAA00",
        )
        self.osc_status_label.pack(anchor="w")

        self.audio_status_label = ctk.CTkLabel(
            status_block,
            text=f"🔧  Audio Engine  —  {audio_cfg['status']}",
            font=ctk.CTkFont(family="Menlo", size=11),
            text_color="#FFAA00",
        )
        self.audio_status_label.pack(anchor="w")

        # 시계
        self.clock_label = ctk.CTkLabel(
            header,
            text="",
            font=ctk.CTkFont(family="Menlo", size=13),
            text_color="#444466",
        )
        self.clock_label.pack(side="right", padx=(0, 20))
        self._tick_clock()

        # PANIC 버튼
        panic_cfg = self.cfg["panic"]
        self.panic_btn = ctk.CTkButton(
            header,
            text=panic_cfg["label"],
            font=ctk.CTkFont(family="AppleGothic", size=15, weight="bold"),
            fg_color=panic_cfg["color"],
            hover_color=panic_cfg["hover_color"],
            text_color="#FFFFFF",
            width=220,
            height=46,
            corner_radius=10,
            command=self._on_panic,
        )
        self.panic_btn.pack(side="right", padx=(0, 14), pady=12)

        # 구분선
        ctk.CTkFrame(
            self, height=2, fg_color="#1E1E35", corner_radius=0
        ).pack(fill="x")

    # ── 룸 패널 영역 ─────────────────────────────────────────────────────────────
    def _build_rooms(self):
        rooms_frame = ctk.CTkFrame(self, fg_color="#0A0A14", corner_radius=0)
        rooms_frame.pack(fill="both", expand=True, padx=12, pady=10)

        rooms_cfg = self.cfg["rooms"]
        for i, room_cfg in enumerate(rooms_cfg):
            panel = RoomPanel(
                rooms_frame,
                room_cfg=room_cfg,
                log_callback=self.append_log,
                fg_color="#12121F",
                corner_radius=12,
            )
            panel.grid(row=0, column=i, sticky="nsew", padx=6, pady=4)
            self._room_panels.append(panel)

        # 3등분 균등 배치
        for i in range(len(rooms_cfg)):
            rooms_frame.grid_columnconfigure(i, weight=1)
        rooms_frame.grid_rowconfigure(0, weight=1)

    # ── 하단 디버그 로그 ─────────────────────────────────────────────────────────
    def _build_log(self):
        log_frame = ctk.CTkFrame(
            self, fg_color="#08080F", corner_radius=0, height=160
        )
        log_frame.pack(fill="x", side="bottom")
        log_frame.pack_propagate(False)

        log_header = ctk.CTkFrame(log_frame, fg_color="transparent")
        log_header.pack(fill="x", padx=12, pady=(8, 0))

        ctk.CTkLabel(
            log_header,
            text="📋  SYSTEM LOG",
            font=ctk.CTkFont(family="Menlo", size=11, weight="bold"),
            text_color="#3A3A5C",
        ).pack(side="left")

        ctk.CTkButton(
            log_header,
            text="지우기",
            font=ctk.CTkFont(size=10),
            width=60,
            height=22,
            fg_color="#1E1E35",
            hover_color="#2A2A4A",
            text_color="#666699",
            command=self._clear_log,
        ).pack(side="right")

        self.log_box = ctk.CTkTextbox(
            log_frame,
            font=ctk.CTkFont(family="Menlo", size=11),
            fg_color="#000000",
            text_color="#33FF99",
            corner_radius=0,
            state="disabled",
            wrap="word",
        )
        self.log_box.pack(fill="both", expand=True, padx=0, pady=(4, 0))

    # ── 시작 로그 메시지 ─────────────────────────────────────────────────────────
    def _startup_log(self):
        app_cfg = self.cfg["app"]
        osc_cfg = self.cfg["osc"]
        audio_cfg = self.cfg["audio_engine"]

        messages = [
            "=" * 72,
            f"  {app_cfg['title']}  v{app_cfg['version']}  부팅 완료",
            f"  Config 경로 : {CONFIG_PATH}",
            f"  OSC 엔드포인트 : {osc_cfg['host']}:{osc_cfg['port']}",
            f"  Audio Engine : {audio_cfg['sample_rate']} Hz  /  버퍼 {audio_cfg['buffer_size']} samples",
            "=" * 72,
            "[INFO] UI 초기화 완료 — 오디오 엔진 및 OSC 서버 대기 중",
            "[INFO] PANIC 버튼 준비됨",
        ]
        for msg in messages:
            self.append_log(msg)

        # 룸별 초기 OSC 더미 예시
        for panel in self._room_panels:
            panel.append_osc("시스템 준비 완료 — OSC 신호 대기 중")

    # ── PANIC 핸들러 ─────────────────────────────────────────────────────────────
    def _on_panic(self):
        if self._panic_active:
            # 해제
            self._panic_active = False
            self.panic_btn.configure(text="🚨 PANIC STOP ALL", fg_color="#FF2D2D")
            self.append_log("[PANIC] ▶ PANIC 해제됨 — 정상 모드 복귀")
            for panel in self._room_panels:
                panel.set_status("대기 중", "#555555")
                panel.append_osc("PANIC 해제 — 재개 대기")
        else:
            # 발동
            self._panic_active = True
            self.panic_btn.configure(text="⚠  PANIC 중 — 클릭하여 해제", fg_color="#880000")
            self.append_log("[PANIC] 🚨 PANIC STOP ALL 발동! 모든 룸 오디오 정지 명령 전송")
            self.append_log("[PANIC] OSC → /panic/all  1")
            for panel in self._room_panels:
                panel.set_status("⛔ PANIC 정지", "#FF2D2D")
                panel.append_osc("🚨 PANIC 수신 — 오디오 정지")
                panel.set_bgm("── 정지됨 ──")

    # ── 공개 API: 시스템 로그 추가 ────────────────────────────────────────────────
    def append_log(self, message: str):
        # UI 스레드 안전 호출
        def _write():
            self.log_box.configure(state="normal")
            self.log_box.insert("end", f"[{ts()}]  {message}\n")
            self.log_box.see("end")
            self.log_box.configure(state="disabled")

        # 메인 스레드 여부 확인
        if threading.current_thread() is threading.main_thread():
            _write()
        else:
            self.after(0, _write)

    # ── 로그 지우기 ───────────────────────────────────────────────────────────────
    def _clear_log(self):
        self.log_box.configure(state="normal")
        self.log_box.delete("1.0", "end")
        self.log_box.configure(state="disabled")
        self.append_log("[INFO] 로그 클리어됨")

    # ── 시계 업데이트 (UI 스레드, after 반복) ─────────────────────────────────────
    def _tick_clock(self):
        now = datetime.now().strftime("%Y-%m-%d  %H:%M:%S")
        self.clock_label.configure(text=now)
        self.after(1000, self._tick_clock)

    # ── 공개 API: OSC/Audio 상태 텍스트 갱신 ──────────────────────────────────────
    def set_osc_status(self, text: str, color: str = "#00FF88"):
        self.osc_status_label.configure(text=f"📡  OSC  — {text}", text_color=color)

    def set_audio_status(self, text: str, color: str = "#00FF88"):
        self.audio_status_label.configure(
            text=f"🔧  Audio Engine  — {text}", text_color=color
        )


# ══════════════════════════════════════════════════════════════════════════════
# 진입점
# ══════════════════════════════════════════════════════════════════════════════
def main():
    cfg = load_config()
    app = ArtmosApp(cfg)
    app.mainloop()


if __name__ == "__main__":
    main()
