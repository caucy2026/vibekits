import 'package:flutter/material.dart';

/// Stable semantic accents used by feature status indicators.
abstract final class VibekitsColors {
  static const Color primary = Color(0xFF0A9F9A);
  static const Color primaryHover = Color(0xFF087E7A);
  static const Color info = Color(0xFF2788E8);
  static const Color warning = Color(0xFFE09A32);
  static const Color danger = Color(0xFFD85B57);

  // Legacy light tokens. New layout code should use [VibekitsPalette].
  static const Color appBackground = Color(0xFFF3F7F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF16232D);
  static const Color textSecondary = Color(0xFF60717D);
  static const Color divider = Color(0xFFD8E3E8);
}

@immutable
class VibekitsPalette extends ThemeExtension<VibekitsPalette> {
  const VibekitsPalette({
    required this.canvas,
    required this.panel,
    required this.panelRaised,
    required this.border,
    required this.muted,
    required this.success,
    required this.glow,
  });

  final Color canvas;
  final Color panel;
  final Color panelRaised;
  final Color border;
  final Color muted;
  final Color success;
  final Color glow;

  @override
  VibekitsPalette copyWith({
    Color? canvas,
    Color? panel,
    Color? panelRaised,
    Color? border,
    Color? muted,
    Color? success,
    Color? glow,
  }) {
    return VibekitsPalette(
      canvas: canvas ?? this.canvas,
      panel: panel ?? this.panel,
      panelRaised: panelRaised ?? this.panelRaised,
      border: border ?? this.border,
      muted: muted ?? this.muted,
      success: success ?? this.success,
      glow: glow ?? this.glow,
    );
  }

  @override
  VibekitsPalette lerp(covariant VibekitsPalette? other, double t) {
    if (other == null) return this;
    return VibekitsPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelRaised: Color.lerp(panelRaised, other.panelRaised, t)!,
      border: Color.lerp(border, other.border, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      success: Color.lerp(success, other.success, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
    );
  }
}

extension VibekitsThemeContext on BuildContext {
  VibekitsPalette get vibe =>
      Theme.of(this).extension<VibekitsPalette>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? const VibekitsPalette(
              canvas: Color(0xFF071119),
              panel: Color(0xFF0C1821),
              panelRaised: Color(0xFF11212C),
              border: Color(0xFF253B47),
              muted: Color(0xFF91A4AF),
              success: Color(0xFF4DD5AA),
              glow: Color(0x3335D1C8),
            )
          : const VibekitsPalette(
              canvas: Color(0xFFF3F7F9),
              panel: Color(0xFFF9FCFD),
              panelRaised: Color(0xFFFFFFFF),
              border: Color(0xFFD7E4E9),
              muted: Color(0xFF60717D),
              success: Color(0xFF16856B),
              glow: Color(0x1F0A9F9A),
            ));
}

abstract final class VibekitsTheme {
  static const VibekitsPalette _lightPalette = VibekitsPalette(
    canvas: Color(0xFFF3F7F9),
    panel: Color(0xFFF9FCFD),
    panelRaised: Color(0xFFFFFFFF),
    border: Color(0xFFD7E4E9),
    muted: Color(0xFF60717D),
    success: Color(0xFF16856B),
    glow: Color(0x1F0A9F9A),
  );

  static const VibekitsPalette _darkPalette = VibekitsPalette(
    canvas: Color(0xFF071119),
    panel: Color(0xFF0C1821),
    panelRaised: Color(0xFF11212C),
    border: Color(0xFF253B47),
    muted: Color(0xFF91A4AF),
    success: Color(0xFF4DD5AA),
    glow: Color(0x3335D1C8),
  );

  static ThemeData light() => _build(
    brightness: Brightness.light,
    palette: _lightPalette,
    foreground: const Color(0xFF16232D),
    primary: VibekitsColors.primary,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    palette: _darkPalette,
    foreground: const Color(0xFFE7F0F3),
    primary: const Color(0xFF35D1C8),
  );

  static ThemeData _build({
    required Brightness brightness,
    required VibekitsPalette palette,
    required Color foreground,
    required Color primary,
  }) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      surface: palette.panelRaised,
      error: VibekitsColors.danger,
    );
    final OutlineInputBorder inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: palette.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.canvas,
      fontFamily: 'Microsoft YaHei UI',
      extensions: <ThemeExtension<dynamic>>[palette],
      splashFactory: InkSparkle.splashFactory,
      textTheme: TextTheme(
        headlineSmall: TextStyle(
          color: foreground,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: TextStyle(color: foreground, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: foreground, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(color: foreground, height: 1.35),
        bodySmall: TextStyle(color: palette.muted, height: 1.35),
        labelLarge: const TextStyle(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.panel,
        foregroundColor: foreground,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: palette.border, thickness: 1),
      cardTheme: CardThemeData(
        color: palette.panelRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.panelRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.panel,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(40, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(40, 40),
          backgroundColor: primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(40, 40),
          side: BorderSide(color: palette.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(40, 40)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.muted,
        textColor: foreground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(primary.withValues(alpha: 0.45)),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
    );
  }
}
