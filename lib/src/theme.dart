/// App-wide theme system: semantic color palettes, the built-in theme specs,
/// and the ThemeData assembly. Widgets read colors through the global [P]
/// accessor; changing [AppState.themeId] rebuilds the app tree from the root,
/// so every read observes the new palette.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Selected-theme store: persists the id and notifies the app root to rebuild
/// with the new palette.
class ThemeController extends ChangeNotifier {
  String _themeId = kAppThemes.first.id;

  /// The persisted selection (a [kAppThemes] id).
  String get themeId => _themeId;

  /// The resolved palette of the current selection.
  AppPalette get palette => paletteFor(_themeId);

  /// Loads the persisted selection; call once at app start.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('obsidianMigrationV1') != true) {
      await prefs.setString('themeId', 'obsidian');
      await prefs.setBool('obsidianMigrationV1', true);
    }
    final stored = prefs.getString('themeId');
    if (stored != null && stored != _themeId) {
      _themeId = stored;
      notifyListeners();
    }
  }

  /// Selects and persists a theme (no-op for unknown ids).
  Future<void> select(String id) async {
    if (id == _themeId || kAppThemes.every((s) => s.id != id)) return;
    _themeId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeId', id);
  }
}

/// Semantic color set for one app theme. Every visual surface reads from
/// these fields instead of hardcoded colors.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.bg,
    required this.card,
    required this.cardAlt,
    required this.code,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accent2,
    required this.accentLight,
    required this.onAccent,
    required this.divider,
    required this.fillSubtle,
    required this.fillLight,
    required this.fillMedium,
    required this.danger,
    required this.success,
  });

  final Brightness brightness;

  /// Scaffold/page background.
  final Color bg;

  /// Cards, composer, chips on the background.
  final Color card;

  /// Elevated surfaces: bottom sheets, dialogs, menus.
  final Color cardAlt;

  /// Code blocks and preformatted surfaces.
  final Color code;

  final Color text;
  final Color textSecondary;
  final Color textTertiary;

  /// Brand accent (buttons, active states); gradient pairs with [accent2].
  final Color accent;
  final Color accent2;

  /// Accent variant readable as text/icons directly on [bg]/[card].
  final Color accentLight;

  /// Text/icons on accent-filled surfaces.
  final Color onAccent;

  final Color divider;

  /// Neutral fills, weakest to strongest (hover/highlight wells).
  final Color fillSubtle;
  final Color fillLight;
  final Color fillMedium;

  final Color danger;
  final Color success;

  Color get info => isDark ? const Color(0xFF22D3EE) : const Color(0xFF087F91);
  Color get agent => isDark ? const Color(0xFFA78BFA) : const Color(0xFF7052BC);
  Color get warning =>
      isDark ? const Color(0xFFFFB547) : const Color(0xFF9C6009);
  Color get glassFill =>
      isDark ? const Color(0x0BFFFFFF) : const Color(0xBFFFFFFF);
  Color get glassStroke => isDark ? const Color(0x14FFFFFF) : divider;
  Color get glassHighlight =>
      isDark ? const Color(0x29FFFFFF) : const Color(0xFFFFFFFF);
  Color get neuHighlight =>
      isDark ? const Color(0x09FFFFFF) : const Color(0xFFFFFFFF);
  Color get neuShadow =>
      isDark ? const Color(0xD9000000) : const Color(0x33818F87);
  Color get accentGlow => accent.withValues(alpha: .35);
  Color get transparent => const Color(0x00000000);
  List<BoxShadow> get neuShadows => [
    BoxShadow(
      color: neuHighlight,
      blurRadius: 12,
      offset: const Offset(-5, -5),
    ),
    BoxShadow(color: neuShadow, blurRadius: 16, offset: const Offset(7, 7)),
  ];

  bool get isDark => brightness == Brightness.dark;

  /// Brand gradient for bubbles, primary buttons, and the logo tile.
  LinearGradient get brandGradient => LinearGradient(
    colors: [accentLight, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Soft glow behind accent-filled controls (brand mark, send button).
  BoxShadow get brandGlow => BoxShadow(
    color: accent.withValues(alpha: 0.35),
    blurRadius: 14,
    offset: const Offset(0, 4),
  );

  /// Card drop shadow — visible on light themes, subtle depth on dark ones.
  List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: isDark
          ? Colors.black.withValues(alpha: 0.3)
          : text.withValues(alpha: 0.06),
      blurRadius: isDark ? 12 : 16,
      offset: Offset(0, isDark ? 3 : 4),
    ),
  ];
}

/// One selectable theme: identity, palette, and the swatches shown in the
/// theme picker.
class AppThemeSpec {
  const AppThemeSpec({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.palette,
  });

  final String id;
  final String name;

