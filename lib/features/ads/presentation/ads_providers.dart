import 'package:debt_destroyer/core/crash_reporter.dart';
import 'package:debt_destroyer/features/ads/data/ad_platform.dart';
import 'package:debt_destroyer/features/ads/data/admob_ads_service.dart';
import 'package:debt_destroyer/features/ads/domain/ads_config.dart';
import 'package:debt_destroyer/features/ads/domain/ads_service.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ads_providers.g.dart';

@Riverpod(keepAlive: true)
AdsConfig adsConfig(Ref ref) => AdsConfig.fromEnvironment();

/// AdMob when ads are enabled, otherwise nothing.
@Riverpod(keepAlive: true)
AdsService adsService(Ref ref) {
  final config = ref.watch(adsConfigProvider);
  if (!config.enabled) return NoopAdsService();
  final service = AdMobAdsService(
    config: config,
    consent: UmpConsentGateway(),
    tracking: AttTrackingGateway(),
    sdk: GoogleMobileAdsSdk(),
    platform: defaultTargetPlatform,
    reporter: ref.watch(crashReporterProvider),
  );
  ref.onDispose(service.dispose);
  return service;
}

/// Whether Settings should offer "Privacy choices".
@riverpod
Future<bool> privacyOptionsRequired(Ref ref) =>
    ref.watch(adsServiceProvider).privacyOptionsRequired();
