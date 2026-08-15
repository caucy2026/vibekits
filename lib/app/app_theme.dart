import 'package:flutter/material.dart';

/// Vibekits 设计变量，与 docs/01_WINDOWS_UI_LAYOUT.md 保持一致。
abstract final class VibekitsColors {
  static const Color appBackground = Color(0xFFF4F6F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF17212B);
  static const Color textSecondary = Color(0xFF5E6B78);
  static const Color primary = Color(0xFF0F766E);
  static const Color primaryHover = Color(0xFF115E59);
  static const Color info = Color(0xFF2563EB);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFC2413B);
  static const Color divider = Color(0xFFDCE2E8);
}

/// 主题构建，仅表达层级与状态，不使用装饰性视觉资产。
abstract final class VibekitsTheme {
  static ThemeData light() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: VibekitsColors.primary,
      brightness: Brightness.light,
      primary: VibekitsColors.primary,
      error: VibekitsColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: VibekitsColors.appBackground,
      fontFamily: 'Microsoft YaHei UI',
      appBarTheme: const AppBarTheme(
        backgroundColor: VibekitsColors.surface,
        foregroundColor: VibekitsColors.textPrimary,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: VibekitsColors.divider,
        thickness: 1,
      ),
      textTheme: const TextTheme(
        titleMedium: TextStyle(
          color: VibekitsColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(color: VibekitsColors.textPrimary),
        bodySmall: TextStyle(color: VibekitsColors.textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: VibekitsColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
    );
  }
}
