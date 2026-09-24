import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // Legacy bug: `(int) (a - b) * 100` made APRs < 1% apart compare equal.
  final low = debt(id: 'a', name: 'Alpha', balance: 100, aprBps: 1800);
  final high = debt(id: 'b', name: 'Beta', balance: 100, aprBps: 1850);

  test('highest-first separates APRs less than 1% apart', () {
    expect([low, high]..sort((a, b) => compareHighestAprInMonth(a, b, 1)), [
      high,
      low,
    ]);
  });

  test('highest-first uses the rate charged in that month', () {
    final promo = debt(
      id: 'p',
      balance: 100,
      aprBps: 3000,
      promo: const Promo(aprBps: 0, months: 2),
    );
    int Function(Debt, Debt) inMonth(int m) =>
        (a, b) => compareHighestAprInMonth(a, b, m);
    expect([promo, low]..sort(inMonth(2)), [low, promo]);
    expect([promo, low]..sort(inMonth(3)), [promo, low]);
  });

  test('smallest balance first', () {
    final big = debt(id: 'big', balance: 500);
    final small = debt(id: 'small', balance: 300);
    expect([big, small]..sort(compareSmallestBalanceFirst), [small, big]);
  });

  test('ties break by name, then id', () {
    final b = debt(id: '2', name: 'Bravo', balance: 100, aprBps: 1000);
    final a1 = debt(id: '1', name: 'Alpha', balance: 100, aprBps: 1000);
    final a0 = debt(id: '0', name: 'Alpha', balance: 100, aprBps: 1000);
    expect([b, a1, a0]..sort((x, y) => compareHighestAprInMonth(x, y, 1)), [
      a0,
      a1,
      b,
    ]);
    expect([b, a1, a0]..sort(compareSmallestBalanceFirst), [a0, a1, b]);
  });
}
