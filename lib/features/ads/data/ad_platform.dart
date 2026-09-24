import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google's User Messaging Platform (consent). Wrapped so the order of
/// calls in `AdMobAdsService` can be tested without the plugin.
abstract interface class ConsentGateway {
  /// Refreshes the consent status. Returns the error message if the
  /// refresh failed (the previous status still applies).
  Future<String?> requestUpdate();

  /// Shows the consent form if the user must answer it. Returns the error
  /// message if it couldn't be shown.
  Future<String?> showFormIfRequired();

  Future<bool> canRequestAds();

  Future<bool> privacyOptionsRequired();

  Future<void> showPrivacyOptions();
}

/// Apple's App Tracking Transparency prompt.
abstract interface class TrackingGateway {
  /// Whether the user hasn't been asked yet.
  Future<bool> canPrompt();

  Future<void> prompt();
}

/// The ads SDK itself.
abstract interface class AdsSdk {
  Future<void> initialize();
}

class UmpConsentGateway implements ConsentGateway {
  @override
  Future<String?> requestUpdate() {
    final done = Completer<String?>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => done.complete(null),
      (error) => done.complete(error.message),
    );
    return done.future;
  }

  @override
  Future<String?> showFormIfRequired() {
    final done = Completer<String?>();
    unawaited(
      ConsentForm.loadAndShowConsentFormIfRequired(
        (error) => done.complete(error?.message),
      ),
    );
    return done.future;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptions() {
    final done = Completer<void>();
    unawaited(ConsentForm.showPrivacyOptionsForm((_) => done.complete()));
    return done.future;
  }
}

class AttTrackingGateway implements TrackingGateway {
  @override
  Future<bool> canPrompt() async =>
      await AppTrackingTransparency.trackingAuthorizationStatus ==
      TrackingStatus.notDetermined;

  @override
  Future<void> prompt() async {
    await AppTrackingTransparency.requestTrackingAuthorization();
  }
}

class GoogleMobileAdsSdk implements AdsSdk {
  @override
  Future<void> initialize() async {
    await MobileAds.instance.initialize();
  }
}
