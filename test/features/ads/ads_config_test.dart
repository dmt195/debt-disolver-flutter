import 'package:debt_destroyer/features/ads/domain/ads_config.dart';
import 'package:debt_destroyer/features/ads/domain/ads_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug builds default to no ads and Google test units', () {
    final config = AdsConfig.fromEnvironment();
    expect(config.enabled, isFalse);
    expect(config.androidBannerId, AdsConfig.testAndroidBannerId);
    expect(config.iosBannerId, AdsConfig.testIosBannerId);
    expect(config.usesTestIds, isTrue);
  });

  test('picks the banner unit for the platform', () {
    const config = AdsConfig(
      enabled: true,
      androidBannerId: 'android-unit',
      iosBannerId: 'ios-unit',
    );
    expect(config.bannerIdFor(TargetPlatform.android), 'android-unit');
    expect(config.bannerIdFor(TargetPlatform.iOS), 'ios-unit');
    expect(config.usesTestIds, isFalse);
  });

  test('the no-op service never shows ads or asks for anything', () async {
    final ads = NoopAdsService();
    await ads.initialize();
    expect(ads.canShowAds.value, isFalse);
    expect(await ads.privacyOptionsRequired(), isFalse);
  });
}
