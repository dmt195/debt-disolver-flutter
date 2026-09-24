import 'dart:convert';

import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/domain/settings_repository.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All settings are stored as one JSON object under [settings], so each save
/// is a single atomic write and can never be half-applied. The other
/// constants are that object's field names.
abstract final class SettingsKeys {
  static const settings = 'settings.v1';

  static const currencyCode = 'currencyCode';
  static const monthlyBudgetMinor = 'monthlyBudgetMinor';
  static const consolidationAprBps = 'consolidationAprBps';
  static const transferFeeBps = 'transferFeeBps';
  static const promoMonths = 'promoMonths';
  static const revertAprBps = 'revertAprBps';
  static const onboardingComplete = 'onboardingComplete';
}

class PrefsSettingsRepository implements SettingsRepository {
  PrefsSettingsRepository(this._prefs, {required this.defaultCurrencyCode});

  final SharedPreferencesAsync _prefs;

  /// Used until the user picks a currency.
  final String defaultCurrencyCode;

  @override
  Future<AppSettings> load() async {
    final stored = await _storedFields();
    T? field<T>(String key) => switch (stored[key]) {
      final T value => value,
      _ => null, // missing, or stored with the wrong type
    };

    final storedCode = field<String>(SettingsKeys.currencyCode);
    final currencyCode = storedCode != null && isCurrencyCode(storedCode)
        ? storedCode
        : defaultCurrencyCode;
    final defaults = AppSettings.defaults(currencyCode);

    final budgetMinor = field<int>(SettingsKeys.monthlyBudgetMinor);
    final budget = budgetMinor == null
        ? defaults.monthlyBudget
        : Money(budgetMinor, currencyCode);

    const d = StrategyParameters();
    final parameters = StrategyParameters(
      consolidationAprBps:
          field<int>(SettingsKeys.consolidationAprBps) ?? d.consolidationAprBps,
      transferFeeBps:
          field<int>(SettingsKeys.transferFeeBps) ?? d.transferFeeBps,
      promoMonths: field<int>(SettingsKeys.promoMonths) ?? d.promoMonths,
      revertAprBps: field<int>(SettingsKeys.revertAprBps) ?? d.revertAprBps,
    );

    return AppSettings(
      currencyCode: currencyCode,
      monthlyBudget: validateBudget(budget).isEmpty
          ? budget
          : defaults.monthlyBudget,
      strategyParameters: validateStrategyParameters(parameters).isEmpty
          ? parameters
          : defaults.strategyParameters,
      onboardingComplete: field<bool>(SettingsKeys.onboardingComplete) ?? false,
    );
  }

  @override
  Future<void> save(AppSettings settings) {
    final p = settings.strategyParameters;
    return _prefs.setString(
      SettingsKeys.settings,
      jsonEncode({
        SettingsKeys.currencyCode: settings.currencyCode,
        SettingsKeys.monthlyBudgetMinor: settings.monthlyBudget.minor,
        SettingsKeys.consolidationAprBps: p.consolidationAprBps,
        SettingsKeys.transferFeeBps: p.transferFeeBps,
        SettingsKeys.promoMonths: p.promoMonths,
        SettingsKeys.revertAprBps: p.revertAprBps,
        SettingsKeys.onboardingComplete: settings.onboardingComplete,
      }),
    );
  }

  /// The stored JSON object, or an empty map if it is missing or unreadable.
  Future<Map<String, Object?>> _storedFields() async {
    try {
      final raw = await _prefs.getString(SettingsKeys.settings);
      final decoded = raw == null ? null : jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : const {};
    } on Object {
      return const {};
    }
  }
}
