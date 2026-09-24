import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/scenarios/data/drift_scenario_repository.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  late AppDatabase db;
  late DriftScenarioRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftScenarioRepository(db);
  });
  tearDown(() => db.close());

  final bonus = Scenario(
    id: 's1',
    name: 'Bonus',
    monthlyBudget: const Money(45050, 'GBP'),
    parameters: const StrategyParameters(
      consolidationAprBps: 399,
      consolidationTermMonths: 36,
      consolidationFeeBps: 150,
      transferFeeBps: 250,
      promoMonths: 18,
      revertAprBps: 2290,
      transferCreditLimit: Money(500000, 'GBP'),
    ),
    createdAt: DateTime(2026, 9, 24, 10),
  );

  test('stores every field', () async {
    await repo.save(bonus);
    expect(await repo.loadAll('GBP'), [bonus]);
  });

  test('saving the same id replaces it', () async {
    await repo.save(bonus);
    await repo.save(bonus.copyWith(name: 'Pay rise'));
    expect((await repo.loadAll('GBP')).single.name, 'Pay rise');
  });

  test('lists oldest first and labels amounts with the currency', () async {
    final later = bonus.copyWith(
      id: 's2',
      name: 'Later',
      createdAt: DateTime(2026, 9, 25),
    );
    await repo.save(later);
    await repo.save(bonus);
    final all = await repo.loadAll('USD');
    expect(all.map((s) => s.id), ['s1', 's2']);
    expect(all.first.monthlyBudget, const Money(45050, 'USD'));
    expect(
      all.first.parameters.transferCreditLimit,
      const Money(500000, 'USD'),
    );
  });

  test('deletes', () async {
    await repo.save(bonus);
    await repo.delete('s1');
    expect(await repo.loadAll('GBP'), isEmpty);
  });

  test('watchAll emits after each change', () async {
    final lengths = <int>[];
    final sub = repo.watchAll('GBP').listen((s) => lengths.add(s.length));
    await pumpEventQueue();
    await repo.save(bonus);
    await pumpEventQueue();
    await sub.cancel();
    expect(lengths, [0, 1]);
  });
}
