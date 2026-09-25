import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  TransferOffer offer({
    int feeBps = 300,
    Promo? promo = const Promo(aprBps: 0, months: 12),
    Money? credit,
  }) => TransferOffer(
    feeBps: feeBps,
    availableCredit: credit ?? gbp(200000),
    promo: promo,
  );

  Set<DebtValidationError> errors(
    TransferOffer o, {
    DebtType type = DebtType.creditCard,
  }) => validateDebt(
    debt(id: 'a', balance: 100, aprBps: 1990, type: type, transferOffer: o),
  );

  test('accepts a card offer with or without a promo', () {
    expect(errors(offer()), isEmpty);
    expect(errors(offer(promo: null)), isEmpty);
    expect(errors(offer(), type: DebtType.storeCard), isEmpty);
  });

  test('only cards can receive transfers', () {
    expect(errors(offer(), type: DebtType.loan), {
      DebtValidationError.offerOnNonCard,
    });
  });

  test('checks the fee and the promo', () {
    expect(errors(offer(feeBps: 10001)), {
      DebtValidationError.offerFeeOutOfRange,
    });
    expect(errors(offer(promo: const Promo(aprBps: 10001, months: 3))), {
      DebtValidationError.offerPromoAprOutOfRange,
    });
    expect(errors(offer(promo: const Promo(aprBps: 0, months: 0))), {
      DebtValidationError.offerPromoMonthsOutOfRange,
    });
    expect(
      errors(offer(promo: const Promo(aprBps: 0, months: kMaxPromoMonths + 1))),
      {DebtValidationError.offerPromoMonthsOutOfRange},
    );
  });

  test('checks the available credit', () {
    expect(errors(offer(credit: gbp(0))), {
      DebtValidationError.offerCreditNotPositive,
    });
    expect(errors(offer(credit: gbp(kMaxAmountMinor + 1))), {
      DebtValidationError.offerCreditTooLarge,
    });
    expect(errors(offer(credit: const Money(100, 'USD'))), {
      DebtValidationError.offerCurrencyMismatch,
    });
  });
}
