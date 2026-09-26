import 'dart:async';

import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/features/analysis/domain/plan_series.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:debt_destroyer/features/progress/domain/progress_math.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/presentation/current_plans.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'progress_providers.g.dart';

/// Everything recorded, in the current currency.
@Riverpod(keepAlive: true)
Stream<ProgressHistory> progressHistory(Ref ref) {
  final code = ref.watch(
    settingsControllerProvider.select((s) => s.value?.currencyCode),
  );
  if (code == null) return const Stream.empty();
  return ref.watch(progressRepositoryProvider).watch(code);
}

/// What Home's progress hero and chart show.
typedef ProgressSummary = ({
  ({Money amount, int percent, DateTime? since}) paid,
  AheadBehind standing,
  CheckIn? lastCheckIn,

  /// Null until there is a starting point.
  ProgressChart? chart,
});

@riverpod
Future<ProgressSummary> progressSummary(Ref ref) async {
  final history = await ref.watch(progressHistoryProvider.future);
  final debts = await ref.watch(debtsProvider.future);
  final cleared = await ref.watch(clearedDebtsProvider.future);
  final code = (await ref.watch(settingsControllerProvider.future))
      .currencyCode;
  final now = ref.watch(clockProvider)();
  return (
    paid: paidOff(history, debts, cleared, code),
    standing: aheadBehind(history, code),
    lastCheckIn: history.lastCheckIn,
    chart: history.firstStart == null
        ? null
        : progressChartData(history, now, code),
  );
}

/// Records a starting point whenever one is due (spec §6.3): watched by the
/// app for its whole life. Decisions use freshly loaded history and debts,
/// and only one recording runs at a time, so a trigger is never recorded
/// twice.
@Riverpod(keepAlive: true)
class ProgressReconciler extends _$ProgressReconciler {
  var _busy = false;
  var _again = false;

  @override
  void build() {
    void check(Object? _, Object? _) => _check();
    ref
      ..listen(homePlanProvider, check)
      ..listen(debtsProvider, check)
      ..listen(clearedDebtsProvider, check)
      ..listen(progressHistoryProvider, check)
      ..listen(settingsControllerProvider, check);
    unawaited(Future.microtask(_check));
  }

  Future<void> _check() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _recordIfDue();
      } while (_again);
    } on Object {
      // A failed check is retried on the next change; never crash the app.
    } finally {
      _busy = false;
    }
  }

  /// Records at most one starting point; returns after it is stored.
  Future<void> _recordIfDue() async {
    final settings = ref.read(settingsControllerProvider).value;
    if (settings == null) return;
    final home = await ref.read(homePlanProvider.future);
    final code = settings.currencyCode;
    final debtRepository = ref.read(debtRepositoryProvider);
    final history = await ref.read(progressRepositoryProvider).load(code);
    final debts = await debtRepository.loadAll(code);
    final cleared = await debtRepository.watchCleared().first;
    final followed =
        settings.followedStrategy ??
        (home is HomeFollowing ? home.result.strategyId : null);
    if (followed == null) return;
    final due = nextStart(
      history: history,
      uncleared: debts,
      cleared: cleared,
      followed: followed,
      feasible: home is HomeFollowing && home.result.strategyId == followed,
    );
    if (due == null) return;
    if (settings.followedStrategy == null) {
      await ref
          .read(settingsControllerProvider.notifier)
          .followStrategy(followed);
    }
    await ref
        .read(progressControllerProvider.notifier)
        .recordStart(due.reason, debtName: due.debtName);
    _again = true; // look again with the new history
  }
}

/// One cleared debt to celebrate.
typedef Cleared = ({
  String debtId,
  String name,

  /// Everything paid off it since it was first recorded.
  Money gone,

  /// What it frees up each month, which now moves on to [next].
  Money rollsOn,
  String? next,

  /// Debts cleared, counting this one, out of all debts.
  int clearedCount,
  int totalCount,
});

/// What a check-in changed, for the result and celebration screens.
typedef CheckInOutcome = ({
  List<Cleared> cleared,
  List<({String name, Money up})> wentUp,

  /// The followed plan's months to clear before the check-in.
  int? monthsBefore,
});

/// The user's progress actions. Its state is the last check-in's outcome.
@Riverpod(keepAlive: true)
class ProgressController extends _$ProgressController {
  @override
  CheckInOutcome? build() => null;

