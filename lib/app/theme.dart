import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ---- Google Translate 风格主色 ----
  static const Color primaryBlue = Color(0xFF4285F4);
  static const Color secondaryBlue = Color(0xFF1A73E8);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color backgroundGrey = Color(0xFFF8F9FA);
  static const Color dividerGrey = Color(0xFFDADCE0);
  static const Color textPrimary = Color(0xFF202124);
  static const Color textSecondary = Color(0xFF5F6368);
  static const Color textHint = Color(0xFF9AA0A6);
  static const Color accentBlue = Color(0xFF1A73E8);

  // ---- 翻译卡片颜色 ----
  static const Color sourceCardBg = Colors.white;
  static const Color targetCardBg = Color(0xFFE8F0FE);
  static const Color targetTextColor = Color(0xFF1A73E8);

  // ---- 历史记录颜色 ----
  static const Color historySourceText = Color(0xFF202124);
  static const Color historyTranslatedText = Color(0xFF1A73E8);

  // ---- 对话气泡 ----
  static const Color myBubbleColor = Color(0xFF1A73E8);
  static const Color theirBubbleColor = Color(0xFFE8F0FE);
  static const Color myBubbleTextColor = Colors.white;
  static const Color theirBubbleTextColor = Color(0xFF202124);
  static const Color translatedTextColor = Color(0xFFBBDEFB);
  static const Color translatedTextDarkColor = Color(0xFF1A73E8);

  // ---- 亮色主题 ----
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: primaryBlue,
      brightness: Brightness.light,
      scaffoldBackgroundColor: backgroundGrey,
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceWhite,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceWhite,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: dividerGrey,
        thickness: 1,
        space: 0,
      ),
    );
  }
}
