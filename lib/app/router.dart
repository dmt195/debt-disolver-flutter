import 'package:debt_destroyer/features/analysis/presentation/plan_detail_screen.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_screen.dart';
import 'package:debt_destroyer/features/onboarding/presentation/onboarding_screen.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_screen.dart';
import 'package:debt_destroyer/features/strategies/presentation/strategies_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'router.g.dart';

abstract final class Routes {
  static const debts = '/';
  static const onboarding = '/onboarding';
  static const strategies = '/strategies';
  static const settings = '/settings';

  static String plan(StrategyId id) => '$strategies/${id.name}';
}

/// App navigation. Until onboarding is complete every location redirects to
/// the onboarding screen; afterwards onboarding redirects home.
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

  final router = GoRouter(
    refreshListenable: onboardingComplete,
    redirect: (context, state) {
      final complete = onboardingComplete.value;
      if (complete == null) return null; // settings still loading
      final atOnboarding = state.matchedLocation == Routes.onboarding;
      if (!complete && !atOnboarding) return Routes.onboarding;
      if (complete && atOnboarding) return Routes.debts;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.debts,
        builder: (context, state) => const DebtsScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.strategies,
        builder: (context, state) => const StrategiesScreen(),
        routes: [
          GoRoute(
            path: ':strategyId',
            redirect: (context, state) =>
                _strategyId(state) == null ? Routes.strategies : null,
            builder: (context, state) =>
                PlanDetailScreen(strategyId: _strategyId(state)!),
          ),
        ],
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}

StrategyId? _strategyId(GoRouterState state) =>
    StrategyId.values.asNameMap()[state.pathParameters['strategyId']];
