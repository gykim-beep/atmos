import 'package:flutter/material.dart';
import 'colors.dart';

class AtmosTypography {
  static const TextStyle h1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AtmosColors.neonCyan,
    letterSpacing: 2.0,
  );
  
  static const TextStyle h2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AtmosColors.textMain,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AtmosColors.textMain,
  );

  static const TextStyle bodyDim = TextStyle(
    fontSize: 12,
    color: AtmosColors.textDim,
  );
}
