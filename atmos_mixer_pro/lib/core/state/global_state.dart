import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atmos_mixer_pro/src/rust/api/simple.dart' as rust_api;
import 'package:atmos_mixer_pro/src/rust/common/config.dart';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String> _getConfigPath() async {
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}/config.json';
}

class ConfigNotifier extends Notifier<AppConfig?> {
  @override
  AppConfig? build() {
    loadConfig();
    return null;
  }

  void loadConfig() async {
    try {
      final path = await _getConfigPath();
      final config = await rust_api.apiGetConfig(path: path);
      try {
        await rust_api.apiPreloadAllSounds(config: config);
      } catch (e) {
        // Ignore initial preload errors
      }
      state = config;
      await rust_api.apiStartOscListener(port: config.oscPort);
    } catch (e) {
      ref.read(globalErrorProvider.notifier).showError('설정 로드 실패: $e');
    }
  }

  void saveConfig(AppConfig newConfig) async {
    // Optimistic UI Update: immediately set state so UI reflects the added track
    state = newConfig;
    
    try {
      final path = await _getConfigPath();
      await rust_api.apiSaveConfig(path: path, config: newConfig);
      try {
        await rust_api.apiPreloadAllSounds(config: newConfig);
      } catch (e) {
        // Ignore preload errors, keep UI responsive
      }
      await rust_api.apiStartOscListener(port: newConfig.oscPort);
    } catch (e) {
      ref.read(globalErrorProvider.notifier).showError('설정 저장 실패: $e');
    }
  }
}

final configProvider = NotifierProvider<ConfigNotifier, AppConfig?>(ConfigNotifier.new);

final hardwareChannelsProvider = FutureProvider<List<String>>((ref) async {
  final config = ref.watch(configProvider);
  if (config == null || config.deviceName == null || config.deviceName!.isEmpty) return [];
  try {
    return await rust_api.apiGetDeviceChannelNames(deviceName: config.deviceName!);
  } catch (e) {
    return [];
  }
});

class LogNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    _initStream();
    return [];
  }

  void _initStream() {
    final stream = rust_api.apiCreateLogStream();
    stream.listen((log) {
      final newList = List<String>.from(state)..add(log);
      if (newList.length > 100) {
        newList.removeAt(0);
      }
      state = newList;
    });
  }

  void clearLogs() {
    state = [];
  }
}

final logProvider = NotifierProvider<LogNotifier, List<String>>(LogNotifier.new);

class EngineState {
  final String? activeRoomId;
  final Set<String> clearedRoomIds;
  final bool duckingActive;
  final bool themeStarted;
  final List<String> playingTrackIds;

  EngineState({
    this.activeRoomId,
    this.clearedRoomIds = const {},
    this.duckingActive = false,
    this.themeStarted = false,
    this.playingTrackIds = const [],
  });

  EngineState copyWith({
    String? activeRoomId,
    bool forceNullActiveRoom = false,
    Set<String>? clearedRoomIds,
    bool? duckingActive,
    bool? themeStarted,
    List<String>? playingTrackIds,
  }) {
    return EngineState(
      activeRoomId: forceNullActiveRoom ? null : (activeRoomId ?? this.activeRoomId),
      clearedRoomIds: clearedRoomIds ?? this.clearedRoomIds,
      duckingActive: duckingActive ?? this.duckingActive,
      themeStarted: themeStarted ?? this.themeStarted,
      playingTrackIds: playingTrackIds ?? this.playingTrackIds,
    );
  }
}

class EngineStateNotifier extends Notifier<EngineState> {
  @override
  EngineState build() {
    // Subscribe to rust_api.apiCreateEngineStateStream()
    rust_api.apiCreateEngineStateStream().listen((update) {
      state = state.copyWith(
        activeRoomId: update.activeRoomId,
        forceNullActiveRoom: update.activeRoomId == null,
        duckingActive: update.duckingActive,
        playingTrackIds: update.playingTrackIds,
      );
    });

    return EngineState();
  }

  Future<void> setActiveRoom(String roomId) async {
    try {
      await rust_api.apiSetActiveRoom(roomId: roomId);
    } catch (e) {
      // Ignored or handled elsewhere
    }
  }

  Future<void> clearActiveRoom() async {
    try {
      await rust_api.apiSetActiveRoom(roomId: null);
    } catch (e) {
      // ignored
    }
  }

  void clearRoom(String roomId) {
    final newCleared = Set<String>.from(state.clearedRoomIds)..add(roomId);
    state = state.copyWith(clearedRoomIds: newCleared);
  }
  
  Future<void> startTheme(String firstRoomId) async {
    state = state.copyWith(themeStarted: true, clearedRoomIds: {});
    try {
      await rust_api.apiSetActiveRoom(roomId: firstRoomId);
    } catch (e) {
      // ignored
    }
  }

  void reset() {
    state = state.copyWith(themeStarted: false, clearedRoomIds: {});
  }
}

final engineStateProvider = NotifierProvider<EngineStateNotifier, EngineState>(EngineStateNotifier.new);

class GlobalErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void showError(String message) {
    state = message;
  }

  void clearError() {
    state = null;
  }
}

final globalErrorProvider = NotifierProvider<GlobalErrorNotifier, String?>(GlobalErrorNotifier.new);

class OutputConfigState {
  final Set<int> monoChannels;
  final Set<int> stereoChannels; // Storing the first channel index of the pair

  OutputConfigState({
    this.monoChannels = const {},
    this.stereoChannels = const {},
  });

  OutputConfigState copyWith({
    Set<int>? monoChannels,
    Set<int>? stereoChannels,
  }) {
    return OutputConfigState(
      monoChannels: monoChannels ?? this.monoChannels,
      stereoChannels: stereoChannels ?? this.stereoChannels,
    );
  }
}

class OutputConfigNotifier extends Notifier<OutputConfigState> {
  @override
  OutputConfigState build() {
    _load();
    return OutputConfigState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final monoList = prefs.getStringList('output_config_mono') ?? [];
    final stereoList = prefs.getStringList('output_config_stereo') ?? [];
    
    state = OutputConfigState(
      monoChannels: monoList.map(int.parse).toSet(),
      stereoChannels: stereoList.map(int.parse).toSet(),
    );
  }

  Future<void> save(Set<int> mono, Set<int> stereo) async {
    state = OutputConfigState(monoChannels: mono, stereoChannels: stereo);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('output_config_mono', mono.map((e) => e.toString()).toList());
    await prefs.setStringList('output_config_stereo', stereo.map((e) => e.toString()).toList());
  }
}

final outputConfigProvider = NotifierProvider<OutputConfigNotifier, OutputConfigState>(OutputConfigNotifier.new);
