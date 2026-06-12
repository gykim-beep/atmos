import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atmos_mixer_pro/core/theme/colors.dart';
import 'package:atmos_mixer_pro/core/state/global_state.dart';
import 'package:atmos_mixer_pro/features/dashboard/widgets/room_card.dart';
import 'package:atmos_mixer_pro/features/settings/widgets/preferences_modal.dart';
import 'package:atmos_mixer_pro/src/rust/api/simple.dart' as rust_api;
import 'package:atmos_mixer_pro/src/rust/common/config.dart';
import 'package:file_picker/file_picker.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(context, ref),
              Expanded(
                child: _buildRoomPanels(context, ref),
              ),
              _buildSystemLog(context, ref),
            ],
          ),
          _buildErrorBanner(),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Consumer(
      builder: (context, ref, child) {
        final error = ref.watch(globalErrorProvider);
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          top: error != null ? 0 : -100,
          left: 0,
          right: 0,
          child: Material(
            elevation: 8,
            color: Colors.transparent,
            child: Container(
              color: AppColors.danger.withValues(alpha: 0.95),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        error ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => ref.read(globalErrorProvider.notifier).clearError(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.headerBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          const Text(
            '🎛 Atmos Mixer Pro',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                onPressed: () async {
                  try {
                    await rust_api.apiStopAll();
                  } catch (e) {
                    ref.read(globalErrorProvider.notifier).showError('정지 실패: $e');
                  }
                  final config = ref.read(configProvider);
                  if (config != null && config.rooms.isNotEmpty) {
                    final firstRoom = config.rooms.first;
                    ref.read(engineStateProvider.notifier).setActiveRoom(firstRoom.id);
                    for (final track in firstRoom.tracks) {
                      if (track.isLoop) {
                        try {
                          await rust_api.apiPlayTrack(roomId: firstRoom.id, trackId: track.id);
                        } catch (e) {
                          ref.read(globalErrorProvider.notifier).showError('트랙 재생 실패: $e');
                        }
                      }
                    }
                  }
                },
                child: const Text('테마 시작', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () async {
                  try {
                    await rust_api.apiStopAll();
                  } catch (e) {
                    ref.read(globalErrorProvider.notifier).showError('비상 정지 실패: $e');
                  }
                },
                child: const Text('비상 정지', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.darkGrey),
                onPressed: () async {
                  try {
                    await rust_api.apiStopAll();
                  } catch (e) {
                    ref.read(globalErrorProvider.notifier).showError('시스템 리셋 실패: $e');
                  }
                  ref.read(logProvider.notifier).clearLogs();
                  ref.read(engineStateProvider.notifier).reset();
                },
                child: const Text('시스템 리셋', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6A1B9A)),
                onPressed: () async {
                  final config = ref.read(configProvider);
                  if (config == null) return;
                  String? outputFile = await FilePicker.saveFile(
                    dialogTitle: '설정 저장',
                    fileName: 'atmos_config_backup.json',
                    allowedExtensions: ['json'],
                    type: FileType.custom,
                  );
                  if (outputFile != null) {
                    try {
                      await rust_api.apiSaveConfig(path: outputFile, config: config);
                    } catch (e) {
                      ref.read(globalErrorProvider.notifier).showError('설정 저장 실패: $e');
                    }
                  }
                },
                child: const Text('💾 설정 보내기', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00838F)),
                onPressed: () async {
                  FilePickerResult? result = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['json'],
                  );
                  if (result != null && result.files.single.path != null) {
                    try {
                      final importedConfig = await rust_api.apiGetConfig(path: result.files.single.path!);
                      ref.read(configProvider.notifier).saveConfig(importedConfig);
                    } catch (e) {
                      ref.read(globalErrorProvider.notifier).showError('설정 불러오기 실패: $e');
                    }
                  }
                },
                child: const Text('📂 설정 불러오기', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                onPressed: () {
                  final config = ref.read(configProvider);
                  if (config != null) {
                    final palette = ['#1565C0', '#6A1B9A', '#2E7D32', '#B71C1C', '#E65100'];
                    final colorHex = palette[config.rooms.length % 5];
                    final newRoom = RoomConfig(
                      id: 'room_${DateTime.now().millisecondsSinceEpoch}',
                      name: '새로운 룸',
                      colorHex: colorHex,
                      volume: 1.0,
                      clearOscAddress: '/room/clear',
                      tracks: [],
                    );
                    final updated = AppConfig(
                      oscPort: config.oscPort,
                      deviceName: config.deviceName,
                      bufferSize: config.bufferSize,
                      rooms: [...config.rooms, newRoom],
                    );
                    ref.read(configProvider.notifier).saveConfig(updated);
                  }
                },
                child: const Text('➕ 룸 추가', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.lightGrey),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const PreferencesModal(),
                  );
                },
                child: const Text('⚙️ 환경설정', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          Consumer(builder: (context, ref, child) {
            final config = ref.watch(configProvider);
            final engineState = ref.watch(engineStateProvider);
            
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (engineState.duckingActive)
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.brown.withValues(alpha: 0.3),
                      border: Border.all(color: AppColors.brown),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '🦆 스마트 더킹 작동중',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                Text(
                  config?.deviceName ?? '기본 오디오 출력',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                const Text('[24 Output]', style: TextStyle(color: AppColors.primaryNeon)),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: '스캔',
                  onPressed: () {},
                )
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRoomPanels(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);
    if (config == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final engineState = ref.watch(engineStateProvider);

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: config.rooms.length,
      itemBuilder: (context, index) {
        final room = config.rooms[index];
        Color accentColor;
        try {
          accentColor = Color(int.parse(room.colorHex.replaceFirst('#', '0xFF')));
        } catch (e) {
          accentColor = AppColors.primaryNeon;
        }

        final isActive = engineState.activeRoomId == room.id;
        final isCleared = engineState.clearedRoomIds.contains(room.id);

        return RoomCard(
          room: room,
          isActive: isActive,
          isCleared: isCleared,
          accentColor: accentColor,
        );
      },
    );
  }

  Widget _buildSystemLog(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logProvider);
    
    return Container(
      height: 155,
      color: AppColors.logBackground,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('System Log', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () => ref.read(logProvider.notifier).clearLogs(),
                child: const Text('지우기', style: TextStyle(color: AppColors.textPrimary)),
              ),
            ],
          ),
          const Divider(color: AppColors.darkGrey),
          Expanded(
            child: ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) {
                return Text(
                  logs[index],
                  style: const TextStyle(color: AppColors.logText, fontFamily: 'monospace', fontSize: 12),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}