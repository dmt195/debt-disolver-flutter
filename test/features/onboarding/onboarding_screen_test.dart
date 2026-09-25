import 'package:debt_destroyer/core/illustrations/illustration.dart';
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
  Future<AppHarness> welcome(
    WidgetTester tester, {
    FakeNotificationsService? notifications,
  }) => pumpApp(
    tester,
    settings: {SettingsKeys.onboardingComplete: false},
    notifications: notifications,
  );

  // Past the welcome pages, to the setup form.
  Future<void> openSetup(WidgetTester tester) async {
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
  }

  Future<AppHarness> open(
    WidgetTester tester, {
    FakeNotificationsService? notifications,
  }) async {
    final app = await welcome(tester, notifications: notifications);
    await openSetup(tester);
    return app;
  }

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

  group('welcome pages', () {
    testWidgets('open on the first, with its picture and dots', (tester) async {
      await welcome(tester);
      debugPrint(
        [for (final t in tester.widgetList<Text>(find.byType(Text))) t.data]
            .join(' | '),
      );
      expect(find.text('Knock down your debt, brick by brick'), findsOneWidget);
      expect(find.textContaining('compares ways'), findsOneWidget);
      expect(find.byType(Illustration), findsOneWidget);
      expect(find.bySemanticsLabel('Page 1 of 3'), findsOneWidget);
    });

    testWidgets('Next walks through them to setup', (tester) async {
      await welcome(tester);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Highest rate first'), findsOneWidget);
      expect(find.textContaining('highest interest rate'), findsOneWidget);
      expect(find.bySemanticsLabel('Page 2 of 3'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Payments roll on'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('GBP (£)'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('swiping moves between pages', (tester) async {
      await welcome(tester);
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Highest rate first'), findsOneWidget);
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Knock down your debt, brick by brick'), findsOneWidget);
    });

    testWidgets('Skip goes straight to setup, with its picture', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('GBP (£)'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);
      expect(find.byType(Illustration), findsOneWidget);
    });

    testWidgets('with reduced motion, Skip lands at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await welcome(tester);
      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.pump();
      expect(find.text('GBP (£)'), findsOneWidget);
    });

    testWidgets('large text fits every page on a phone', (tester) async {
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = const Size(360 * 3, 740 * 3);
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await welcome(tester);
      for (var i = 0; i < 3; i++) {
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(find.text('GBP (£)'), findsOneWidget);
    });
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
    expect(settings.checkInNudgeMonths, 2);
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
    expect(settings.checkInNudgeMonths, 0);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining("phone's settings"), findsOneWidget);
  });

  testWidgets('with the reminder switched off, nothing is asked', (
    tester,
  ) async {
    final fake = FakeNotificationsService();
    final app = await open(tester, notifications: fake);
    await tester.scrollUntilVisible(
      find.text('Remind me to pay each month'),
      100,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remind me to pay each month'));
    await tester.pumpAndSettle();
    await start(tester);
    expect(fake.requests, 0);
    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.payDayReminder, isFalse);
    expect(settings.checkInNudgeMonths, 0);
  });
}
