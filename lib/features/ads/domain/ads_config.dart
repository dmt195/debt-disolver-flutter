import 'package:flutter/foundation.dart';

/// Ad settings, fixed at build time with `--dart-define`:
///
/// * `ADS_ENABLED`: show ads (default: on in release/profile, off in debug).
/// * `ADMOB_BANNER_ANDROID`, `ADMOB_BANNER_IOS`: banner ad unit ids.
///   Without them Google's test units are used, which show "Test Ad".
@immutable
class AdsConfig {
  const AdsConfig({
    required this.enabled,
    required this.androidBannerId,
    required this.iosBannerId,
  });

  factory AdsConfig.fromEnvironment() => const AdsConfig(
    enabled: bool.fromEnvironment(
      'ADS_ENABLED',
      // Analysis sees a debug build, where this is false; in release and
      // profile builds it is true, so it is not redundant.
      // ignore: avoid_redundant_argument_values
      defaultValue: !kDebugMode,
    ),
    androidBannerId: String.fromEnvironment(
      'ADMOB_BANNER_ANDROID',
      defaultValue: testAndroidBannerId,
    ),
    iosBannerId: String.fromEnvironment(
      'ADMOB_BANNER_IOS',
      defaultValue: testIosBannerId,
    ),
  );

  /// Google's always-available test units for adaptive banners.
  static const testAndroidBannerId = 'ca-app-pub-3940256099942544/9214589741';
  static const testIosBannerId = 'ca-app-pub-3940256099942544/2435281174';

  final bool enabled;
  final String androidBannerId;
  final String iosBannerId;

  /// Whether any banner id is still one of Google's test units.
  bool get usesTestIds =>
      androidBannerId == testAndroidBannerId || iosBannerId == testIosBannerId;

  String bannerIdFor(TargetPlatform platform) =>
      platform == TargetPlatform.iOS ? iosBannerId : androidBannerId;
}
