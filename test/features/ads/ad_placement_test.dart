import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/ads/presentation/ads_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/fake_ads_service.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<AppHarness> open(
    WidgetTester tester,
    FakeAdsService ads, {
    String location = Routes.debts,
  }) => pumpApp(
    tester,
    debts: [testDebt(id: 'a')],
    location: location,
    overrides: [adsServiceProvider.overrideWithValue(ads)],
  );

  testWidgets('banners appear on debts and strategies once allowed', (
    tester,
  ) async {
    final ads = FakeAdsService();
    final app = await open(tester, ads);
    expect(find.text('Ad banner'), findsNothing);

    ads.showing = true;
    await tester.pumpAndSettle();
    expect(find.text('Ad banner'), findsOneWidget);

    await app.router.go(tester, Routes.strategies);
    expect(find.text('Ad banner'), findsOneWidget);
  });

  testWidgets('no banners on forms, plan detail, settings or onboarding', (
    tester,
  ) async {
    final ads = FakeAdsService(canShowAds: true);
    final app = await open(tester, ads, location: Routes.newDebt);
    expect(find.text('Ad banner'), findsNothing);
    for (final location in [
      Routes.plan(StrategyId.avalanche),
      Routes.settings,
    ]) {
      await app.router.go(tester, location);
      expect(find.text('Ad banner'), findsNothing, reason: location);
    }
  });

  testWidgets('settings offers privacy choices only where required', (
    tester,
  ) async {
    final ads = FakeAdsService(privacyRequired: true);
    await open(tester, ads, location: Routes.settings);
    await tester.scrollUntilVisible(
      find.text('Privacy choices'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy choices'));
    await tester.pumpAndSettle();
    expect(ads.privacyOptionsShown, 1);
  });

  testWidgets('no privacy choices where they are not required', (tester) async {
    await open(tester, FakeAdsService(), location: Routes.settings);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Privacy choices'), findsNothing);
  });
}
