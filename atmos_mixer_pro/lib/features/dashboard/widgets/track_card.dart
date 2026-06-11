import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';

class TrackCard extends StatelessWidget {
  final int trackIndex;
  
  const TrackCard({super.key, required this.trackIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AtmosColors.trackCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, color: Colors.white54, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: "Track $trackIndex",
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AtmosColors.deleteRed, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.play_circle_fill, color: AtmosColors.neonCyan),
                onPressed: () {},
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AtmosColors.neonCyan,
                    inactiveTrackColor: Colors.black45,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    trackHeight: 2,
                  ),
                  child: Slider(
                    value: 0.8,
                    onChanged: (val) {},
                  ),
                ),
              ),
              const Text("Out: 1", style: TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
          Row(
            children: [
              const Text("Loop (BGM)", style: TextStyle(color: Colors.white54, fontSize: 10)),
              Switch(
                value: trackIndex % 2 == 0,
                activeThumbColor: AtmosColors.neonCyan,
                onChanged: (val) {},
              ),
            ],
          )
        ],
      ),
    );
  }
}
