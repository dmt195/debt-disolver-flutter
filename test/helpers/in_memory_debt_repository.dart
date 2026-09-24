import 'dart:async';

import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/debts/domain/debt_repository.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// A [DebtRepository] held in memory, for widget tests: the Drift one relies
/// on timers and I/O that don't run under the widget test clock. Amounts are
/// kept in minor units, relabelled with the requested currency like Drift.
class InMemoryDebtRepository implements DebtRepository {
  InMemoryDebtRepository([List<Debt> initial = const []])
    : _debts = [...initial];

  final List<Debt> _debts;
  final _changes = StreamController<void>.broadcast();
  String? _amountsCurrency;

  /// Set to make every write throw, to test error handling.
  Exception? failWritesWith;

  List<Debt> get stored => List.unmodifiable(_debts);

  List<Debt> _labelled(String currency) => [
    for (final d in _debts)
      d.copyWith(
        balance: Money(d.balance.minor, currency),
        minPaymentFloor: Money(d.minPaymentFloor.minor, currency),
      ),
  ];

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
  Future<void> delete(String id) =>
      _write(() => _debts.removeWhere((d) => d.id == id));

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
      );
    }
    _changes.add(null);
  }
}
