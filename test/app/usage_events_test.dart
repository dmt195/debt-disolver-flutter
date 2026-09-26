import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/progress/presentation/progress_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../helpers/debts.dart';
import '../helpers/fake_diagnostics.dart';
import '../helpers/test_container.dart';

void main() {
  late FakeDiagnostics fake;
  late ProviderContainer container;

  setUp(() {
    fake = FakeDiagnostics();
    container = createTestContainer(diagnostics: fake)
      ..listen(progressReconcilerProvider, (_, _) {});
  });

  List<List<Object>> logged() => [
    for (final e in fake.events) [e.name, e.parameters],
  ];

  Future<String> add(Debt debt) async {
    final outcome = await container
        .read(debtActionsProvider.notifier)
        .add(debt);
    return (outcome as DebtSaved).debt.id;
  }

  test('a debt added, by kind only', () async {
    await add(testDebt(id: '', name: 'Visa'));
    expect(logged(), [
      [
        'debt_added',
        {'type': 'creditCard'},
      ],
    ]);
  });

  test('a rejected debt is not counted', () async {
    await container
        .read(debtActionsProvider.notifier)
        .add(testDebt(id: '', name: ''));
    expect(logged(), isEmpty);
  });

  test('a plan followed', () async {
    await container
        .read(progressControllerProvider.notifier)
        .follow(StrategyId.snowball);
    expect(logged(), [
      [
        'plan_followed',
        {'strategy': 'snowball'},
      ],
    ]);
  });

  test('a check-in, and each debt it clears', () async {
    final a = await add(testDebt(id: '', name: 'A'));
    final b = await add(testDebt(id: '', name: 'B', balance: 30000));
    final c = await add(testDebt(id: '', name: 'C', balance: 20000));
    await container.read(progressHistoryProvider.future);
    await pumpEventQueue();
    fake.events.clear();
    await container.read(progressControllerProvider.notifier).saveCheckIn({
      a: const Money(90000, 'GBP'),
      b: const Money(0, 'GBP'),
      c: const Money(0, 'GBP'),
    });
    expect(logged(), [
      ['check_in_saved', <String, String>{}],
      ['debt_cleared', <String, String>{}],
      ['debt_cleared', <String, String>{}],
    ]);
  });

  test('reminders turned on, once', () async {
    final settings = container.read(settingsControllerProvider.notifier);
    await container.read(settingsControllerProvider.future);
    await settings.setPayDayReminder(on: true);
    await settings.setPayDayReminder(on: true, day: 3);
    await settings.setPayDayReminder(on: false);
    expect(logged(), [
      ['reminders_turned_on', <String, String>{}],
    ]);
  });
}
