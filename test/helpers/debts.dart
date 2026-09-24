import 'package:payoff_engine/payoff_engine.dart';

/// A valid credit-card debt in [currency] with amounts in minor units.
Debt testDebt({
  required String id,
  String? name,
  int balance = 100000,
  int aprBps = 1990,
  int minPaymentPercentBps = 300,
  int minPaymentFloor = 2500,
  bool allowsOverpayment = true,
  DebtType type = DebtType.creditCard,
  String currency = 'GBP',
  Promo? promo,
}) => Debt(
  id: id,
  name: name ?? 'Debt $id',
  type: type,
  balance: Money(balance, currency),
  aprBps: aprBps,
  minPaymentPercentBps: minPaymentPercentBps,
  minPaymentFloor: Money(minPaymentFloor, currency),
  allowsOverpayment: allowsOverpayment,
  promo: promo,
);