  /// Picker caption describing the mood (e.g. "经典深色").
  final String subtitle;
  final AppPalette palette;
}

const _obsidian = AppPalette(
  brightness: Brightness.dark,
  bg: Color(0xFF050706),
  card: Color(0xFF0F1412),
  cardAlt: Color(0xFF151B18),
  code: Color(0xFF070A09),
  text: Color(0xFFECF3EE),
  textSecondary: Color(0xFF9DAAA2),
  textTertiary: Color(0xFF5E6B64),
  accent: Color(0xFF39FF88),
  accent2: Color(0xFF22D3EE),
  accentLight: Color(0xFF9CFFC4),
  onAccent: Color(0xFF02140A),
  divider: Color(0x14FFFFFF),
  fillSubtle: Color(0x0BFFFFFF),
  fillLight: Color(0x14FFFFFF),
  fillMedium: Color(0x1FFFFFFF),
  danger: Color(0xFFFF5C7A),
  success: Color(0xFF39FF88),
);

const _night = AppPalette(
  brightness: Brightness.dark,
  bg: Color(0xFF0E1220),
  card: Color(0xFF171D2E),
  cardAlt: Color(0xFF1B2338),
  code: Color(0xFF11182B),
  text: Color(0xFFEEF1F8),
  textSecondary: Color(0xFFA8B1C8),
  textTertiary: Color(0xFF79839C),
  accent: Color(0xFF4D6BFE),
  accent2: Color(0xFF7C5CFF),
  accentLight: Color(0xFF8FA6FF),
  onAccent: Color(0xFFFFFFFF),
  divider: Color(0xFF232A42),
  fillSubtle: Color(0x08FFFFFF),
  fillLight: Color(0x0FFFFFFF),
  fillMedium: Color(0x17FFFFFF),
  danger: Color(0xFFFF5252),
  success: Color(0xFF34C759),
);

const _light = AppPalette(
  brightness: Brightness.light,
  bg: Color(0xFFF4F7F5),
  card: Color(0xFFFFFFFF),
  cardAlt: Color(0xFFFFFFFF),
  code: Color(0xFFEEF0F6),
  text: Color(0xFF1B1F2A),
  textSecondary: Color(0xFF5B6274),
  textTertiary: Color(0xFF969DB0),
  accent: Color(0xFF12B866),
  accent2: Color(0xFF087F91),
  accentLight: Color(0xFF087F43),
  onAccent: Color(0xFFFFFFFF),
  divider: Color(0xFFE4E6F0),
  fillSubtle: Color(0x0A1B1F2A),
  fillLight: Color(0x0F1B1F2A),
  fillMedium: Color(0x141B1F2A),
  danger: Color(0xFFE53935),
  success: Color(0xFF2E9E5B),
);

const _eyecare = AppPalette(
  brightness: Brightness.light,
  bg: Color(0xFFC7EDCC),
  card: Color(0xFFD9F3DD),
  cardAlt: Color(0xFFE6F7E9),
  code: Color(0xFFC2E5C6),
  text: Color(0xFF24352A),
  textSecondary: Color(0xFF4E6455),
  textTertiary: Color(0xFF7A9281),
  accent: Color(0xFF2E9E5B),
  accent2: Color(0xFF55B36B),
  accentLight: Color(0xFF1F7A43),
  onAccent: Color(0xFFFFFFFF),
  divider: Color(0xFFAFDCB4),
  fillSubtle: Color(0x0D0F2E1A),
  fillLight: Color(0x140F2E1A),
  fillMedium: Color(0x1C0F2E1A),
  danger: Color(0xFFD23F3F),
  success: Color(0xFF1F7A43),
);

const _sakura = AppPalette(
  brightness: Brightness.light,
  bg: Color(0xFFFFF3F6),
  card: Color(0xFFFFFFFF),
  cardAlt: Color(0xFFFFF6F8),
  code: Color(0xFFFBE7EE),
  text: Color(0xFF38262D),
  textSecondary: Color(0xFF7C5E69),
  textTertiary: Color(0xFFB0929D),
  accent: Color(0xFFF06292),
  accent2: Color(0xFFA66CFF),
  accentLight: Color(0xFFD8437E),
  onAccent: Color(0xFFFFFFFF),
  divider: Color(0xFFF3D8E1),
  fillSubtle: Color(0x0A8C2E52),
  fillLight: Color(0x0F8C2E52),
  fillMedium: Color(0x148C2E52),
  danger: Color(0xFFE53935),
  success: Color(0xFF2E9E5B),
);

