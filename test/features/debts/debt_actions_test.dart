import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/test_container.dart';

void main() {
  late ProviderContainer container;
  DebtActions actions() => container.read(debtActionsProvider.notifier);
  Future<List<Debt>> debts() =>
      container.read(debtRepositoryProvider).loadAll('GBP');

  setUp(() => container = createTestContainer());

  test('add assigns a fresh id and stores the debt', () async {
    final outcome = await actions().add(testDebt(id: '', name: 'Card'));
    final saved = (outcome as DebtSaved).debt;
    expect(saved.id, isNotEmpty);
    expect(await debts(), [saved]);
  });

  test('add rejects an invalid debt without storing it', () async {
    final outcome = await actions().add(
      testDebt(id: '', name: ' ', balance: 0),
    );
    expect(
      outcome,
      const DebtSaveOutcome.rejected(
        errors: {
          DebtValidationError.nameEmpty,
          DebtValidationError.balanceNotPositive,
        },
      ),
    );
    expect(await debts(), isEmpty);
  });

  test('add rejects a debt beyond the maximum count', () async {
    for (var i = 0; i < kMaxDebts; i++) {
      expect(await actions().add(testDebt(id: '')), isA<DebtSaved>());
    }
    final outcome = await actions().add(testDebt(id: ''));
    expect(
      outcome,
      const DebtSaveOutcome.rejected(
        listErrors: {DebtListValidationError.tooMany},
      ),
    );
    expect(await debts(), hasLength(kMaxDebts));
  });

  test('update validates and stores changes', () async {
    final saved = (await actions().add(testDebt(id: '')) as DebtSaved).debt;
    final renamed = saved.copyWith(name: 'Renamed');
    expect(await actions().update(renamed), DebtSaveOutcome.saved(renamed));
    expect(await debts(), [renamed]);

    final invalid = saved.copyWith(aprBps: -1);
    expect(await actions().update(invalid), isA<DebtRejected>());
    expect(await debts(), [renamed]);
  });

  test('delete and reorder pass through to the repository', () async {
    final a =
        (await actions().add(testDebt(id: '', name: 'A')) as DebtSaved).debt;
    final b =
        (await actions().add(testDebt(id: '', name: 'B')) as DebtSaved).debt;
    await actions().reorder([b.id, a.id]);
    expect((await debts()).map((d) => d.name), ['B', 'A']);
    await actions().delete(b.id);
    expect((await debts()).map((d) => d.name), ['A']);
  });
}
