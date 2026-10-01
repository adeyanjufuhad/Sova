import 'package:flutter/material.dart';

import 'sova_colors.dart';
import 'sova_spacing.dart';
import 'sova_text_styles.dart';

/// Flat Material theme: no elevation, hairline borders, solid blue actions.
abstract final class SovaTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: SovaColors.electric,
      onPrimary: SovaColors.white,
      secondary: SovaColors.navy900,
      onSecondary: SovaColors.white,
      surface: SovaColors.white,
      onSurface: SovaColors.textPrimary,
      error: SovaColors.navy900,
      onError: SovaColors.white,
      outline: SovaColors.borderStrong,
      outlineVariant: SovaColors.border,
    );

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(SovaRadius.md));
    const buttonSize = Size.fromHeight(54);

    OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(SovaRadius.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: SovaText.family,
      scaffoldBackgroundColor: SovaColors.white,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displaySmall: SovaText.display,
        headlineMedium: SovaText.h1,
        titleLarge: SovaText.h2,
        titleMedium: SovaText.h3,
        bodyLarge: SovaText.body,
        bodyMedium: SovaText.bodySmall,
        labelLarge: SovaText.label,
        bodySmall: SovaText.caption,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SovaColors.white,
        foregroundColor: SovaColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: SovaText.h3,
        shape: Border(bottom: BorderSide(color: SovaColors.border)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SovaColors.electric,
          foregroundColor: SovaColors.white,
          disabledBackgroundColor: SovaColors.electricTint,
          disabledForegroundColor: SovaColors.textMuted,
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: SovaText.button,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SovaColors.textPrimary,
          minimumSize: buttonSize,
          shape: buttonShape,
          side: const BorderSide(color: SovaColors.borderStrong),
          textStyle: SovaText.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SovaColors.electric,
          textStyle: SovaText.label,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SovaColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: SovaSpacing.lg, vertical: SovaSpacing.lg),
        hintStyle: SovaText.body.copyWith(color: SovaColors.textMuted),
        labelStyle: SovaText.bodySmall,
        border: inputBorder(SovaColors.borderStrong),
        enabledBorder: inputBorder(SovaColors.borderStrong),
        focusedBorder: inputBorder(SovaColors.electric, 2),
        errorBorder: inputBorder(SovaColors.navy900),
        focusedErrorBorder: inputBorder(SovaColors.navy900, 2),
        errorStyle: SovaText.caption.copyWith(color: SovaColors.navy900, fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        color: SovaColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SovaRadius.xl),
          side: const BorderSide(color: SovaColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: SovaColors.border, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: SovaColors.white,
        selectedColor: SovaColors.electricTint,
        side: const BorderSide(color: SovaColors.borderStrong),
        labelStyle: SovaText.label,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SovaRadius.full)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SovaColors.navy900,
        contentTextStyle: SovaText.bodySmall.copyWith(color: SovaColors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SovaRadius.md)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SovaColors.white,
        indicatorColor: SovaColors.electricTint,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => SovaText.caption.copyWith(
            color: states.contains(WidgetState.selected) ? SovaColors.electric : SovaColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
