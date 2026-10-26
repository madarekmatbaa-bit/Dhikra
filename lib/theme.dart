import 'package:flutter/material.dart';

/// ألوان ذِكرى: الغالب فاتح، والأخضر والقمحي للأزرار والتقدم والتمييز فقط.
class AppColors {
  static const olive = Color(0xFF3F5A44);
  static const sage = Color(0xFF6E8B6A);
  static const sageLight = Color(0xFFE6ECE1);
  static const wheat = Color(0xFFC7A85A);
  static const wheatLight = Color(0xFFF3EBD3);
  static const paper = Color(0xFFFAFBF7);
  static const ink = Color(0xFF1F2A21);
  static const muted = Color(0xFF5E6B60);
  static const line = Color(0xFFDDE3D8);

  static const nightBg = Color(0xFF111914);
  static const nightSurface = Color(0xFF1A241D);
  static const nightCard = Color(0xFF223026);
  static const nightInk = Color(0xFFE6ECE4);
  static const nightMuted = Color(0xFFA3B2A5);
}

/// ألوان تتبدل حسب الوضع (فاتح/ليلي).
class Palette extends ThemeExtension<Palette> {
  final Color card;
  final Color soft;
  final Color highlight;
  final Color muted;
  final Color line;
  const Palette({required this.card, required this.soft, required this.highlight, required this.muted, required this.line});

  static Palette of(BuildContext context) => Theme.of(context).extension<Palette>()!;

  @override
  Palette copyWith({Color? card, Color? soft, Color? highlight, Color? muted, Color? line}) => Palette(
        card: card ?? this.card,
        soft: soft ?? this.soft,
        highlight: highlight ?? this.highlight,
        muted: muted ?? this.muted,
        line: line ?? this.line,
      );

  @override
  Palette lerp(Palette? other, double t) {
    if (other == null) return this;
    return Palette(
      card: Color.lerp(card, other.card, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
    );
  }
}

const uiFont = 'Readex';
const readingFont = 'Naskh';

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = dark ? AppColors.nightBg : AppColors.paper;
  final surface = dark ? AppColors.nightSurface : Colors.white;
  final ink = dark ? AppColors.nightInk : AppColors.ink;
  final primary = dark ? const Color(0xFF9DBB98) : AppColors.olive;
  final palette = dark
      ? const Palette(
          card: AppColors.nightCard,
          soft: Color(0xFF2A3A2E),
          highlight: Color(0xFF5A4C25),
          muted: AppColors.nightMuted,
          line: Color(0xFF2E3D32),
        )
      : const Palette(
          card: Colors.white,
          soft: AppColors.sageLight,
          highlight: AppColors.wheatLight,
          muted: AppColors.muted,
          line: AppColors.line,
        );

  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: dark ? AppColors.nightBg : Colors.white,
    secondary: AppColors.sage,
    onSecondary: Colors.white,
    tertiary: AppColors.wheat,
    onTertiary: AppColors.ink,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
    surface: surface,
    onSurface: ink,
    surfaceContainerHighest: palette.soft,
    outline: palette.line,
    outlineVariant: palette.line,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: uiFont, brightness: brightness);
  final text = base.textTheme.apply(bodyColor: ink, displayColor: ink, fontFamily: uiFont);

  return base.copyWith(
    scaffoldBackgroundColor: bg,
    extensions: [palette],
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.35),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w500, height: 1.4),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.6),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.6),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: uiFont, fontSize: 20, fontWeight: FontWeight.w700, color: ink),
    ),
    cardTheme: CardThemeData(
      color: palette.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: palette.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontFamily: uiFont, fontSize: 16, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: primary,
        side: BorderSide(color: palette.line),
        textStyle: const TextStyle(fontFamily: uiFont, fontSize: 15, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(fontFamily: uiFont, fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: palette.card,
      selectedColor: palette.soft,
      side: BorderSide(color: palette.line),
      labelStyle: TextStyle(fontFamily: uiFont, color: ink, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: primary, width: 1.5)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: palette.soft,
      elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontFamily: uiFont, fontSize: 13, color: ink)),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? primary : palette.muted),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.sage, linearTrackColor: palette.soft),
    dividerTheme: DividerThemeData(color: palette.line, space: 1),
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: AppColors.wheat.withValues(alpha: 0.35),
      selectionHandleColor: AppColors.wheat,
      cursorColor: primary,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
