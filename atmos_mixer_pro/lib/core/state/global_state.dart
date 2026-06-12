import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atmos_mixer_pro/src/rust/api/simple.dart' as rust_api;
import 'package:atmos_mixer_pro/src/rust/common/config.dart';

class ConfigNotifier extends Notifier<AppConfig?> {
  @override
  AppConfig? build() {
    loadConfig();
    return null;
  }

  void loadConfig() async {
    final config = await rust_api.apiGetConfig(path: "config.json");
    state = config;
  }

  void saveConfig(AppConfig newConfig) async {
    await rust_api.apiSaveConfig(path: "config.json", config: newConfig);
    state = newConfig;
    await rust_api.apiStartOscListener(port: newConfig.oscPort, config: newConfig);
  }
}

final configProvider = NotifierProvider<ConfigNotifier, AppConfig?>(ConfigNotifier.new);

class ChannelPairConfig {
  final int pairIndex; // 0-based. pair 0 is ch 1 & 2.
  final bool isStereo;
  final bool active1; // ch1 active (if mono) or stereo active
  final bool active2; // ch2 active (if mono)

  ChannelPairConfig({
    required this.pairIndex,
    this.isStereo = true,
    this.active1 = false,
    this.active2 = false,
  });

  ChannelPairConfig copyWith({bool? isStereo, bool? active1, bool? active2}) {
    return ChannelPairConfig(
      pairIndex: pairIndex,
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
      isStereo: true, 
      active1: true, 
      active2: true
    ));
  }

  void initMatrix(int totalChannels) {
    if (totalChannels <= 0) return;
    int pairs = totalChannels ~/ 2;
    state = List.generate(pairs, (i) {
      // Preserve existing active states if possible
      if (i < state.length) return state[i];
      // Default new channels to off
      return ChannelPairConfig(
        pairIndex: i, 
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
  
  // List of active channel labels (e.g. "1/2", "3", "4")
  List<String> get activeChannelLabels {
    final labels = <String>[];
    for (var p in state) {
      int c1 = p.pairIndex * 2 + 1;
      int c2 = p.pairIndex * 2 + 2;
      if (p.isStereo && p.active1) {
        labels.add('$c1/$c2');
      } else if (!p.isStereo) {
        if (p.active1) labels.add('$c1');
        if (p.active2) labels.add('$c2');
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

  EngineState({this.activeRoomId, this.clearedRoomIds = const {}, this.duckingActive = false});

  EngineState copyWith({String? activeRoomId, Set<String>? clearedRoomIds, bool? duckingActive}) {
    return EngineState(
      activeRoomId: activeRoomId ?? this.activeRoomId,
      clearedRoomIds: clearedRoomIds ?? this.clearedRoomIds,
      duckingActive: duckingActive ?? this.duckingActive,
    );
  }
}

class EngineStateNotifier extends Notifier<EngineState> {
  @override
  EngineState build() {
    // Listen to config changes to set initial active room if not set
    ref.listen(configProvider, (previous, next) {
      if (next != null && next.rooms.isNotEmpty && state.activeRoomId == null) {
        state = state.copyWith(activeRoomId: next.rooms.first.id);
      }
    });
    
    // Subscribe to rust_api.apiCreateEngineStateStream()
    rust_api.apiCreateEngineStateStream().listen((update) {
      state = state.copyWith(
        activeRoomId: update.activeRoomId,
        duckingActive: update.duckingActive,
      );
    });

    return EngineState();
  }

  void setActiveRoom(String roomId) {
    state = state.copyWith(activeRoomId: roomId);
  }

  void clearRoom(String roomId) {
    final newCleared = Set<String>.from(state.clearedRoomIds)..add(roomId);
    state = state.copyWith(clearedRoomIds: newCleared);
  }
  
  void reset() {
    final config = ref.read(configProvider);
    state = EngineState(activeRoomId: config?.rooms.firstOrNull?.id);
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
