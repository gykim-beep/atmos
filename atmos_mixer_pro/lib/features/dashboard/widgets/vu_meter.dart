import 'package:flutter/material.dart';
import 'dart:async';
import 'package:atmos_mixer_pro/core/theme/colors.dart';
import 'package:atmos_mixer_pro/src/rust/api/simple.dart' as rust_api;

class VUMeterPainter extends CustomPainter {
  final ValueNotifier<double> levelNotifier; // 0.0 to 1.0

  VUMeterPainter(this.levelNotifier) : super(repaint: levelNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    double level = levelNotifier.value;
    final paint = Paint()
      ..style = PaintingStyle.fill;

    // Draw background segments
    int totalSegments = 20;
    double segmentHeight = (size.height - (totalSegments - 1) * 2) / totalSegments;

    for (int i = 0; i < totalSegments; i++) {
      double y = size.height - (i * (segmentHeight + 2)) - segmentHeight;
      double threshold = (i + 1) / totalSegments;

      Color color;
      if (threshold > 0.85) {
        color = Colors.red;
      } else if (threshold > 0.6) {
        color = Colors.yellow;
      } else {
        color = AppColors.primaryNeon;
      }

      // Draw dimmed background
      paint.color = color.withValues(alpha: 0.2);
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, segmentHeight), paint);

      // Draw active foreground with Neon Glow if level > threshold
      if (level >= (i / totalSegments)) {
        paint.color = color;
        // Neon glow effect
        paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 3.0);
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, segmentHeight), paint);
        paint.maskFilter = null; // Reset
      }
    }
  }

  @override
  bool shouldRepaint(VUMeterPainter oldDelegate) {
    return oldDelegate.levelNotifier != levelNotifier;
  }
}

class NeonVUMeter extends StatefulWidget {
  final int outputChannel;

  const NeonVUMeter({super.key, required this.outputChannel});

  @override
  State<NeonVUMeter> createState() => _NeonVUMeterState();
}

class _NeonVUMeterState extends State<NeonVUMeter> {
  StreamSubscription<List<double>>? _vuSubscription;
  final ValueNotifier<double> _levelNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _vuSubscription = rust_api.apiCreateVuStream().listen((levels) {
      if (widget.outputChannel >= 0 && widget.outputChannel < levels.length) {
        final newLevel = levels[widget.outputChannel];
        double currentLevel = _levelNotifier.value;
        // Apply some basic decay for smoother visual
        if (newLevel > currentLevel) {
          currentLevel = newLevel;
        } else {
          currentLevel -= 0.05; // Decay rate
          if (currentLevel < 0) currentLevel = 0;
        }
        _levelNotifier.value = currentLevel;
      }
    });
  }

  @override
  void dispose() {
    _vuSubscription?.cancel();
    _levelNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: VUMeterPainter(_levelNotifier),
        ),
      ),
    );
  }
}
