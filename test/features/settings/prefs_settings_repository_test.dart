import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  PrefsSettingsRepository repositoryWith(Map<String, Object> stored) {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(stored);
    return PrefsSettingsRepository(
      SharedPreferencesAsync(),
      defaultCurrencyCode: 'GBP',
    );
  }

  test(
    'loads the legacy Settings-screen defaults when nothing is stored',
    () async {
      final settings = await repositoryWith({}).load();
      expect(settings, AppSettings.defaults('GBP'));
      expect(settings.monthlyBudget, const Money(30000, 'GBP'));
      expect(settings.strategyParameters, const StrategyParameters());
      expect(settings.onboardingComplete, isFalse);
    },
  );

  test('default budget is 300 major units in the default currency', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repo = PrefsSettingsRepository(
      SharedPreferencesAsync(),
      defaultCurrencyCode: 'JPY',
    );
    expect((await repo.load()).monthlyBudget, const Money(300, 'JPY'));
  });

  test('saves and loads every field', () async {
    final repo = repositoryWith({});
    const saved = AppSettings(
      currencyCode: 'USD',
      monthlyBudget: Money(45050, 'USD'),
      strategyParameters: StrategyParameters(
        consolidationAprBps: 399,
        transferFeeBps: 250,
        promoMonths: 18,
        revertAprBps: 2290,
      ),
      onboardingComplete: true,
    );
    await repo.save(saved);
    expect(await repo.load(), saved);
  });

  group('falls back to defaults for bad stored values', () {
    test('an invalid currency code', () async {
      final s = await repositoryWith({SettingsKeys.currencyCode: 'pounds'})
          .load();
      expect(s.currencyCode, 'GBP');
    });

    test('a non-positive budget', () async {
      final s = await repositoryWith({SettingsKeys.monthlyBudgetMinor: -500})
          .load();
      expect(s.monthlyBudget, const Money(30000, 'GBP'));
    });

    test('any out-of-range strategy parameter resets them all', () async {
      final s = await repositoryWith({
        SettingsKeys.consolidationAprBps: 700,
        SettingsKeys.promoMonths: -3,
      }).load();
      expect(s.strategyParameters, const StrategyParameters());
    });

    test('a value stored with the wrong type', () async {
      final s = await repositoryWith({
        SettingsKeys.monthlyBudgetMinor: 'lots',
        SettingsKeys.onboardingComplete: 'yes',
      }).load();
      expect(s.monthlyBudget, const Money(30000, 'GBP'));
      expect(s.onboardingComplete, isFalse);
    });
  });
}
