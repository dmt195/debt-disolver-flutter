import 'dart:convert';

import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:debt_destroyer/features/progress/domain/progress_repository.dart';
import 'package:drift/drift.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:uuid/uuid.dart';

class DriftProgressRepository implements ProgressRepository {
  DriftProgressRepository(this._db);

  static const _uuid = Uuid();
  final AppDatabase _db;

  @override
  Stream<ProgressHistory> watch(String currencyCode) async* {
    yield await load(currencyCode);
    // Re-read whenever any of the three tables changes.
    final changes = _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.checkInRows,
        _db.checkInBalanceRows,
        _db.startingPointRows,
      ]),
    );
    await for (final _ in changes) {
      yield await load(currencyCode);
    }
  }

  @override
  Future<ProgressHistory> load(String currencyCode) async {
    Money money(int minor) => Money(minor, currencyCode);
    // By time, then in the order they were made.
    final checkIns =
        await (_db.select(_db.checkInRows)..orderBy([
              (t) => OrderingTerm(expression: t.at),
              (t) => OrderingTerm(expression: t.rowId),
            ]))
            .get();
    final balances = await _db.select(_db.checkInBalanceRows).get();
    final starts =
        await (_db.select(_db.startingPointRows)..orderBy([
              (t) => OrderingTerm(expression: t.at),
              (t) => OrderingTerm(expression: t.rowId),
            ]))
            .get();
    return ProgressHistory(
      checkIns: [
        for (final c in checkIns)
          CheckIn(
            id: c.id,
            at: c.at,
            isStart: c.isStart,
            total: money(c.totalMinor),
            balances: {
              for (final b in balances)
                if (b.checkInId == c.id)
                  b.debtId: (name: b.debtName, balance: money(b.balanceMinor)),
            },
          ),
      ],
      starts: [
        for (final s in starts)
          StartingPoint(
            id: s.id,
            at: s.at,
            checkInId: s.checkInId,
            strategy: s.strategy,
            reason: s.reason,
            debtName: s.debtName,
            projectedTotals: decodeTotals(s.projectedTotalsJson),
          ),
      ],
    );
  }

  Future<CheckIn> _insertCheckIn(
    DateTime at,
    Map<String, Money> balances, {
    required bool isStart,
  }) async {
    final names = {
      for (final r in await _db.select(_db.debtRows).get()) r.id: r.name,
    };
    final id = _uuid.v4();
    final total = balances.values.fold<int>(0, (s, b) => s + b.minor);
    await _db
        .into(_db.checkInRows)
        .insert(
          CheckInRowsCompanion.insert(
            id: id,
            at: at,
            isStart: isStart,
            totalMinor: total,
          ),
        );
    for (final MapEntry(key: debtId, value: balance) in balances.entries) {
      await _db
          .into(_db.checkInBalanceRows)
          .insert(
            CheckInBalanceRowsCompanion.insert(
              checkInId: id,
              debtId: debtId,
              debtName: names[debtId] ?? '',
              balanceMinor: balance.minor,
            ),
          );
    }
    final currency = balances.values.firstOrNull?.currency ?? 'XXX';
    return CheckIn(
      id: id,
      at: at,
      isStart: isStart,
      total: Money(total, currency),
      balances: {
        for (final MapEntry(key: debtId, value: balance) in balances.entries)
          debtId: (name: names[debtId] ?? '', balance: balance),
      },
    );
  }

  @override
  Future<CheckIn> saveCheckIn({
    required DateTime at,
    required Map<String, Money> balances,
  }) => _db.transaction(() async {
    for (final MapEntry(key: id, value: balance) in balances.entries) {
      await (_db.update(_db.debtRows)..where((t) => t.id.equals(id))).write(
        DebtRowsCompanion(
          balanceMinor: Value(balance.minor),
          clearedAt: balance.isZero ? Value(at) : const Value.absent(),
          updatedAt: Value(at),
        ),
      );
    }
    return await _insertCheckIn(at, balances, isStart: false);
  });

  @override
  Future<StartingPoint> recordStart({
    required DateTime at,
    required Map<String, Money> balances,
    required StrategyId strategy,
    required StartReason reason,
    required List<int> projectedTotals,
    String? debtName,
  }) => _db.transaction(() async {
    final checkIn = await _insertCheckIn(at, balances, isStart: true);
    final id = _uuid.v4();
    await _db
        .into(_db.startingPointRows)
        .insert(
          StartingPointRowsCompanion.insert(
            id: id,
            checkInId: checkIn.id,
            at: at,
            strategy: strategy,
            reason: reason,
            debtName: Value(debtName),
            projectedTotalsJson: jsonEncode(projectedTotals),
          ),
        );
    return StartingPoint(
      id: id,
      at: at,
      checkInId: checkIn.id,
      strategy: strategy,
      reason: reason,
      debtName: debtName,
      projectedTotals: projectedTotals,
    );
  });

  @override
  Future<void> clearHistory() => _db.transaction(() async {
    await _db.delete(_db.startingPointRows).go();
    await _db.delete(_db.checkInBalanceRows).go();
    await _db.delete(_db.checkInRows).go();
  });
}

/// A starting point's stored projection.
List<int> decodeTotals(String json) => [
  for (final v in jsonDecode(json) as List<Object?>) v! as int,
];
