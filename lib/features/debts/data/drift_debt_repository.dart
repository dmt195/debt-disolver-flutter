import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/debts/data/app_database.dart';
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
      _db.select(_db.debtRows)..orderBy([
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
  Future<void> reorder(List<String> idsInOrder) => _db.transaction(() async {
    final stored = await _db.select(_db.debtRows).map((r) => r.id).get();
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

  Debt _toDebt(DebtRow row, String currencyCode) => Debt(
    id: row.id,
    name: row.name,
    type: row.type,
    balance: Money(row.balanceMinor, currencyCode),
    aprBps: row.aprBps,
    minPaymentPercentBps: row.minPaymentPercentBps,
    minPaymentFloor: Money(row.minPaymentFloorMinor, currencyCode),
    allowsOverpayment: row.allowsOverpayment,
    promo: switch ((row.promoAprBps, row.promoEndsYearMonth)) {
      (final int apr, final int end) when promoMonthsLeft(end, _now()) >= 1 =>
        Promo(aprBps: apr, months: promoMonthsLeft(end, _now())),
      _ => null, // none, or it has ended
    },
  );

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
  );
}
