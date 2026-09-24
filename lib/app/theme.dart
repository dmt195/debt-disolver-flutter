import 'package:flutter/material.dart';

/// The blue of the app icon (legacy/resources/artwork.png).
const Color kBrandBlue = Color(0xFF1F78D1);

ThemeData buildTheme(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: kBrandBlue,
    brightness: brightness,
  ),
);
