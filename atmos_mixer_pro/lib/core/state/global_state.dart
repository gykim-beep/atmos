import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atmos_mixer_pro/src/rust/api/simple.dart' as rust_api;
import 'package:atmos_mixer_pro/src/rust/common/config.dart';

import 'package:path_provider/path_provider.dart';

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

class ChannelPairConfig {
  final int pairIndex; // 0-based. pair 0 is ch 1 & 2.
  final String name1;
  final String name2;
  final bool isStereo;
  final bool active1; // ch1 active (if mono) or stereo active
  final bool active2; // ch2 active (if mono)

  ChannelPairConfig({
    required this.pairIndex,
    required this.name1,
    required this.name2,
    this.isStereo = true,
    this.active1 = false,
    this.active2 = false,
  });

  ChannelPairConfig copyWith({bool? isStereo, bool? active1, bool? active2}) {
    return ChannelPairConfig(
      pairIndex: pairIndex,
      name1: name1,
      name2: name2,
      isStereo: isStereo ?? this.isStereo,
      active1: active1 ?? this.active1,
      active2: active2 ?? this.active2,
    );
  }
}

class RoutingMatrixNotifier extends Notifier<List<ChannelPairConfig>> {
  @override
  List<ChannelPairConfig> build() {
    // Default 1 pair (2 channels) until initialized
    return List.generate(1, (i) => ChannelPairConfig(
      pairIndex: i, 
      name1: 'Ch 1',
      name2: 'Ch 2',
      isStereo: true, 
      active1: true, 
      active2: true
    ));
  }

  void initMatrix(List<String> channelNames) {
    if (channelNames.isEmpty) return;
    int pairs = (channelNames.length / 2).ceil();
    state = List.generate(pairs, (i) {
      String n1 = i * 2 < channelNames.length ? channelNames[i * 2] : 'Ch ${i * 2 + 1}';
      String n2 = i * 2 + 1 < channelNames.length ? channelNames[i * 2 + 1] : 'Ch ${i * 2 + 2}';
      
      // Preserve existing active states if possible
      if (i < state.length) {
        return ChannelPairConfig(
          pairIndex: i,
          name1: n1,
          name2: n2,
          isStereo: state[i].isStereo,
          active1: state[i].active1,
          active2: state[i].active2,
        );
      }
      // Default new channels to off
      return ChannelPairConfig(
        pairIndex: i, 
        name1: n1,
        name2: n2,
        isStereo: true, 
        active1: false, 
        active2: false
      );
    });
  }

  void toggleStereoLink(int pairIndex) {
    final newState = [...state];
    final current = newState[pairIndex];
    newState[pairIndex] = current.copyWith(
      isStereo: !current.isStereo,
      // If switching to stereo, align active2 with active1
      active2: !current.isStereo ? current.active1 : current.active2
    );
    state = newState;
  }

  void toggleActive(int pairIndex, {bool isCh2 = false}) {
    final newState = [...state];
    final current = newState[pairIndex];
    if (current.isStereo) {
      // Toggle both
      newState[pairIndex] = current.copyWith(
        active1: !current.active1,
        active2: !current.active1
      );
    } else {
      if (isCh2) {
        newState[pairIndex] = current.copyWith(active2: !current.active2);
      } else {
        newState[pairIndex] = current.copyWith(active1: !current.active1);
      }
    }
    state = newState;
  }
  
  List<String> get activeChannelLabels {
    final labels = <String>[];
    for (var p in state) {
      if (p.isStereo && p.active1) {
        labels.add('${p.name1}/${p.name2}');
      } else if (!p.isStereo) {
        if (p.active1) labels.add(p.name1);
        if (p.active2) labels.add(p.name2);
      }
    }
    return labels;
  }
}

final routingMatrixProvider = NotifierProvider<RoutingMatrixNotifier, List<ChannelPairConfig>>(RoutingMatrixNotifier.new);


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
    Set<String>? clearedRoomIds,
    bool? duckingActive,
    bool? themeStarted,
    List<String>? playingTrackIds,
  }) {
    return EngineState(
      activeRoomId: activeRoomId ?? this.activeRoomId,
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
        duckingActive: update.duckingActive,
        playingTrackIds: update.playingTrackIds,
      );
    });

    return EngineState();
  }

  void setActiveRoom(String roomId) {
    state = state.copyWith(activeRoomId: roomId);
  }

  void clearActiveRoom() {
    state = EngineState(
      activeRoomId: null,
      clearedRoomIds: state.clearedRoomIds,
      duckingActive: state.duckingActive,
      themeStarted: state.themeStarted,
      playingTrackIds: state.playingTrackIds,
    );
  }

  void clearRoom(String roomId) {
    final newCleared = Set<String>.from(state.clearedRoomIds)..add(roomId);
    state = state.copyWith(clearedRoomIds: newCleared);
  }
  
  void startTheme(String firstRoomId) {
    state = EngineState(themeStarted: true, activeRoomId: firstRoomId, clearedRoomIds: {});
  }

  void reset() {
    state = EngineState();
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
