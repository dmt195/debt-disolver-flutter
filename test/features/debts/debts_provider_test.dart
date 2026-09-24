import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/in_memory_debt_repository.dart';
import '../../helpers/test_container.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    // A StreamProvider with no listener is paused and never emits.
    container = createTestContainer()..listen(debtsProvider, (_, _) {});
  });

  test('streams the stored debts once settings have loaded', () async {
    await container.read(debtRepositoryProvider).add(testDebt(id: 'a'));
    expect(await container.read(debtsProvider.future), [testDebt(id: 'a')]);
  });

  test('relabels and rescales after a currency change', () async {
    await container.read(settingsControllerProvider.future);
    await container
        .read(debtRepositoryProvider)
        .add(testDebt(id: 'a', balance: 123456));
    await container
        .read(settingsControllerProvider.notifier)
        .setCurrency('JPY');
    final debts = await container.read(debtsProvider.future);
    expect(debts.single.balance, const Money(1235, 'JPY'));
  });

  test('only re-subscribes when the currency changes', () async {
    final repository = InMemoryDebtRepository([testDebt(id: 'a')]);
    final c = ProviderContainer.test(
      overrides: [
        ...testOverrides(),
        debtRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (_, _) => null,
    )..listen(debtsProvider, (_, _) {});
    await c.read(debtsProvider.future);
    final settings = c.read(settingsControllerProvider.notifier);
    final before = repository.watchCount;

    await settings.setMonthlyBudget(12345);
    await settings.completeOnboarding();
    await c.pump();
    await c.read(debtsProvider.future);
    expect(repository.watchCount, before);

    await settings.setCurrency('USD');
    await c.pump();
    await c.read(debtsProvider.future);
    expect(repository.watchCount, before + 1);
  });
}
