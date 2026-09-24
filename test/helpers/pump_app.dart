import 'package:debt_destroyer/app/app.dart';
import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import 'in_memory_debt_repository.dart';
import 'test_container.dart';

/// The whole app for a widget test, opened at [location], with in-memory
/// storage holding [debts] and settings seeded from [settings] (onboarding
/// complete unless overridden). Plans are calculated synchronously.
Future<AppHarness> pumpApp(
  WidgetTester tester, {
  String location = Routes.debts,
  List<Debt> debts = const [],
  Map<String, Object?> settings = const {},
  List<Override> overrides = const [],
}) async {
  final repository = InMemoryDebtRepository(debts);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...testOverrides(
          prefs: storedSettings({
            SettingsKeys.onboardingComplete: true,
            ...settings,
          }),
        ),
        debtRepositoryProvider.overrideWithValue(repository),
        planCalculatorProvider.overrideWithValue(
          (debts, budget, parameters) async => calculateAll(
            debts: debts,
            monthlyBudget: budget,
            parameters: parameters,
          ),
        ),
        ...overrides,
      ],
      child: const DebtDestroyerApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  if (location != Routes.debts) {
    container.read(routerProvider).go(location);
    await tester.pumpAndSettle();
  }
  return AppHarness(container, repository);
}

class AppHarness {
  AppHarness(this.container, this.repository);

  final ProviderContainer container;
  final InMemoryDebtRepository repository;

  GoRouterNavigator get router => GoRouterNavigator(container);
}

/// Small wrapper so tests can navigate without importing go_router.
class GoRouterNavigator {
  GoRouterNavigator(this._container);

  final ProviderContainer _container;

  Future<void> go(WidgetTester tester, String location) async {
    _container.read(routerProvider).go(location);
    await tester.pumpAndSettle();
  }

  /// The location on top of the stack, including screens opened with push.
  String get location => _container
      .read(routerProvider)
      .routerDelegate
      .currentConfiguration
      .last
      .matchedLocation;
}
