import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/diagnostics.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'screen_names.g.dart';

/// The name a screen view is logged under: the route's template, never its
/// IDs (diagnostics spec §2.3).
String screenNameFor(String? routeTemplate) => switch (routeTemplate) {
  '/' => 'home',
  '/debts' => 'debts',
  '/debts/new' => 'debt_new',
  '/debts/:debtId' => 'debt_edit',
  '/plans' => 'plans',
  '/plans/scenarios' => 'scenarios',
  '/plans/scenarios/:scenarioId' => 'scenario_edit',
  '/plans/loan-calculator' => 'loan_calculator',
  '/plans/:strategyId' => 'plan_detail',
  '/settings' => 'settings',
  '/onboarding' => 'onboarding',
  '/check-in' => 'check_in',
  '/check-in/result' => 'check_in_result',
  '/cleared/:debtId' => 'celebration',
  '/debt-free' => 'debt_free',
  _ => 'other',
};

/// Logs a screen view whenever the route changes, for as long as the app
/// runs. (Sent only if the user has chosen to share diagnostics.)
@Riverpod(keepAlive: true)
void diagnosticsScreenTracker(Ref ref) {
  final router = ref.watch(routerProvider);
  final diagnostics = ref.watch(diagnosticsProvider);
  String? last;
  void changed() {
    final template = router.routerDelegate.currentConfiguration.fullPath;
    // Nothing matched yet (the router is still starting).
    if (template.isEmpty) return;
    final name = screenNameFor(template);
    if (name == last) return;
    last = name;
    diagnostics.logScreen(name);
  }

  router.routerDelegate.addListener(changed);
  ref.onDispose(() => router.routerDelegate.removeListener(changed));
  changed();
}
