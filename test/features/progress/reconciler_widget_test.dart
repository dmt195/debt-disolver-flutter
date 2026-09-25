import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('opening the app records the first starting point', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      location: Routes.home,
      debts: [testDebt(id: 'a')],
    );
    await tester.pumpAndSettle();
    final history = await app.progress.load('GBP');
    expect([for (final s in history.starts) s.reason], [StartReason.initial]);
  });
}
