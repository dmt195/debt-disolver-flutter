import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
import 'package:debt_destroyer/features/reminders/presentation/reminder_scheduler.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/fake_notifications_service.dart';
import '../../helpers/test_container.dart';

void main() {
  late ProviderContainer container;
  late FakeNotificationsService fake;

  setUp(() {
    fake = FakeNotificationsService();
    container = createTestContainer(notifications: fake)
      ..listen(progressReconcilerProvider, (_, _) {})
      ..listen(reminderSchedulerProvider, (_, _) {});
  });

  /// Waits until the scheduler and the plan calculations go quiet.
  Future<void> settled() async {
    var last = -1;
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (fake.replaceCount == last && i > 10) return;
      last = fake.replaceCount;
    }
  }

  SettingsController settings() =>
      container.read(settingsControllerProvider.notifier);

  Future<String> addDebt(String name, {int balance = 100000}) async {
    final outcome = await container
        .read(debtActionsProvider.notifier)
        .add(testDebt(id: '', name: name, balance: balance));
    return (outcome as DebtSaved).debt.id;
  }

  List<int> ids() => [for (final r in fake.scheduled) r.id];

  test(
    'pay days list what to pay; the nudge follows the last check-in',
    () async {
      await addDebt('Visa');
      await settings().setPayDayReminder(on: true, day: 28);
      await settled();
      expect(ids(), [1, 2, 3, 10]);
      final first = fake.scheduled.first;
      expect(first.at, DateTime(2026, 9, 28, 9));
      expect(first.title, 'Pay day: £300.00 across your debts');
      expect(first.body, 'Visa £300.00');
      expect(fake.scheduled[1].body, isNot(contains('£')));
      // The first starting point (24 Sep) counts as the last check-in.
      expect(fake.scheduled.last.at, DateTime(2026, 11, 24, 9));
    },
  );

  test('pay days only when switched on; nothing when all is off', () async {
    await addDebt('Visa');
    await settled();
    expect(ids(), [10]);
    await settings().setCheckInNudgeMonths(0);
    await settled();
    expect(ids(), isEmpty);
  });

  test('nothing while the budget cannot cover the minimums', () async {
    await addDebt('Visa');
    await settings().setPayDayReminder(on: true);
    await settings().setMonthlyBudget(1000);
    await settled();
    expect(ids(), isEmpty);
  });

  test('an unrelated change does not reschedule', () async {
    await addDebt('Visa');
    await settings().setPayDayReminder(on: true);
    await settled();
    final before = fake.replaceCount;
    await settings().setStrategyParameters(const StrategyParameters());
    await settled();
    expect(fake.replaceCount, before);
  });

  test('a cleared debt drops out of the reminder', () async {
    final visa = await addDebt('Visa');
    final amex = await addDebt('Amex', balance: 30000);
    await settings().setPayDayReminder(on: true);
    await settled();
    expect(fake.scheduled.first.body, contains('Amex'));
    await container.read(progressControllerProvider.notifier).saveCheckIn({
      visa: const Money(100000, 'GBP'),
      amex: const Money(0, 'GBP'),
    });
    await settled();
    expect(fake.scheduled.first.body, isNot(contains('Amex')));
  });

  test('a currency change shows the new currency', () async {
    await addDebt('Visa');
    await settings().setPayDayReminder(on: true);
    await settled();
    await settings().setCurrency('JPY');
    await settled();
    expect(fake.scheduled.first.body, contains('¥'));
  });

  test('scheduling waits for the service to be set up', () async {
    await addDebt('Visa');
    await settings().setPayDayReminder(on: true);
    await settled();
    expect(fake.initialized, isTrue);
  });
}
