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

  /// Converts every stored amount between currencies with different numbers
  /// of decimal digits, keeping the same major-unit values.
  Future<void> rescaleAmounts({required int fromDigits, required int toDigits});
}
