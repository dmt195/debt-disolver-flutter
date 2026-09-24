import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/pump_app.dart';

void main() {
  Future<AppHarness> open(WidgetTester tester) =>
      pumpApp(tester, settings: {SettingsKeys.onboardingComplete: false});

  Future<void> start(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
  }

  testWidgets('explains the app and suggests the defaults', (tester) async {
    await open(tester);
    expect(find.text('Welcome to Debt Destroyer'), findsOneWidget);
    expect(find.textContaining('highest interest rate'), findsOneWidget);
    expect(find.text('GBP (£)'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
  });

  testWidgets('saves the chosen currency and budget, then opens debts', (
    tester,
  ) async {
    final app = await open(tester);
    await tester.tap(find.text('GBP (£)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EUR (€)').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '450');
    await start(tester);

    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.currencyCode, 'EUR');
    expect(settings.monthlyBudget, const Money(45000, 'EUR'));
    expect(settings.onboardingComplete, isTrue);
    expect(find.text('Your debts'), findsOneWidget);
  });

  testWidgets('does not continue with an invalid budget', (tester) async {
    final app = await open(tester);
    await tester.enterText(find.byType(TextFormField), '0');
    await start(tester);
    expect(find.text('Enter a budget above zero'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'abc');
    await start(tester);
    expect(find.text('Enter an amount, e.g. 300'), findsOneWidget);
    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.onboardingComplete, isFalse);
  });
}
