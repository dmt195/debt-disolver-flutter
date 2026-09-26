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
  Promo? promo,
  TransferOffer? transferOffer,
}) => Debt(
  id: id,
  name: name ?? id,
  type: type,
  balance: gbp(balance),
  aprBps: aprBps,
  minPaymentPercentBps: minPaymentPercentBps,
  minPaymentFloor: gbp(minPaymentFloor),
  allowsOverpayment: allowsOverpayment,
  promo: promo,
  transferOffer: transferOffer,
);

PayoffPlan planOf(PayoffResult result) => switch (result) {
  Feasible(:final plan) => plan,
  _ => throw StateError('Expected a feasible result, got $result'),
};

/// Runs [body] with the 2013 app's APR ÷ 12 interest: for tests whose
/// figures were worked out that way and whose subject isn't the rate.
T nominal<T>(T Function() body) =>
    runWithInterestMode(InterestMode.nominal, body);