/// 炫彩霓光: near-black indigo night with neon cyan→magenta brand gradient.
/// Bright accents sit on dark surfaces, so onAccent is near-black for
/// readable labels on neon-filled controls.
const _neon = AppPalette(
  brightness: Brightness.dark,
  bg: Color(0xFF0A0A14),
  card: Color(0xFF14142A),
  cardAlt: Color(0xFF1B1B38),
  code: Color(0xFF101024),
  text: Color(0xFFF2F5FF),
  textSecondary: Color(0xFFAEB4D8),
  textTertiary: Color(0xFF6B729E),
  accent: Color(0xFF00E5FF),
  accent2: Color(0xFFFF2ED1),
  accentLight: Color(0xFF4DF3FF),
  onAccent: Color(0xFF001318),
  divider: Color(0xFF26264A),
  fillSubtle: Color(0x08FFFFFF),
  fillLight: Color(0x0FFFFFFF),
  fillMedium: Color(0x17FFFFFF),
  danger: Color(0xFFFF3D71),
  success: Color(0xFF3DFF9E),
);

/// Built-in themes in picker order. The first entry is the default.
const kAppThemes = [
  AppThemeSpec(
    id: 'obsidian',
    name: '黑曜荧光',
    subtitle: '液态玻璃 · 荧光绿',
    palette: _obsidian,
  ),
  AppThemeSpec(id: 'night', name: '暗夜蓝', subtitle: '经典深色', palette: _night),
  AppThemeSpec(id: 'light', name: '晨雾白', subtitle: '清新浅色', palette: _light),
  AppThemeSpec(id: 'eyecare', name: '护眼绿', subtitle: '柔和舒缓', palette: _eyecare),
  AppThemeSpec(id: 'sakura', name: '樱花粉', subtitle: '温柔甜美', palette: _sakura),
  AppThemeSpec(id: 'neon', name: '炫彩霓光', subtitle: '赛博霓虹', palette: _neon),
];

/// Resolves a stored theme id to its palette (unknown ids fall back to the
/// default night theme).
AppPalette paletteFor(String themeId) {
  for (final spec in kAppThemes) {
    if (spec.id == themeId) return spec.palette;
  }
  return _obsidian;
}

/// The active palette. Reassigned by the root widget before its tree builds;
/// a theme change rebuilds the whole tree, so reads always observe the
/// current value.
AppPalette P = _obsidian;

/// Assembles the Material theme for [palette].
ThemeData buildAppTheme(AppPalette palette, {String? fontFamily}) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: palette.brightness,
      ).copyWith(
        surface: palette.bg,
        primary: palette.accent,
        onSurface: palette.text,
        onPrimary: palette.onAccent,
        secondary: palette.info,
        error: palette.danger,
      );
  final overlay = palette.isDark
      ? SystemUiOverlayStyle.light
      : SystemUiOverlayStyle.dark;
  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    colorScheme: scheme,
    brightness: palette.brightness,
    scaffoldBackgroundColor: palette == _obsidian
        ? Colors.transparent
        : palette.bg,
    splashFactory: InkSparkle.splashFactory,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.card,
        foregroundColor: palette.text,
        shadowColor: palette.neuShadow,
        elevation: 4,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.accentLight,
        side: BorderSide(color: palette.divider),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: palette.accentLight),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? palette.accent
            : palette.textTertiary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? palette.accent.withValues(alpha: .18)
            : palette.code,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? palette.accent.withValues(alpha: .4)
            : palette.divider,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.card,
      selectedColor: palette.accent.withValues(alpha: .12),
      labelStyle: TextStyle(
        color: palette.textSecondary,
        fontFamily: fontFamily,
      ),
      side: BorderSide(color: palette.divider),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? palette.accentLight
              : palette.textSecondary,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? palette.cardAlt : palette.code,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: palette.divider)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.code,
      hintStyle: TextStyle(color: palette.textTertiary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.accent),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.card.withValues(alpha: .92),
      indicatorColor: palette.accent.withValues(alpha: .12),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? palette.accent
              : palette.textTertiary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          color: s.contains(WidgetState.selected)
              ? palette.accent
              : palette.textSecondary,
          fontSize: 12,
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.bg,
      foregroundColor: palette.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: overlay,
    ),
    cardTheme: CardThemeData(
      color: palette.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.cardAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.cardAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: palette.bg),
    dividerTheme: DividerThemeData(color: palette.divider, thickness: 0.5),
    iconTheme: IconThemeData(color: palette.textSecondary),
    textTheme:
        (palette.isDark
                ? Typography.material2021().white
                : Typography.material2021().black)
            .apply(
              bodyColor: palette.text,
              displayColor: palette.text,
              fontFamily: fontFamily,
            ),
    hintColor: palette.textTertiary,
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.accentLight,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: palette.isDark ? palette.cardAlt : palette.text,
      contentTextStyle: TextStyle(
        color: palette.isDark ? palette.text : palette.bg,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