  /// Records a starting point from the followed plan as it stands now.
  Future<void> recordStart(StartReason reason, {String? debtName}) async {
    final settings = await ref.read(settingsControllerProvider.future);
    final home = await ref.read(homePlanProvider.future);
    if (home is! HomeFollowing) return;
    final debts = await ref
        .read(debtRepositoryProvider)
        .loadAll(settings.currencyCode);
    await ref
        .read(progressRepositoryProvider)
        .recordStart(
          at: ref.read(clockProvider)(),
          balances: {for (final d in debts) d.id: d.balance},
          strategy: home.result.strategyId,
          reason: reason,
          debtName: debtName,
          projectedTotals: projectedTotals(home.result.plan),
        );
  }

  /// Saves today's balances (debt id → balance; zero clears a debt) and
  /// works out what changed.
  Future<CheckInOutcome> saveCheckIn(Map<String, Money> balances) async {
    final settings = await ref.read(settingsControllerProvider.future);
    final code = settings.currencyCode;
    final debtRepository = ref.read(debtRepositoryProvider);
    final debts = await debtRepository.loadAll(code);
    final clearedBefore = await debtRepository.watchCleared().first;
    final history = await ref.read(progressRepositoryProvider).load(code);
    final home = await ref.read(homePlanProvider.future);
    final plan = home is HomeFollowing ? home.result.plan : null;

    final current = {for (final d in debts) d.id: d};
    final first = <String, Money>{};
    for (final c in history.checkIns) {
      for (final MapEntry(key: id, value: b) in c.balances.entries) {
        first.putIfAbsent(id, () => b.balance);
      }
    }
    final clearing = [
      for (final MapEntry(key: id, value: balance) in balances.entries)
        if (balance.isZero && (current[id]?.balance.isPositive ?? false)) id,
    ];
    final order = plan == null
        ? [for (final d in debts) d.id]
        : [for (final g in groupPlanDebts(plan, (d) => d.name)) g.id];
    // What a cleared debt frees up each month: its own minimum, plus the
    // extra over the minimums if it was the debt getting it (the first still
    // taking overpayments in clearing order).
    final extra =
        settings.monthlyBudget - totalMinimumPayments(debts, currency: code);
    final focus = order
        .map((id) => current[id])
        .firstWhere((d) => d != null && d.allowsOverpayment, orElse: () => null)
        ?.id;
    Money freed(Debt debt) => debt.id == focus && extra.isPositive
        ? minimumPayment(debt) + extra
        : minimumPayment(debt);
    final totalCount = clearedBefore.length + debts.length;
    // The freed money rolls on to the first debt still open in the plan's
    // order, which isn't always one planned after the debt just cleared.
    String? nextAfter(String id) {
      for (final other in order) {
        if (other != id &&
            current.containsKey(other) &&
            !clearing.contains(other)) {
          return current[other]!.name;
        }
      }
      return null;
    }

    final outcome = (
      cleared: [
        for (final (i, id) in clearing.indexed)
          (
            debtId: id,
            name: current[id]!.name,
            gone: first[id] ?? current[id]!.balance,
            rollsOn: freed(current[id]!),
            next: nextAfter(id),
            clearedCount: clearedBefore.length + i + 1,
            totalCount: totalCount,
          ),
      ],
      wentUp: [
        for (final MapEntry(key: id, value: balance) in balances.entries)
          if (current[id] case final debt? when balance > debt.balance)
            (name: debt.name, up: balance - debt.balance),
      ],
      monthsBefore: plan?.monthsToClear,
    );
    await ref
        .read(progressRepositoryProvider)
        .saveCheckIn(at: ref.read(clockProvider)(), balances: balances);
    state = outcome;
    return outcome;
  }

  /// A check-in with [debtId] at 0 and everything else as it is (spec §4.4).
  Future<CheckInOutcome> markPaidOff(String debtId) async {
    final settings = await ref.read(settingsControllerProvider.future);
    final debts = await ref
        .read(debtRepositoryProvider)
        .loadAll(settings.currencyCode);
    return await saveCheckIn({
      for (final d in debts)
        d.id: d.id == debtId ? Money.zero(d.balance.currency) : d.balance,
    });
  }

  /// Follows [id]; the reconciler records the switch.
  Future<void> follow(StrategyId id) =>
      ref.read(settingsControllerProvider.notifier).followStrategy(id);

  /// Restart from here (spec §6.8). Clearing history leaves the reconciler to
  /// record a new first starting point.
  Future<void> restart({required bool clearHistory}) async {
    if (clearHistory) {
      await ref.read(progressRepositoryProvider).clearHistory();
    } else {
      await recordStart(StartReason.restarted);
    }
  }

  /// Starts paying a cleared debt again; the reconciler records it as added.
  Future<void> reopen(String debtId, Money balance) =>
      ref.read(debtRepositoryProvider).reopen(debtId, balance);
}
