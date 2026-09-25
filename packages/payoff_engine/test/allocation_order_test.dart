import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final promo = debt(
    id: 'promo',
    balance: 100000,
    aprBps: 3000,
    promo: const Promo(aprBps: 0, months: 2),
  );
  final plain = debt(id: 'plain', balance: 30000, aprBps: 1000);

  test('without a horizon, avalanche ranks by the rate charged that month', () {
    final order = allocationOrder(const Strategy.avalanche(), [promo, plain]);
    expect(order(1), [1, 0]);
    expect(order(3), [0, 1]);
  });

  test('with a horizon, avalanche ranks by interest saved until then', () {
    // Promo: 0% for 2 months, then 30%. Plain: 10% throughout.
    // To month 20, a pound off the promo debt saves 30% x 18 months,
    // more than 10% x 20 months off the plain one.
    final long = allocationOrder(const Strategy.avalanche(), [
      promo,
      plain,
    ], horizon: 20);
    expect(long(1), [0, 1]);
    // If the plan ends in month 2, the promo debt never charges interest.
    final short = allocationOrder(const Strategy.avalanche(), [
      promo,
      plain,
    ], horizon: 2);
    expect(short(1), [1, 0]);
  });

  test('snowball ranks by starting balance and never re-ranks', () {
    final order = allocationOrder(const Strategy.snowball(), [promo, plain]);
    expect(order(1), [1, 0]);
    expect(order(30), [1, 0]);
  });

  test('custom order keeps the list order', () {
    final order = allocationOrder(const Strategy.customOrder(), [plain, promo]);
    expect(order(1), [0, 1]);
    expect(order(3), [0, 1]);
  });
}
