import 'package:flutter/material.dart';

const kDisplayFont = 'BricolageGrotesque';
const kBodyFont = 'AtkinsonHyperlegible';
const _navy = Color(0xFF14213D);
const _hiVis = Color(0xFFFFC400);

/// Direction A ("Demolition crew") colours that Material has no slot for.
/// See the v3 spec, §5.1.
@immutable
class DestroyerColors extends ThemeExtension<DestroyerColors> {
  const DestroyerColors({
    required this.ink,
    required this.ink2,
    required this.ground,
    required this.surface,
    required this.outline,
    required this.track,
    required this.navBar,
    required this.navInactive,
    required this.today,
    required this.faint,
    required this.series,
    this.hiVis = _hiVis,
    this.onHiVis = _navy,
  });

  final Color ink;
  final Color ink2;
  final Color ground;
  final Color surface;
  final Color outline;
  final Color track;
  final Color navBar;
  final Color navInactive;
  final Color today;
  final Color faint;

  /// The one hero block per screen. Never a text colour; always carries
  /// [onHiVis] text.
  final Color hiVis;
  final Color onHiVis;

  /// One colour per debt, by list order (validated for colour blindness).
  final List<Color> series;

  static const light = DestroyerColors(
    ink: _navy,
    ink2: Color(0xFF4A5568),
    ground: Color(0xFFF3F4F6),
    surface: Color(0xFFFFFFFF),
    outline: _navy,
    track: Color(0xFFE6E8EC),
    navBar: _navy,
    navInactive: Color(0xFFC9D1E0),
    today: Color(0xFFD9590B),
    faint: Color(0xFF9AA3B2),
    series: [
      Color(0xFF1F4FD1),
      Color(0xFFD9590B),
      Color(0xFF0F9D7A),
      Color(0xFF7A5AF8),
      Color(0xFFC23B8A),
      Color(0xFFA87A00),
    ],
  );

  static const dark = DestroyerColors(
    ink: Color(0xFFEEF1F6),
    ink2: Color(0xFFA9B4C7),
    ground: Color(0xFF0E1628),
    surface: Color(0xFF17223A),
    outline: Color(0xFF3A4B6E),
    track: Color(0xFF24314D),
    navBar: Color(0xFF0A1120),
    navInactive: Color(0xFF8C99B3),
    today: Color(0xFFE0661A),
    faint: Color(0xFF5E6C88),
    series: [
      Color(0xFF4F83F5),
      Color(0xFFE0661A),
      Color(0xFF16A080),
      Color(0xFF8E78F5),
      Color(0xFFDE559F),
      Color(0xFFB08A00),
    ],
  );

  @override
  DestroyerColors copyWith() => this;

  @override
  DestroyerColors lerp(DestroyerColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

extension DestroyerTheme on BuildContext {
  DestroyerColors get colors => Theme.of(this).extension<DestroyerColors>()!;
}

/// Bricolage Grotesque ExtraBold with tight display tracking (−3%).
TextStyle displayStyle(double size, {Color? color}) => TextStyle(
  fontFamily: kDisplayFont,
  fontSize: size,
  fontWeight: FontWeight.w800,
  fontVariations: const [FontVariation.weight(800)],
  letterSpacing: -0.03 * size,
  height: 1,
  color: color,
);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? DestroyerColors.dark : DestroyerColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? _hiVis : _navy,
    onPrimary: dark ? _navy : Colors.white,
    secondary: _hiVis,
    onSecondary: _navy,
    error: dark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E),
    onError: dark ? _navy : Colors.white,
    errorContainer: dark ? const Color(0xFF5C1A1A) : const Color(0xFFFCE4E2),
    onErrorContainer: dark ? const Color(0xFFFFDAD6) : const Color(0xFF5C1A1A),
    surface: c.surface,
    onSurface: c.ink,
    onSurfaceVariant: c.ink2,
    outline: c.outline,
    outlineVariant: c.track,
    surfaceContainerHighest: c.track,
    // Hi-vis is only for the one hero block per screen (spec §5.1).
    primaryContainer: c.track,
    onPrimaryContainer: c.ink,
  );
  const buttonText = TextStyle(
    fontFamily: kBodyFont,
    fontWeight: FontWeight.w700,
    fontSize: 16,
  );
  final corners = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(6),
  );
  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: kBodyFont,
    scaffoldBackgroundColor: c.ground,
    extensions: [c],
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: c.ground,
      foregroundColor: c.ink,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: displayStyle(22, color: c.ink),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.outline, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: corners,
        textStyle: buttonText,
      ),
    ),
    // Hi-vis is never a text colour (spec §5.1), even where it is primary.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.ink),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        foregroundColor: c.ink,
        side: BorderSide(color: dark ? c.ink : c.outline, width: 2),
        shape: corners,
        textStyle: buttonText,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.ink,
      unselectedLabelColor: c.ink2,
      indicatorColor: dark ? _hiVis : _navy,
    ),
    inputDecorationTheme: InputDecorationTheme(
      floatingLabelStyle: TextStyle(color: c.ink),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: c.outline, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: dark ? c.ink2 : c.outline, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(color: c.outline, width: 1.5),
      color: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.surface : c.track,
      ),
      selectedColor: c.surface,
      backgroundColor: c.track,
      // Material's default for a selected chip is navy in dark mode: set the
      // text from Direction A's inks (shown = ink, hidden = secondary ink).
      labelStyle: TextStyle(
        color: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.ink : c.ink2,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.navBar,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? _hiVis : c.navInactive,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: kBodyFont,
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
          color: s.contains(WidgetState.selected) ? _hiVis : c.navInactive,
        ),
      ),
    ),
  );
}
