import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/notifications.dart';
import 'package:debt_destroyer/features/onboarding/presentation/onboarding_screen.dart';
import 'package:debt_destroyer/features/progress/presentation/check_in_screen.dart';
import 'package:debt_destroyer/features/reminders/presentation/reminder_scheduler.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/debts.dart';
import '../../helpers/fake_notifications_service.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('tapping a reminder opens Check in', (tester) async {
    final fake = FakeNotificationsService();
    await pumpApp(
      tester,
      location: Routes.home,
      debts: [testDebt(id: 'a')],
      notifications: fake,
    );
    fake.tap(kCheckInPayload);
    await tester.pumpAndSettle();
    expect(find.byType(CheckInScreen), findsOneWidget);
  });

  testWidgets('a reminder that launched the app opens Check in', (
    tester,
  ) async {
    final fake = FakeNotificationsService(launch: kCheckInPayload);
    final app = await pumpApp(
      tester,
      location: Routes.home,
      debts: [testDebt(id: 'a')],
      notifications: fake,
    );
    await openLaunchReminder(app.container);
    await tester.pumpAndSettle();
    expect(find.byType(CheckInScreen), findsOneWidget);
  });

  testWidgets('before onboarding, onboarding still comes first', (
    tester,
  ) async {
    final fake = FakeNotificationsService(launch: kCheckInPayload);
    final app = await pumpApp(
      tester,
      location: Routes.home,
      settings: {SettingsKeys.onboardingComplete: false},
      notifications: fake,
    );
    await openLaunchReminder(app.container);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });
}
