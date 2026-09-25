import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/debts/domain/cleared_debt.dart';
import 'package:debt_destroyer/features/debts/domain/debt_repository.dart';
import 'package:debt_destroyer/features/debts/domain/promo_dates.dart';
import 'package:drift/drift.dart';
import 'package:payoff_engine/payoff_engine.dart';

class DriftDebtRepository implements DebtRepository {
  DriftDebtRepository(this._db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const _amountsCurrencyKey = 'amountsCurrencyCode';

  final AppDatabase _db;
  final DateTime Function() _now;

  @override
  Stream<List<Debt>> watchAll(String currencyCode) => _ordered().watch().map(
    (rows) => [for (final row in rows) _toDebt(row, currencyCode)],
  );

  @override
  Future<List<Debt>> loadAll(String currencyCode) async => [
    for (final row in await _ordered().get()) _toDebt(row, currencyCode),
  ];

  SimpleSelectStatement<$DebtRowsTable, DebtRow> _ordered() =>
      _db.select(_db.debtRows)
        ..where((t) => t.clearedAt.isNull())
        ..orderBy([
          (t) => OrderingTerm(expression: t.sortIndex),
          (t) => OrderingTerm(expression: t.createdAt),
        ]);

  @override
  Future<void> add(Debt debt) => _db.transaction(() async {
    final max = _db.debtRows.sortIndex.max();
    final query = _db.selectOnly(_db.debtRows)..addColumns([max]);
    final last = await query.map((r) => r.read(max)).getSingle();
    final now = _now();
    await _db
        .into(_db.debtRows)
        .insert(
          _toCompanion(debt).copyWith(
            sortIndex: Value((last ?? -1) + 1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  });

  @override
  Future<void> update(Debt debt) async {
    final changed =
        await (_db.update(_db.debtRows)..where((t) => t.id.equals(debt.id)))
            .write(_toCompanion(debt).copyWith(updatedAt: Value(_now())));
    if (changed == 0) throw StateError('No debt with id ${debt.id}');
  }

  @override
  Future<void> delete(String id) =>
      (_db.delete(_db.debtRows)..where((t) => t.id.equals(id))).go();

  @override
  Stream<List<ClearedDebt>> watchCleared() =>
      (_db.select(_db.debtRows)
            ..where((t) => t.clearedAt.isNotNull())
            ..orderBy([(t) => OrderingTerm.desc(t.clearedAt)]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                ClearedDebt(
                  id: r.id,
                  name: r.name,
                  type: r.type,
                  clearedAt: r.clearedAt!,
                ),
            ],
          );

  @override
  Future<void> reopen(String id, Money balance) => _db.transaction(() async {
    final row =
        await (_db.select(_db.debtRows)
              ..where((t) => t.id.equals(id) & t.clearedAt.isNotNull()))
            .getSingleOrNull();
    if (row == null) throw StateError('No cleared debt with id $id');
    final max = _db.debtRows.sortIndex.max();
    final query = _db.selectOnly(_db.debtRows)
      ..addColumns([max])
      ..where(_db.debtRows.clearedAt.isNull());
    final last = await query.map((r) => r.read(max)).getSingle();
    await (_db.update(_db.debtRows)..where((t) => t.id.equals(id))).write(
      DebtRowsCompanion(
        balanceMinor: Value(balance.minor),
        clearedAt: const Value(null),
        sortIndex: Value((last ?? -1) + 1),
        updatedAt: Value(_now()),
      ),
    );
  });

  @override
  Future<void> reorder(List<String> idsInOrder) => _db.transaction(() async {
    final stored = await (_db.select(
      _db.debtRows,
    )..where((t) => t.clearedAt.isNull())).map((r) => r.id).get();
    if (idsInOrder.length != stored.length ||
        !stored.toSet().containsAll(idsInOrder) ||
        idsInOrder.toSet().length != idsInOrder.length) {
      throw ArgumentError.value(
        idsInOrder,
        'idsInOrder',
        'must list every stored debt id exactly once',
      );
    }
    for (final (index, id) in idsInOrder.indexed) {
      await (_db.update(_db.debtRows)..where((t) => t.id.equals(id))).write(
        DebtRowsCompanion(sortIndex: Value(index)),
      );
    }
  });

  @override
  Future<String?> amountsCurrencyCode() async {
    final row = await (_db.select(
      _db.appMeta,
    )..where((t) => t.key.equals(_amountsCurrencyKey))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> convertAmounts({required String toCurrencyCode}) =>
      _db.transaction(() async {
        final from = await amountsCurrencyCode();
        if (from == toCurrencyCode) return;
        if (from != null) {
          final fromDigits = currencyDecimalDigits(from);
          final toDigits = currencyDecimalDigits(toCurrencyCode);
          if (fromDigits != toDigits) {
            int rescale(int minor, {required int min}) => rescaleMinor(
              minor,
              fromDigits: fromDigits,
              toDigits: toDigits,
            ).clamp(min, kMaxAmountMinor);
            final rows = await _db.select(_db.debtRows).get();
            for (final row in rows) {
              await (_db.update(
                _db.debtRows,
              )..where((t) => t.id.equals(row.id))).write(
                DebtRowsCompanion(
                  balanceMinor: Value(rescale(row.balanceMinor, min: 1)),
                  minPaymentFloorMinor: Value(
                    rescale(row.minPaymentFloorMinor, min: 0),
                  ),
                  offerAvailableCreditMinor: Value(
                    switch (row.offerAvailableCreditMinor) {
                      final credit? => rescale(credit, min: 1),
                      null => null,
                    },
                  ),
                ),
              );
            }
            // Scenarios hold amounts in the same app-wide currency.
            final scenarios = await _db.select(_db.scenarioRows).get();
            for (final row in scenarios) {
              await (_db.update(
                _db.scenarioRows,
              )..where((t) => t.id.equals(row.id))).write(
                ScenarioRowsCompanion(
                  monthlyBudgetMinor: Value(
                    rescale(row.monthlyBudgetMinor, min: 1),
                  ),
                  transferCreditLimitMinor: Value(
                    switch (row.transferCreditLimitMinor) {
                      final limit? => rescale(limit, min: 1),
                      null => null,
                    },
                  ),
                ),
              );
            }
          }
        }
        await _db
            .into(_db.appMeta)
            .insertOnConflictUpdate(
              AppMetaCompanion.insert(
                key: _amountsCurrencyKey,
                value: toCurrencyCode,
              ),
            );
      });

  Debt _toDebt(DebtRow row, String currencyCode) {
    // Read the clock once: reading it twice (once to check the promo is
    // still live, once to compute its remaining months) can straddle a
    // month boundary and produce an invalid Promo(months: 0).
    final now = _now();
    final left = switch (row.promoEndsYearMonth) {
      final int end => promoMonthsLeft(end, now),
      null => 0,
    };
    return Debt(
      id: row.id,
      name: row.name,
      type: row.type,
      balance: Money(row.balanceMinor, currencyCode),
      aprBps: row.aprBps,
      minPaymentPercentBps: row.minPaymentPercentBps,
      minPaymentFloor: Money(row.minPaymentFloorMinor, currencyCode),
      allowsOverpayment: row.allowsOverpayment,
      promo: switch (row.promoAprBps) {
        final int apr when left >= 1 => Promo(aprBps: apr, months: left),
        _ => null, // none, or it has ended
      },
      transferOffer: switch ((row.offerFeeBps, row.offerAvailableCreditMinor)) {
        (final int fee, final int credit) => TransferOffer(
          feeBps: fee,
          promo: switch ((row.offerPromoAprBps, row.offerPromoMonths)) {
            (final int apr, final int months) => Promo(
              aprBps: apr,
              months: months,
            ),
            _ => null,
          },
          availableCredit: Money(credit, currencyCode),
        ),
        _ => null,
      },
    );
  }

  DebtRowsCompanion _toCompanion(Debt debt) => DebtRowsCompanion(
    id: Value(debt.id),
    name: Value(debt.name),
    type: Value(debt.type),
    balanceMinor: Value(debt.balance.minor),
    aprBps: Value(debt.aprBps),
    minPaymentPercentBps: Value(debt.minPaymentPercentBps),
    minPaymentFloorMinor: Value(debt.minPaymentFloor.minor),
    allowsOverpayment: Value(debt.allowsOverpayment),
    promoAprBps: Value(debt.promo?.aprBps),
    promoEndsYearMonth: Value(switch (debt.promo) {
      final promo? => promoEndYearMonth(promo.months, _now()),
      null => null,
    }),
    offerFeeBps: Value(debt.transferOffer?.feeBps),
    offerPromoAprBps: Value(debt.transferOffer?.promo?.aprBps),
    offerPromoMonths: Value(debt.transferOffer?.promo?.months),
    offerAvailableCreditMinor: Value(debt.transferOffer?.availableCredit.minor),
  );
}
