import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/domain/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

/// Fails to load until [recover] is called.
class _FlakySettingsRepository implements SettingsRepository {
  bool _broken = true;

  void recover() => _broken = false;

  @override
  Future<AppSettings> load() async {
    if (_broken) throw Exception('storage unavailable');
    return AppSettings.defaults('GBP').copyWith(onboardingComplete: true);
  }

  @override
  Future<void> save(AppSettings settings) async {}
}

void main() {
  const errorText = 'Something went wrong. Please try again.';

  Future<(AppHarness, _FlakySettingsRepository)> open(
    WidgetTester tester,
    String location,
  ) async {
    final settings = _FlakySettingsRepository();
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a', name: 'Visa')],
      location: location,
      overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
    );
    return (app, settings);
  }

  Future<void> retry(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
    await tester.pumpAndSettle();
  }

  for (final (name, location, recovered) in [
    ('debts', Routes.debts, 'Visa'),
    ('settings', Routes.settings, 'Monthly budget'),
    ('the debt form', Routes.newDebt, 'Balance'),
  ]) {
    testWidgets('$name offers a retry when settings fail to load', (
      tester,
    ) async {
      final (_, settings) = await open(tester, location);
      expect(find.text(errorText), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      settings.recover();
      await retry(tester);
      expect(find.text(errorText), findsNothing);
      expect(find.text(recovered), findsWidgets);
    });
  }
}
