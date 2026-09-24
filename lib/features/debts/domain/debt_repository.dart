import 'package:payoff_engine/payoff_engine.dart';

abstract interface class DebtRepository {
  /// All debts in the user's order, re-emitted after every change. Amounts
  /// are labelled with [currencyCode].
  Stream<List<Debt>> watchAll(String currencyCode);

  /// The current debts, read once. Use this rather than the latest stream
  /// value when a decision must see the effect of a write just made.
  Future<List<Debt>> loadAll(String currencyCode);

  /// Appends [debt] to the end of the list.
  Future<void> add(Debt debt);

  /// Replaces the stored debt with the same id. Throws [StateError] if there
  /// is none.
  Future<void> update(Debt debt);

  /// Removes the debt with [id], if it exists.
  Future<void> delete(String id);

  /// Sets the list order. [idsInOrder] must contain every stored id exactly
  /// once, or [ArgumentError] is thrown.
  Future<void> reorder(List<String> idsInOrder);

  /// The currency the stored amounts are currently in, or null before the
  /// first [convertAmounts].
  Future<String?> amountsCurrencyCode();

  /// Makes [toCurrencyCode] the currency of the stored amounts. If they are
  /// in a currency with a different number of decimal digits, every balance
  /// and floor, and every saved scenario's budget and credit limit, is
  /// rescaled to keep its major-unit value, clamped to the valid range
  /// (balances stay at least 1). Rescaling and recording the currency
  /// happen in one transaction, so repeating a call is harmless.
  Future<void> convertAmounts({required String toCurrencyCode});
}
