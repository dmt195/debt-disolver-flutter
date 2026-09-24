import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Test doubles for the app's platform dependencies: in-memory preferences
/// seeded with [prefs], an in-memory database, and GBP as the device
/// currency. Pass the result to a [ProviderContainer] or [ProviderScope].
List<Override> testOverrides({Map<String, Object> prefs = const {}}) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(prefs);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return [
    appDatabaseProvider.overrideWithValue(db),
    defaultCurrencyCodeProvider.overrideWithValue('GBP'),
  ];
}

/// A container with [testOverrides], disposed after the test. Failing
/// providers are not retried, so errors surface immediately.
ProviderContainer createTestContainer({Map<String, Object> prefs = const {}}) =>
    ProviderContainer.test(
      overrides: testOverrides(prefs: prefs),
      retry: (_, _) => null,
    );
