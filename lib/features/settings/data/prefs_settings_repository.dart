import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/domain/settings_repository.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preference keys. Every key the app stores is listed here.
abstract final class SettingsKeys {
  static const currencyCode = 'settings.currencyCode';
  static const monthlyBudgetMinor = 'settings.monthlyBudgetMinor';
  static const consolidationAprBps = 'settings.consolidationAprBps';
  static const transferFeeBps = 'settings.transferFeeBps';
  static const promoMonths = 'settings.promoMonths';
  static const revertAprBps = 'settings.revertAprBps';
  static const onboardingComplete = 'settings.onboardingComplete';
}

class PrefsSettingsRepository implements SettingsRepository {
  PrefsSettingsRepository(this._prefs, {required this.defaultCurrencyCode});

  final SharedPreferencesAsync _prefs;

  /// Used until the user picks a currency.
  final String defaultCurrencyCode;

  @override
  Future<AppSettings> load() async {
    final storedCode = await _string(SettingsKeys.currencyCode);
    final currencyCode = storedCode != null && isCurrencyCode(storedCode)
        ? storedCode
        : defaultCurrencyCode;
    final defaults = AppSettings.defaults(currencyCode);

    final budgetMinor = await _int(SettingsKeys.monthlyBudgetMinor);
    final budget = budgetMinor == null
        ? defaults.monthlyBudget
        : Money(budgetMinor, currencyCode);

    const d = StrategyParameters();
    final parameters = StrategyParameters(
      consolidationAprBps:
          await _int(SettingsKeys.consolidationAprBps) ?? d.consolidationAprBps,
      transferFeeBps:
          await _int(SettingsKeys.transferFeeBps) ?? d.transferFeeBps,
      promoMonths: await _int(SettingsKeys.promoMonths) ?? d.promoMonths,
      revertAprBps: await _int(SettingsKeys.revertAprBps) ?? d.revertAprBps,
    );

    return AppSettings(
      currencyCode: currencyCode,
      monthlyBudget: validateBudget(budget).isEmpty
          ? budget
          : defaults.monthlyBudget,
      strategyParameters: validateStrategyParameters(parameters).isEmpty
          ? parameters
          : defaults.strategyParameters,
      onboardingComplete: await _bool(SettingsKeys.onboardingComplete) ?? false,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final p = settings.strategyParameters;
    await _prefs.setString(SettingsKeys.currencyCode, settings.currencyCode);
    await _prefs.setInt(
      SettingsKeys.monthlyBudgetMinor,
      settings.monthlyBudget.minor,
    );
    await _prefs.setInt(
      SettingsKeys.consolidationAprBps,
      p.consolidationAprBps,
    );
    await _prefs.setInt(SettingsKeys.transferFeeBps, p.transferFeeBps);
    await _prefs.setInt(SettingsKeys.promoMonths, p.promoMonths);
    await _prefs.setInt(SettingsKeys.revertAprBps, p.revertAprBps);
    await _prefs.setBool(
      SettingsKeys.onboardingComplete,
      settings.onboardingComplete,
    );
  }

  // A value stored with the wrong type reads as missing.
  Future<String?> _string(String key) => _read(() => _prefs.getString(key));
  Future<int?> _int(String key) => _read(() => _prefs.getInt(key));
  Future<bool?> _bool(String key) => _read(() => _prefs.getBool(key));

  Future<T?> _read<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } on Object {
      return null;
    }
  }
}
