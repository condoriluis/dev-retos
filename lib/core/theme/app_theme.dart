import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Use a modern, premium dark scheme (Deep Blue/Purple Neon)
  static ThemeData get darkTheme {
    final theme = FlexThemeData.dark(
      scheme: FlexScheme.blue,
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 15,
      appBarStyle: FlexAppBarStyle.background,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 20,
        useTextTheme: true,
        useM2StyleDividerInM3: true,
        defaultRadius: 16.0,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorUnfocusedBorderIsColored: false,
        fabUseShape: true,
        fabAlwaysCircular: true,
        chipRadius: 12.0,
        cardRadius: 20.0,
        buttonPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      useMaterial3: true,
      swapColors: true,
      fontFamily: GoogleFonts.outfit().fontFamily,
    );
    
    return theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        primary: const Color(0xFF2196F3), // Forzamos azul vibrante
      ),
    );
  }

  // Neon accent colors for specific UI elements
  static const Color neonPurple = Color(0xFFBB86FC);
  static const Color neonBlue = Color(0xFF03DAC6);
  static const Color deeperBlack = Color(0xFF0D0D0D);
}
