import 'package:debt_destroyer/app/app_shell.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_detail_screen.dart';
import 'package:debt_destroyer/features/debts/presentation/debt_form_screen.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_screen.dart';
import 'package:debt_destroyer/features/home/presentation/home_screen.dart';
import 'package:debt_destroyer/features/onboarding/presentation/onboarding_screen.dart';
import 'package:debt_destroyer/features/progress/presentation/check_in_screen.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenario_form_screen.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_screen.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_screen.dart';
import 'package:debt_destroyer/features/strategies/presentation/strategies_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'router.g.dart';

abstract final class Routes {
  static const home = '/';
  static const debts = '/debts';
  static const newDebt = '/debts/new';
  static const plans = '/plans';
  static const scenarios = '/plans/scenarios';
  static const settings = '/settings';
  static const onboarding = '/onboarding';
  static const checkIn = '/check-in';

  static String editDebt(String id) => '/debts/$id';

  /// A strategy's plan. [current] shows it on Current settings, ignoring the
  /// selected scenario and the slider: the plan Home follows.
  static String plan(StrategyId id, {bool current = false}) =>
      '$plans/${id.name}${current ? '?view=current' : ''}';

  static String editScenario(String id) => '$scenarios/$id';
}

/// App navigation: three tabs (Home, Debts, Plans) in a shell, and full-screen
/// routes above them. Until onboarding is complete every location redirects
/// to the onboarding screen; afterwards onboarding redirects to Home.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final onboardingComplete = ValueNotifier<bool?>(null);
  ref
    ..listen(
      settingsControllerProvider.select((s) => s.value?.onboardingComplete),
      (_, next) => onboardingComplete.value = next,
      fireImmediately: true,
    )
    ..onDispose(onboardingComplete.dispose);

  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final router = GoRouter(
    navigatorKey: rootKey,
    refreshListenable: onboardingComplete,
    redirect: (context, state) {
      final complete = onboardingComplete.value;
      if (complete == null) return null; // settings still loading
      final atOnboarding = state.matchedLocation == Routes.onboarding;
      if (!complete && !atOnboarding) return Routes.onboarding;
      if (complete && atOnboarding) return Routes.home;
      return null;
    },
    routes: [
      // Home, Debts and Plans, each with its own stack.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.debts,
                builder: (context, state) => const DebtsScreen(),
                routes: [
                  // The form is a focused task: full screen, no tabs.
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: rootKey,
                    builder: (context, state) => const DebtFormScreen(),
                  ),
                  GoRoute(
                    path: ':debtId',
                    parentNavigatorKey: rootKey,
                    builder: (context, state) =>
                        DebtFormScreen(debtId: state.pathParameters['debtId']),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.plans,
                builder: (context, state) => const StrategiesScreen(),
                routes: [
                  // Before ':strategyId', so "scenarios" is never read as a
                  // strategy.
                  GoRoute(
                    path: 'scenarios',
                    builder: (context, state) => const ScenariosScreen(),
                    routes: [
                      GoRoute(
                        path: ':scenarioId',
                        builder: (context, state) => ScenarioFormScreen(
                          scenarioId: state.pathParameters['scenarioId']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: ':strategyId',
                    redirect: (context, state) =>
                        _strategyId(state) == null ? Routes.plans : null,
                    builder: (context, state) => PlanDetailScreen(
                      strategyId: _strategyId(state)!,
                      current: state.uri.queryParameters['view'] == 'current',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.checkIn,
        builder: (context, state) => const CheckInScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}

StrategyId? _strategyId(GoRouterState state) =>
    StrategyId.values.asNameMap()[state.pathParameters['strategyId']];
