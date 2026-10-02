import 'package:flutter/painting.dart';

/// Sova palette: flat, white-first, blue. Same tokens as the website.
/// Never hardcode colours in widgets; use these.
abstract final class SovaColors {
  // Brand
  static const navy900 = Color(0xFF0B1A33);
  static const navy800 = Color(0xFF102447);
  static const navy700 = Color(0xFF17305E);
  static const electric = Color(0xFF1D4ED8);
  static const electricLight = Color(0xFF3B6AE8);
  static const sky = Color(0xFF7DC3E3);

  // Surfaces
  static const white = Color(0xFFFFFFFF);
  static const mist = Color(0xFFF3F6FD);

  // Text
  static const textPrimary = navy900;
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF64748B);
  static const textOnBlue = white;

  // Lines
  static const border = Color(0x1A0B1A33); // navy at 10%
  static const borderStrong = Color(0x330B1A33); // navy at 20%

  // Tints
  static const electricTint = Color(0x1A1D4ED8); // electric at 10%
  static const skyTint = Color(0x267DC3E3); // sky at 15%

  // Opaque versions of the tints, for use on dark or patterned backgrounds.
  static const electricTintSolid = Color(0xFFE8EDFB);
  static const mistSolid = Color(0xFFF3F6FD);
}
