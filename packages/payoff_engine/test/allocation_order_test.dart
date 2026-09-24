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

  test('avalanche re-ranks when a promo ends', () {
    final order = allocationOrder(const Strategy.avalanche(), [promo, plain]);
    expect(order(1), [1, 0]);
    expect(order(2), [1, 0]);
    expect(order(3), [0, 1]);
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
