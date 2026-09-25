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

  test('an unaffordable budget is infeasible, not "no worthwhile moves"', () {
    // 10.00 covers neither card's minimum, with or without a move.
    final result = run([store, amex], 1000);
    expect(result, isA<Infeasible>());
    expect(result.strategyId, StrategyId.cardTransfers);
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
}
