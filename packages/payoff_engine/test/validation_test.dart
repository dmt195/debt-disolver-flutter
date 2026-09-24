import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final valid = debt(
    id: 'a',
    name: 'Card',
    balance: 100000,
    aprBps: 1990,
    minPaymentPercentBps: 300,
    minPaymentFloor: 2500,
  );

  group('validateDebt', () {
    test('accepts a valid debt', () {
      expect(validateDebt(valid), isEmpty);
    });

    test('rejects a blank name', () {
      expect(validateDebt(valid.copyWith(name: '   ')), {
        DebtValidationError.nameEmpty,
      });
    });

    test('rejects zero, negative and oversized balances', () {
      expect(validateDebt(valid.copyWith(balance: gbp(0))), {
        DebtValidationError.balanceNotPositive,
      });
      expect(validateDebt(valid.copyWith(balance: gbp(-1))), {
        DebtValidationError.balanceNotPositive,
      });
      expect(validateDebt(valid.copyWith(balance: gbp(kMaxAmountMinor + 1))), {
        DebtValidationError.balanceTooLarge,
      });
      expect(
        validateDebt(valid.copyWith(balance: gbp(kMaxAmountMinor))),
        isEmpty,
      );
    });

    test('accepts APR 0-100% and rejects outside it', () {
      expect(validateDebt(valid.copyWith(aprBps: 0)), isEmpty);
      expect(validateDebt(valid.copyWith(aprBps: 10000)), isEmpty);
      expect(validateDebt(valid.copyWith(aprBps: -1)), {
        DebtValidationError.aprOutOfRange,
      });
      expect(validateDebt(valid.copyWith(aprBps: 10001)), {
        DebtValidationError.aprOutOfRange,
      });
    });

    test('rejects a minimum percent outside 0-100%', () {
      expect(validateDebt(valid.copyWith(minPaymentPercentBps: -1)), {
        DebtValidationError.minPaymentPercentOutOfRange,
      });
      expect(validateDebt(valid.copyWith(minPaymentPercentBps: 10001)), {
        DebtValidationError.minPaymentPercentOutOfRange,
      });
    });

    test('rejects a negative or oversized minimum floor', () {
      expect(validateDebt(valid.copyWith(minPaymentFloor: gbp(-1))), {
        DebtValidationError.minPaymentFloorNegative,
      });
      expect(
        validateDebt(valid.copyWith(minPaymentFloor: gbp(kMaxAmountMinor + 1))),
        {DebtValidationError.minPaymentFloorTooLarge},
      );
    });

    test('reports every problem at once', () {
      final bad = valid.copyWith(name: '', balance: gbp(0), aprBps: -5);
      expect(validateDebt(bad), {
        DebtValidationError.nameEmpty,
        DebtValidationError.balanceNotPositive,
        DebtValidationError.aprOutOfRange,
      });
    });
  });

  group('validateBudget', () {
    test('accepts a positive budget up to the maximum', () {
      expect(validateBudget(gbp(25000)), isEmpty);
      expect(validateBudget(gbp(kMaxAmountMinor)), isEmpty);
    });

    test('rejects zero, negative and oversized budgets', () {
      expect(validateBudget(gbp(0)), {BudgetValidationError.notPositive});
      expect(validateBudget(gbp(-100)), {BudgetValidationError.notPositive});
      expect(validateBudget(gbp(kMaxAmountMinor + 1)), {
        BudgetValidationError.tooLarge,
      });
    });
  });
}
