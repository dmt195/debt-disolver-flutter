import 'package:debt_destroyer/features/ads/domain/ads_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Ads that can be switched on and off by a test; the banner is a text.
class FakeAdsService implements AdsService {
  FakeAdsService({
    bool canShowAds = false,
    this.privacyRequired = false,
    this.banner = const Text('Ad banner'),
  }) : _canShowAds = ValueNotifier(canShowAds);

  /// What [buildBanner] returns; use a real ad size to test layout.
  final Widget banner;

  final ValueNotifier<bool> _canShowAds;
  bool privacyRequired;
  int privacyOptionsShown = 0;

  // Tests flip this to simulate consent arriving.
  // ignore: avoid_setters_without_getters
  set showing(bool value) => _canShowAds.value = value;

  @override
  ValueListenable<bool> get canShowAds => _canShowAds;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> privacyOptionsRequired() async => privacyRequired;

  @override
  Future<void> showPrivacyOptions() async => privacyOptionsShown++;

  @override
  Widget buildBanner() => banner;
}
