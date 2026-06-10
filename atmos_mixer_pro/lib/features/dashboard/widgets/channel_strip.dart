import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import 'vu_meter.dart';

class ChannelStrip extends StatelessWidget {
  final int index;

  const ChannelStrip({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text("CH ${index + 1}", style: const TextStyle(color: AtmosColors.neonCyan, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // VU Meter
              Container(
                width: 24,
                decoration: BoxDecoration(
                  border: Border.all(color: AtmosColors.neonCyan.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const VuMeter(level: 0.5), // Placeholder level
              ),
              const SizedBox(width: 8),
              // Fader
              RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AtmosColors.neonCyan,
                    inactiveTrackColor: Colors.black45,
                    thumbColor: AtmosColors.textMain,
                    trackHeight: 8.0,
                  ),
                  child: Slider(
                    value: 0.8, // Placeholder
                    onChanged: (val) {},
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Mute / Solo buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildMiniBtn("M", Colors.redAccent),
            const SizedBox(width: 4),
            _buildMiniBtn("S", Colors.amber),
          ],
        )
      ],
    );
  }

  Widget _buildMiniBtn(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black45,
        border: Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
