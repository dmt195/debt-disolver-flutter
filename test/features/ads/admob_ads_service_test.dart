import 'package:debt_destroyer/features/ads/data/ad_platform.dart';
import 'package:debt_destroyer/features/ads/data/admob_ads_service.dart';
import 'package:debt_destroyer/features/ads/domain/ads_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/recording_crash_reporter.dart';

/// Records every platform call in one list so tests can check the order.
class _Platform implements ConsentGateway, TrackingGateway, AdsSdk {
  final calls = <String>[];
  String? updateError;
  String? formError;
  bool canRequest = true;
  bool trackingUndecided = true;
  bool privacyRequired = false;
  Exception? sdkFailure;

  @override
  Future<String?> requestUpdate() async {
    calls.add('update');
    return updateError;
  }

  @override
  Future<String?> showFormIfRequired() async {
    calls.add('form');
    return formError;
  }

  @override
  Future<bool> canRequestAds() async {
    calls.add('canRequest');
    return canRequest;
  }

  @override
  Future<bool> privacyOptionsRequired() async => privacyRequired;

  @override
  Future<void> showPrivacyOptions() async => calls.add('privacyForm');

  @override
  Future<bool> canPrompt() async => trackingUndecided;

  @override
  Future<void> prompt() async => calls.add('att');

  @override
  Future<void> initialize() async {
    calls.add('sdk');
    if (sdkFailure case final failure?) throw failure;
  }
}

void main() {
  late _Platform platform;
  late RecordingCrashReporter reporter;

  AdMobAdsService service({TargetPlatform on = TargetPlatform.android}) =>
      AdMobAdsService(
        config: AdsConfig.fromEnvironment(),
        consent: platform,
        tracking: platform,
        sdk: platform,
        platform: on,
        reporter: reporter,
      );

  setUp(() {
    platform = _Platform();
    reporter = RecordingCrashReporter();
  });

  test('asks for consent before starting ads', () async {
    final ads = service();
    expect(ads.canShowAds.value, isFalse);
    await ads.initialize();
    expect(platform.calls, ['update', 'form', 'canRequest', 'sdk']);
    expect(ads.canShowAds.value, isTrue);
  });

  test('on iOS, asks to track after the consent form', () async {
    await service(on: TargetPlatform.iOS).initialize();
    expect(platform.calls, ['update', 'form', 'att', 'canRequest', 'sdk']);
  });

  test('does not ask to track twice, or on Android', () async {
    platform.trackingUndecided = false;
    await service(on: TargetPlatform.iOS).initialize();
    expect(platform.calls, isNot(contains('att')));

    platform = _Platform();
    await service().initialize();
    expect(platform.calls, isNot(contains('att')));
  });

  test('shows no ads when consent does not allow them', () async {
    platform.canRequest = false;
    final ads = service();
    await ads.initialize();
    expect(platform.calls, isNot(contains('sdk')));
    expect(ads.canShowAds.value, isFalse);
  });

  test('a failed consent refresh still uses the last known consent', () async {
    platform
      ..updateError = 'offline'
      ..formError = 'no form';
    final ads = service();
    await ads.initialize();
    expect(ads.canShowAds.value, isTrue);
    expect(reporter.errors, hasLength(2));
  });

  test('an SDK failure is reported and shows no ads', () async {
    platform.sdkFailure = Exception('no network');
    final ads = service();
    await ads.initialize();
    expect(ads.canShowAds.value, isFalse);
    expect(reporter.errors.single.$1, platform.sdkFailure);
  });

  test('initialising twice runs the flow once', () async {
    final ads = service();
    await Future.wait([ads.initialize(), ads.initialize()]);
    await ads.initialize();
    expect(platform.calls.where((c) => c == 'sdk'), hasLength(1));
  });

  test('withdrawing consent in privacy options stops ads', () async {
    final ads = service();
    await ads.initialize();
    platform.canRequest = false;
    await ads.showPrivacyOptions();
    expect(platform.calls, contains('privacyForm'));
    expect(ads.canShowAds.value, isFalse);
  });

  test('reports whether privacy options are required', () async {
    platform.privacyRequired = true;
    expect(await service().privacyOptionsRequired(), isTrue);
  });
}
