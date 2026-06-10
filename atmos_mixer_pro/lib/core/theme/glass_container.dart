import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double width;
  final double height;
  final double blur;

  const GlassContainer({
    super.key,
    required this.child,
    this.width = double.infinity,
    this.height = double.infinity,
    this.blur = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AtmosColors.surfaceGlass,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: AtmosColors.neonCyan.withOpacity(0.2)),
          ),
          child: child,
        ),
      ),
    );
  }
}
