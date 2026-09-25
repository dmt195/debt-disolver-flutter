import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:debt_destroyer/features/progress/domain/progress_math.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/test_container.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = createTestContainer()
      // The app keeps the reconciler alive; so must the test.
      ..listen(progressReconcilerProvider, (_, _) {});
  });

  Future<ProgressHistory> history() =>
      container.read(progressRepositoryProvider).load('GBP');

  /// Waits for the reconciler (and its plan calculations) to go quiet.
  Future<ProgressHistory> settled() async {
    var last = -1;
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final count = (await history()).starts.length;
      if (count == last && i > 10) break;
      last = count;
    }
    return await history();
  }

  DebtActions actions() => container.read(debtActionsProvider.notifier);
  ProgressController progress() =>
      container.read(progressControllerProvider.notifier);

  Future<String> addDebt(String name, {int balance = 100000}) async {
    final outcome = await actions().add(
      testDebt(id: '', name: name, balance: balance),
    );
    return (outcome as DebtSaved).debt.id;
  }

  test(
    'the first run records one initial start and follows the cheapest',
    () async {
      await addDebt('Visa');
      final h = await settled();
      expect([for (final s in h.starts) s.reason], [StartReason.initial]);
      final settings = await container.read(settingsControllerProvider.future);
      expect(settings.followedStrategy, StrategyId.avalanche);
      expect(h.starts.single.projectedTotals.first, 100000);
    },
  );

  test('adding a debt records one named start', () async {
    await addDebt('Visa');
    await settled();
    await addDebt('Amex', balance: 30000);
    final h = await settled();
    expect(
      [for (final s in h.starts) (s.reason, s.debtName)],
      [(StartReason.initial, null), (StartReason.debtAdded, 'Amex')],
    );
  });

  test(
    'nothing is recorded while the budget cannot cover the minimums',
    () async {
      await container
          .read(settingsControllerProvider.notifier)
          .setMonthlyBudget(1000);
      await addDebt('Visa');
      expect((await settled()).starts, isEmpty);
      await container
          .read(settingsControllerProvider.notifier)
          .setMonthlyBudget(30000);
      expect(
        [for (final s in (await settled()).starts) s.reason],
        [StartReason.initial],
      );
    },
  );

  test('a check-in clears a debt without restarting', () async {
    final visa = await addDebt('Visa');
    final amex = await addDebt('Amex', balance: 30000);
    await settled();
    final outcome = await progress().saveCheckIn({
      visa: const Money(90000, 'GBP'),
      amex: const Money(0, 'GBP'),
    });
    expect(
      [for (final c in outcome.cleared) (c.name, c.gone.minor)],
      [('Amex', 30000)],
    );
    expect(outcome.cleared.single.next, 'Visa');
    expect(outcome.cleared.single.clearedCount, 1);
    expect(outcome.cleared.single.totalCount, 2);
    expect(outcome.monthsBefore, isPositive);
    final h = await settled();
    expect(h.starts, hasLength(1));
    expect(
      [for (final d in await container.read(debtsProvider.future)) d.name],
      ['Visa'],
    );
    expect(container.read(progressControllerProvider), same(outcome));
  });

  test('a higher balance is reported as gone up', () async {
    final visa = await addDebt('Visa');
    await settled();
    final outcome = await progress().saveCheckIn({
      visa: const Money(103000, 'GBP'),
    });
    expect(
      [for (final w in outcome.wentUp) (w.name, w.up.minor)],
      [('Visa', 3000)],
    );
  });

  test('start fresh leaves one new initial start and keeps the rest', () async {
    final visa = await addDebt('Visa');
    final amex = await addDebt('Amex', balance: 30000);
    await settled();
    await progress().follow(StrategyId.snowball);
    await settled();
    await progress().saveCheckIn({
      amex: const Money(0, 'GBP'),
      visa: const Money(90000, 'GBP'),
    });
    await progress().restart(clearHistory: true);
    final h = await settled();
    expect([for (final s in h.starts) s.reason], [StartReason.initial]);
    expect(h.checkIns, hasLength(1));
    final settings = await container.read(settingsControllerProvider.future);
    expect(settings.followedStrategy, StrategyId.snowball);
    expect(await container.read(clearedDebtsProvider.future), hasLength(1));
  });

  test('restart keeping history adds a restarted start', () async {
    await addDebt('Visa');
    await settled();
    await progress().restart(clearHistory: false);
    expect(
      [for (final s in (await settled()).starts) s.reason],
      [StartReason.initial, StartReason.restarted],
    );
  });

  test('following another plan records a switch', () async {
    await addDebt('Visa');
    await settled();
    await progress().follow(StrategyId.snowball);
    final h = await settled();
    expect(h.starts.last.reason, StartReason.planSwitched);
    expect(h.starts.last.strategy, StrategyId.snowball);
  });

  test('re-opening a cleared debt counts as added', () async {
    final visa = await addDebt('Visa');
    final amex = await addDebt('Amex', balance: 30000);
    await settled();
    await progress().saveCheckIn({
      amex: const Money(0, 'GBP'),
      visa: const Money(90000, 'GBP'),
    });
    await settled();
    await progress().reopen(amex, const Money(5000, 'GBP'));
    final h = await settled();
    expect(
      (h.starts.last.reason, h.starts.last.debtName),
      (StartReason.debtAdded, 'Amex'),
    );
  });

  test('the summary says paid off and where you stand', () async {
    final visa = await addDebt('Visa');
    await settled();
    container.listen(progressSummaryProvider, (_, _) {});
    await progress().saveCheckIn({visa: const Money(60000, 'GBP')});
    await settled();
    final summary = await container.read(progressSummaryProvider.future);
    expect(summary.paid.amount, const Money(40000, 'GBP'));
    expect(summary.standing, isNot(isA<NoProgressYet>()));
    expect(summary.chart, isNotNull);
  });
}
