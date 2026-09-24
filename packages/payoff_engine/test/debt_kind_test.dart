import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

void main() {
  test('only card balances can move to a transfer card', () {
    expect(
      {
        for (final t in DebtType.values)
          if (isTransferable(t)) t,
      },
      {DebtType.creditCard, DebtType.storeCard},
    );
  });

  test('cards, store cards, loans and overdrafts can be consolidated', () {
    expect(
      {
        for (final t in DebtType.values)
          if (isConsolidatable(t)) t,
      },
      {
        DebtType.creditCard,
        DebtType.storeCard,
        DebtType.loan,
        DebtType.overdraft,
      },
    );
  });

  test('student loans and mortgages default to minimums only', () {
    expect(
      {
        for (final t in DebtType.values)
          if (!defaultAllowsOverpayment(t)) t,
      },
      {DebtType.studentLoan, DebtType.mortgage},
    );
  });

  test('v1 kinds keep their stored names', () {
    expect(DebtType.creditCard.name, 'creditCard');
    expect(DebtType.loan.name, 'loan');
    expect(DebtType.personal.name, 'personal');
  });
}
