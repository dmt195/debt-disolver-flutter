import 'dart:ui';

import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/debts/data/drift_debt_repository.dart';
import 'package:debt_destroyer/features/debts/domain/debt_repository.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/domain/settings_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'dependencies.g.dart';

/// The on-device database. Tests override this with an in-memory one.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
}

/// Currency used until the user chooses one: the device locale's.
@Riverpod(keepAlive: true)
String defaultCurrencyCode(Ref ref) =>
    currencyCodeForLocale(PlatformDispatcher.instance.locale.toString());

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) => PrefsSettingsRepository(
  SharedPreferencesAsync(),
  defaultCurrencyCode: ref.watch(defaultCurrencyCodeProvider),
);

@Riverpod(keepAlive: true)
DebtRepository debtRepository(Ref ref) =>
    DriftDebtRepository(ref.watch(appDatabaseProvider));
