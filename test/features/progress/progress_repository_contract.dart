import 'package:debt_destroyer/features/debts/domain/debt_repository.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:debt_destroyer/features/progress/domain/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';

/// Behaviour every [ProgressRepository] must have, run against the Drift one
/// and the in-memory test double. [open] makes a fresh pair holding debts
/// 'a' (Visa, 1,000.00) and 'b' (Loan, 500.00) in GBP.
void progressRepositoryContract(
  Future<(DebtRepository, ProgressRepository)> Function() open,
) {
  late DebtRepository debts;
  late ProgressRepository progress;
  const gbp = 'GBP';
  Money m(int minor) => Money(minor, gbp);

  setUp(() async {
    (debts, progress) = await open();
    await debts.convertAmounts(toCurrencyCode: gbp);
    await debts.add(testDebt(id: 'a', name: 'Visa'));
    await debts.add(testDebt(id: 'b', name: 'Loan', balance: 50000));
  });

  test('a check-in updates balances and clears zeros, in one go', () async {
    final c = await progress.saveCheckIn(
      at: DateTime(2026, 10, 3),
      balances: {'a': m(0), 'b': m(42000)},
    );
    expect(c.total, m(42000));
    expect(c.balances['a']!.name, 'Visa');
    expect(
      [for (final d in await debts.loadAll(gbp)) (d.id, d.balance.minor)],
      [('b', 42000)],
    );
    expect(
      (await debts.watchCleared().first).single.clearedAt,
      DateTime(2026, 10, 3),
    );
    final h = await progress.load(gbp);
    expect(h.checkIns.single.isStart, isFalse);
  });

  test('a starting point records a start check-in, debts untouched', () async {
    final s = await progress.recordStart(
      at: DateTime(2026, 9, 24),
      balances: {'a': m(100000), 'b': m(50000)},
      strategy: StrategyId.avalanche,
      reason: StartReason.initial,
      projectedTotals: [150000, 120000, 0],
    );
    final h = await progress.load(gbp);
    expect(h.starts.single.projectedTotals, [150000, 120000, 0]);
    expect(h.starts.single.strategy, StrategyId.avalanche);
    expect(h.checkInFor(s).isStart, isTrue);
    expect(h.checkInFor(s).total, m(150000));
    expect(await debts.loadAll(gbp), hasLength(2));
  });

  test('history is oldest first and the stream follows changes', () async {
    final stream = progress.watch(gbp);
    expect((await stream.first).checkIns, isEmpty);
    await progress.saveCheckIn(
      at: DateTime(2026, 10, 3),
      balances: {'a': m(90000)},
    );
    await progress.saveCheckIn(
      at: DateTime(2026, 9, 3),
      balances: {'a': m(95000)},
    );
    final h = await progress.watch(gbp).first;
    expect([for (final c in h.checkIns) c.at.month], [9, 10]);
  });

  test('start fresh deletes history, never debts', () async {
    await progress.recordStart(
      at: DateTime(2026, 9, 24),
      balances: {'a': m(100000)},
      strategy: StrategyId.avalanche,
      reason: StartReason.initial,
      projectedTotals: [100000, 0],
    );
    await progress.saveCheckIn(
      at: DateTime(2026, 10, 3),
      balances: {'a': m(0)},
    );
    await progress.clearHistory();
    final h = await progress.load(gbp);
    expect(h.checkIns, isEmpty);
    expect(h.starts, isEmpty);
    expect(await debts.watchCleared().first, hasLength(1)); // clearedAt kept
  });

  test('a debt deleted later keeps its check-in rows and name', () async {
    await progress.recordStart(
      at: DateTime(2026, 9, 24),
      balances: {'a': m(100000), 'b': m(50000)},
      strategy: StrategyId.avalanche,
      reason: StartReason.initial,
      projectedTotals: [150000, 0],
    );
    await debts.delete('b');
    final h = await progress.load(gbp);
    expect(h.checkIns.single.balances['b']!.name, 'Loan');
  });

  test('a currency with other decimals rescales history', () async {
    await progress.recordStart(
      at: DateTime(2026, 9, 24),
      balances: {'a': m(100000)},
      strategy: StrategyId.avalanche,
      reason: StartReason.initial,
      projectedTotals: [100000, 50000, 0],
    );
    await debts.convertAmounts(toCurrencyCode: 'JPY'); // 2 → 0 decimals
    final h = await progress.load('JPY');
    expect(h.checkIns.single.total, const Money(1000, 'JPY'));
    expect(h.checkIns.single.balances['a']!.balance, const Money(1000, 'JPY'));
    expect(h.starts.single.projectedTotals, [1000, 500, 0]);
  });
}
