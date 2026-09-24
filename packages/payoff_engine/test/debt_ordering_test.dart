import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // Legacy bug: `(int) (a - b) * 100` made APRs < 1% apart compare equal.
  final low = debt(id: 'a', name: 'Alpha', balance: 100, aprBps: 1800);
  final high = debt(id: 'b', name: 'Beta', balance: 100, aprBps: 1850);

  test('highest-first separates APRs less than 1% apart', () {
    expect([low, high]..sort(compareHighestAprFirst), [high, low]);
  });

  test('lowest-first separates APRs less than 1% apart', () {
    expect([high, low]..sort(compareLowestAprFirst), [low, high]);
  });

  test('ties break by name, then id', () {
    final b = debt(id: '2', name: 'Bravo', balance: 100, aprBps: 1000);
    final a1 = debt(id: '1', name: 'Alpha', balance: 100, aprBps: 1000);
    final a0 = debt(id: '0', name: 'Alpha', balance: 100, aprBps: 1000);
    expect([b, a1, a0]..sort(compareHighestAprFirst), [a0, a1, b]);
    expect([b, a1, a0]..sort(compareLowestAprFirst), [a0, a1, b]);
  });
}
