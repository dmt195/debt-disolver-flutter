import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DebtDestroyerApp extends ConsumerWidget {
  const DebtDestroyerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    onGenerateTitle: (context) => context.l10n.appTitle,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    routerConfig: ref.watch(routerProvider),
  );
}
