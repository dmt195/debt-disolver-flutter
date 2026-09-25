import 'package:debt_destroyer/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light theme uses the Direction A tokens', () {
    final theme = buildTheme(Brightness.light);
    final c = theme.extension<DestroyerColors>()!;
    expect(c.ink, const Color(0xFF14213D));
    expect(c.hiVis, const Color(0xFFFFC400));
    expect(c.onHiVis, const Color(0xFF14213D));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF3F4F6));
    expect(theme.colorScheme.primary, const Color(0xFF14213D));
    expect(c.series, hasLength(6));
    expect(c.series.first, const Color(0xFF1F4FD1));
    expect(theme.textTheme.bodyMedium!.fontFamily, kBodyFont);
  });

  test('dark theme swaps the primary action to hi-vis', () {
    final theme = buildTheme(Brightness.dark);
    final c = theme.extension<DestroyerColors>()!;
    expect(theme.colorScheme.primary, const Color(0xFFFFC400));
    expect(theme.colorScheme.onPrimary, const Color(0xFF14213D));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0E1628));
    expect(c.series.first, const Color(0xFF4F83F5));
  });

  test('cards have 2px outlines, 6px corners and no elevation', () {
    final theme = buildTheme(Brightness.light);
    final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
    expect(shape.side.width, 2);
    expect(shape.borderRadius, BorderRadius.circular(6));
    expect(theme.cardTheme.elevation, 0);
  });

  test('display style is Bricolage ExtraBold', () {
    final s = displayStyle(40);
    expect(s.fontFamily, kDisplayFont);
    expect(s.fontVariations, contains(const FontVariation.weight(800)));
    expect(s.letterSpacing, closeTo(-1.2, 0.001));
  });

  test('app bar titles sit at the start, as in the design', () {
    expect(buildTheme(Brightness.light).appBarTheme.centerTitle, isFalse);
  });

  test('hi-vis is kept for the hero block, not Material containers', () {
    final theme = buildTheme(Brightness.light);
    const hiVis = Color(0xFFFFC400);
    expect(theme.colorScheme.primaryContainer, isNot(hiVis));
    expect(theme.chipTheme.selectedColor, DestroyerColors.light.surface);
  });

  test('text buttons use ink, never hi-vis text, in dark too', () {
    final theme = buildTheme(Brightness.dark);
    final fg = theme.textButtonTheme.style!.foregroundColor!.resolve({});
    expect(fg, DestroyerColors.dark.ink);
  });
}
