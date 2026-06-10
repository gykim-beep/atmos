import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import 'dart:math';

class VuMeter extends StatefulWidget {
  final double level; // 0.0 to 1.0

  const VuMeter({super.key, required this.level});

  @override
  State<VuMeter> createState() => _VuMeterState();
}

class _VuMeterState extends State<VuMeter> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _smoothLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100))
      ..addListener(() {
        if (!mounted) return;
        setState(() {
          _smoothLevel += (widget.level - _smoothLevel) * 0.3; // Simple smoothing
        });
      })
      ..repeat();
  }

  @override
  void didUpdateWidget(VuMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Smooth level is updated in the animation ticker.
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _VuMeterPainter(level: _smoothLevel),
      size: const Size(20, double.infinity),
    );
  }
}

class _VuMeterPainter extends CustomPainter {
  final double level;

  _VuMeterPainter({required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;
    
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    if (level <= 0.01) return;

    final fillHeight = size.height * min(level, 1.0);
    final topY = size.height - fillHeight;

    final rect = Rect.fromLTWH(0, topY, size.width, fillHeight);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          AtmosColors.neonCyan,
          Colors.yellow,
          AtmosColors.neonMagenta,
        ],
        stops: [0.0, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(rect, paint);

    // Add neon glow
    final glowPaint = Paint()
      ..shader = paint.shader
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    canvas.drawRect(rect, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _VuMeterPainter oldDelegate) {
    return oldDelegate.level != level;
  }
}
