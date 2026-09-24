import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';

abstract interface class ScenarioRepository {
  /// Saved scenarios, oldest first, re-emitted after every change. Amounts
  /// are labelled with [currencyCode].
  Stream<List<Scenario>> watchAll(String currencyCode);

  /// The saved scenarios, read once.
  Future<List<Scenario>> loadAll(String currencyCode);

  /// Inserts [scenario], or replaces the stored one with the same id.
  Future<void> save(Scenario scenario);

  /// Removes the scenario with [id], if it exists.
  Future<void> delete(String id);
}
