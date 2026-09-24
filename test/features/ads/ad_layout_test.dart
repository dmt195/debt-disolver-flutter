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
    for (final label in ['Add debt', 'Compare strategies']) {
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
    // The banner sits on the safe area's edge: no empty strip below it.
    const screenHeight = 2532 / 3;
    expect(banner.bottom, closeTo(screenHeight - 34, 1));
  });
}
