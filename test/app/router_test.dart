import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_detail_screen.dart';
import 'package:debt_destroyer/features/debts/presentation/debt_form_screen.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_screen.dart';
import 'package:debt_destroyer/features/home/presentation/home_screen.dart';
import 'package:debt_destroyer/features/onboarding/presentation/onboarding_screen.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_screen.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_screen.dart';
import 'package:debt_destroyer/features/strategies/presentation/strategies_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../helpers/debts.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('a new user is sent to onboarding', (tester) async {
    final app = await pumpApp(
      tester,
      location: Routes.home,
      settings: {SettingsKeys.onboardingComplete: false},
    );
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await app.router.go(tester, Routes.plans);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('finishing onboarding opens Home', (tester) async {
    final app = await pumpApp(
      tester,
      location: Routes.home,
      settings: {SettingsKeys.onboardingComplete: false},
    );
    await app.container
        .read(settingsControllerProvider.notifier)
        .completeOnboarding();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the bottom nav switches tabs', (tester) async {
    await pumpApp(
      tester,
      location: Routes.home,
      debts: [testDebt(id: 'a')],
    );
    expect(find.byType(HomeScreen), findsOneWidget);
    final nav = find.byType(NavigationBar);
    await tester.tap(find.descendant(of: nav, matching: find.text('Debts')));
    await tester.pumpAndSettle();
    expect(find.byType(DebtsScreen), findsOneWidget);
    await tester.tap(find.descendant(of: nav, matching: find.text('Plans')));
    await tester.pumpAndSettle();
    expect(find.byType(StrategiesScreen), findsOneWidget);
  });

  testWidgets('scenarios is not mistaken for a strategy id', (tester) async {
    final app = await pumpApp(tester, location: Routes.scenarios);
    expect(find.byType(ScenariosScreen), findsOneWidget);
    await app.router.go(tester, Routes.plan(StrategyId.balanceTransfer));
    expect(
      tester.widget<PlanDetailScreen>(find.byType(PlanDetailScreen)).strategyId,
      StrategyId.balanceTransfer,
    );
  });

  testWidgets('an unknown strategy id falls back to Plans', (tester) async {
    final app = await pumpApp(tester);
    await app.router.go(tester, '${Routes.plans}/nonsense');
    expect(find.byType(StrategiesScreen), findsOneWidget);
    expect(app.router.location, Routes.plans);
  });

  testWidgets('the debt form and settings hide the nav', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    expect(find.byType(DebtFormScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await app.router.go(tester, Routes.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('going back from plan detail keeps the Plans tab', (
    tester,
  ) async {
    await pumpApp(
      tester,
      location: Routes.plans,
      debts: [testDebt(id: 'a')],
    );
    await tester.tap(find.text('Highest interest first').first);
    await tester.pumpAndSettle();
    expect(find.byType(PlanDetailScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(StrategiesScreen), findsOneWidget);
  });
}
