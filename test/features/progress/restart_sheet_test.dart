import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<AppHarness> openSheet(WidgetTester tester) async {
    useTallScreen(tester);
    final app = await pumpApp(
      tester,
      location: Routes.home,
      debts: [
        testDebt(id: 'a', name: 'Visa'),
        testDebt(id: 'b', name: 'Loan'),
      ],
    );
    // Some history worth keeping: a switch and a check-in.
    await app.container
        .read(settingsControllerProvider.notifier)
        .followStrategy(StrategyId.snowball);
    await tester.pumpAndSettle();
    await app.progress.saveCheckIn(
      at: DateTime(2026, 9, 24),
      balances: {
        'a': const Money(90000, 'GBP'),
        'b': const Money(90000, 'GBP'),
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart from here'));
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('keeping history adds a restart and deletes nothing', (
    tester,
  ) async {
    final app = await openSheet(tester);
    final before = await app.progress.load('GBP');
    await tester.tap(find.text('Keep my history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();
    final after = await app.progress.load('GBP');
    expect(after.starts.length, before.starts.length + 1);
    expect(after.starts.last.reason, StartReason.restarted);
    expect(after.checkIns.length, before.checkIns.length + 1);
  });

  testWidgets('starting fresh asks again, then clears only history', (
    tester,
  ) async {
    final app = await openSheet(tester);
    await tester.tap(find.text('Start fresh').last);
    await tester.pumpAndSettle();
    expect(find.textContaining("This can't be undone"), findsOneWidget);
    expect((await app.progress.load('GBP')).checkIns, hasLength(3));
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    final after = await app.progress.load('GBP');
    expect([for (final s in after.starts) s.reason], [StartReason.initial]);
    expect(after.checkIns, hasLength(1));
    expect(app.repository.stored, hasLength(2));
    final settings = await app.container.read(
      settingsControllerProvider.future,
    );
    expect(settings.followedStrategy, StrategyId.snowball);
  });

  testWidgets('cancel changes nothing', (tester) async {
    final app = await openSheet(tester);
    final before = await app.progress.load('GBP');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final after = await app.progress.load('GBP');
    expect(after.checkIns.length, before.checkIns.length);
    expect(find.text('Restart from here'), findsWidgets);
  });
}
