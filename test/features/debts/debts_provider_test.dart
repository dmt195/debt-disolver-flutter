import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
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
}
