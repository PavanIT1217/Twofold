import 'package:flutter/material.dart';

/// Twofold's colours, matching the website.
class Brand {
  static const ink = Color(0xFF0B1220);
  static const navy = Color(0xFF1F3A5F);
  static const gold = Color(0xFFE9B949);
  static const paper = Color(0xFFF7F3EA);
  static const teal = Color(0xFF4FD1C5);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.navy,
    brightness: brightness,
    primary: dark ? const Color(0xFF9DBCE6) : Brand.navy,
    secondary: dark ? Brand.gold : const Color(0xFF8A5F0E),
    surface: dark ? const Color(0xFF111A2E) : Brand.paper,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: dark ? Brand.ink : Brand.paper,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? Brand.ink : Brand.paper,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF151F35) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: dark ? const Color(0xFF273352) : const Color(0xFFE2D9C6),
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: dark ? const Color(0xFF151F35) : Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    ),
  );
}

/// Serif display style for big headings, like the website.
TextStyle displaySerif(
  BuildContext context, {
  double size = 34,
  Color? color,
}) => TextStyle(
  fontFamily: 'serif',
  fontFamilyFallback: const ['Georgia', 'Noto Serif'],
  fontSize: size,
  height: 1.1,
  fontWeight: FontWeight.w600,
  color: color ?? Theme.of(context).colorScheme.onSurface,
);
