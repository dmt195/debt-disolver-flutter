import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('aprInMonth', () {
    final card = debt(
      id: 'a',
      balance: 100,
      aprBps: 1990,
      promo: const Promo(aprBps: 0, months: 2),
    );

    test('charges the promo rate for its months, then the normal rate', () {
      expect(aprInMonth(card, 1), 0);
      expect(aprInMonth(card, 2), 0);
      expect(aprInMonth(card, 3), 1990);
    });

    test('a debt without a promo always charges its APR', () {
      expect(aprInMonth(debt(id: 'b', balance: 100, aprBps: 500), 1), 500);
    });
  });

  group('validateDebt with a promo', () {
    Set<DebtValidationError> errors(Promo promo) =>
        validateDebt(debt(id: 'a', balance: 100, aprBps: 1990, promo: promo));

    test('accepts a promo of 1 to kMaxPromoMonths months at 0-100%', () {
      expect(errors(const Promo(aprBps: 0, months: 1)), isEmpty);
      expect(
        errors(const Promo(aprBps: 10000, months: kMaxPromoMonths)),
        isEmpty,
      );
    });

    test('rejects a rate outside 0-100%', () {
      expect(errors(const Promo(aprBps: 10001, months: 3)), {
        DebtValidationError.promoAprOutOfRange,
      });
      expect(errors(const Promo(aprBps: -1, months: 3)), {
        DebtValidationError.promoAprOutOfRange,
      });
    });

    test('rejects an ended or over-long promo', () {
      expect(errors(const Promo(aprBps: 0, months: 0)), {
        DebtValidationError.promoMonthsOutOfRange,
      });
      expect(errors(const Promo(aprBps: 0, months: kMaxPromoMonths + 1)), {
        DebtValidationError.promoMonthsOutOfRange,
      });
    });
  });

  test('the calculator charges the promo rate, then the normal APR', () {
    // 1,200.00 at 12% with 0% for two months, paying 100.00 a month.
    final plan = planOf(
      calculate(
        debts: [
          debt(
            id: 'a',
            balance: 120000,
            aprBps: 1200,
            promo: const Promo(aprBps: 0, months: 2),
          ),
        ],
        monthlyBudget: gbp(10000),
        strategy: const Strategy.avalanche(),
      ),
    );
    // Months 1-2 are free; month 3 charges 1% of 1,000; month 4 1% of 910.
    expect(
      [for (final r in plan.months.take(4)) r.interest.single],
      [gbp(0), gbp(0), gbp(1000), gbp(910)],
    );
  });
}
