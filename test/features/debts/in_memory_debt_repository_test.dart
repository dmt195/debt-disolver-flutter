import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/in_memory_debt_repository.dart';

/// The test double must behave like the Drift repository.
void main() {
  late InMemoryDebtRepository repo;
  const gbp = Money(0, 'GBP');

  setUp(() {
    repo = InMemoryDebtRepository([
      testDebt(id: 'a', name: 'Visa'),
      testDebt(id: 'b', name: 'Loan'),
      testDebt(id: 'c'),
    ]);
  });

  test('a check-in sets balances and clears the zeros', () async {
    repo.applyCheckIn({
      'a': gbp,
      'b': const Money(4200, 'GBP'),
    }, DateTime(2026, 9, 20));
    expect(
      [for (final d in await repo.loadAll('GBP')) (d.id, d.balance.minor)],
      [('b', 4200), ('c', 100000)],
    );
    final cleared = await repo.watchCleared().first;
    expect(
      [for (final c in cleared) (c.id, c.name, c.clearedAt)],
      [('a', 'Visa', DateTime(2026, 9, 20))],
    );
    expect(repo.nameOf('a'), 'Visa');
  });

  test('reopening puts the debt back at the end with its balance', () async {
    repo.applyCheckIn({'a': gbp}, DateTime(2026, 9, 20));
    await repo.reopen('a', const Money(5000, 'GBP'));
    final debts = await repo.loadAll('GBP');
    expect([for (final d in debts) d.id], ['b', 'c', 'a']);
    expect(debts.last.balance, const Money(5000, 'GBP'));
    expect(await repo.watchCleared().first, isEmpty);
    expect(() => repo.reopen('b', const Money(1, 'GBP')), throwsStateError);
  });

  test('reorder covers uncleared debts only', () async {
    repo.applyCheckIn({'b': gbp}, DateTime(2026, 9, 20));
    await repo.reorder(['c', 'a']);
    expect([for (final d in await repo.loadAll('GBP')) d.id], ['c', 'a']);
    expect(() => repo.reorder(['c', 'a', 'b']), throwsArgumentError);
  });

  test('a currency change tells listeners', () async {
    final seen = <(String, String)>[];
    repo.onConvert.add((from, to) => seen.add((from, to)));
    await repo.convertAmounts(toCurrencyCode: 'GBP');
    await repo.convertAmounts(toCurrencyCode: 'JPY');
    expect(seen, [('GBP', 'JPY')]);
  });
}
