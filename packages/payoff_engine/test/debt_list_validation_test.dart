import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('validateDebt — currency', () {
    test('rejects a minimum floor in a different currency', () {
      final d = debt(
        id: 'a',
        balance: 1000,
      ).copyWith(minPaymentFloor: const Money(500, 'USD'));
      expect(validateDebt(d), {DebtValidationError.floorCurrencyMismatch});
    });
  });

  group('validateDebtList', () {
    test('accepts up to kMaxDebts debts with unique ids', () {
      final debts = [
        for (var i = 0; i < kMaxDebts; i++) debt(id: 'd$i', balance: 100),
      ];
      expect(validateDebtList(debts), isEmpty);
      expect(validateDebtList(const []), isEmpty);
    });

    test('rejects more than kMaxDebts debts', () {
      final debts = [
        for (var i = 0; i <= kMaxDebts; i++) debt(id: 'd$i', balance: 100),
      ];
      expect(validateDebtList(debts), {DebtListValidationError.tooMany});
    });

    test('rejects duplicate ids', () {
      final debts = [debt(id: 'a', balance: 100), debt(id: 'a', balance: 200)];
      expect(validateDebtList(debts), {DebtListValidationError.duplicateId});
    });

    test('rejects debts in different currencies', () {
      final usd = debt(id: 'b', balance: 100).copyWith(
        balance: const Money(100, 'USD'),
        minPaymentFloor: const Money(0, 'USD'),
      );
      expect(validateDebtList([debt(id: 'a', balance: 100), usd]), {
        DebtListValidationError.mixedCurrencies,
      });
    });
  });

  group('validateStrategyParameters', () {
    test('accepts the defaults and the range limits', () {
      expect(validateStrategyParameters(const StrategyParameters()), isEmpty);
      expect(
        validateStrategyParameters(
          const StrategyParameters(
            consolidationAprBps: 0,
            transferFeeBps: 0,
            promoMonths: 0,
            revertAprBps: 0,
          ),
        ),
        isEmpty,
      );
      expect(
        validateStrategyParameters(
          const StrategyParameters(
            consolidationAprBps: 10000,
            transferFeeBps: 10000,
            promoMonths: kMaxPromoMonths,
            revertAprBps: 10000,
          ),
        ),
        isEmpty,
      );
    });

    test('rejects each out-of-range value', () {
      expect(
        validateStrategyParameters(
          const StrategyParameters(
            consolidationAprBps: -1,
            transferFeeBps: 10001,
            promoMonths: kMaxPromoMonths + 1,
            revertAprBps: -5,
          ),
        ),
        {
          StrategyParametersValidationError.consolidationAprOutOfRange,
          StrategyParametersValidationError.transferFeeOutOfRange,
          StrategyParametersValidationError.promoMonthsOutOfRange,
          StrategyParametersValidationError.revertAprOutOfRange,
        },
      );
      expect(
        validateStrategyParameters(const StrategyParameters(promoMonths: -1)),
        {StrategyParametersValidationError.promoMonthsOutOfRange},
      );
    });
  });
}
