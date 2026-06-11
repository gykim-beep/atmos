import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/colors.dart';
import '../../../core/state/global_state.dart';
import 'track_card.dart';

class RoomCard extends StatelessWidget {
  final int roomId;

  const RoomCard({super.key, required this.roomId});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<GlobalState>();
    final isLocked = state.lockedRoomIds.contains(roomId);
    final isActive = state.activeRoomId == roomId;

    return Container(
      width: 350,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: AtmosColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? AtmosColors.neonCyan : Colors.white10,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Room $roomId", style: TextStyle(color: isActive ? AtmosColors.neonCyan : Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        const Icon(Icons.volume_up, color: Colors.white54, size: 16),
                        SizedBox(
                          width: 80,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.white54,
                              inactiveTrackColor: Colors.black45,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              trackHeight: 2,
                            ),
                            child: Slider(
                              value: 1.0,
                              onChanged: isLocked ? null : (val) {},
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Tracks List
                Expanded(
                  child: ListView.builder(
                    itemCount: 2, // Dummy tracks
                    itemBuilder: (context, index) {
                      return TrackCard(trackIndex: index);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Footer Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AtmosColors.buttonAdd,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text("Add Audio"),
                      onPressed: isLocked ? null : () {},
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AtmosColors.buttonStart,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: isLocked ? null : () {
                        // Room Clear
                        state.setActiveRoom(roomId + 1);
                        state.setRoomLocked(roomId, true);
                        state.setRoomLocked(roomId + 1, false);
                      },
                      child: const Text("Room Clear"),
                    ),
                  ],
                )
              ],
            ),
          ),
          
          // Locked Overlay
          if (isLocked)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock, color: Colors.white54, size: 48),
                    SizedBox(height: 8),
                    Text(
                      "🔒 잠금 — 이전 룸을 클리어하세요",
                      style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
