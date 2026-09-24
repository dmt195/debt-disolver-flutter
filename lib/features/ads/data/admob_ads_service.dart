import 'package:debt_destroyer/core/crash_reporter.dart';
import 'package:debt_destroyer/features/ads/data/ad_platform.dart';
import 'package:debt_destroyer/features/ads/domain/ads_config.dart';
import 'package:debt_destroyer/features/ads/domain/ads_service.dart';
import 'package:debt_destroyer/features/ads/presentation/admob_banner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// AdMob banners, shown only after Google's consent flow says ads may be
/// requested. On iOS the App Tracking Transparency prompt follows the
/// consent form, as Google recommends. If the user declines tracking or
/// personalised ads, AdMob serves non-personalised ads.
class AdMobAdsService implements AdsService {
  AdMobAdsService({
    required this.config,
    required this.consent,
    required this.tracking,
    required this.sdk,
    required this.platform,
    required this.reporter,
  });

  final AdsConfig config;
  final ConsentGateway consent;
  final TrackingGateway tracking;
  final AdsSdk sdk;
  final TargetPlatform platform;
  final CrashReporter reporter;
  final ValueNotifier<bool> _canShowAds = ValueNotifier(false);
  Future<void>? _initialized;

  @override
  ValueListenable<bool> get canShowAds => _canShowAds;

  @override
  Future<void> initialize() => _initialized ??= _initialize();

  Future<void> _initialize() async {
    try {
      // A failed refresh or form still leaves the last known consent, which
      // canRequestAds() reflects, so carry on either way.
      _report(await consent.requestUpdate(), 'Consent update failed');
      _report(await consent.showFormIfRequired(), 'Consent form failed');
      if (platform == TargetPlatform.iOS && await tracking.canPrompt()) {
        await tracking.prompt();
      }
      if (await consent.canRequestAds()) {
        await sdk.initialize();
        _canShowAds.value = true;
      }
    } on Object catch (error, stackTrace) {
      reporter.recordError(error, stackTrace, reason: 'Ads setup failed');
    }
  }

  void _report(String? message, String reason) {
    if (message != null) {
      reporter.recordError(
        StateError(message),
        StackTrace.current,
        reason: reason,
      );
    }
  }

  @override
  Future<bool> privacyOptionsRequired() async {
    try {
      return await consent.privacyOptionsRequired();
    } on Object catch (error, stackTrace) {
      reporter.recordError(error, stackTrace, reason: 'Privacy status failed');
      return false;
    }
  }

  @override
  Future<void> showPrivacyOptions() async {
    await consent.showPrivacyOptions();
    // The user may have withdrawn consent.
    _canShowAds.value = await consent.canRequestAds();
  }

  @override
  Widget buildBanner() => AdMobBanner(adUnitId: config.bannerIdFor(platform));

  void dispose() => _canShowAds.dispose();
}
