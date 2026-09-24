import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario_repository.dart';
import 'package:drift/drift.dart';
import 'package:payoff_engine/payoff_engine.dart';

class DriftScenarioRepository implements ScenarioRepository {
  DriftScenarioRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Scenario>> watchAll(String currencyCode) => _ordered()
      .watch()
      .map((rows) => [for (final row in rows) _toScenario(row, currencyCode)]);

  @override
  Future<List<Scenario>> loadAll(String currencyCode) async => [
    for (final row in await _ordered().get()) _toScenario(row, currencyCode),
  ];

  SimpleSelectStatement<$ScenarioRowsTable, ScenarioRow> _ordered() =>
      _db.select(_db.scenarioRows)..orderBy([
        (t) => OrderingTerm(expression: t.createdAt),
        (t) => OrderingTerm(expression: t.id),
      ]);

  @override
  Future<void> save(Scenario scenario) =>
      _db.into(_db.scenarioRows).insertOnConflictUpdate(_toCompanion(scenario));

  @override
  Future<void> delete(String id) =>
      (_db.delete(_db.scenarioRows)..where((t) => t.id.equals(id))).go();

  Scenario _toScenario(ScenarioRow row, String currencyCode) => Scenario(
    id: row.id,
    name: row.name,
    monthlyBudget: Money(row.monthlyBudgetMinor, currencyCode),
    parameters: StrategyParameters(
      consolidationAprBps: row.consolidationAprBps,
      consolidationTermMonths: row.consolidationTermMonths,
      consolidationFeeBps: row.consolidationFeeBps,
      transferFeeBps: row.transferFeeBps,
      promoMonths: row.promoMonths,
      revertAprBps: row.revertAprBps,
      transferCreditLimit: switch (row.transferCreditLimitMinor) {
        final limit? => Money(limit, currencyCode),
        null => null,
      },
    ),
    createdAt: row.createdAt,
  );

  ScenarioRowsCompanion _toCompanion(Scenario s) {
    final p = s.parameters;
    return ScenarioRowsCompanion(
      id: Value(s.id),
      name: Value(s.name),
      monthlyBudgetMinor: Value(s.monthlyBudget.minor),
      consolidationAprBps: Value(p.consolidationAprBps),
      consolidationTermMonths: Value(p.consolidationTermMonths),
      consolidationFeeBps: Value(p.consolidationFeeBps),
      transferFeeBps: Value(p.transferFeeBps),
      promoMonths: Value(p.promoMonths),
      revertAprBps: Value(p.revertAprBps),
      transferCreditLimitMinor: Value(p.transferCreditLimit?.minor),
      createdAt: Value(s.createdAt),
    );
  }
}
