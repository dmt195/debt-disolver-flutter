import 'package:payoff_engine/payoff_engine.dart';

/// Money in GBP minor units (pence).
Money gbp(int minor) => Money(minor, 'GBP');

Debt debt({
  required String id,
  required int balance,
  String? name,
  DebtType type = DebtType.creditCard,
  int aprBps = 0,
  int minPaymentPercentBps = 0,
  int minPaymentFloor = 0,
  bool allowsOverpayment = true,
}) => Debt(
  id: id,
  name: name ?? id,
  type: type,
  balance: gbp(balance),
  aprBps: aprBps,
  minPaymentPercentBps: minPaymentPercentBps,
  minPaymentFloor: gbp(minPaymentFloor),
  allowsOverpayment: allowsOverpayment,
);

PayoffPlan planOf(PayoffResult result) => switch (result) {
  Feasible(:final plan) => plan,
  _ => throw StateError('Expected a feasible result, got $result'),
};
