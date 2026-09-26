import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/test_container.dart';

void main() {
  late ProviderContainer container;
  SettingsController controller() =>
      container.read(settingsControllerProvider.notifier);
  Future<AppSettings> settings() =>
      container.read(settingsControllerProvider.future);
  Future<AppSettings> reloaded() =>
      container.read(settingsRepositoryProvider).load();

  setUp(() => container = createTestContainer());

  test('starts from the stored or default settings', () async {
    expect(await settings(), AppSettings.defaults('GBP'));
  });

  group('setMonthlyBudget', () {
    test('saves a valid budget', () async {
      expect(await controller().setMonthlyBudget(45000), isEmpty);
      expect((await settings()).monthlyBudget, const Money(45000, 'GBP'));
      expect((await reloaded()).monthlyBudget, const Money(45000, 'GBP'));
    });

    test('rejects a non-positive budget and keeps the old one', () async {
      expect(await controller().setMonthlyBudget(0), {
        BudgetValidationError.notPositive,
      });
      expect((await settings()).monthlyBudget, const Money(30000, 'GBP'));
    });
  });

  group('setStrategyParameters', () {
    const custom = StrategyParameters(
      consolidationAprBps: 299,
      promoMonths: 24,
    );

    test('saves valid parameters', () async {
      expect(await controller().setStrategyParameters(custom), isEmpty);
      expect((await settings()).strategyParameters, custom);
      expect((await reloaded()).strategyParameters, custom);
    });

    test('rejects invalid parameters', () async {
      final errors = await controller().setStrategyParameters(
        const StrategyParameters(transferFeeBps: -1),
      );
      expect(errors, {StrategyParametersValidationError.transferFeeOutOfRange});
      expect((await settings()).strategyParameters, const StrategyParameters());
    });
  });

  group('setCurrency', () {
    Future<List<Debt>> debts() async {
      final code = (await settings()).currencyCode;
      return await container.read(debtRepositoryProvider).loadAll(code);
    }

    setUp(() async {
      await container.read(settingsControllerProvider.future);
      await container
          .read(debtRepositoryProvider)
          .add(testDebt(id: 'a', balance: 123456, minPaymentFloor: 2550));
    });

    test('relabels amounts when decimal digits match', () async {
      await controller().setCurrency('USD');
      expect((await settings()).monthlyBudget, const Money(30000, 'USD'));
      expect((await debts()).single.balance, const Money(123456, 'USD'));
    });

    test('rescales the budget and debts when decimal digits differ', () async {
      await controller().setCurrency('JPY');
      expect((await settings()).monthlyBudget, const Money(300, 'JPY'));
      final debt = (await debts()).single;
      expect(debt.balance, const Money(1235, 'JPY'));
      expect(debt.minPaymentFloor, const Money(26, 'JPY'));

      await controller().setCurrency('GBP');
      expect((await settings()).monthlyBudget, const Money(30000, 'GBP'));
      expect((await debts()).single.balance, const Money(123500, 'GBP'));
    });

    test('keeps a tiny budget above zero after rounding', () async {
      await controller().setMonthlyBudget(40);
      await controller().setCurrency('JPY');
      expect((await settings()).monthlyBudget, const Money(1, 'JPY'));
    });

    test('rejects a malformed code', () async {
      expect(() => controller().setCurrency('pounds'), throwsArgumentError);
    });

    test('two quick switches to the same currency rescale once', () async {
      await Future.wait([
        controller().setCurrency('JPY'),
        controller().setCurrency('JPY'),
      ]);
      expect((await settings()).monthlyBudget, const Money(300, 'JPY'));
      expect((await debts()).single.balance, const Money(1235, 'JPY'));
    });

    test('a budget change racing a currency switch keeps both', () async {
      await Future.wait([
        controller().setCurrency('JPY'),
        controller().setMonthlyBudget(500),
      ]);
      final s = await settings();
      expect(s.currencyCode, 'JPY');
      expect(s.monthlyBudget, const Money(500, 'JPY'));
      expect((await debts()).single.balance, const Money(1235, 'JPY'));
    });

    test(
      'caps a budget that would exceed the maximum after rescaling',
      () async {
        await controller().setCurrency('JPY');
        await controller().setMonthlyBudget(kMaxAmountMinor);
        await controller().setCurrency('GBP');
        expect(
          (await settings()).monthlyBudget,
          const Money(kMaxAmountMinor, 'GBP'),
        );
      },
    );

    test('rescales the credit limit with the budget', () async {
      await controller().setStrategyParameters(
        const StrategyParameters(transferCreditLimit: Money(12345, 'GBP')),
      );
      await controller().setCurrency('JPY');
      expect(
        (await settings()).strategyParameters.transferCreditLimit,
        const Money(123, 'JPY'),
      );
    });
  });

  test(
    'repairs debts left in another currency by an interrupted switch',
    () async {
      // Simulate a crash after the debts were converted to JPY but before the
      // settings (still GBP) were saved.
      final repo = container.read(debtRepositoryProvider);
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      await repo.add(testDebt(id: 'a', balance: 123456));
      await repo.convertAmounts(toCurrencyCode: 'JPY');

      await container.read(settingsControllerProvider.future);
      expect(await repo.amountsCurrencyCode(), 'GBP');
      expect(
        (await repo.loadAll('GBP')).single.balance,
        const Money(123500, 'GBP'),
      );
    },
  );

  test('completeOnboarding is remembered', () async {
    await controller().completeOnboarding();
    expect((await settings()).onboardingComplete, isTrue);
    expect((await reloaded()).onboardingComplete, isTrue);
  });

  test('followStrategy saves the plan to follow', () async {
    await container
        .read(settingsControllerProvider.notifier)
        .followStrategy(StrategyId.snowball);
    expect(
      (await container.read(settingsControllerProvider.future))
          .followedStrategy,
      StrategyId.snowball,
    );
  });

  test('reminder setters save valid values and refuse others', () async {
    final controller = container.read(settingsControllerProvider.notifier);
    await controller.setPayDayReminder(on: true, day: 15);
    await controller.setCheckInNudgeMonths(1);
    final s = await container.read(settingsControllerProvider.future);
    expect((s.payDayReminder, s.payDay, s.checkInNudgeMonths), (true, 15, 1));
    expect(
      () => controller.setPayDayReminder(on: true, day: 29),
      throwsArgumentError,
    );
    expect(() => controller.setCheckInNudgeMonths(4), throwsArgumentError);
  });

  test('the diagnostics choice is saved', () async {
    final controller = container.read(settingsControllerProvider.notifier);
    await controller.setShareDiagnostics(on: true);
    expect(
      (await container.read(settingsControllerProvider.future))
          .shareDiagnostics,
      isTrue,
    );
    await controller.setShareDiagnostics(on: false);
    expect(
      (await container.read(settingsControllerProvider.future))
          .shareDiagnostics,
      isFalse,
    );
  });
}
