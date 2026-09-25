import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/debts.dart';
import '../../helpers/fake_notifications_service.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<AppHarness> open(WidgetTester tester, FakeNotificationsService fake) {
    useTallScreen(tester, height: 3000);
    return pumpApp(
      tester,
      location: Routes.settings,
      debts: [testDebt(id: 'a')],
      notifications: fake,
    );
  }

  Future<void> turnOnPayDay(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Monthly pay-day reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly pay-day reminder'));
    await tester.pumpAndSettle();
  }

  testWidgets('switching the reminder on asks permission, then saves', (
    tester,
  ) async {
    final fake = FakeNotificationsService();
    final app = await open(tester, fake);
    await turnOnPayDay(tester);
    expect(fake.requests, 1);
    final settings = await app.container.read(
      settingsControllerProvider.future,
    );
    expect(settings.payDayReminder, isTrue);
    expect(fake.scheduled.map((r) => r.id), containsAll([1, 2, 3]));
  });

  testWidgets('if permission is refused, it stays off and says why', (
    tester,
  ) async {
    final fake = FakeNotificationsService(granted: false);
    final app = await open(tester, fake);
    await turnOnPayDay(tester);
    final settings = await app.container.read(
      settingsControllerProvider.future,
    );
    expect(settings.payDayReminder, isFalse);
    expect(find.textContaining("phone's settings"), findsOneWidget);
    expect(fake.scheduled.map((r) => r.id), isNot(contains(1)));
  });

  testWidgets('the last day of the month can be chosen', (tester) async {
    final app = await open(tester, FakeNotificationsService());
    await turnOnPayDay(tester);
    await tester.tap(find.byKey(const ValueKey('payDay')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last day').last);
    await tester.pumpAndSettle();
    final settings = await app.container.read(
      settingsControllerProvider.future,
    );
    expect(settings.payDay, 0);
  });

  testWidgets('the nudge can be turned off', (tester) async {
    final fake = FakeNotificationsService();
    final app = await open(tester, fake);
    await tester.ensureVisible(find.byKey(const ValueKey('nudge')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nudge')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    final settings = await app.container.read(
      settingsControllerProvider.future,
    );
    expect(settings.checkInNudgeMonths, 0);
    expect(fake.scheduled, isEmpty);
  });

  testWidgets('large text fits a phone', (tester) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, location: Routes.settings);
    await tester.scrollUntilVisible(
      find.text('Reminders'),
      200,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refused nudge shows Off again, and saves nothing', (
    tester,
  ) async {
    final fake = FakeNotificationsService(granted: false);
    final app = await open(tester, fake);
    await tester.ensureVisible(find.byKey(const ValueKey('nudge')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nudge')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every month').last);
    await tester.pumpAndSettle();
    final settings = await app.container.read(
      settingsControllerProvider.future,
    );
    expect(settings.checkInNudgeMonths, 0);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('nudge')),
        matching: find.text('Off'),
      ),
      findsOneWidget,
    );
  });
}
