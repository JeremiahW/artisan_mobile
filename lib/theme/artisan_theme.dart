import 'package:flutter/material.dart';

class ArtisanColors {
  static const canvas = Color(0xFFF8F8F8);
  static const plot = Color(0xFFFFFFFF);
  static const grid = Color(0xFFE5E5E5);
  static const axis = Color(0xFF808080);
  static const title = Color(0xFF0C6AA6);
  // Kaleido / Artisan 双系统说明书：风温蓝、豆温深红、SV 橙。
  static const et = Color(0xFF005493);
  static const bt = Color(0xFF941100);
  static const sv = Color(0xFFE67E22);
  static const button = Color(0xFF147BB3);
  static const buttonPressed = Color(0xFF0F5C86);
  static const selected = Color(0xFFD4336A);
  static const deltaBackground = Color(0xFFEBEBEB);
  static const timerBackground = Color(0xFFF8F8F8);
  static const timerDigit = Color(0xFF262626);
  static const phaseDry = Color(0xFFE6E6E6);
  static const phaseMaillard = Color(0xFFB2B2B2);
  static const phaseDev = Color(0xFFBDE0EE);
  static const onText = Color(0xFF147BB3);
  static const offText = Color(0xFFCC0F50);
  static const eventColors = <Color>[
    Color(0xFF43A7CF),
    Color(0xFF49B160),
    Color(0xFFAD0427),
    Color(0xFF800080),
  ];
}

ThemeData artisanTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: ArtisanColors.bt, primary: ArtisanColors.bt);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: ArtisanColors.canvas,
    fontFamily: 'sans-serif',
    dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
    sliderTheme: const SliderThemeData(
      activeTrackColor: ArtisanColors.button,
      thumbColor: ArtisanColors.button,
      overlayColor: Color(0x33147BB3),
    ),
  );
}

ButtonStyle artisanAction({
  required Color background,
  required Color foreground,
  bool enabled = true,
}) {
  return ButtonStyle(
    backgroundColor: WidgetStatePropertyAll(enabled ? background : const Color(0xFFE0E0E0)),
    foregroundColor: WidgetStatePropertyAll(enabled ? foreground : const Color(0xFF9E9E9E)),
    elevation: const WidgetStatePropertyAll(0),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
    minimumSize: const WidgetStatePropertyAll(Size(64, 42)),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
    ),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
  );
}
