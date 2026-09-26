import 'dart:convert';

import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/core/app_version.dart';
import 'package:debt_destroyer/core/diagnostics.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/links.dart';
import 'package:debt_destroyer/core/notifications.dart';
import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fake_link_opener.dart';
import 'fake_notifications_service.dart';

/// Test doubles for the app's platform dependencies: in-memory preferences
/// seeded with [prefs], an in-memory database, GBP as the device currency,
/// `en_GB` number formatting and a fixed clock (24 Sep 2026, unless [clock]
/// is given). Pass the
/// result to a [ProviderContainer] or [ProviderScope].
List<Override> testOverrides({
  Map<String, Object> prefs = const {},
  DateTime Function()? clock,
  NotificationsService? notifications,
  DiagnosticsService? diagnostics,
  LinkOpener? linkOpener,
}) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(prefs);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return [
    appDatabaseProvider.overrideWithValue(db),
    defaultCurrencyCodeProvider.overrideWithValue('GBP'),
    formatLocaleProvider.overrideWithValue('en_GB'),
    clockProvider.overrideWithValue(clock ?? () => DateTime(2026, 9, 24)),
    notificationsServiceProvider.overrideWithValue(
      notifications ?? FakeNotificationsService(),
    ),
    diagnosticsProvider.overrideWithValue(diagnostics ?? NoDiagnostics()),
    linkOpenerProvider.overrideWithValue(linkOpener ?? FakeLinkOpener()),
    appVersionProvider.overrideWith((ref) async => '0.1.0 (2001)'),
  ];
}

/// A container with [testOverrides], disposed after the test. Failing
/// providers are not retried, so errors surface immediately.
ProviderContainer createTestContainer({
  Map<String, Object> prefs = const {},
  NotificationsService? notifications,
  DiagnosticsService? diagnostics,
  List<Override> overrides = const [],
}) => ProviderContainer.test(
  overrides: [
    ...testOverrides(
      prefs: prefs,
      notifications: notifications,
      diagnostics: diagnostics,
    ),
    ...overrides,
  ],
  retry: (_, _) => null,
);

/// Preferences holding a stored settings object with only [fields] set;
/// the rest fall back to defaults when loaded.
Map<String, Object> storedSettings(Map<String, Object?> fields) => {
  SettingsKeys.settings: jsonEncode(fields),
};
