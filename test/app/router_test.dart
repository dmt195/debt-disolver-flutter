import 'package:debt_destroyer/app/app.dart';
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../helpers/test_container.dart';

void main() {
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    bool onboardingComplete = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(
          prefs: storedSettings({
            SettingsKeys.onboardingComplete: onboardingComplete,
          }),
        ),
        child: const DebtDestroyerApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  Future<void> go(WidgetTester tester, ProviderContainer c, String loc) async {
    c.read(routerProvider).go(loc);
    await tester.pumpAndSettle();
  }

  testWidgets('a new user is sent to onboarding', (tester) async {
    final container = await pumpApp(tester);
    expect(find.text('Welcome'), findsWidgets);

    await go(tester, container, Routes.strategies);
    expect(find.text('Welcome'), findsWidgets);
  });

  testWidgets('finishing onboarding opens the debts screen', (tester) async {
    final container = await pumpApp(tester);
    await container
        .read(settingsControllerProvider.notifier)
        .completeOnboarding();
    await tester.pumpAndSettle();
    expect(find.text('Debts'), findsWidgets);
  });

  testWidgets('a returning user starts on debts and can navigate', (
    tester,
  ) async {
    final container = await pumpApp(tester, onboardingComplete: true);
    expect(find.text('Debts'), findsWidgets);

    await go(tester, container, Routes.onboarding);
    expect(find.text('Debts'), findsWidgets);

    await go(tester, container, Routes.strategies);
    expect(find.text('Strategies'), findsWidgets);

    await go(tester, container, Routes.plan(StrategyId.balanceTransfer));
    expect(find.text('Plan: balanceTransfer'), findsWidgets);

    await go(tester, container, Routes.settings);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('an unknown strategy id falls back to the strategies list', (
    tester,
  ) async {
    final container = await pumpApp(tester, onboardingComplete: true);
    await go(tester, container, '${Routes.strategies}/nonsense');
    expect(find.text('Strategies'), findsWidgets);
  });
}
