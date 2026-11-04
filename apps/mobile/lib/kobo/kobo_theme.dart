import 'package:flutter/material.dart';

abstract final class KoboColors {
  static const Color paper = Color(0xFFF5E8D1);
  static const Color paperLight = Color(0xFFFAF3E6);
  static const Color divider = Color(0xFFD8C8AF);
  static const Color ink = Color(0xFF1F1F23);
  static const Color brown = Color(0xFF5B3A22);
  static const Color navy = Color(0xFF243A5A);
  static const Color red = Color(0xFFC7362E);
  static const Color mustard = Color(0xFFD4A126);
  static const Color error = Color(0xFFB3261E);
  static const Color success = Color(0xFF496A45);
}

abstract final class KoboSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class KoboRadii {
  static const double card = 14;
  static const double button = 16;
  static const double input = 14;
  static const double chip = 999;
}

abstract final class KoboTextStyles {
  static const TextStyle heroTitle = TextStyle(
    fontSize: 32,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: KoboColors.ink,
  );
  static const TextStyle pageTitle = TextStyle(
    fontSize: 28,
    height: 1.25,
    fontWeight: FontWeight.w700,
    color: KoboColors.ink,
  );
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 22,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: KoboColors.ink,
  );
  static const TextStyle cardTitle = TextStyle(
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: KoboColors.ink,
  );
  static const TextStyle body = TextStyle(
    fontSize: 16,
    height: 1.5,
    color: KoboColors.ink,
  );
  static const TextStyle secondary = TextStyle(
    fontSize: 13,
    height: 1.4,
    color: KoboColors.brown,
  );
  static const TextStyle mainButton = TextStyle(
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );
}

abstract final class KoboTheme {
  static ThemeData light() {
    const ColorScheme colors = ColorScheme.light(
      primary: KoboColors.red,
      onPrimary: Colors.white,
      secondary: KoboColors.mustard,
      onSecondary: KoboColors.ink,
      error: KoboColors.error,
      onError: Colors.white,
      surface: KoboColors.paperLight,
      onSurface: KoboColors.ink,
      outline: KoboColors.divider,
    );

    return ThemeData(
      colorScheme: colors,
      scaffoldBackgroundColor: KoboColors.paperLight,
      dividerColor: KoboColors.divider,
      useMaterial3: true,
      textTheme: const TextTheme(
        headlineLarge: KoboTextStyles.heroTitle,
        headlineMedium: KoboTextStyles.pageTitle,
        titleLarge: KoboTextStyles.sectionTitle,
        titleMedium: KoboTextStyles.cardTitle,
        bodyLarge: KoboTextStyles.body,
        bodyMedium: KoboTextStyles.body,
        bodySmall: KoboTextStyles.secondary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: KoboColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 68,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: const CardThemeData(
        color: KoboColors.paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(KoboRadii.card)),
          side: BorderSide(color: KoboColors.divider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: KoboColors.red,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(KoboRadii.button)),
          ),
          textStyle: KoboTextStyles.mainButton,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: KoboColors.paper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(KoboRadii.input)),
          borderSide: BorderSide(color: KoboColors.divider),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: KoboColors.ink,
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 15),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
