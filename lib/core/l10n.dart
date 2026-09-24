import 'dart:ui';

import 'package:debt_destroyer/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:debt_destroyer/l10n/app_localizations.dart';

part 'l10n.g.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Locale for number and date formatting: the device's, so separators match
/// what the user expects even though the UI text is English only.
@Riverpod(keepAlive: true)
String formatLocale(Ref ref) =>
    Intl.verifiedLocale(
      PlatformDispatcher.instance.locale.toString(),
      NumberFormat.localeExists,
      onFailure: (_) => 'en',
    ) ??
    'en';

/// The current time. Tests override it to get stable dates.
@Riverpod(keepAlive: true)
DateTime Function() clock(Ref ref) => DateTime.now;
