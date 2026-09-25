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

  test('rate-months until the horizon count the promo, then the APR', () {
    final promo = debt(
      id: 'p',
      balance: 100,
      aprBps: 3000,
      promo: const Promo(aprBps: 0, months: 2),
    );
    // Months 1-2 at 0%, months 3-5 at 30%.
    expect(aprMonthsUntil(promo, 1, 5), 9000);
    // From month 4: months 4-5 at 30%.
    expect(aprMonthsUntil(promo, 4, 5), 6000);
    // Past the horizon nothing is saved.
    expect(aprMonthsUntil(promo, 6, 5), 0);
  });

  test('most interest saved first; ties by the rate charged that month', () {
    final soon = debt(
      id: 's',
      balance: 100,
      aprBps: 1200,
      promo: const Promo(aprBps: 0, months: 1),
    );
    final flat = debt(id: 'f', balance: 100, aprBps: 1000);
    int Function(Debt, Debt) until(int h) =>
        (a, b) => compareMostInterestSaved(a, b, 1, h);
    // To month 6: soon saves 12% x 5 = 60, flat 10% x 6 = 60 — a tie,
    // broken by this month's rate (flat 10% > soon 0%).
    expect([soon, flat]..sort(until(6)), [flat, soon]);
    // To month 12: soon 12% x 11 = 132 beats flat 10% x 12 = 120.
    expect([flat, soon]..sort(until(12)), [soon, flat]);
  });
}
