import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/glass_container.dart';

class RoomCard extends StatelessWidget {
  final int roomId;

  const RoomCard({super.key, required this.roomId});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Room $roomId", style: const TextStyle(color: AtmosColors.neonMagenta, fontWeight: FontWeight.bold)),
                const Icon(Icons.volume_up, color: AtmosColors.textDim, size: 16),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AtmosColors.neonMagenta,
                    inactiveTrackColor: Colors.black45,
                    thumbColor: AtmosColors.textMain,
                    trackHeight: 6.0,
                  ),
                  child: Slider(
                    value: 1.0,
                    onChanged: (val) {},
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.2),
                border: Border.all(color: Colors.redAccent),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text("MUTE", style: TextStyle(color: Colors.redAccent, fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }
}
