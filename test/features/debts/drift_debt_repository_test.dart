import 'dart:io';

import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/debts/data/drift_debt_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';

void main() {
  late AppDatabase db;
  late DriftDebtRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftDebtRepository(db);
  });
  tearDown(() => db.close());

  Future<List<Debt>> all([String currency = 'GBP']) =>
      repo.watchAll(currency).first;

  test('starts empty', () async {
    expect(await all(), isEmpty);
  });

  test('stores every field and appends in insertion order', () async {
    final a = testDebt(id: 'a', name: 'Card A');
    final b = testDebt(
      id: 'b',
      name: 'Car loan',
      type: DebtType.loan,
      balance: 300000,
      aprBps: 650,
      minPaymentPercentBps: 0,
      minPaymentFloor: 15000,
      allowsOverpayment: false,
    );
    await repo.add(a);
    await repo.add(b);
    expect(await all(), [a, b]);
  });

  test('loadAll reads the same list once', () async {
    await repo.add(testDebt(id: 'a'));
    await repo.add(testDebt(id: 'b'));
    expect(await repo.loadAll('GBP'), await all());
  });

  test('labels amounts with the requested currency', () async {
    await repo.add(testDebt(id: 'a', balance: 5000));
    final debts = await all('USD');
    expect(debts.single.balance, const Money(5000, 'USD'));
    expect(debts.single.minPaymentFloor.currency, 'USD');
  });

  test('emits again after each change', () async {
    final lengths = <int>[];
    final sub = repo.watchAll('GBP').listen((d) => lengths.add(d.length));
    addTearDown(sub.cancel);
    // Let each query run before the next change so no emission is merged.
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    await settle();
    await repo.add(testDebt(id: 'a'));
    await settle();
    await repo.add(testDebt(id: 'b'));
    await settle();
    await repo.delete('a');
    await settle();
    expect(lengths, [0, 1, 2, 1]);
  });

  test('updates a debt in place, keeping its position', () async {
    await repo.add(testDebt(id: 'a'));
    await repo.add(testDebt(id: 'b'));
    final changed = testDebt(id: 'a', name: 'Renamed', balance: 1);
    await repo.update(changed);
    expect(await all(), [changed, testDebt(id: 'b')]);
  });

  test('updating a missing debt throws', () async {
    expect(() => repo.update(testDebt(id: 'nope')), throwsStateError);
  });

  test('deleting a missing debt does nothing', () async {
    await repo.add(testDebt(id: 'a'));
    await repo.delete('nope');
    expect(await all(), hasLength(1));
  });

  test('reorders to the given id order', () async {
    for (final id in ['a', 'b', 'c']) {
      await repo.add(testDebt(id: id));
    }
    await repo.reorder(['c', 'a', 'b']);
    expect((await all()).map((d) => d.id), ['c', 'a', 'b']);
    await repo.add(testDebt(id: 'd'));
    expect((await all()).map((d) => d.id), ['c', 'a', 'b', 'd']);
  });

  test('reorder rejects a list that is not exactly the stored ids', () async {
    await repo.add(testDebt(id: 'a'));
    await repo.add(testDebt(id: 'b'));
    expect(() => repo.reorder(['a']), throwsArgumentError);
    expect(() => repo.reorder(['a', 'a']), throwsArgumentError);
    expect(() => repo.reorder(['a', 'x']), throwsArgumentError);
    expect((await all()).map((d) => d.id), ['a', 'b']);
  });

  test('rescales balances and floors between decimal-digit counts', () async {
    await repo.add(testDebt(id: 'a', balance: 123456, minPaymentFloor: 2550));
    await repo.rescaleAmounts(fromDigits: 2, toDigits: 0);
    final debt = (await all('JPY')).single;
    expect(debt.balance, const Money(1235, 'JPY'));
    expect(debt.minPaymentFloor, const Money(26, 'JPY'));
  });

  test('data survives closing and reopening the database file', () async {
    final dir = await Directory.systemTemp.createTemp('debts');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/debts.sqlite');

    final first = AppDatabase(NativeDatabase(file));
    await DriftDebtRepository(first).add(testDebt(id: 'a'));
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final reopened = await DriftDebtRepository(second).watchAll('GBP').first;
    expect(reopened, [testDebt(id: 'a')]);
  });
}
