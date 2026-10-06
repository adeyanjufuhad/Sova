import 'package:flutter/painting.dart';

import 'sova_colors.dart';

/// Type scale. Never set fontSize directly in widgets.
abstract final class SovaText {
  static const family = 'PlusJakartaSans';

  // Tabular figures so naira amounts line up like a bank statement.
  static const _tabular = [FontFeature.tabularFigures()];

  static const display = TextStyle(
    fontFamily: family,
    fontSize: 34,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    color: SovaColors.textPrimary,
  );

  static const h1 = TextStyle(
    fontFamily: family,
    fontSize: 26,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: SovaColors.textPrimary,
  );

  static const h2 = TextStyle(
    fontFamily: family,
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: SovaColors.textPrimary,
  );

  static const h3 = TextStyle(
    fontFamily: family,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: SovaColors.textPrimary,
  );

  static const body = TextStyle(
    fontFamily: family,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: SovaColors.textSecondary,
  );

  static const bodySmall = TextStyle(
    fontFamily: family,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: SovaColors.textSecondary,
  );

  static const label = TextStyle(
    fontFamily: family,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: SovaColors.textPrimary,
  );

  static const caption = TextStyle(
    fontFamily: family,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: SovaColors.textMuted,
  );

  /// Small section label in sentence case, like the website's eyebrows.
  static const eyebrow = TextStyle(
    fontFamily: family,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: SovaColors.electric,
  );

  static const button = TextStyle(
    fontFamily: family,
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );

  static const moneyLarge = TextStyle(
    fontFamily: family,
    fontSize: 34,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    color: SovaColors.textPrimary,
    fontFeatures: _tabular,
  );

  static const moneyMedium = TextStyle(
    fontFamily: family,
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: SovaColors.textPrimary,
    fontFeatures: _tabular,
  );

  static const moneySmall = TextStyle(
    fontFamily: family,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: SovaColors.textPrimary,
    fontFeatures: _tabular,
  );
}
