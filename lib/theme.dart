import 'package:flutter/material.dart';

import 'widgets/ornaments.dart';

/// ألوان ذِكرى: الغالب فاتح، والأخضر والقمحي للأزرار والتقدم والتمييز فقط.
class AppColors {
  static const olive = Color(0xFF3F5A44);
  static const sage = Color(0xFF6E8B6A);
  static const sageLight = Color(0xFFE6ECE1);
  static const wheat = Color(0xFFC7A85A);
  static const wheatLight = Color(0xFFF3EBD3);

  /// ورق عاجي دافئ كورق الكتب، لا أبيض شاشة.
  static const paper = Color(0xFFF7F3EA);
  static const sheet = Color(0xFFFCFAF5);
  static const parchment = Color(0xFFEFE8D8);
  static const ink = Color(0xFF1F241E);
  static const muted = Color(0xFF6B685C);
  static const line = Color(0xFFE3DBC9);

  static const nightBg = Color(0xFF151510);
  static const nightSurface = Color(0xFF1D1C17);
  static const nightCard = Color(0xFF23221C);
  static const nightInk = Color(0xFFECE6D8);
  static const nightMuted = Color(0xFFA59F8E);
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

/// خط مصحف المدينة من مجمع الملك فهد، يطابق نص المصحف المضمّن.
const quranFont = 'Hafs';

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = dark ? AppColors.nightBg : AppColors.paper;
  final surface = dark ? AppColors.nightSurface : AppColors.sheet;
  final ink = dark ? AppColors.nightInk : AppColors.ink;
  final primary = dark ? const Color(0xFFB7C9A3) : AppColors.olive;
  final palette = dark
      ? const Palette(
          card: AppColors.nightCard,
          soft: Color(0xFF2B2922),
          highlight: Color(0xFF4A3F22),
          muted: AppColors.nightMuted,
          line: Color(0xFF36332B),
        )
      : const Palette(
          card: AppColors.sheet,
          soft: AppColors.parchment,
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
      headlineSmall: text.headlineSmall?.copyWith(fontFamily: readingFont, fontWeight: FontWeight.w700, height: 1.4),
      titleLarge: text.titleLarge?.copyWith(fontFamily: readingFont, fontWeight: FontWeight.w700, height: 1.4),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w500, height: 1.4),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.6),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.6),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: RuledBottomBorder(accent: AppColors.wheat, line: palette.line),
      centerTitle: false,
      // عناوين الصفحات بخط النسخ كعناوين الكتب، والواجهة بخط Readex.
      titleTextStyle: TextStyle(fontFamily: readingFont, fontSize: 22, fontWeight: FontWeight.w700, color: ink, height: 1.4),
    ),
    cardTheme: CardThemeData(
      color: palette.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      // إطار كإطار صفحة الكتاب: خط خارجي وخط ذهبي داخلي ومعيّنات في الزوايا.
      shape: BookFrameBorder(line: palette.line, accent: AppColors.wheat),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 50),
        textStyle: const TextStyle(fontFamily: uiFont, fontSize: 16, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: primary,
        side: BorderSide(color: palette.line),
        textStyle: const TextStyle(fontFamily: uiFont, fontSize: 15, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primary, width: 1.5)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      elevation: 0,
      height: 66,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? TextStyle(fontFamily: uiFont, fontSize: 12.5, color: primary, fontWeight: FontWeight.w700)
            : TextStyle(fontFamily: uiFont, fontSize: 12.5, color: palette.muted),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? primary : palette.muted),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary, linearTrackColor: palette.soft),
    dividerTheme: DividerThemeData(color: palette.line, space: 1, thickness: 1),
    listTileTheme: ListTileThemeData(iconColor: palette.muted),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titleTextStyle: TextStyle(fontFamily: readingFont, fontSize: 21, fontWeight: FontWeight.w700, color: ink, height: 1.4),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: palette.line)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: AppColors.wheat.withValues(alpha: 0.35),
      selectionHandleColor: AppColors.wheat,
      cursorColor: primary,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: dark ? AppColors.nightBg : Colors.white,
      elevation: 2,
      highlightElevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      extendedTextStyle: const TextStyle(fontFamily: uiFont, fontSize: 15, fontWeight: FontWeight.w500),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(color: palette.muted, width: 1.4),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
