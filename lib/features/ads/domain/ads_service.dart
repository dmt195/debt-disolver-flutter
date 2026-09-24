import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Ads behind the user's consent. The app talks only to this interface;
/// tests and debug builds use [NoopAdsService].
abstract interface class AdsService {
  /// Asks for consent where the law requires it (and, on iOS, permission to
  /// track), then starts the ads SDK if ads may be shown. Safe to call more
  /// than once; later calls wait for the first. Never throws.
  Future<void> initialize();

  /// Whether banners may be requested now. Starts false.
  ValueListenable<bool> get canShowAds;

  /// Whether the user must be offered a way to change their privacy
  /// choices (for example in the EU and UK).
  Future<bool> privacyOptionsRequired();

  /// Shows the consent form again so the user can change their choices.
  Future<void> showPrivacyOptions();

  /// A banner ad. Only called while [canShowAds] is true.
  Widget buildBanner();
}

/// Shows no ads and asks for nothing.
class NoopAdsService implements AdsService {
  final ValueNotifier<bool> _canShowAds = ValueNotifier(false);

  @override
  Future<void> initialize() async {}

  @override
  ValueListenable<bool> get canShowAds => _canShowAds;

  @override
  Future<bool> privacyOptionsRequired() async => false;

  @override
  Future<void> showPrivacyOptions() async {}

  @override
  Widget buildBanner() => const SizedBox.shrink();
}
