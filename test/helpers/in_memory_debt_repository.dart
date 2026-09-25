import 'dart:async';

import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/debts/domain/cleared_debt.dart';
import 'package:debt_destroyer/features/debts/domain/debt_repository.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// A [DebtRepository] held in memory, for widget tests: the Drift one relies
/// on timers and I/O that don't run under the widget test clock. Amounts are
/// kept in minor units, relabelled with the requested currency like Drift.
class InMemoryDebtRepository implements DebtRepository {
  InMemoryDebtRepository([List<Debt> initial = const []])
    : _debts = [...initial];

  /// Uncleared debts, in the user's order.
  final List<Debt> _debts;

  /// Cleared debts (balance 0) with when they were cleared.
  final List<(Debt, DateTime)> _cleared = [];
  final _changes = StreamController<void>.broadcast();
  String? _amountsCurrency;

  /// Set to make every write throw, to test error handling.
  Exception? failWritesWith;

  /// Called with (from, to) after amounts are rescaled to a new currency, so
  /// the in-memory progress repository can rescale its history too.
  final List<void Function(String from, String to)> onConvert = [];

  List<Debt> get stored => List.unmodifiable(_debts);

  /// The name of a stored debt, cleared or not.
  String? nameOf(String id) {
    for (final d in _debts) {
      if (d.id == id) return d.name;
    }
    for (final (d, _) in _cleared) {
      if (d.id == id) return d.name;
    }
    return null;
  }

  List<Debt> _labelled(String currency) => [
    for (final d in _debts)
      d.copyWith(
        balance: Money(d.balance.minor, currency),
        minPaymentFloor: Money(d.minPaymentFloor.minor, currency),
        transferOffer: d.transferOffer?.copyWith(
          availableCredit: Money(
            d.transferOffer!.availableCredit.minor,
            currency,
          ),
        ),
      ),
  ];

  List<ClearedDebt> _clearedList() => [
    for (final (d, at) in _cleared.reversed)
      ClearedDebt(id: d.id, name: d.name, type: d.type, clearedAt: at),
  ]..sort((a, b) => b.clearedAt.compareTo(a.clearedAt));

  /// How many times [watchAll] has been called.
  int watchCount = 0;

  @override
  Stream<List<Debt>> watchAll(String currencyCode) async* {
    watchCount++;
    yield _labelled(currencyCode);
    await for (final _ in _changes.stream) {
      yield _labelled(currencyCode);
    }
  }

  @override
  Future<List<Debt>> loadAll(String currencyCode) async =>
      _labelled(currencyCode);

  @override
  Stream<List<ClearedDebt>> watchCleared() async* {
    yield _clearedList();
    await for (final _ in _changes.stream) {
      yield _clearedList();
    }
  }

  Future<void> _write(void Function() change) async {
    if (failWritesWith case final error?) throw error;
    change();
    _changes.add(null);
  }

  @override
  Future<void> add(Debt debt) => _write(() => _debts.add(debt));

  @override
  Future<void> update(Debt debt) => _write(() {
    final i = _debts.indexWhere((d) => d.id == debt.id);
    if (i < 0) throw StateError('No debt with id ${debt.id}');
    _debts[i] = debt;
  });

  @override
  Future<void> delete(String id) => _write(() {
    _debts.removeWhere((d) => d.id == id);
    _cleared.removeWhere((c) => c.$1.id == id);
  });

  @override
  Future<void> reorder(List<String> idsInOrder) => _write(() {
    final byId = {for (final d in _debts) d.id: d};
    if (idsInOrder.length != byId.length ||
        !byId.keys.toSet().containsAll(idsInOrder)) {
      throw ArgumentError.value(idsInOrder, 'idsInOrder');
    }
    _debts
      ..clear()
      ..addAll([for (final id in idsInOrder) byId[id]!]);
  });

  @override
  Future<void> reopen(String id, Money balance) => _write(() {
    final i = _cleared.indexWhere((c) => c.$1.id == id);
    if (i < 0) throw StateError('No cleared debt with id $id');
    final (debt, _) = _cleared.removeAt(i);
    _debts.add(debt.copyWith(balance: balance));
  });

  /// Sets each debt's balance, as a check-in does; a zero clears the debt
  /// at [at].
  void applyCheckIn(Map<String, Money> balances, DateTime at) {
    for (final MapEntry(key: id, value: balance) in balances.entries) {
      final i = _debts.indexWhere((d) => d.id == id);
      if (i < 0) continue;
      if (balance.isZero) {
        _cleared.add((_debts.removeAt(i).copyWith(balance: balance), at));
      } else {
        _debts[i] = _debts[i].copyWith(balance: balance);
      }
    }
    _changes.add(null);
  }

  @override
  Future<String?> amountsCurrencyCode() async => _amountsCurrency;

  @override
  Future<void> convertAmounts({required String toCurrencyCode}) async {
    final from = _amountsCurrency;
    _amountsCurrency = toCurrencyCode;
    if (from == null || from == toCurrencyCode) return;
    int rescale(int minor, int min) => rescaleMinor(
      minor,
      fromDigits: currencyDecimalDigits(from),
      toDigits: currencyDecimalDigits(toCurrencyCode),
    ).clamp(min, kMaxAmountMinor);
    for (var i = 0; i < _debts.length; i++) {
      final d = _debts[i];
      _debts[i] = d.copyWith(
        balance: Money(rescale(d.balance.minor, 1), toCurrencyCode),
        minPaymentFloor: Money(
          rescale(d.minPaymentFloor.minor, 0),
          toCurrencyCode,
        ),
        transferOffer: d.transferOffer?.copyWith(
          availableCredit: Money(
            rescale(d.transferOffer!.availableCredit.minor, 1),
            toCurrencyCode,
          ),
        ),
      );
    }
    for (final listener in onConvert) {
      listener(from, toCurrencyCode);
    }
    _changes.add(null);
  }
}
