import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/ads/presentation/ads_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/debts.dart';
import '../../helpers/fake_ads_service.dart';
import '../../helpers/pump_app.dart';

void main() {
  // A large adaptive banner's real size.
  const bannerKey = ValueKey('banner');
  final ads = FakeAdsService(
    canShowAds: true,
    banner: const SizedBox(key: bannerKey, width: 320, height: 90),
  );

  testWidgets('no control overlaps or touches the banner on Debts', (
    tester,
  ) async {
    // A phone with a home indicator.
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3
      ..padding = const FakeViewPadding(bottom: 102)
      ..viewPadding = const FakeViewPadding(bottom: 102);
    addTearDown(tester.view.reset);

    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      overrides: [adsServiceProvider.overrideWithValue(ads)],
    );

    final banner = tester.getRect(find.byKey(bannerKey));
    for (final label in ['Add debt', 'See plans']) {
      final button = tester.getRect(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (w) => w is ButtonStyleButton || w is FloatingActionButton,
              ),
            )
            .first,
      );
      expect(button.overlaps(banner), isFalse, reason: label);
      expect(button.bottom, lessThanOrEqualTo(banner.top - 8), reason: label);
    }
    // The banner sits directly on the bottom nav: no empty strip between.
    final nav = tester.getRect(find.byType(NavigationBar));
    expect(banner.bottom, closeTo(nav.top, 1));
  });

  testWidgets('on Plans the banner sits at the bottom, under the plans', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3
      ..padding = const FakeViewPadding(bottom: 102)
      ..viewPadding = const FakeViewPadding(bottom: 102);
    addTearDown(tester.view.reset);

    await pumpApp(
      tester,
      location: Routes.plans,
      debts: [
        testDebt(id: 'a'),
        testDebt(id: 'b', aprBps: 990),
      ],
      overrides: [adsServiceProvider.overrideWithValue(ads)],
    );

    final banner = tester.getRect(find.byKey(bannerKey));
    final nav = tester.getRect(find.byType(NavigationBar));
    // Just above the tabs (allowing for the home-indicator padding), not
    // floating mid-screen with the plans squeezed out.
    expect(banner.bottom, greaterThan(nav.top - 40));
    expect(find.byType(ListView), findsWidgets);
    final list = tester.getRect(find.byType(ListView).first);
    expect(list.height, greaterThan(400));
    expect(list.bottom, lessThanOrEqualTo(banner.top + 1));
  });
}
