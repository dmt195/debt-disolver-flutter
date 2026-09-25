import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/debt_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  const order = ['a', 'b', 'c'];

  test('a portion belongs to its card', () {
    expect(baseDebtId('b#from-a'), 'b');
    expect(baseDebtId('b'), 'b');
  });

  test('colour follows list order, not clearing order', () {
    expect(debtColorIndex('c', order), 2);
    expect(debtColorIndex('b#from-a', order), 1);
  });

  test('synthetic debts take the next colour after the user list', () {
    expect(debtColorIndex(kConsolidationDebtId, order), 3);
    expect(debtColorIndex(kBalanceTransferDebtId, order), 3);
  });

  test('more than six debts wrap round', () {
    final many = [for (var i = 0; i < 8; i++) 'd$i'];
    expect(debtColorIndex('d6', many), 0);
    expect(debtColorIndex('d7', many), 1);
    expect(
      debtColor(DestroyerColors.light, 'd7', many),
      DestroyerColors.light.series[1],
    );
  });
}
