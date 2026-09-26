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
  static const consolidationTermMonths = 'consolidationTermMonths';
  static const consolidationFeeBps = 'consolidationFeeBps';
  static const transferFeeBps = 'transferFeeBps';
  static const promoMonths = 'promoMonths';
  static const revertAprBps = 'revertAprBps';
  static const transferCreditLimitMinor = 'transferCreditLimitMinor';
  static const onboardingComplete = 'onboardingComplete';
  static const followedStrategy = 'followedStrategy';
  static const payDayReminder = 'payDayReminder';
  static const payDay = 'payDay';
  static const checkInNudgeMonths = 'checkInNudgeMonths';
  static const shareDiagnostics = 'shareDiagnostics';
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
    final limitMinor = field<int>(SettingsKeys.transferCreditLimitMinor);
    final parameters = StrategyParameters(
      consolidationAprBps:
          field<int>(SettingsKeys.consolidationAprBps) ?? d.consolidationAprBps,
      consolidationTermMonths:
          field<int>(SettingsKeys.consolidationTermMonths) ??
          d.consolidationTermMonths,
      consolidationFeeBps:
          field<int>(SettingsKeys.consolidationFeeBps) ?? d.consolidationFeeBps,
      transferFeeBps:
          field<int>(SettingsKeys.transferFeeBps) ?? d.transferFeeBps,
      promoMonths: field<int>(SettingsKeys.promoMonths) ?? d.promoMonths,
      revertAprBps: field<int>(SettingsKeys.revertAprBps) ?? d.revertAprBps,
      transferCreditLimit: limitMinor == null
          ? null
          : Money(limitMinor, currencyCode),
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
      followedStrategy: StrategyId.values
          .asNameMap()[field<String>(SettingsKeys.followedStrategy)],
      payDayReminder: field<bool>(SettingsKeys.payDayReminder) ?? false,
      payDay: switch (field<int>(SettingsKeys.payDay)) {
        final day? when day >= 0 && day <= 28 => day,
        _ => 28,
      },
      checkInNudgeMonths: switch (field<int>(SettingsKeys.checkInNudgeMonths)) {
        final months? when months >= 0 && months <= 3 => months,
        _ => 0,
      },
      shareDiagnostics: field<bool>(SettingsKeys.shareDiagnostics) ?? false,
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
        SettingsKeys.consolidationTermMonths: p.consolidationTermMonths,
        SettingsKeys.consolidationFeeBps: p.consolidationFeeBps,
        SettingsKeys.transferFeeBps: p.transferFeeBps,
        SettingsKeys.promoMonths: p.promoMonths,
        SettingsKeys.revertAprBps: p.revertAprBps,
        SettingsKeys.transferCreditLimitMinor: p.transferCreditLimit?.minor,
        SettingsKeys.onboardingComplete: settings.onboardingComplete,
        SettingsKeys.followedStrategy: settings.followedStrategy?.name,
        SettingsKeys.payDayReminder: settings.payDayReminder,
        SettingsKeys.payDay: settings.payDay,
        SettingsKeys.checkInNudgeMonths: settings.checkInNudgeMonths,
        SettingsKeys.shareDiagnostics: settings.shareDiagnostics,
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
