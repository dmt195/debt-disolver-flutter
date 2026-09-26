import 'package:debt_destroyer/app/diagnostics_sync.dart';
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/screen_names.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
import 'package:debt_destroyer/features/reminders/presentation/reminder_scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DebtDestroyerApp extends ConsumerWidget {
  const DebtDestroyerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Records starting points for as long as the app runs (spec §6.3).
    ref
      ..watch(progressReconcilerProvider)
      // Keeps reminders in step with the plan (spec §7).
      ..watch(reminderSchedulerProvider)
      // Diagnostics follow the user's choice (diagnostics spec §2.2).
      ..watch(diagnosticsSettingSyncProvider)
      ..watch(diagnosticsScreenTrackerProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
