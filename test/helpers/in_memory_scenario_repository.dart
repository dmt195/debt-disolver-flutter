import 'dart:async';

import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario_repository.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Widget tests can't use Drift streams. Unlike the Drift repository, a
/// currency switch does not rescale these scenarios.
class InMemoryScenarioRepository implements ScenarioRepository {
  InMemoryScenarioRepository([List<Scenario> initial = const []])
    : _scenarios = [...initial];

  final List<Scenario> _scenarios;
  final _changes = StreamController<void>.broadcast();

  List<Scenario> get stored => List.unmodifiable(_scenarios);

  List<Scenario> _labelled(String currency) => [
    for (final s in _scenarios)
      s.copyWith(
        monthlyBudget: Money(s.monthlyBudget.minor, currency),
        parameters: s.parameters.copyWith(
          transferCreditLimit: switch (s.parameters.transferCreditLimit) {
            final limit? => Money(limit.minor, currency),
            null => null,
          },
        ),
      ),
  ];

  @override
  Stream<List<Scenario>> watchAll(String currencyCode) async* {
    yield _labelled(currencyCode);
    await for (final _ in _changes.stream) {
      yield _labelled(currencyCode);
    }
  }

  @override
  Future<List<Scenario>> loadAll(String currencyCode) async =>
      _labelled(currencyCode);

  @override
  Future<void> save(Scenario scenario) async {
    final i = _scenarios.indexWhere((s) => s.id == scenario.id);
    if (i < 0) {
      _scenarios.add(scenario);
    } else {
      _scenarios[i] = scenario;
    }
    _changes.add(null);
  }

  @override
  Future<void> delete(String id) async {
    _scenarios.removeWhere((s) => s.id == id);
    _changes.add(null);
  }
}
