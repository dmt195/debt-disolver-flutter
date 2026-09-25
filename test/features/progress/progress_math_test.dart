import 'package:debt_destroyer/features/debts/domain/cleared_debt.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:debt_destroyer/features/progress/domain/progress_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';

Money gbp(int minor) => Money(minor, 'GBP');

CheckIn ci(String id, DateTime at, Map<String, int> b, {bool start = false}) =>
    CheckIn(
      id: id,
      at: at,
      isStart: start,
      total: gbp(b.values.fold(0, (s, v) => s + v)),
      balances: {
        for (final e in b.entries)
          e.key: (name: e.key.toUpperCase(), balance: gbp(e.value)),
      },
    );

StartingPoint sp(
  String id,
  String checkIn,
  DateTime at,
  List<int> totals, {
  StrategyId s = StrategyId.avalanche,
  StartReason r = StartReason.initial,
  String? name,
}) => StartingPoint(
  id: id,
  at: at,
  checkInId: checkIn,
  strategy: s,
  reason: r,
  projectedTotals: totals,
  debtName: name,
);

ClearedDebt cleared(String id, DateTime at) =>
    ClearedDebt(id: id, name: id, type: DebtType.loan, clearedAt: at);

void main() {
  test('monthIndex counts calendar months across the year end', () {
    expect(monthIndex(DateTime(2026, 12, 31), DateTime(2027)), 1);
    expect(monthIndex(DateTime(2026, 9, 24), DateTime(2026, 9, 30)), 0);
    expect(monthIndex(DateTime(2026, 9, 24), DateTime(2028, 2)), 17);
  });

  test('projected totals: the start, then each month', () {
    final plan = PayoffPlan(
      debts: [PlanDebt(id: 'a', name: 'A', startingBalance: gbp(20000))],
      months: [
        MonthRow(
          month: 1,
          interest: [gbp(0)],
          payments: [gbp(10000)],
          closingBalances: [gbp(10000)],
        ),
      ],
      totalPaid: gbp(20000),
      totalInterest: gbp(0),
      totalFees: gbp(0),
    );
    expect(projectedTotals(plan), [20000, 10000]);
  });

  test("paid off counts from each debt's first recorded balance", () {
    final h = ProgressHistory(
      checkIns: [
        ci('s', DateTime(2026, 6), {'a': 100000, 'b': 50000}, start: true),
        ci('c', DateTime(2026, 9), {'a': 90000, 'b': 0}),
        ci('s2', DateTime(2026, 9, 2), {'a': 90000, 'n': 20000}, start: true),
      ],
      starts: [
        sp('1', 's', DateTime(2026, 6), [150000, 0]),
        sp('2', 's2', DateTime(2026, 9, 2), [
          110000,
          0,
        ], r: StartReason.debtAdded),
      ],
    );
    final r = paidOff(
      h,
      [testDebt(id: 'a', balance: 80000), testDebt(id: 'n', balance: 20000)],
      [cleared('b', DateTime(2026, 9))],
      'GBP',
    );
    // a: 1,000 → 800; b: 500 → 0; n: 200 → 200.
    expect(r.amount, gbp(70000));
    expect(r.percent, 41); // 70,000 / 170,000
    expect(r.since, DateTime(2026, 6));
  });

  test('a deleted debt drops out; owing more is negative', () {
    final h = ProgressHistory(
      checkIns: [
        ci('s', DateTime(2026, 6), {'a': 100000, 'gone': 5000}, start: true),
      ],
      starts: [
        sp('1', 's', DateTime(2026, 6), [105000, 0]),
      ],
    );
    final r = paidOff(h, [testDebt(id: 'a', balance: 110000)], const [], 'GBP');
    expect(r.amount, gbp(-10000));
    expect(r.percent, 0);
  });

  group('ahead or behind', () {
    // Start 1 Jun: 1,000.00 projected to fall 100.00 a month.
    final totals = [for (var i = 0; i <= 10; i++) 100000 - i * 10000];
    ProgressHistory at(DateTime when, int total) => ProgressHistory(
      checkIns: [
        ci('s', DateTime(2026, 6), {'a': 100000}, start: true),
        ci('c', when, {'a': total}),
      ],
      starts: [sp('1', 's', DateTime(2026, 6), totals)],
    );

    test('nothing since the start', () {
      final h = ProgressHistory(
        checkIns: [
          ci('s', DateTime(2026, 6), {'a': 100000}, start: true),
        ],
        starts: [sp('1', 's', DateTime(2026, 6), totals)],
      );
      expect(aheadBehind(h, 'GBP'), isA<NoProgressYet>());
      expect(aheadBehind(const ProgressHistory(), 'GBP'), isA<NoProgressYet>());
    });

    test('within 1% is on track', () {
      expect(aheadBehind(at(DateTime(2026, 9), 70500), 'GBP'), isA<OnTrack>());
    });

    test('months ahead when a later month is matched', () {
      final r = aheadBehind(at(DateTime(2026, 9), 60000), 'GBP');
      expect((r as AheadMonths).months, 1);
    });

    test('money ahead when less than a month ahead', () {
      final r = aheadBehind(at(DateTime(2026, 9), 65000), 'GBP');
      expect((r as AheadMoney).amount, gbp(5000));
    });

    test('behind', () {
      final r = aheadBehind(at(DateTime(2026, 9), 78000), 'GBP');
      expect((r as Behind).amount, gbp(8000));
    });

    test("past the projection's end, anything owed is behind", () {
      final r = aheadBehind(at(DateTime(2027, 12), 3000), 'GBP');
      expect((r as Behind).amount, gbp(3000));
    });
  });

  test('expected balances: now, after k months, beyond the end', () {
    MonthRow row(int month, List<int> closing) => MonthRow(
      month: month,
      interest: [for (final _ in closing) gbp(0)],
      payments: [for (final _ in closing) gbp(0)],
      closingBalances: [for (final c in closing) gbp(c)],
    );
    final plan = PayoffPlan(
      debts: [
        PlanDebt(id: 'a', name: 'A', startingBalance: gbp(20000)),
        PlanDebt(id: 'b', name: 'B', startingBalance: gbp(30000)),
        PlanDebt(id: 'b#from-c', name: 'C', startingBalance: gbp(10000)),
      ],
      months: [
        row(1, [10000, 25000, 8000]),
        row(2, [0, 20000, 0]),
      ],
      totalPaid: gbp(60000),
      totalInterest: gbp(0),
      totalFees: gbp(0),
    );
    final debts = [
      testDebt(id: 'a', balance: 20000),
      testDebt(id: 'b', balance: 30000),
      testDebt(id: 'c', balance: 10000),
    ];
    expect(expectedBalances(plan, 0, debts), {
      'a': gbp(20000),
      'b': gbp(30000),
      'c': gbp(10000),
    });
    // c was moved onto b: its own column is gone, so it expects 0.
    expect(expectedBalances(plan, 1, debts), {
      'a': gbp(10000),
      'b': gbp(33000),
      'c': gbp(0),
    });
    expect(expectedBalances(plan, 5, debts), {
      'a': gbp(0),
      'b': gbp(0),
      'c': gbp(0),
    });
  });

  group('next starting point', () {
    final a = testDebt(id: 'a', name: 'Visa');
    final b = testDebt(id: 'b', name: 'Loan');
    final base = ProgressHistory(
      checkIns: [
        ci('s', DateTime(2026, 6), {'a': 100000, 'b': 50000}, start: true),
      ],
      starts: [
        sp('1', 's', DateTime(2026, 6), [150000, 0]),
      ],
    );
    ({StartReason reason, String? debtName})? next(
      ProgressHistory history,
      List<Debt> uncleared, {
      List<ClearedDebt> clearedDebts = const [],
      StrategyId followed = StrategyId.avalanche,
      bool feasible = true,
    }) => nextStart(
      history: history,
      uncleared: uncleared,
      cleared: clearedDebts,
      followed: followed,
      feasible: feasible,
    );

    test('the first one is initial', () {
      expect(next(const ProgressHistory(), [a])!.reason, StartReason.initial);
    });

    test('none while infeasible', () {
      expect(next(const ProgressHistory(), [a], feasible: false), isNull);
    });

    test('none when nothing changed', () {
      expect(next(base, [a, b]), isNull);
    });

    test('a plan switch', () {
      expect(
        next(base, [a, b], followed: StrategyId.snowball)!.reason,
        StartReason.planSwitched,
      );
    });

    test('an added debt, named', () {
      final r = next(base, [a, b, testDebt(id: 'n', name: 'Amex')])!;
      expect((r.reason, r.debtName), (StartReason.debtAdded, 'Amex'));
    });

    test('a deleted debt, named from history', () {
      final r = next(base, [a])!;
      expect((r.reason, r.debtName), (StartReason.debtDeleted, 'B'));
    });

    final afterClearing = ProgressHistory(
      checkIns: [
        ...base.checkIns,
        ci('c', DateTime(2026, 8), {'a': 90000, 'b': 0}),
        ci('c2', DateTime(2026, 9), {'a': 80000}),
      ],
      starts: base.starts,
    );

    test('clearing is progress, not a restart', () {
      expect(
        next(
          afterClearing,
          [a],
          clearedDebts: [cleared('b', DateTime(2026, 8))],
        ),
        isNull,
      );
    });

    test('re-opening a cleared debt counts as added', () {
      expect(next(afterClearing, [a, b])!.reason, StartReason.debtAdded);
    });
  });

  test('chart: actual across restarts, latest projection, original', () {
    final h = ProgressHistory(
      checkIns: [
        ci('s', DateTime(2026, 6), {'a': 100000}, start: true),
        ci('c', DateTime(2026, 7), {'a': 90000}),
        ci('s2', DateTime(2026, 8), {'a': 80000}, start: true),
      ],
      starts: [
        sp('1', 's', DateTime(2026, 6), [100000, 90000, 0]),
        sp(
          '2',
          's2',
          DateTime(2026, 8),
          [80000, 40000, 0],
          s: StrategyId.snowball,
          r: StartReason.planSwitched,
        ),
      ],
    );
    final chart = progressChartData(h, DateTime(2026, 8, 16), 'GBP');
    expect(chart.actual, [(0.0, 1000.0), (1.0, 900.0), (2.0, 800.0)]);
    expect(chart.current, [(2.0, 800.0), (3.0, 400.0), (4.0, 0.0)]);
    expect(chart.original, [(0.0, 1000.0), (1.0, 900.0), (2.0, 0.0)]);
    expect(chart.markers.single.strategy, StrategyId.snowball);
    expect(chart.markers.single.x, 2.0);
    expect(chart.today, closeTo(2.5, 0.05));
  });

  test('chart: one start has no original line', () {
    final h = ProgressHistory(
      checkIns: [
        ci('s', DateTime(2026, 6), {'a': 100000}, start: true),
      ],
      starts: [
        sp('1', 's', DateTime(2026, 6), [100000, 0]),
      ],
    );
    expect(progressChartData(h, DateTime(2026, 6), 'GBP').original, isNull);
  });
}
