import 'package:debt_destroyer/features/debts/presentation/debt_form_screen.dart';
import 'package:debt_destroyer/features/home/presentation/home_screen.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/fake_notifications_service.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<AppHarness> open(
    WidgetTester tester, {
    FakeNotificationsService? notifications,
  }) => pumpApp(
    tester,
    settings: {SettingsKeys.onboardingComplete: false},
    notifications: notifications,
  );

  // The setup list builds lazily: scroll the buttons into being first.
  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      100,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) =>
      tapButton(tester, "I'll do it later");

  testWidgets('explains the app and suggests the defaults', (tester) async {
    await open(tester);
    expect(find.text('Welcome to Debt Destroyer'), findsOneWidget);
    expect(find.textContaining('highest interest rate'), findsOneWidget);
    expect(find.text('GBP (£)'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
  });

  testWidgets('saves the chosen currency and budget, then opens Home', (
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
    expect(find.byType(HomeScreen), findsOneWidget);
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

  testWidgets('add my first debt: reminder on, then the debt form', (
    tester,
  ) async {
    final fake = FakeNotificationsService();
    final app = await open(tester, notifications: fake);
    expect(find.text('Remind me to pay each month'), findsOneWidget);
    await tapButton(tester, 'Add my first debt');
    expect(find.byType(DebtFormScreen), findsOneWidget);
    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.onboardingComplete, isTrue);
    expect(settings.payDayReminder, isTrue);
    expect(fake.requests, 1);
  });

  testWidgets('a refused permission saves the reminder off, and carries on', (
    tester,
  ) async {
    final app = await open(
      tester,
      notifications: FakeNotificationsService(granted: false),
    );
    await start(tester);
    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.onboardingComplete, isTrue);
    expect(settings.payDayReminder, isFalse);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('with the reminder switched off, nothing is asked', (
    tester,
  ) async {
    final fake = FakeNotificationsService();
    final app = await open(tester, notifications: fake);
    await tester.tap(find.text('Remind me to pay each month'));
    await tester.pumpAndSettle();
    await start(tester);
    expect(fake.requests, 0);
    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.payDayReminder, isFalse);
  });
}
