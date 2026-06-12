import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atmos_mixer_pro/core/theme/colors.dart';
import 'package:atmos_mixer_pro/core/state/global_state.dart';
import 'package:atmos_mixer_pro/src/rust/common/config.dart';
import 'package:atmos_mixer_pro/src/rust/api/simple.dart' as rust_api;
class PreferencesModal extends ConsumerStatefulWidget {
  const PreferencesModal({super.key});

  @override
  ConsumerState<PreferencesModal> createState() => _PreferencesModalState();
}

class _PreferencesModalState extends ConsumerState<PreferencesModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late AppConfig _tempConfig;
  List<String> _devices = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // clone config for editing
    final currentConfig = ref.read(configProvider);
    _tempConfig = currentConfig != null ? cloneConfig(currentConfig) : AppConfig(
      oscPort: 8000,
      bufferSize: 256,
      rooms: [],
    );
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final deviceInfos = await rust_api.apiGetOutputDevices();
      final devices = deviceInfos.map((d) => d.name).toList();
      setState(() {
        _devices = devices;
      });
      _loadDeviceChannels(_tempConfig.deviceName);
    } catch (e) {
      if (mounted) {
        ref.read(globalErrorProvider.notifier).showError('장치 스캔 실패: $e');
      }
    }
  }

  Future<void> _loadDeviceChannels(String? deviceName) async {
    if (deviceName == null) {
      ref.read(routingMatrixProvider.notifier).initMatrix(2); // Default
      return;
    }
    try {
      final channels = await rust_api.apiGetDeviceChannelCount(deviceName: deviceName);
      ref.read(routingMatrixProvider.notifier).initMatrix(channels);
    } catch (e) {
      ref.read(globalErrorProvider.notifier).showError('채널 탐색 실패: $e');
    }
  }

  // Very basic deep clone for editing
  AppConfig cloneConfig(AppConfig config) {
    return AppConfig(
      oscPort: config.oscPort,
      deviceName: config.deviceName,
      bufferSize: config.bufferSize,
      rooms: config.rooms.map((r) => RoomConfig(
        id: r.id,
        name: r.name,
        colorHex: r.colorHex,
        volume: r.volume,
        clearOscAddress: r.clearOscAddress,
        tracks: r.tracks.map((t) => TrackConfig(
          id: t.id,
          name: t.name,
          filePath: t.filePath,
          volume: t.volume,
          isLoop: t.isLoop,
          outputChannel: t.outputChannel,
          playOscAddress: t.playOscAddress,
          stopOscAddress: t.stopOscAddress,
        )).toList(),
      )).toList(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _saveAndClose() {
    ref.read(configProvider.notifier).saveConfig(_tempConfig);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.headerBackground,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text('환경설정 (Preferences)', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            
            // Tab Bar
            TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primaryBlue,
              labelColor: AppColors.primaryBlue,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: '오디오 출력 설정 (Audio Routing)'),
                Tab(text: '룸별 신호 및 라우팅 설정 (OSC/Arduino)'),
              ],
            ),
            
            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAudioTab(),
                  _buildOscTab(),
                ],
              ),
            ),
            
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.darkGrey)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('취소', style: TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                    onPressed: _saveAndClose,
                    child: const Text('저장 후 닫기', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('하드웨어 오디오 인터페이스', style: TextStyle(color: AppColors.primaryNeon, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _tempConfig.deviceName,
                  dropdownColor: AppColors.cardSurface,
                  decoration: const InputDecoration(filled: true, fillColor: AppColors.cardSurface, border: OutlineInputBorder()),
                  hint: const Text('디바이스 선택 (Select Device)', style: TextStyle(color: Colors.white54)),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('기본 오디오 출력 (Default)')),
                    ..._devices.map((d) => DropdownMenuItem(value: d, child: Text(d))),
                  ],
                  onChanged: (val) {
                    setState(() { 
                      _tempConfig = AppConfig(
                        oscPort: _tempConfig.oscPort,
                        deviceName: val,
                        bufferSize: _tempConfig.bufferSize,
                        rooms: _tempConfig.rooms,
                      ); 
                    });
                    _loadDeviceChannels(val);
                  },
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<int>(
                  initialValue: _tempConfig.bufferSize,
                  dropdownColor: AppColors.cardSurface,
                  decoration: const InputDecoration(filled: true, fillColor: AppColors.cardSurface, border: OutlineInputBorder()),
                  items: [64, 128, 256, 512, 1024].map((e) => DropdownMenuItem(value: e, child: Text('$e samples'))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() { 
                        _tempConfig = AppConfig(
                          oscPort: _tempConfig.oscPort,
                          deviceName: _tempConfig.deviceName,
                          bufferSize: val,
                          rooms: _tempConfig.rooms,
                        ); 
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildChannelMatrix(),
          const SizedBox(height: 24),
          const Text('1:1 스피커 매핑 (Track Routing)', style: TextStyle(color: AppColors.primaryNeon, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _tempConfig.rooms.length,
              itemBuilder: (context, rIndex) {
                final room = _tempConfig.rooms[rIndex];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Text('■ ${room.name}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    ),
                    ...room.tracks.asMap().entries.map((entry) {
                      final tIndex = entry.key;
                      final track = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 8),
                        child: Row(
                          children: [
                            Expanded(child: Text(track.name, style: const TextStyle(color: Colors.white))),
                            const Text('👉 Output Ch.', style: TextStyle(color: Colors.white54)),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              child: TextFormField(
                                initialValue: track.outputChannel.toString(),
                                style: const TextStyle(color: Colors.white),
                                decoration: const InputDecoration(isDense: true, filled: true, fillColor: AppColors.cardSurface),
                                keyboardType: TextInputType.number,
                                onChanged: (val) {
                                  final num = int.tryParse(val);
                                  if (num != null && num > 0 && num <= 24) {
                                    final newRooms = List<RoomConfig>.from(_tempConfig.rooms);
                                    final newTracks = List<TrackConfig>.from(newRooms[rIndex].tracks);
                                    newTracks[tIndex] = TrackConfig(
                                      id: track.id, name: track.name, filePath: track.filePath, volume: track.volume, isLoop: track.isLoop,
                                      outputChannel: num, playOscAddress: track.playOscAddress, stopOscAddress: track.stopOscAddress,
                                    );
                                    newRooms[rIndex] = RoomConfig(
                                      id: room.id, name: room.name, colorHex: room.colorHex, volume: room.volume, clearOscAddress: room.clearOscAddress, tracks: newTracks,
                                    );
                                    setState(() {
                                      _tempConfig = AppConfig(oscPort: _tempConfig.oscPort, deviceName: _tempConfig.deviceName, bufferSize: _tempConfig.bufferSize, rooms: newRooms);
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    })
                  ],
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildOscTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('OSC 네트워크 서버 설정', style: TextStyle(color: AppColors.primaryNeon, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('수신 포트 (Port): ', style: TextStyle(color: Colors.white)),
              SizedBox(
                width: 100,
                child: TextFormField(
                  initialValue: _tempConfig.oscPort.toString(),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(isDense: true, filled: true, fillColor: AppColors.cardSurface),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final p = int.tryParse(val);
                    if (p != null) {
                      setState(() { 
                        _tempConfig = AppConfig(
                          oscPort: p,
                          deviceName: _tempConfig.deviceName,
                          bufferSize: _tempConfig.bufferSize,
                          rooms: _tempConfig.rooms,
                        ); 
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('룸 클리어 및 트랙 트리거 주소 매핑', style: TextStyle(color: AppColors.primaryNeon, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _tempConfig.rooms.length,
              itemBuilder: (context, rIndex) {
                final room = _tempConfig.rooms[rIndex];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.cardSurface, borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('■ ${room.name} 센서 매핑', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const SizedBox(width: 80, child: Text('룸 클리어', style: TextStyle(color: AppColors.brown, fontWeight: FontWeight.bold))),
                          Expanded(
                            child: TextFormField(
                              initialValue: room.clearOscAddress,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(isDense: true, hintText: '예: /room1/clear'),
                              onChanged: (val) {
                                final newRooms = List<RoomConfig>.from(_tempConfig.rooms);
                                newRooms[rIndex] = RoomConfig(
                                  id: room.id, name: room.name, colorHex: room.colorHex, volume: room.volume, clearOscAddress: val, tracks: room.tracks,
                                );
                                setState(() {
                                  _tempConfig = AppConfig(oscPort: _tempConfig.oscPort, deviceName: _tempConfig.deviceName, bufferSize: _tempConfig.bufferSize, rooms: newRooms);
                                });
                              },
                            ),
                          )
                        ],
                      ),
                      const Divider(color: AppColors.darkGrey),
                      ...room.tracks.asMap().entries.map((entry) {
                        final tIndex = entry.key;
                        final track = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              SizedBox(width: 80, child: Text(track.name, style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: track.playOscAddress,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.play_arrow, color: Colors.green, size: 16), hintText: 'Play OSC'),
                                  onChanged: (val) {
                                    final newRooms = List<RoomConfig>.from(_tempConfig.rooms);
                                    final newTracks = List<TrackConfig>.from(newRooms[rIndex].tracks);
                                    newTracks[tIndex] = TrackConfig(
                                      id: track.id, name: track.name, filePath: track.filePath, volume: track.volume, isLoop: track.isLoop,
                                      outputChannel: track.outputChannel, playOscAddress: val, stopOscAddress: track.stopOscAddress,
                                    );
                                    newRooms[rIndex] = RoomConfig(
                                      id: room.id, name: room.name, colorHex: room.colorHex, volume: room.volume, clearOscAddress: room.clearOscAddress, tracks: newTracks,
                                    );
                                    setState(() {
                                      _tempConfig = AppConfig(oscPort: _tempConfig.oscPort, deviceName: _tempConfig.deviceName, bufferSize: _tempConfig.bufferSize, rooms: newRooms);
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: track.stopOscAddress,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.stop, color: Colors.red, size: 16), hintText: 'Stop OSC'),
                                  onChanged: (val) {
                                    final newRooms = List<RoomConfig>.from(_tempConfig.rooms);
                                    final newTracks = List<TrackConfig>.from(newRooms[rIndex].tracks);
                                    newTracks[tIndex] = TrackConfig(
                                      id: track.id, name: track.name, filePath: track.filePath, volume: track.volume, isLoop: track.isLoop,
                                      outputChannel: track.outputChannel, playOscAddress: track.playOscAddress, stopOscAddress: val,
                                    );
                                    newRooms[rIndex] = RoomConfig(
                                      id: room.id, name: room.name, colorHex: room.colorHex, volume: room.volume, clearOscAddress: room.clearOscAddress, tracks: newTracks,
                                    );
                                    setState(() {
                                      _tempConfig = AppConfig(oscPort: _tempConfig.oscPort, deviceName: _tempConfig.deviceName, bufferSize: _tempConfig.bufferSize, rooms: newRooms);
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      })
                    ],
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildChannelMatrix() {
    final matrixState = ref.watch(routingMatrixProvider);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('오디오 채널 매트릭스 (출력 활성화)', style: TextStyle(color: AppColors.primaryNeon, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          height: 180, // Constrained height for scrolling
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.darkGrey),
          ),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              childAspectRatio: 1.5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: matrixState.length,
            itemBuilder: (context, index) {
              final pair = matrixState[index];
              final ch1 = pair.pairIndex * 2 + 1;
              final ch2 = pair.pairIndex * 2 + 2;
              
              return Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.darkGrey),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    // Link toggle
                    InkWell(
                      onTap: () => ref.read(routingMatrixProvider.notifier).toggleStereoLink(pair.pairIndex),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        decoration: const BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
                        ),
                        child: Icon(
                          pair.isStereo ? Icons.link : Icons.link_off,
                          size: 14,
                          color: pair.isStereo ? AppColors.primaryNeon : Colors.white54,
                        ),
                      ),
                    ),
                    Expanded(
                      child: pair.isStereo
                          ? _buildToggleButton(
                              label: '$ch1/$ch2',
                              isActive: pair.active1,
                              onTap: () => ref.read(routingMatrixProvider.notifier).toggleActive(pair.pairIndex),
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: _buildToggleButton(
                                    label: '$ch1',
                                    isActive: pair.active1,
                                    onTap: () => ref.read(routingMatrixProvider.notifier).toggleActive(pair.pairIndex),
                                  ),
                                ),
                                Container(width: 1, color: AppColors.darkGrey),
                                Expanded(
                                  child: _buildToggleButton(
                                    label: '$ch2',
                                    isActive: pair.active2,
                                    onTap: () => ref.read(routingMatrixProvider.notifier).toggleActive(pair.pairIndex, isCh2: true),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToggleButton({required String label, required bool isActive, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryNeon.withValues(alpha: 0.2) : Colors.transparent,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? AppColors.primaryNeon : Colors.white54,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
