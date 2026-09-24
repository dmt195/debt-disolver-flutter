import 'dart:async';
import 'dart:io';

import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/debts/data/drift_debt_repository.dart';
import 'package:debt_destroyer/features/scenarios/data/drift_scenario_repository.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
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
    final emitted = StreamController<void>.broadcast();
    addTearDown(emitted.close);
    final sub = repo.watchAll('GBP').listen((d) {
      lengths.add(d.length);
      emitted.add(null);
    });
    addTearDown(sub.cancel);

    // Wait for each emission before the next change, so none are merged.
    Future<void> after(Future<void> Function() change) async {
      final next = emitted.stream.first;
      await change();
      await next;
    }

    await emitted.stream.first;
    await after(() => repo.add(testDebt(id: 'a')));
    await after(() => repo.add(testDebt(id: 'b')));
    await after(() => repo.delete('a'));
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

  group('convertAmounts', () {
    test('the first call only records the currency', () async {
      await repo.add(testDebt(id: 'a', balance: 123456));
      expect(await repo.amountsCurrencyCode(), isNull);
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      expect(await repo.amountsCurrencyCode(), 'GBP');
      expect((await all()).single.balance, const Money(123456, 'GBP'));
    });

    test('rescales balances and floors between decimal-digit counts', () async {
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      await repo.add(testDebt(id: 'a', balance: 123456, minPaymentFloor: 2550));
      await repo.convertAmounts(toCurrencyCode: 'JPY');
      final debt = (await all('JPY')).single;
      expect(debt.balance, const Money(1235, 'JPY'));
      expect(debt.minPaymentFloor, const Money(26, 'JPY'));
      expect(await repo.amountsCurrencyCode(), 'JPY');
    });

    test('converting to the current currency again changes nothing', () async {
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      await repo.add(testDebt(id: 'a', balance: 123456));
      await repo.convertAmounts(toCurrencyCode: 'JPY');
      await repo.convertAmounts(toCurrencyCode: 'JPY');
      expect((await all('JPY')).single.balance, const Money(1235, 'JPY'));
    });

    test('concurrent conversions to the same currency rescale once', () async {
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      await repo.add(testDebt(id: 'a', balance: 123456));
      await Future.wait([
        repo.convertAmounts(toCurrencyCode: 'JPY'),
        repo.convertAmounts(toCurrencyCode: 'JPY'),
      ]);
      expect((await all('JPY')).single.balance, const Money(1235, 'JPY'));
    });

    test('keeps rescaled amounts within the valid range', () async {
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      await repo.add(testDebt(id: 'small', balance: 40, minPaymentFloor: 40));
      await repo.convertAmounts(toCurrencyCode: 'JPY');
      final small = (await all('JPY')).single;
      expect(small.balance, const Money(1, 'JPY'), reason: 'never 0');
      expect(small.minPaymentFloor, const Money(0, 'JPY'));

      await repo.delete('small');
      await repo.add(
        testDebt(
          id: 'big',
          balance: kMaxAmountMinor,
          minPaymentFloor: kMaxAmountMinor,
        ),
      );
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      final big = (await all()).single;
      expect(big.balance, const Money(kMaxAmountMinor, 'GBP'));
      expect(big.minPaymentFloor, const Money(kMaxAmountMinor, 'GBP'));
      for (final d in await all()) {
        expect(validateDebt(d), isEmpty);
      }
    });

    test('converting amounts rescales saved scenarios too', () async {
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      final scenarios = DriftScenarioRepository(db);
      await scenarios.save(
        Scenario(
          id: 's',
          name: 'Bonus',
          monthlyBudget: const Money(45050, 'GBP'),
          parameters: const StrategyParameters(
            transferCreditLimit: Money(12345, 'GBP'),
          ),
          createdAt: DateTime(2026, 9, 24),
        ),
      );
      await repo.convertAmounts(toCurrencyCode: 'JPY');
      final s = (await scenarios.loadAll('JPY')).single;
      expect(
        s.monthlyBudget,
        const Money(450, 'JPY'),
      ); // 450.50 → 450 (half-even)
      expect(s.parameters.transferCreditLimit, const Money(123, 'JPY'));
    });
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

  group('promotional rates', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 9, 24);
      repo = DriftDebtRepository(db, now: () => now);
    });

    test('stores the end month and reads back the months left', () async {
      await repo.add(
        testDebt(id: 'a', promo: const Promo(aprBps: 0, months: 7)),
      );
      final row = await db.select(db.debtRows).getSingle();
      expect(row.promoAprBps, 0);
      expect(row.promoEndsYearMonth, 202703);
      expect(
        (await repo.loadAll('GBP')).single.promo,
        const Promo(aprBps: 0, months: 7),
      );

      now = DateTime(2027, 1, 5);
      expect(
        (await repo.loadAll('GBP')).single.promo,
        const Promo(aprBps: 0, months: 3),
      );
    });

    test('a promo that has ended reads back as none', () async {
      await repo.add(
        testDebt(id: 'a', promo: const Promo(aprBps: 0, months: 1)),
      );
      now = DateTime(2026, 10);
      final debt = (await repo.loadAll('GBP')).single;
      expect(debt.promo, isNull);
      // Never 0 or negative months, which the engine would reject.
      expect(validateDebt(debt), isEmpty);
    });

    test('saving a debt without a promo clears it', () async {
      final withPromo = testDebt(
        id: 'a',
        promo: const Promo(aprBps: 0, months: 7),
      );
      await repo.add(withPromo);
      await repo.update(withPromo.copyWith(promo: null));
      final row = await db.select(db.debtRows).getSingle();
      expect(row.promoAprBps, isNull);
      expect(row.promoEndsYearMonth, isNull);
    });
  });
}
