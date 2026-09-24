import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_detail_screen.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_screen.dart';
import 'package:debt_destroyer/features/onboarding/presentation/onboarding_screen.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_screen.dart';
import 'package:debt_destroyer/features/strategies/presentation/strategies_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('a new user is sent to onboarding', (tester) async {
    final app = await pumpApp(
      tester,
      settings: {SettingsKeys.onboardingComplete: false},
    );
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await app.router.go(tester, Routes.strategies);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('finishing onboarding opens the debts screen', (tester) async {
    final app = await pumpApp(
      tester,
      settings: {SettingsKeys.onboardingComplete: false},
    );
    await app.container
        .read(settingsControllerProvider.notifier)
        .completeOnboarding();
    await tester.pumpAndSettle();
    expect(find.byType(DebtsScreen), findsOneWidget);
  });

  testWidgets('a returning user starts on debts and can navigate', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    expect(find.byType(DebtsScreen), findsOneWidget);

    await app.router.go(tester, Routes.onboarding);
    expect(find.byType(DebtsScreen), findsOneWidget);

    await app.router.go(tester, Routes.strategies);
    expect(find.byType(StrategiesScreen), findsOneWidget);

    await app.router.go(tester, Routes.plan(StrategyId.balanceTransfer));
    final detail = tester.widget<PlanDetailScreen>(
      find.byType(PlanDetailScreen),
    );
    expect(detail.strategyId, StrategyId.balanceTransfer);

    await app.router.go(tester, Routes.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('an unknown strategy id falls back to the strategies list', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await app.router.go(tester, '${Routes.strategies}/nonsense');
    expect(find.byType(StrategiesScreen), findsOneWidget);
    expect(app.router.location, Routes.strategies);
  });
}
