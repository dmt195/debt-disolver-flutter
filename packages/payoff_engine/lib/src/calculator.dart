import 'package:payoff_engine/src/allocation_order.dart';
import 'package:payoff_engine/src/card_transfers.dart';
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/restructure.dart';
import 'package:payoff_engine/src/simulate.dart';
import 'package:payoff_engine/src/strategy.dart';
import 'package:payoff_engine/src/validation.dart';

/// Simulates paying off [debts] with [monthlyBudget] using [strategy].
/// Pure: [debts] is not modified.
///
/// Throws [ArgumentError] if any debt fails [validateDebt], the list fails
/// [validateDebtList], or [monthlyBudget] is negative.
PayoffResult calculate({
  required List<Debt> debts,
  required Money monthlyBudget,
  required Strategy strategy,
}) {
  if (monthlyBudget.isNegative) {
    throw ArgumentError.value(monthlyBudget, 'monthlyBudget', 'is negative');
  }
  if (validateDebtList(debts).isNotEmpty ||
      debts.any((d) => validateDebt(d).isNotEmpty)) {
    throw ArgumentError.value(debts, 'debts', 'contains invalid debts');
  }
  final currency = monthlyBudget.currency;
  if (strategy case BalanceTransfer(
    creditLimit: final limit?,
  ) when limit.currency != currency) {
    throw ArgumentError.value(
      limit,
      'creditLimit',
      'not in the budget currency',
    );
  }
  if (strategy case Consolidation(:final termMonths) when termMonths < 1) {
    throw ArgumentError.value(termMonths, 'termMonths', 'must be at least 1');
  }
  final zero = Money.zero(currency);
  if (debts.isEmpty) {
    return PayoffResult.feasible(
      strategyId: strategy.id,
      plan: PayoffPlan(
        debts: const [],
        months: const [],
        totalPaid: zero,
        totalInterest: zero,
        totalFees: zero,
      ),
    );
  }

  if (strategy is CardTransfers) {
    return _cardTransfers(debts, monthlyBudget, strategy);
  }

  return switch (restructure(debts, strategy)) {
    NotRestructurable(:final reason) => PayoffResult.notApplicable(
      strategyId: strategy.id,
      reason: reason,
    ),
    Restructured(debts: final paid, :final fees, :final change) =>
      _simulateBest(
        strategy: strategy,
        debts: paid,
        budget: monthlyBudget,
        fees: fees,
        change: change,
      ),
  };
}

/// Most passes spent looking for the plan's end month (see [_simulateBest]).
const int _maxHorizonPasses = 4;

/// Simulates [strategy]. For avalanche-style strategies the best order
/// depends on when the plan ends, which depends on the order, so this starts
/// from ranking by each month's rate, then re-ranks by interest saved up to
/// the end month just found, until that month stops changing. It returns
/// the cheapest plan seen (then the quickest), so looking ahead never does
/// worse than ranking by each month's rate.
PayoffResult _simulateBest({
  required Strategy strategy,
  required List<Debt> debts,
  required Money budget,
  required Money fees,
  required PlanChange? change,
  List<List<int>>? groups,
}) {
  PayoffResult run({int? horizon}) => simulate(
    strategyId: strategy.id,
    debts: debts,
    budget: budget,
    fees: fees,
    change: change,
    order: allocationOrder(strategy, debts, horizon: horizon),
    allowExtra: strategy is! MinimumsOnly,
    groups: groups,
  );

  var best = run();
  final looksAhead = switch (strategy) {
    Avalanche() ||
    CardTransfers() ||
    Consolidation() ||
    BalanceTransfer() => true,
    Snowball() || CustomOrder() || MinimumsOnly() => false,
  };
  if (!looksAhead || best is! Feasible) return best;

  final tried = <int>{};
  var horizon = best.plan.monthsToClear;
  for (var pass = 0; pass < _maxHorizonPasses; pass++) {
    if (!tried.add(horizon)) break;
    final next = run(horizon: horizon);
    if (next is! Feasible) break;
    if (_cheaper(next.plan, (best as Feasible).plan)) best = next;
    horizon = next.plan.monthsToClear;
  }
  return best;
}

bool _cheaper(PayoffPlan a, PayoffPlan b) {
  final byPaid = a.totalPaid.compareTo(b.totalPaid);
  return byPaid != 0 ? byPaid < 0 : a.monthsToClear < b.monthsToClear;
}

/// Greedy search for worthwhile moves between the user's own cards: each
/// round simulates every candidate on top of the moves kept so far and
/// keeps the one that makes the plan cheapest, until none helps or
/// [kMaxCardMoves] are made. A plan that isn't feasible is never preferred.
PayoffResult _cardTransfers(List<Debt> debts, Money budget, Strategy strategy) {
  if (!debts.any((d) => d.transferOffer != null)) {
    return PayoffResult.notApplicable(
      strategyId: strategy.id,
      reason: NotApplicableReason.noCardOffers,
    );
  }
  final zero = Money.zero(budget.currency);
  PayoffResult evaluate(List<CardMove> moves) {
    final applied = applyCardMoves(debts, moves);
    final fee = moves.fold(zero, (s, m) => s + m.fee);
    return _simulateBest(
      strategy: strategy,
      debts: applied.debts,
      groups: applied.groups,
      budget: budget,
      fees: fee,
      change: moves.isEmpty
          ? null
          : PlanChange.cardTransfers(moves: moves, fee: fee),
    );
  }

  var moves = const <CardMove>[];
  var best = evaluate(moves);
  while (moves.length < kMaxCardMoves) {
    List<CardMove>? roundMoves;
    var roundBest = best;
    for (final candidate in cardMoveCandidates(debts, moves)) {
      final tried = [...moves, candidate];
      final result = evaluate(tried);
      if (_better(result, roundBest)) {
        roundBest = result;
        roundMoves = tried;
      }
    }
    if (roundMoves == null) break;
    moves = roundMoves;
    best = roundBest;
  }
  if (moves.isEmpty) {
    // No move helped. If the no-move plan itself isn't feasible (e.g. the
    // budget doesn't cover the minimums), report that, not "no worthwhile
    // moves" — a move can't be blamed for a budget that was already short.
    if (best is! Feasible) return best;
    return PayoffResult.notApplicable(
      strategyId: strategy.id,
      reason: NotApplicableReason.noWorthwhileMoves,
    );
  }
  return best;
}

bool _better(PayoffResult a, PayoffResult b) => switch ((a, b)) {
  (Feasible(plan: final pa), Feasible(plan: final pb)) => _cheaper(pa, pb),
  (Feasible(), _) => true,
  _ => false,
};

/// Runs every strategy in [standardStrategies], in that order.
List<PayoffResult> calculateAll({
  required List<Debt> debts,
  required Money monthlyBudget,
  required StrategyParameters parameters,
}) => [
  for (final strategy in standardStrategies(parameters))
    calculate(debts: debts, monthlyBudget: monthlyBudget, strategy: strategy),
];

/// Paying only the minimums: the baseline [calculateAll]'s plans are
/// compared with.
PayoffResult calculateBaseline({
  required List<Debt> debts,
  required Money monthlyBudget,
}) => calculate(
  debts: debts,
  monthlyBudget: monthlyBudget,
  strategy: const Strategy.minimumsOnly(),
);
