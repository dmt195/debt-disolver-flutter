import 'dart:math';

import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const strategy = Strategy.cardTransfers();
  const zeroForAYear = Promo(aprBps: 0, months: 12);

  // Store card: 1,000.00 at 30%. Amex: 500.00 at 12% with an offer of
  // 0% for 12 months, 3% fee, 600.00 of room.
  final store = debt(
    id: 'store',
    name: 'Store',
    type: DebtType.storeCard,
    balance: 100000,
    aprBps: 3000,
    minPaymentPercentBps: 300,
    minPaymentFloor: 2500,
  );
  final amex = debt(
    id: 'amex',
    name: 'Amex',
    balance: 50000,
    aprBps: 1200,
    minPaymentPercentBps: 300,
    minPaymentFloor: 2500,
    transferOffer: TransferOffer(
      feeBps: 300,
      promo: zeroForAYear,
      availableCredit: gbp(60000),
    ),
  );

  PayoffResult run(List<Debt> debts, int budget) =>
      calculate(debts: debts, monthlyBudget: gbp(budget), strategy: strategy);

  test('moves the most that fits the room, fee included', () {
    // x + 3% of x <= 600.00 gives x = 582.52 with a 17.48 fee (600.00);
    // 582.53 would need 600.01.
    final plan = planOf(run([store, amex], 30000));
    final change = plan.change! as CardTransferChange;
    expect(change.moves, [
      CardMove(
        fromDebtId: 'store',
        fromName: 'Store',
        toDebtId: 'amex',
        toName: 'Amex',
        amount: gbp(58252),
        fee: gbp(1748),
        promo: zeroForAYear,
      ),
    ]);
    expect(plan.totalFees, gbp(1748));
    expect(
      plan.debts.map((d) => d.id),
      containsAll(['store', 'amex', 'amex#from-store']),
    );
    expect(
      plan.debts.firstWhere((d) => d.id == 'amex#from-store').name,
      'Amex (moved from Store)',
    );
  });

  test('a move is kept only because the plan costs less with it', () {
    final withMoves = planOf(run([store, amex], 30000));
    final without = planOf(
      calculate(
        debts: [store, amex],
        monthlyBudget: gbp(30000),
        strategy: const Strategy.avalanche(),
      ),
    );
    expect(withMoves.totalPaid < without.totalPaid, isTrue);
  });

  test('no offers means not applicable', () {
    expect(
      run([store, amex.copyWith(transferOffer: null)], 30000),
      const PayoffResult.notApplicable(
        strategyId: StrategyId.cardTransfers,
        reason: NotApplicableReason.noCardOffers,
      ),
    );
  });

  test('a move that costs more than it saves is not made', () {
    // 13% onto 12% with a 10% fee and no promo never pays for itself.
    final a = debt(id: 'a', balance: 10000, aprBps: 1300);
    final b = debt(
      id: 'b',
      balance: 10000,
      aprBps: 1200,
      transferOffer: TransferOffer(feeBps: 1000, availableCredit: gbp(50000)),
    );
    expect(
      run([a, b], 5000),
      const PayoffResult.notApplicable(
        strategyId: StrategyId.cardTransfers,
        reason: NotApplicableReason.noWorthwhileMoves,
      ),
    );
  });

  test('a 0%-fee move that saves no money is not made', () {
    // Both balances are small enough, relative to their APRs, that a
    // month's interest rounds to zero either way: moving one onto the
    // other's offer (no fee) cannot lower totalPaid, so it must not be
    // made, even if it happened to finish in fewer months.
    final a = debt(id: 'a', balance: 1000, aprBps: 59);
    final b = debt(
      id: 'b',
      balance: 2000,
      aprBps: 1,
      transferOffer: TransferOffer(feeBps: 0, availableCredit: gbp(1000000)),
    );
    expect(
      run([a, b], 1000),
      const PayoffResult.notApplicable(
        strategyId: StrategyId.cardTransfers,
        reason: NotApplicableReason.noWorthwhileMoves,
      ),
    );
  });

  test('an unaffordable budget is infeasible, not "no worthwhile moves"', () {
    // 10.00 covers neither card's minimum, with or without a move.
    final result = run([store, amex], 1000);
    expect(result, isA<Infeasible>());
    expect(result.strategyId, StrategyId.cardTransfers);
  });

  test('a move that rescues an unaffordable budget is kept', () {
    // Store: 100.00 at 30%, 25.00 floor. Amex: 100.00 at 12%, 25.00 floor,
    // an offer of 0% fee, 0% for 12 months, 500.00 room. At 30.00 a month,
    // the minimums (50.00) aren't affordable without a move; emptying the
    // store card onto Amex leaves one 25.00 minimum, which is.
    final storeSmall = debt(
      id: 'store',
      name: 'Store',
      type: DebtType.storeCard,
      balance: 10000,
      aprBps: 3000,
      minPaymentFloor: 2500,
    );
    final amexSmall = debt(
      id: 'amex',
      name: 'Amex',
      balance: 10000,
      aprBps: 1200,
      minPaymentFloor: 2500,
      transferOffer: TransferOffer(
        feeBps: 0,
        promo: zeroForAYear,
        availableCredit: gbp(50000),
      ),
    );
    final withoutMove = calculate(
      debts: [storeSmall, amexSmall],
      monthlyBudget: gbp(3000),
      strategy: const Strategy.avalanche(),
    );
    expect(withoutMove, isA<Infeasible>());

    final result = run([storeSmall, amexSmall], 3000);
    final change = planOf(result).change! as CardTransferChange;
    expect(change.moves, hasLength(1));
  });

  test('never moves onto a card whose rate is not lower', () {
    final b = amex.copyWith(
      aprBps: 3500,
      transferOffer: TransferOffer(feeBps: 0, availableCredit: gbp(60000)),
    );
    expect(cardMoveCandidates([store, b], const []), isEmpty);
  });

  test('never moves from a loan or onto the same card', () {
    final loan = debt(
      id: 'loan',
      type: DebtType.loan,
      balance: 100000,
      aprBps: 3000,
    );
    expect(
      cardMoveCandidates([loan, amex], const []).map((m) => m.fromDebtId),
      isNot(contains('loan')),
    );
    expect(
      cardMoveCandidates([amex], const []),
      isEmpty,
      reason: 'the only card with an offer cannot move onto itself',
    );
  });

  test('a card never both gives and receives money', () {
    // Both cards have offers and each could move to the other.
    final a = debt(
      id: 'a',
      name: 'A',
      balance: 100000,
      aprBps: 3000,
      transferOffer: TransferOffer(
        feeBps: 0,
        promo: zeroForAYear,
        availableCredit: gbp(200000),
      ),
    );
    final b = debt(
      id: 'b',
      name: 'B',
      balance: 100000,
      aprBps: 2500,
      transferOffer: TransferOffer(
        feeBps: 0,
        promo: zeroForAYear,
        availableCredit: gbp(200000),
      ),
    );
    final change = planOf(run([a, b], 30000)).change! as CardTransferChange;
    final sources = change.moves.map((m) => m.fromDebtId).toSet();
    final targets = change.moves.map((m) => m.toDebtId).toSet();
    expect(sources.intersection(targets), isEmpty);
  });

  test('never chooses moves that make the minimums unaffordable', () {
    // Amex's minimum is 50% of its balance: taking the store balance on
    // would push its minimum past the budget.
    final a = debt(
      id: 'a',
      type: DebtType.storeCard,
      balance: 10000,
      aprBps: 3000,
      minPaymentPercentBps: 300,
    );
    final b = debt(
      id: 'b',
      balance: 10000,
      aprBps: 1200,
      minPaymentPercentBps: 5000,
      transferOffer: TransferOffer(
        feeBps: 0,
        promo: zeroForAYear,
        availableCredit: gbp(20000),
      ),
    );
    expect(
      run([a, b], 5400),
      const PayoffResult.notApplicable(
        strategyId: StrategyId.cardTransfers,
        reason: NotApplicableReason.noWorthwhileMoves,
      ),
    );
  });

  test('stops after kMaxCardMoves moves', () {
    final sources = [
      for (var i = 0; i < 12; i++)
        debt(
          id: 's${i.toString().padLeft(2, '0')}',
          balance: 1000,
          aprBps: 3000,
        ),
    ];
    final target = debt(
      id: 't',
      balance: 1000,
      aprBps: 1200,
      transferOffer: TransferOffer(
        feeBps: 0,
        promo: zeroForAYear,
        availableCredit: gbp(1000000),
      ),
    );
    final change =
        planOf(run([...sources, target], 30000)).change! as CardTransferChange;
    expect(change.moves, hasLength(kMaxCardMoves));
  });

  group('shortlistCardMoves', () {
    // aprBps 1000 throughout; a candidate's estimate is
    // (1000 - to.aprBps) * amount / 10000 - fee.
    final a = debt(id: 'a', balance: 100000, aprBps: 1000);
    final x = debt(id: 'x', balance: 100000);
    final y = debt(id: 'y', balance: 100000, aprBps: 500);
    final w = debt(id: 'w', balance: 100000);
    final debts = [a, x, y, w];

    CardMove move({
      required String to,
      required int amount,
      int fee = 0,
      String from = 'a',
    }) => CardMove(
      fromDebtId: from,
      fromName: from,
      toDebtId: to,
      toName: to,
      amount: gbp(amount),
      fee: gbp(fee),
    );

    test('ranks the highest saving estimate first', () {
      // x: (1000-0)*10000/10000-0 = 1000. y: (1000-500)*10000/10000-0 =
      // 500. Given out of order, the shortlist puts the bigger saving first.
      final lowSaving = move(to: 'y', amount: 10000);
      final highSaving = move(to: 'x', amount: 10000);
      expect(shortlistCardMoves(debts, [lowSaving, highSaving]), [
        highSaving,
        lowSaving,
      ]);
    });

    test('subtracts the fee from the estimate', () {
      // Same rate cut and amount as x above (estimate 1000 before the fee),
      // but a 700 fee drops w's estimate to 300: below y's 500.
      final y500 = move(to: 'y', amount: 10000);
      final wWithFee = move(to: 'w', amount: 10000, fee: 700);
      expect(shortlistCardMoves(debts, [wWithFee, y500]), [y500, wWithFee]);
    });

    test("keeps candidates' order on a tie", () {
      final first = move(to: 'x', amount: 10000);
      final second = move(to: 'x', amount: 10000);
      expect(shortlistCardMoves(debts, [first, second]), [first, second]);
    });

    test('returns at most kCardMoveShortlist candidates, highest first', () {
      // Amounts 1..12 (in whole pounds) give estimates 100, 200, … 1200;
      // only the top 8 (amounts 5..12) should survive.
      final candidates = [
        for (var i = 1; i <= 12; i++) move(to: 'x', amount: i * 100),
      ];
      final shortlisted = shortlistCardMoves(debts, candidates);
      expect(shortlisted, hasLength(kCardMoveShortlist));
      expect(shortlisted.map((m) => m.amount.minor), [
        1200,
        1100,
        1000,
        900,
        800,
        700,
        600,
        500,
      ]);
    });
  });

  test('50 debts and 10 card offers complete within 5 seconds', () {
    // A deterministic mid-sized book: 50 cards, 10 of which carry an
    // offer. This is the shape that made the greedy search slow when it
    // ran the full multi-pass simulation for every candidate every round.
    final random = Random(7);
    final debts = [
      for (var i = 0; i < 50; i++)
        debt(
          id: 'c${i.toString().padLeft(2, '0')}',
          balance: 50000 + random.nextInt(450000), // 500.00-5,000.00
          aprBps: 1500 + random.nextInt(1501), // 15%-30%
          minPaymentPercentBps: 300,
          minPaymentFloor: 2500,
          transferOffer: i < 10
              ? TransferOffer(feeBps: 300, availableCredit: gbp(500000))
              : null,
        ),
    ];
    final budget = gbp(totalMinimumPayments(debts, currency: 'GBP').minor * 2);
    final stopwatch = Stopwatch()..start();
    final result = calculate(
      debts: debts,
      monthlyBudget: budget,
      strategy: strategy,
    );
    stopwatch.stop();
    expect(
      stopwatch.elapsed,
      lessThan(const Duration(seconds: 5)),
      reason: 'took ${stopwatch.elapsedMilliseconds}ms',
    );
    expect(result, isA<Feasible>());
    final avalanche = calculate(
      debts: debts,
      monthlyBudget: budget,
      strategy: const Strategy.avalanche(),
    );
    expect(planOf(result).totalPaid <= planOf(avalanche).totalPaid, isTrue);
  });
}
