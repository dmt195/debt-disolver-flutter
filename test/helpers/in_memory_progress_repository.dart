import 'dart:async';

import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:debt_destroyer/features/progress/domain/progress_repository.dart';
import 'package:payoff_engine/payoff_engine.dart';

import 'in_memory_debt_repository.dart';

/// A [ProgressRepository] held in memory beside [debts], for widget tests.
/// It rescales its history when [debts] changes currency, as the Drift pair
/// does in one transaction.
class InMemoryProgressRepository implements ProgressRepository {
  InMemoryProgressRepository(this.debts) {
    debts.onConvert.add(_rescale);
  }

  final InMemoryDebtRepository debts;
  final List<CheckIn> _checkIns = [];
  final List<StartingPoint> _starts = [];
  final _changes = StreamController<void>.broadcast();
  var _nextId = 0;

  ProgressHistory _history(String currency) {
    Money relabel(Money m) => Money(m.minor, currency);
    final checkIns = [..._checkIns]..sort((a, b) => a.at.compareTo(b.at));
    final starts = [..._starts]..sort((a, b) => a.at.compareTo(b.at));
    return ProgressHistory(
      checkIns: [
        for (final c in checkIns)
          CheckIn(
            id: c.id,
            at: c.at,
            isStart: c.isStart,
            total: relabel(c.total),
            balances: {
              for (final MapEntry(key: id, value: b) in c.balances.entries)
                id: (name: b.name, balance: relabel(b.balance)),
            },
          ),
      ],
      starts: starts,
    );
  }

  @override
  Stream<ProgressHistory> watch(String currencyCode) async* {
    yield _history(currencyCode);
    await for (final _ in _changes.stream) {
      yield _history(currencyCode);
    }
  }

  @override
  Future<ProgressHistory> load(String currencyCode) async =>
      _history(currencyCode);

  CheckIn _add(DateTime at, Map<String, Money> balances, bool isStart) {
    final currency = balances.values.firstOrNull?.currency ?? 'XXX';
    final checkIn = CheckIn(
      id: 'c${_nextId++}',
      at: at,
      isStart: isStart,
      total: Money(
        balances.values.fold<int>(0, (s, b) => s + b.minor),
        currency,
      ),
      balances: {
        for (final MapEntry(key: id, value: balance) in balances.entries)
          id: (name: debts.nameOf(id) ?? '', balance: balance),
      },
    );
    _checkIns.add(checkIn);
    return checkIn;
  }

  @override
  Future<CheckIn> saveCheckIn({
    required DateTime at,
    required Map<String, Money> balances,
  }) async {
    final checkIn = _add(at, balances, false);
    debts.applyCheckIn(balances, at);
    _changes.add(null);
    return checkIn;
  }

  @override
  Future<StartingPoint> recordStart({
    required DateTime at,
    required Map<String, Money> balances,
    required StrategyId strategy,
    required StartReason reason,
    required List<int> projectedTotals,
    String? debtName,
  }) async {
    final checkIn = _add(at, balances, true);
    final start = StartingPoint(
      id: 's${_nextId++}',
      at: at,
      checkInId: checkIn.id,
      strategy: strategy,
      reason: reason,
      debtName: debtName,
      projectedTotals: projectedTotals,
    );
    _starts.add(start);
    _changes.add(null);
    return start;
  }

  @override
  Future<void> clearHistory() async {
    _checkIns.clear();
    _starts.clear();
    _changes.add(null);
  }

  void _rescale(String from, String to) {
    final fromDigits = currencyDecimalDigits(from);
    final toDigits = currencyDecimalDigits(to);
    if (fromDigits == toDigits) return;
    int rescale(int minor) => rescaleMinor(
      minor,
      fromDigits: fromDigits,
      toDigits: toDigits,
    ).clamp(0, kMaxAmountMinor);
    Money money(Money m) => Money(rescale(m.minor), to);
    for (var i = 0; i < _checkIns.length; i++) {
      final c = _checkIns[i];
      _checkIns[i] = CheckIn(
        id: c.id,
        at: c.at,
        isStart: c.isStart,
        total: money(c.total),
        balances: {
          for (final MapEntry(key: id, value: b) in c.balances.entries)
            id: (name: b.name, balance: money(b.balance)),
        },
      );
    }
    for (var i = 0; i < _starts.length; i++) {
      final s = _starts[i];
      _starts[i] = StartingPoint(
        id: s.id,
        at: s.at,
        checkInId: s.checkInId,
        strategy: s.strategy,
        reason: s.reason,
        debtName: s.debtName,
        projectedTotals: [for (final t in s.projectedTotals) rescale(t)],
      );
    }
    _changes.add(null);
  }
}
