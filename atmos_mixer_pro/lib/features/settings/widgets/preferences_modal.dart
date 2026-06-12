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
  List<String> _channelNames = [];

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
      setState(() {
        _channelNames = ['Ch 1', 'Ch 2'];
      });
      ref.read(routingMatrixProvider.notifier).initMatrix(_channelNames);
      return;
    }
    try {
      final channelNames = await rust_api.apiGetDeviceChannelNames(deviceName: deviceName);
      setState(() {
        _channelNames = channelNames;
      });
      ref.read(routingMatrixProvider.notifier).initMatrix(_channelNames);
    } catch (e) {
      if (mounted) {
        ref.read(globalErrorProvider.notifier).showError('채널 탐색 실패: $e');
      }
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
          outputStereo: t.outputStereo,
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
        width: 800,
        height: 700,
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
    final List<DropdownMenuItem<int>> channelItems = [];
    for (int i = 0; i < _channelNames.length; i++) {
      channelItems.add(DropdownMenuItem(value: i + 1, child: Text('${i + 1}: ${_channelNames[i]}', overflow: TextOverflow.ellipsis)));
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text('하드웨어 오디오 인터페이스', style: TextStyle(color: AppColors.primaryNeon, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _tempConfig.deviceName,
                dropdownColor: AppColors.cardSurfaceSolid,
                decoration: const InputDecoration(filled: true, fillColor: AppColors.cardSurface, border: OutlineInputBorder()),
                hint: const Text('디바이스 선택 (Select Device)', style: TextStyle(color: Colors.white54)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('기본 오디오 출력 (Default)')),
                  ..._devices.map((d) => DropdownMenuItem(value: d, child: Text(d))),
                  if (_tempConfig.deviceName != null && !_devices.contains(_tempConfig.deviceName))
                    DropdownMenuItem(value: _tempConfig.deviceName, child: Text('${_tempConfig.deviceName} (Disconnected)')),
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
            Expanded(
              flex: 1,
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _tempConfig.bufferSize,
                dropdownColor: AppColors.cardSurfaceSolid,
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
        const Text('출력 채널 구성 (Channel Config)', style: TextStyle(color: AppColors.primaryNeon, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.cardSurface, borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: ref.watch(routingMatrixProvider).map((pair) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    // Mono 1
                    Expanded(
                      child: InkWell(
                        onTap: pair.isStereo ? null : () => ref.read(routingMatrixProvider.notifier).toggleActive(pair.pairIndex, isCh2: false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          decoration: BoxDecoration(
                            color: pair.isStereo ? AppColors.darkGrey.withValues(alpha: 0.3) : (pair.active1 ? AppColors.primaryNeon.withValues(alpha: 0.3) : AppColors.background),
                            border: Border.all(color: pair.active1 && !pair.isStereo ? AppColors.primaryNeon : AppColors.darkGrey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Mono: ${pair.name1}', textAlign: TextAlign.center, style: TextStyle(color: pair.isStereo ? Colors.white30 : Colors.white)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Mono 2
                    Expanded(
                      child: InkWell(
                        onTap: pair.isStereo ? null : () => ref.read(routingMatrixProvider.notifier).toggleActive(pair.pairIndex, isCh2: true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          decoration: BoxDecoration(
                            color: pair.isStereo ? AppColors.darkGrey.withValues(alpha: 0.3) : (pair.active2 ? AppColors.primaryNeon.withValues(alpha: 0.3) : AppColors.background),
                            border: Border.all(color: pair.active2 && !pair.isStereo ? AppColors.primaryNeon : AppColors.darkGrey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Mono: ${pair.name2}', textAlign: TextAlign.center, style: TextStyle(color: pair.isStereo ? Colors.white30 : Colors.white)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Link button
                    IconButton(
                      icon: Icon(pair.isStereo ? Icons.link : Icons.link_off),
                      color: pair.isStereo ? AppColors.primaryBlue : Colors.white54,
                      onPressed: () => ref.read(routingMatrixProvider.notifier).toggleStereoLink(pair.pairIndex),
                    ),
                    const SizedBox(width: 8),
                    // Stereo
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: !pair.isStereo ? null : () => ref.read(routingMatrixProvider.notifier).toggleActive(pair.pairIndex),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          decoration: BoxDecoration(
                            color: !pair.isStereo ? AppColors.darkGrey.withValues(alpha: 0.3) : (pair.active1 ? AppColors.primaryBlue.withValues(alpha: 0.3) : AppColors.background),
                            border: Border.all(color: pair.active1 && pair.isStereo ? AppColors.primaryBlue : AppColors.darkGrey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Stereo: ${pair.name1}/${pair.name2}', textAlign: TextAlign.center, style: TextStyle(color: !pair.isStereo ? Colors.white30 : Colors.white)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),
        const Text('1:1 스피커 매핑 (Track Routing)', style: TextStyle(color: AppColors.primaryNeon, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._tempConfig.rooms.asMap().entries.map((rEntry) {
          final rIndex = rEntry.key;
          final room = rEntry.value;
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
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<int>(
                          initialValue: channelItems.any((item) => item.value == track.outputChannel) ? track.outputChannel : null,
                          dropdownColor: AppColors.cardSurfaceSolid,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true, filled: true, fillColor: AppColors.cardSurface, border: OutlineInputBorder()),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          items: [
                            ...channelItems,
                            if (!channelItems.any((item) => item.value == track.outputChannel))
                              DropdownMenuItem(value: track.outputChannel, child: Text('${track.outputChannel} (Missing)', overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              final newRooms = List<RoomConfig>.from(_tempConfig.rooms);
                              final newTracks = List<TrackConfig>.from(newRooms[rIndex].tracks);
                              newTracks[tIndex] = TrackConfig(
                                id: track.id,
                                name: track.name,
                                filePath: track.filePath,
                                volume: track.volume,
                                isLoop: track.isLoop,
                                outputChannel: val,
                                outputStereo: track.outputStereo,
                                playOscAddress: track.playOscAddress,
                                stopOscAddress: track.stopOscAddress,
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
        }),
      ],
    );
  }

  Widget _buildOscTab() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text('룸 클리어 및 트랙 트리거 주소 매핑', style: TextStyle(color: AppColors.primaryNeon, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._tempConfig.rooms.asMap().entries.map((rEntry) {
          final rIndex = rEntry.key;
          final room = rEntry.value;
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
                                id: track.id,
                                name: track.name,
                                filePath: track.filePath,
                                volume: track.volume,
                                isLoop: track.isLoop,
                                outputChannel: track.outputChannel,
                                outputStereo: track.outputStereo,
                                playOscAddress: val,
                                stopOscAddress: track.stopOscAddress,
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
                                outputChannel: track.outputChannel, outputStereo: track.outputStereo, playOscAddress: track.playOscAddress, stopOscAddress: val,
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
        }),
        const SizedBox(height: 24),
        const Divider(color: AppColors.darkGrey),
        const SizedBox(height: 16),
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
      ],
    );
  }


}
