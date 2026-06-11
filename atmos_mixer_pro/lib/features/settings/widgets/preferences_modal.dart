import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';

class PreferencesModal extends StatefulWidget {
  const PreferencesModal({super.key});

  @override
  State<PreferencesModal> createState() => _PreferencesModalState();
}

class _PreferencesModalState extends State<PreferencesModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;



  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AtmosColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        width: 720,
        height: 560,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            // Modal Header
            Container(
              height: 50,
              color: AtmosColors.header,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("시스템 환경설정", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              indicatorColor: AtmosColors.neonCyan,
              labelColor: AtmosColors.neonCyan,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(text: "오디오 출력 설정"),
                Tab(text: "룸별 신호 및 라우팅 설정"),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAudioOutputTab(),
                  _buildArduinoOscTab(),
                ],
              ),
            ),
            // Footer
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("취소", style: TextStyle(color: Colors.white54)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AtmosColors.buttonStart,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("저장 및 적용"),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildAudioOutputTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("트랙 아웃풋 1:1 매핑", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: 10, // Dummy 10 tracks
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AtmosColors.trackCard,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Text("Room ${(index ~/ 2) + 1} - Track ${(index % 2) + 1}", style: const TextStyle(color: Colors.white)),
                      const Spacer(),
                      const Text("출력 채널:", style: TextStyle(color: Colors.white54)),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 100,
                        child: DropdownButtonFormField<int>(
                          initialValue: index + 1,
                          dropdownColor: AtmosColors.header,
                          style: const TextStyle(color: AtmosColors.neonCyan),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.all(8),
                            border: OutlineInputBorder(),
                          ),
                          items: List.generate(24, (i) => i + 1)
                              .map((i) => DropdownMenuItem(value: i, child: Text("CH $i")))
                              .toList(),
                          onChanged: (val) {},
                        ),
                      )
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

  Widget _buildArduinoOscTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text("OSC 수신 포트:", style: TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(width: 16),
              SizedBox(
                width: 100,
                child: TextFormField(
                  initialValue: "9000",
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.all(8),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text("OSC 주소 타이핑 매핑", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: 4, // Dummy rooms
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AtmosColors.trackCard,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Room ${index + 1}", style: const TextStyle(color: AtmosColors.neonCyan, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const SizedBox(
                            width: 120,
                            child: Text("클리어 신호:", style: TextStyle(color: Colors.white54)),
                          ),
                          Expanded(
                            child: TextFormField(
                              initialValue: "/room${index+1}/clear",
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.all(8),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const SizedBox(
                            width: 120,
                            child: Text("효과음 1 트리거:", style: TextStyle(color: Colors.white54)),
                          ),
                          Expanded(
                            child: TextFormField(
                              initialValue: "/room${index+1}/sfx1/play",
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.all(8),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
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
}
