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
/// round shortlists the most promising candidates on top of the moves kept
/// so far ([shortlistCardMoves]), screens them with one cheap simulation to
/// pick the round's likely best, then confirms it with the full (look-ahead)
/// evaluation — keeping it only if that beats the current best. Stops when
/// nothing helps or [kMaxCardMoves] are made. A plan that isn't feasible is
/// never preferred. Running the full evaluation on every candidate every
/// round (rather than just the round's screened winner) is what made this
/// slow with many debts and offers.
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

  // A single, no-look-ahead simulation (what _simulateBest's first pass
  // does): cheap enough to run on every shortlisted candidate each round.
  PayoffResult screen(List<CardMove> moves) {
    final applied = applyCardMoves(debts, moves);
    final fee = moves.fold(zero, (s, m) => s + m.fee);
    return simulate(
      strategyId: strategy.id,
      debts: applied.debts,
      groups: applied.groups,
      budget: budget,
      fees: fee,
      change: moves.isEmpty
          ? null
          : PlanChange.cardTransfers(moves: moves, fee: fee),
      order: allocationOrder(strategy, applied.debts),
    );
  }

  var moves = const <CardMove>[];
  var best = evaluate(moves);
  while (moves.length < kMaxCardMoves) {
    final shortlisted = shortlistCardMoves(
      debts,
      cardMoveCandidates(debts, moves),
    );
    List<CardMove>? screenWinner;
    PayoffResult? screenBest;
    for (final candidate in shortlisted) {
      final tried = [...moves, candidate];
      final result = screen(tried);
      if (screenBest == null || _better(result, screenBest)) {
        screenBest = result;
        screenWinner = tried;
      }
    }
    if (screenWinner == null) break;
    final full = evaluate(screenWinner);
    if (!_better(full, best)) break;
    moves = screenWinner;
    best = full;
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

/// Whether [a] is a plan worth keeping over [b]: a move is only kept
/// because it costs strictly less, never merely because it ties on
/// totalPaid but finishes sooner (that's not a saving).
bool _better(PayoffResult a, PayoffResult b) => switch ((a, b)) {
  (Feasible(plan: final pa), Feasible(plan: final pb)) =>
    pa.totalPaid < pb.totalPaid,
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
