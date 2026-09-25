import 'dart:ui';

import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/debts/data/drift_debt_repository.dart';
import 'package:debt_destroyer/features/debts/domain/debt_repository.dart';
import 'package:debt_destroyer/features/progress/data/drift_progress_repository.dart';
import 'package:debt_destroyer/features/progress/domain/progress_repository.dart';
import 'package:debt_destroyer/features/scenarios/data/drift_scenario_repository.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario_repository.dart';
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
DebtRepository debtRepository(Ref ref) => DriftDebtRepository(
  ref.watch(appDatabaseProvider),
  now: ref.watch(clockProvider),
);

@Riverpod(keepAlive: true)
ScenarioRepository scenarioRepository(Ref ref) =>
    DriftScenarioRepository(ref.watch(appDatabaseProvider));

/// Check-ins and starting points, in the same database as the debts.
@Riverpod(keepAlive: true)
ProgressRepository progressRepository(Ref ref) =>
    DriftProgressRepository(ref.watch(appDatabaseProvider));
