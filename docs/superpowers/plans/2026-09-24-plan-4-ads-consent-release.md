# Plan 4: Ads, Consent, Crash Reporting and Release Prep — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app releasable. That means consent-gated AdMob banners on the Debts and Strategies screens, iOS tracking permission, a crash-reporting seam, Android dev/prod flavours with release signing, the app icon, a privacy policy and release guide, and CI pinned to one Flutter version with an Android build check.

**Architecture:** The app talks only to two interfaces.
- **`AdsService`:** `NoopAdsService` is used in debug builds and tests. `AdMobAdsService` runs Google's consent (UMP) and then Apple's ATT prompt, starts the SDK only if consent allows, and exposes `canShowAds` for the banner slot. Its platform calls sit behind small gateways, so the order of the flow is unit-tested.
- **`CrashReporter`:** `LogCrashReporter` writes to the device log. `installErrorHandlers` routes uncaught errors to it, and `runGuarded` reports handled ones.
- **Native configuration:** production AdMob ids and signing keys come from git-ignored files, with Google's test ids as the fallback.

**Tech Stack:** Plan 3's stack, plus google_mobile_ads 9.1 (with the UMP consent SDK), app_tracking_transparency 2.0 and flutter_launcher_icons 0.14.

**Spec:** `docs/superpowers/specs/2026-09-24-flutter-rebuild-design.md`: §7 ads and privacy, §8 crash reporting, §9 flavours, CI and release. Read it alongside this plan.

**This is the last of four plans.**

## Global Constraints

- Everything from Plans 1–3 still holds: TDD, `./tool/codegen.sh`, generated files not committed, clean analyze and format, and `pumpApp` for widget tests.
- **Ads appear only on the Debts and Strategies screens,** as an adaptive banner, and only after consent. There are no interstitials.
- **Debug builds and tests show no ads** (`ADS_ENABLED` defaults to off in debug). Without real ids, builds use Google's test ad units and app ids, never another publisher's.
- **Secrets never go into git:** `android/key.properties`, `android/admob.properties`, `ios/Flutter/AdMob.xcconfig`, and keystores.
- **Crash reports stay on the device** until a Firebase project exists. Wiring Crashlytics needs the user's Firebase account, so it's documented in `docs/release.md` rather than implemented (spec §8). Ruling: cost if wrong is one small adapter later.
- **Android flavours:** Android gets `dev`/`prod` flavours. iOS schemes need interactive Xcode work, so iOS builds differ only by `--dart-define`, and this is documented (spec §9). Ruling: cost if wrong is that dev and prod iOS builds can't be installed side by side.
- **Plan-time verification:** the finished plan was verified end to end. That covers analyze, 152 app and 68 engine tests, `apk --debug --flavor dev`, `apk --release --flavor prod`, `ios --simulator`, and a check of the built manifest and plist values. The per-task counts below are cumulative.

## Review Focus

1. **A user who declines consent, or whose consent check fails offline:** they should get no ads if consent doesn't allow them. A failed refresh must not block ads the user already agreed to, or show ads they didn't. Covered in Task 2 ("shows no ads when consent does not allow them", "a failed consent refresh still uses the last known consent").
2. **Withdrawing consent later:** Settings → Privacy choices must stop ads straight away. Covered in Task 2 ("withdrawing consent in privacy options stops ads") and Task 3 ("settings offers privacy choices only where required").
3. **iOS tracking prompt:** it should appear once, after the consent form, and never on Android. Covered in Task 2 ("on iOS, asks to track after the consent form", "does not ask to track twice, or on Android").
4. **A release build made without real ids or keys:** it should still build and run, but with test ads and a debug signature. It must not silently use someone else's ids. Covered in Task 4 (manifest and plist checks on the built apps) and `docs/release.md`.
5. **Ads never cover content:** the banner must take no space until an ad loads, and only on the two allowed screens. Covered in Task 3 ("banners appear on debts and strategies once allowed", "no banners on forms, plan detail, settings or onboarding").

---

### Task 1: Crash reporting seam

**Files:**
- Create: `lib/core/crash_reporter.dart`
- Modify: `lib/core/guarded.dart` (reports handled errors)
- Create: `test/helpers/recording_crash_reporter.dart`
- Test: `test/core/crash_reporter_test.dart`, `test/core/guarded_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class CrashReporter`, with `void recordError(Object error, StackTrace stackTrace, {bool fatal = false, String? reason})`
  - `LogCrashReporter` and `crashReporterProvider` (keepAlive)
  - `void installErrorHandlers(CrashReporter reporter)`
  - `runGuarded` now reports to `crashReporterProvider`, so it needs a `ProviderScope` ancestor, which every screen has.

- [ ] **Step 1: Write the failing tests**

`test/helpers/recording_crash_reporter.dart`:
```dart
import 'package:debt_destroyer/core/crash_reporter.dart';

class RecordingCrashReporter implements CrashReporter {
  final errors = <(Object, bool)>[];

  @override
  void recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) => errors.add((error, fatal));
}
```

`test/core/crash_reporter_test.dart`:
```dart
import 'package:debt_destroyer/core/crash_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/recording_crash_reporter.dart';

void main() {
  test('uncaught framework and platform errors reach the reporter', () {
    final flutterBefore = FlutterError.onError;
    final platformBefore = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = flutterBefore;
      PlatformDispatcher.instance.onError = platformBefore;
    });
    var previousCalled = false;
    FlutterError.onError = (_) => previousCalled = true;
    final reporter = RecordingCrashReporter();

    installErrorHandlers(reporter);
    final framework = Exception('build failed');
    FlutterError.onError!(FlutterErrorDetails(exception: framework));
    final platform = StateError('channel closed');
    final handled = PlatformDispatcher.instance.onError!(
      platform,
      StackTrace.current,
    );

    expect(reporter.errors, [(framework, true), (platform, true)]);
    expect(previousCalled, isTrue, reason: 'earlier handler still runs');
    expect(handled, isTrue);
  });

  test('the local reporter accepts errors without throwing', () {
    LogCrashReporter().recordError(Exception('x'), StackTrace.current);
  });
}
```

`test/core/guarded_test.dart`:
```dart
import 'package:debt_destroyer/core/crash_reporter.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/recording_crash_reporter.dart';

void main() {
  testWidgets('a failed action is reported and explained', (tester) async {
    final reporter = RecordingCrashReporter();
    final failure = Exception('disk full');
    Object? result = 'unset';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [crashReporterProvider.overrideWithValue(reporter)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await runGuarded<int>(
                  context,
                  () async => throw failure,
                ),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(reporter.errors.single, (failure, false));
    expect(
      find.text("Couldn't save your changes. Please try again."),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/core/crash_reporter_test.dart test/core/guarded_test.dart`
Expected: FAIL to load, because `crash_reporter.dart` doesn't exist.

- [ ] **Step 3: Implement**

`lib/core/crash_reporter.dart`:
```dart
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'crash_reporter.g.dart';

/// Where unexpected errors go. The app logs them locally; a remote service
/// (for example Firebase Crashlytics, once a project is set up) can be
/// plugged in by overriding [crashReporterProvider].
abstract interface class CrashReporter {
  void recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  });
}

/// Writes errors to the developer log. Nothing leaves the device.
class LogCrashReporter implements CrashReporter {
  @override
  void recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) => log(
    reason ?? (fatal ? 'Uncaught error' : 'Handled error'),
    error: error,
    stackTrace: stackTrace,
    level: fatal ? 1000 : 900,
  );
}

@Riverpod(keepAlive: true)
CrashReporter crashReporter(Ref ref) => LogCrashReporter();

/// Sends uncaught framework and platform errors to [reporter], keeping any
/// handler that was already installed.
void installErrorHandlers(CrashReporter reporter) {
  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    reporter.recordError(
      details.exception,
      details.stack ?? StackTrace.empty,
      fatal: true,
      reason: details.context?.toString(),
    );
    previousFlutter?.call(details);
  };
  final previousPlatform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    reporter.recordError(error, stackTrace, fatal: true);
    return previousPlatform?.call(error, stackTrace) ?? true;
  };
}
```

Replace `lib/core/guarded.dart` with:
```dart
import 'package:debt_destroyer/core/crash_reporter.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs [action]. If it throws, reports the error, shows [failureMessage]
/// (by default, that the change wasn't saved) and returns null.
Future<T?> runGuarded<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? failureMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final reporter = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(crashReporterProvider);
  final message = failureMessage ?? context.l10n.errorSaving;
  try {
    return await action();
  } on Object catch (error, stackTrace) {
    reporter.recordError(error, stackTrace, reason: 'Action failed');
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return null;
  }
}
```

- [ ] **Step 4: Generate code and run the tests**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+136: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add lib/core test/core test/helpers/recording_crash_reporter.dart
git commit -m "feat(core): crash reporter seam for handled and uncaught errors"
```

---

### Task 2: Consent-gated AdMob service

**Files:**
- Modify: `pubspec.yaml` (google_mobile_ads, app_tracking_transparency; dev dependency flutter_launcher_icons for Task 5)
- Create: `lib/features/ads/domain/ads_config.dart`, `lib/features/ads/domain/ads_service.dart`
- Create: `lib/features/ads/data/ad_platform.dart`, `lib/features/ads/data/admob_ads_service.dart`
- Create: `lib/features/ads/presentation/admob_banner.dart`, `lib/features/ads/presentation/ads_providers.dart`
- Test: `test/features/ads/ads_config_test.dart`, `test/features/ads/admob_ads_service_test.dart`

**Interfaces:**
- Consumes: `CrashReporter`, `crashReporterProvider` (Task 1).
- Produces:
  - `AdsConfig({required bool enabled, required String androidBannerId, required String iosBannerId})`, with `AdsConfig.fromEnvironment()`, `usesTestIds`, `bannerIdFor(TargetPlatform)`, `testAndroidBannerId` and `testIosBannerId`
  - `abstract interface class AdsService`, with `Future<void> initialize()`, `ValueListenable<bool> canShowAds`, `Future<bool> privacyOptionsRequired()`, `Future<void> showPrivacyOptions()` and `Widget buildBanner()`
  - `NoopAdsService`
  - the gateways `ConsentGateway`, `TrackingGateway` and `AdsSdk`, with their platform implementations `UmpConsentGateway`, `AttTrackingGateway` and `GoogleMobileAdsSdk`
  - `AdMobAdsService({required AdsConfig config, required ConsentGateway consent, required TrackingGateway tracking, required AdsSdk sdk, required TargetPlatform platform, required CrashReporter reporter})`
  - `AdMobBanner({required String adUnitId})`
  - `adsConfigProvider`, `adsServiceProvider` and `privacyOptionsRequiredProvider`
- The platform classes (`UmpConsentGateway`, `AttTrackingGateway`, `GoogleMobileAdsSdk`, `AdMobBanner`) call native plugins, which don't run in `flutter test`. They are exercised by the builds in Task 4 and on a device. Ruling: cost if wrong is a device-only bug in thin adapter code.

- [ ] **Step 1: Write the failing tests**

`test/features/ads/ads_config_test.dart`:
```dart
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
```

`test/features/ads/admob_ads_service_test.dart`:
```dart
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
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/ads`
Expected: FAIL to load, because `ads_config.dart` and `admob_ads_service.dart` don't exist.

- [ ] **Step 3: Dependencies**

Replace `pubspec.yaml` with:
```yaml
name: debt_destroyer
description: "Compare debt payoff strategies and plan your way to debt freedom."
publish_to: none
version: 0.1.0+1

environment:
  sdk: ^3.13.2

dependencies:
  app_tracking_transparency: ^2.0.7
  drift: ^2.35.0
  drift_flutter: ^0.3.1
  excel: ^4.0.6
  fl_chart: ^1.2.0
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  flutter_riverpod: ^3.4.3
  freezed_annotation: ^3.1.0
  go_router: ^18.0.1
  google_mobile_ads: ^9.1.0
  intl: ^0.20.3
  path_provider: ^2.1.6
  payoff_engine:
    path: packages/payoff_engine
  riverpod_annotation: ^4.0.7
  share_plus: ^13.3.0
  shared_preferences: ^2.5.5
  uuid: ^4.6.0

dev_dependencies:
  build_runner: ^2.16.1
  drift_dev: ^2.35.0
  flutter_launcher_icons: ^0.14.0
  flutter_test:
    sdk: flutter
  freezed: ^4.0.2
  riverpod_generator: ^4.0.9
  shared_preferences_platform_interface: ^2.4.2
  very_good_analysis: ^11.0.0

flutter:
  generate: true
  uses-material-design: true
```

- [ ] **Step 4: Implement**

`lib/features/ads/domain/ads_config.dart`:
```dart
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
```

`lib/features/ads/domain/ads_service.dart`:
```dart
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
```

`lib/features/ads/data/ad_platform.dart`:
```dart
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
```

`lib/features/ads/data/admob_ads_service.dart`:
```dart
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
```

`lib/features/ads/presentation/admob_banner.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// An anchored adaptive banner sized to the screen width. Takes no space
/// until an ad has loaded, and none if loading fails.
class AdMobBanner extends StatefulWidget {
  const AdMobBanner({required this.adUnitId, super.key});

  final String adUnitId;

  @override
  State<AdMobBanner> createState() => _AdMobBannerState();
}

class _AdMobBannerState extends State<AdMobBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  int? _width;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (width != _width) {
      _width = width;
      unawaited(_load(width));
    }
  }

  Future<void> _load(int width) async {
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) return;
    await _ad?.dispose();
    _loaded = false;
    final ad = BannerAd(
      adUnitId: widget.adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    unawaited(_ad?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
```

`lib/features/ads/presentation/ads_providers.dart`:
```dart
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
```

- [ ] **Step 5: Generate code and run the tests**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+148: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/ads test/features/ads
git commit -m "feat(ads): consent-gated AdMob service with ATT and test-unit defaults"
```

---

### Task 3: Banners on Debts and Strategies, privacy choices in Settings

**Files:**
- Create: `lib/features/ads/presentation/ad_banner.dart`
- Modify: `lib/features/debts/presentation/debts_screen.dart`, `lib/features/strategies/presentation/strategies_screen.dart`, `lib/features/settings/presentation/settings_screen.dart`, `lib/l10n/app_en.arb`, `lib/main.dart`
- Create: `test/helpers/fake_ads_service.dart`
- Test: `test/features/ads/ad_placement_test.dart`

**Interfaces:**
- Produces:
  - `AdBanner()`, the banner slot
  - `FakeAdsService({bool canShowAds, bool privacyRequired})`, with `showing=`, `privacyOptionsShown` and a `Text('Ad banner')` banner
  - `main()` installs the error handlers and starts ads initialisation after the first frame.

- [ ] **Step 1: Write the failing test**

`test/helpers/fake_ads_service.dart`:
```dart
import 'package:debt_destroyer/features/ads/domain/ads_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Ads that can be switched on and off by a test; the banner is a text.
class FakeAdsService implements AdsService {
  FakeAdsService({bool canShowAds = false, this.privacyRequired = false})
    : _canShowAds = ValueNotifier(canShowAds);

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
  Widget buildBanner() => const Text('Ad banner');
}
```

`test/features/ads/ad_placement_test.dart`:
```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/ads/presentation/ads_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/fake_ads_service.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<AppHarness> open(
    WidgetTester tester,
    FakeAdsService ads, {
    String location = Routes.debts,
  }) => pumpApp(
    tester,
    debts: [testDebt(id: 'a')],
    location: location,
    overrides: [adsServiceProvider.overrideWithValue(ads)],
  );

  testWidgets('banners appear on debts and strategies once allowed', (
    tester,
  ) async {
    final ads = FakeAdsService();
    final app = await open(tester, ads);
    expect(find.text('Ad banner'), findsNothing);

    ads.showing = true;
    await tester.pumpAndSettle();
    expect(find.text('Ad banner'), findsOneWidget);

    await app.router.go(tester, Routes.strategies);
    expect(find.text('Ad banner'), findsOneWidget);
  });

  testWidgets('no banners on forms, plan detail, settings or onboarding', (
    tester,
  ) async {
    final ads = FakeAdsService(canShowAds: true);
    final app = await open(tester, ads, location: Routes.newDebt);
    expect(find.text('Ad banner'), findsNothing);
    for (final location in [
      Routes.plan(StrategyId.avalanche),
      Routes.settings,
    ]) {
      await app.router.go(tester, location);
      expect(find.text('Ad banner'), findsNothing, reason: location);
    }
  });

  testWidgets('settings offers privacy choices only where required', (
    tester,
  ) async {
    final ads = FakeAdsService(privacyRequired: true);
    await open(tester, ads, location: Routes.settings);
    await tester.scrollUntilVisible(
      find.text('Privacy choices'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Privacy choices'));
    await tester.pumpAndSettle();
    expect(ads.privacyOptionsShown, 1);
  });

  testWidgets('no privacy choices where they are not required', (tester) async {
    await open(tester, FakeAdsService(), location: Routes.settings);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Privacy choices'), findsNothing);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/ads/ad_placement_test.dart`
Expected: FAIL, because no screen shows a banner or privacy choices. "no banners on forms…" passes already, since it guards against a regression.

- [ ] **Step 3: Implement**

`lib/features/ads/presentation/ad_banner.dart`:
```dart
import 'package:debt_destroyer/features/ads/presentation/ads_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The banner slot at the bottom of the Debts and Strategies screens. Empty
/// until consent allows ads.
class AdBanner extends ConsumerWidget {
  const AdBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ads = ref.watch(adsServiceProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: ads.canShowAds,
      builder: (context, canShow, _) => canShow
          ? SafeArea(top: false, child: Center(child: ads.buildBanner()))
          : const SizedBox.shrink(),
    );
  }
}
```

Replace `lib/features/debts/presentation/debts_screen.dart` with:
```dart
import 'dart:async';

import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/ads/presentation/ad_banner.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final debts = ref.watch(debtsProvider);
    final settingsState = ref.watch(settingsControllerProvider);
    final settings = settingsState.value;
    final hasDebts = debts.value?.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.debtsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTooltip,
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newDebt),
        icon: const Icon(Icons.add),
        label: Text(l10n.addDebt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdBanner(),
          BottomAppBar(
            child: Row(
              children: [
                FilledButton(
                  onPressed: hasDebts
                      ? () => context.push(Routes.strategies)
                      : null,
                  child: Text(l10n.compareStrategies),
                ),
              ],
            ),
          ),
        ],
      ),
      body: switch ((debts, settings)) {
        _ when settingsState.hasError || debts.hasError => ErrorRetryView(
          // Debts depend on settings, so reload both.
          onRetry: () => ref
            ..invalidate(settingsControllerProvider)
            ..invalidate(debtsProvider),
        ),
        (AsyncData(:final value), final AppSettings settings) => _DebtsBody(
          debts: value,
          settings: settings,
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _DebtsBody extends ConsumerStatefulWidget {
  const _DebtsBody({required this.debts, required this.settings});

  final List<Debt> debts;
  final AppSettings settings;

  @override
  ConsumerState<_DebtsBody> createState() => _DebtsBodyState();
}

class _DebtsBodyState extends ConsumerState<_DebtsBody> {
  /// Debts swiped away but not yet gone from the stream. A dismissed
  /// Dismissible must leave the tree immediately.
  final _removed = <String>{};

  @override
  void didUpdateWidget(_DebtsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Forget deletions the stream has caught up with.
    _removed.retainWhere((id) => widget.debts.any((d) => d.id == id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final debts = [
      for (final d in widget.debts)
        if (!_removed.contains(d.id)) d,
    ];
    final currency = widget.settings.currencyCode;
    final minimums = totalMinimumPayments(debts, currency: currency);
    final budget = widget.settings.monthlyBudget;

    return Column(
      children: [
        _SummaryCard(
          total: debts.fold(Money.zero(currency), (sum, d) => sum + d.balance),
          minimums: minimums,
          budget: budget,
          locale: locale,
        ),
        if (minimums > budget)
          _ShortfallBanner(shortfall: minimums - budget, locale: locale),
        Expanded(
          child: debts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.debtsEmpty, textAlign: TextAlign.center),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: debts.length,
                  onReorderItem: (from, to) => _reorder(debts, from, to),
                  itemBuilder: (context, i) => _dismissible(debts[i], locale),
                ),
        ),
      ],
    );
  }

  Widget _dismissible(Debt debt, String locale) => Dismissible(
    key: ValueKey(debt.id),
    direction: DismissDirection.endToStart,
    background: ColoredBox(
      color: Theme.of(context).colorScheme.errorContainer,
      child: const Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Icon(Icons.delete_outline),
        ),
      ),
    ),
    confirmDismiss: (_) => _confirmDelete(debt),
    onDismissed: (_) {
      setState(() => _removed.add(debt.id));
      unawaited(_delete(debt));
    },
    child: DebtTile(debt: debt, locale: locale),
  );

  Future<bool> _confirmDelete(Debt debt) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteDebtTitle(debt.name)),
        content: Text(l10n.deleteDebtBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _delete(Debt debt) async {
    final deleted = await runGuarded(context, () async {
      await ref.read(debtActionsProvider.notifier).delete(debt.id);
      return true;
    });
    if (deleted != null) return;
    // Nothing was deleted, so show the debt again. Wait until the dismissed
    // tile has left the tree first, or Dismissible asserts.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) setState(() => _removed.remove(debt.id));
  }

  Future<void> _reorder(List<Debt> visible, int from, int to) async {
    final ids = reorderedIds(
      [for (final d in visible) d.id],
      from: from,
      to: to,
      hidden: [
        for (final d in widget.debts)
          if (_removed.contains(d.id)) d.id,
      ],
    );
    await runGuarded(
      context,
      () => ref.read(debtActionsProvider.notifier).reorder(ids),
    );
  }
}

/// The full id order after moving the debt at [from] to [to] among
/// [visibleIds] (`to` as adjusted by `onReorderItem`). Debts [hidden] while
/// their deletion is pending stay at the end, because the repository needs
/// every stored id.
@visibleForTesting
List<String> reorderedIds(
  List<String> visibleIds, {
  required int from,
  required int to,
  List<String> hidden = const [],
}) {
  final ids = [...visibleIds];
  ids.insert(to, ids.removeAt(from));
  return [...ids, ...hidden];
}

class DebtTile extends StatelessWidget {
  const DebtTile({required this.debt, required this.locale, super.key});

  final Debt debt;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      leading: Icon(switch (debt.type) {
        DebtType.creditCard => Icons.credit_card,
        DebtType.loan => Icons.account_balance_outlined,
        DebtType.personal => Icons.people_outline,
      }, semanticLabel: debtTypeLabel(l10n, debt.type)),
      title: Text(debt.name),
      subtitle: Text(
        '${l10n.debtApr(formatPercent(debt.aprBps, locale))} · '
        '${l10n.debtMinimum(formatMoney(minimumPayment(debt), locale))}',
      ),
      trailing: Text(
        formatMoney(debt.balance, locale),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: () => context.push(Routes.editDebt(debt.id)),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.minimums,
    required this.budget,
    required this.locale,
  });

  final Money total;
  final Money minimums;
  final Money budget;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget figure(String label, Money value) => Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(
            formatMoney(value, locale),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            figure(l10n.totalDebt, total),
            figure(l10n.minimumPayments, minimums),
            figure(l10n.monthlyBudget, budget),
          ],
        ),
      ),
    );
  }
}

class _ShortfallBanner extends StatelessWidget {
  const _ShortfallBanner({required this.shortfall, required this.locale});

  final Money shortfall;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: ListTile(
        leading: Icon(Icons.warning_amber, color: scheme.onErrorContainer),
        title: Text(
          l10n.budgetShortfall(formatMoney(shortfall, locale)),
          style: TextStyle(color: scheme.onErrorContainer),
        ),
        trailing: TextButton(
          onPressed: () => context.push(Routes.settings),
          child: Text(l10n.changeBudget),
        ),
      ),
    );
  }
}
```

Replace `lib/features/strategies/presentation/strategies_screen.dart` with:
```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/ads/presentation/ad_banner.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';

class StrategiesScreen extends ConsumerWidget {
  const StrategiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final debts = ref.watch(debtsProvider).value;
    final plans = ref.watch(plansProvider);
    final parameters = ref
        .watch(settingsControllerProvider)
        .value
        ?.strategyParameters;

    final Widget body;
    if (debts != null && debts.isEmpty) {
      body = _Message(l10n.strategiesEmpty);
    } else {
      body = switch ((plans, parameters)) {
        (AsyncData(:final value), final StrategyParameters parameters) =>
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final (i, result) in value.indexed)
                _StrategyCard(
                  result: result,
                  parameters: parameters,
                  cheapest: i == 0 && result is Feasible,
                ),
            ],
          ),
        (AsyncError(), _) => _Message(
          l10n.plansError,
          // Plans depend on settings, which may be what failed.
          onRetry: () => ref
            ..invalidate(settingsControllerProvider)
            ..invalidate(plansProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.strategiesTitle)),
      body: body,
      bottomNavigationBar: const AdBanner(),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ],
      ),
    ),
  );
}

class _StrategyCard extends ConsumerWidget {
  const _StrategyCard({
    required this.result,
    required this.parameters,
    required this.cheapest,
  });

  final PayoffResult result;
  final StrategyParameters parameters;
  final bool cheapest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final theme = Theme.of(context);
    final id = result.strategyId;

    final details = switch (result) {
      Feasible(:final plan) => _FeasibleDetails(plan: plan, locale: locale),
      Infeasible(:final shortfall, :final month) => Text(
        l10n.infeasible(formatMoney(shortfall, locale), month),
        style: TextStyle(color: theme.colorScheme.error),
      ),
      NeverClears() => Text(
        l10n.neverClears,
        style: TextStyle(color: theme.colorScheme.error),
      ),
    };

    return Card(
      key: ValueKey(id),
      color: cheapest ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: result is Feasible ? () => context.push(Routes.plan(id)) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strategyName(l10n, id),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (cheapest) Chip(label: Text(l10n.cheapest)),
                ],
              ),
              Text(
                strategyDescription(l10n, id, parameters, locale),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              details,
            ],
          ),
        ),
      ),
    );
  }
}

class _FeasibleDetails extends StatelessWidget {
  const _FeasibleDetails({required this.plan, required this.locale});

  final PayoffPlan plan;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (plan.monthsToClear == 0) return Text(l10n.alreadyDebtFree);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.debtFreeIn(formatDuration(l10n, plan.monthsToClear)),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          '${l10n.totalInterest}: ${formatMoney(plan.totalInterest, locale)}',
        ),
        if (plan.totalFees.isPositive)
          Text('${l10n.fees}: ${formatMoney(plan.totalFees, locale)}'),
        Text('${l10n.totalPaid}: ${formatMoney(plan.totalPaid, locale)}'),
      ],
    );
  }
}
```

Replace `lib/features/settings/presentation/settings_screen.dart` with:
```dart
import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/ads/presentation/ads_providers.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/presentation/currency_picker.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsControllerProvider);
    final settings = state.value;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: state.hasError
          ? ErrorRetryView(
              onRetry: () => ref.invalidate(settingsControllerProvider),
            )
          : settings == null
          ? const Center(child: CircularProgressIndicator())
          // Rebuild the fields when the currency changes: amounts are rescaled.
          : _SettingsForm(
              key: ValueKey(settings.currencyCode),
              settings: settings,
            ),
    );
  }
}

enum _Field { budget, consolidationApr, promoMonths, transferFee, revertApr }

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings, super.key});

  final AppSettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<_Field, TextEditingController> _controllers;
  Map<_Field, String> _errors = const {};

  @override
  void initState() {
    super.initState();
    final locale = ref.read(formatLocaleProvider);
    final s = widget.settings;
    final p = s.strategyParameters;
    String percent(int bps) => formatPercentInput(bps, locale);
    _controllers = {
      _Field.budget: TextEditingController(
        text: formatAmountInput(s.monthlyBudget, locale),
      ),
      _Field.consolidationApr: TextEditingController(
        text: percent(p.consolidationAprBps),
      ),
      _Field.promoMonths: TextEditingController(text: '${p.promoMonths}'),
      _Field.transferFee: TextEditingController(
        text: percent(p.transferFeeBps),
      ),
      _Field.revertApr: TextEditingController(text: percent(p.revertAprBps)),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final code = widget.settings.currencyCode;
    final percentError = l10n.errorInvalidPercent(
      formatPercentInput(1990, locale),
    );
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);

    Widget field(
      _Field f,
      String label,
      String? Function(String) validate, {
      TextInputType keyboard = numberKeyboard,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey(f),
        controller: _controllers[f],
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (v) => validate(v ?? ''),
        forceErrorText: _errors[f],
        onChanged: (_) {
          if (_errors.containsKey(f)) {
            setState(() => _errors = {..._errors}..remove(f));
          }
        },
      ),
    );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CurrencyPicker(
              value: code,
              onChanged: (next) => runGuarded(
                context,
                () => ref
                    .read(settingsControllerProvider.notifier)
                    .setCurrency(next),
              ),
            ),
          ),
          field(
            _Field.budget,
            l10n.settingsBudget,
            (v) =>
                parseAmountMinor(v, currencyCode: code, locale: locale) == null
                ? l10n.errorInvalidAmount(
                    formatAmountInput(Money(30000, code), locale),
                  )
                : null,
          ),
          heading(l10n.settingsConsolidation),
          field(
            _Field.consolidationApr,
            l10n.settingsConsolidationApr,
            (v) => parsePercentBps(v, locale) == null ? percentError : null,
          ),
          heading(l10n.settingsTransfer),
          field(
            _Field.promoMonths,
            l10n.settingsPromoMonths,
            (v) => parseWholeNumber(v) == null ? l10n.errorWholeNumber : null,
            keyboard: TextInputType.number,
          ),
          field(
            _Field.transferFee,
            l10n.settingsTransferFee,
            (v) => parsePercentBps(v, locale) == null ? percentError : null,
          ),
          field(
            _Field.revertApr,
            l10n.settingsRevertApr,
            (v) => parsePercentBps(v, locale) == null ? percentError : null,
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: Text(l10n.save)),
          if (ref.watch(privacyOptionsRequiredProvider).value ?? false)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(l10n.privacyChoices),
              subtitle: Text(l10n.privacyChoicesHint),
              onTap: () => runGuarded(
                context,
                () => ref.read(adsServiceProvider).showPrivacyOptions(),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    // A field rejected last time keeps its message until it is edited.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final locale = ref.read(formatLocaleProvider);
    String text(_Field f) => _controllers[f]!.text;
    final budgetMinor = parseAmountMinor(
      text(_Field.budget),
      currencyCode: widget.settings.currencyCode,
      locale: locale,
    )!;
    final parameters = StrategyParameters(
      consolidationAprBps: parsePercentBps(
        text(_Field.consolidationApr),
        locale,
      )!,
      promoMonths: parseWholeNumber(text(_Field.promoMonths))!,
      transferFeeBps: parsePercentBps(text(_Field.transferFee), locale)!,
      revertAprBps: parsePercentBps(text(_Field.revertApr), locale)!,
    );
    final controller = ref.read(settingsControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final result = await runGuarded(context, () async {
      final budgetErrors = await controller.setMonthlyBudget(budgetMinor);
      final parameterErrors = await controller.setStrategyParameters(
        parameters,
      );
      return (budgetErrors, parameterErrors);
    });
    if (result == null || !mounted) return;
    final (budgetErrors, parameterErrors) = result;
    final errors = <_Field, String>{
      if (budgetErrors.contains(BudgetValidationError.notPositive))
        _Field.budget: l10n.errorBudgetNotPositive,
      if (budgetErrors.contains(BudgetValidationError.tooLarge))
        _Field.budget: l10n.errorTooLarge,
      for (final e in parameterErrors)
        switch (e) {
          StrategyParametersValidationError.consolidationAprOutOfRange =>
            _Field.consolidationApr,
          StrategyParametersValidationError.transferFeeOutOfRange =>
            _Field.transferFee,
          StrategyParametersValidationError.promoMonthsOutOfRange =>
            _Field.promoMonths,
          StrategyParametersValidationError.revertAprOutOfRange =>
            _Field.revertApr,
        }: switch (e) {
          StrategyParametersValidationError.promoMonthsOutOfRange =>
            l10n.errorPromoMonthsRange(kMaxPromoMonths),
          _ => l10n.errorRateRange,
        },
    };
    setState(() => _errors = errors);
    if (errors.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSaved)));
    }
  }
}
```

Replace `lib/l10n/app_en.arb` with this version, which adds `privacyChoices` and `privacyChoicesHint`:
```json
{
  "@@locale": "en",
  "appTitle": "Debt Destroyer",
  "save": "Save",
  "cancel": "Cancel",
  "delete": "Delete",
  "retry": "Try again",
  "errorGeneric": "Something went wrong. Please try again.",
  "errorSaving": "Couldn't save your changes. Please try again.",
  "exportFailed": "Couldn't share this plan. Please try again.",

  "onboardingTitle": "Welcome to Debt Destroyer",
  "onboardingIntro1": "Debt Destroyer compares ways of paying off your debts, so you can choose the fastest and cheapest.",
  "onboardingIntro2": "Pay the minimum on every debt, then put everything else towards the one with the highest interest rate.",
  "onboardingIntro3": "When a debt is cleared, its payment rolls on to the next one: the quickest route to being debt-free.",
  "onboardingBudgetQuestion": "How much can you pay towards your debts each month?",
  "onboardingStart": "Get started",

  "debtsTitle": "Your debts",
  "debtsEmpty": "No debts yet. Add your first one to get started.",
  "addDebt": "Add debt",
  "compareStrategies": "Compare strategies",
  "totalDebt": "Total debt",
  "minimumPayments": "Minimum payments",
  "monthlyBudget": "Monthly budget",
  "budgetShortfall": "Your budget is {shortfall} short of this month's minimum payments.",
  "@budgetShortfall": {"placeholders": {"shortfall": {"type": "String"}}},
  "changeBudget": "Change budget",
  "deleteDebtTitle": "Delete {name}?",
  "@deleteDebtTitle": {"placeholders": {"name": {"type": "String"}}},
  "deleteDebtBody": "This can't be undone.",
  "debtApr": "{apr} APR",
  "@debtApr": {"placeholders": {"apr": {"type": "String"}}},
  "debtMinimum": "Minimum {amount}",
  "@debtMinimum": {"placeholders": {"amount": {"type": "String"}}},
  "settingsTooltip": "Settings",

  "debtTypeCreditCard": "Credit card",
  "debtTypeLoan": "Loan",
  "debtTypePersonal": "Friends & family",

  "newDebtTitle": "Add debt",
  "editDebtTitle": "Edit debt",
  "fieldName": "Name",
  "fieldBalance": "Balance",
  "fieldApr": "Interest rate (APR %)",
  "fieldMinPercent": "Minimum payment (% of balance)",
  "fieldMinFloor": "Minimum payment (at least)",
  "fieldAllowsOverpayment": "Can pay more than the minimum",
  "fieldAllowsOverpaymentHint": "Turn off for loans with fixed repayments",

  "errorInvalidAmount": "Enter an amount, e.g. {example}",
  "@errorInvalidAmount": {"placeholders": {"example": {"type": "String"}}},
  "errorInvalidPercent": "Enter a percentage, e.g. {example}",
  "@errorInvalidPercent": {"placeholders": {"example": {"type": "String"}}},
  "errorWholeNumber": "Enter a whole number",
  "errorNameEmpty": "Enter a name",
  "errorBalanceNotPositive": "Enter a balance above zero",
  "errorTooLarge": "That's more than the maximum allowed",
  "errorRateRange": "Enter a rate between 0 and 100",
  "errorPercentRange": "Enter a percentage between 0 and 100",
  "errorFloorNegative": "Can't be negative",
  "errorTooManyDebts": "You can track up to {max} debts",
  "@errorTooManyDebts": {"placeholders": {"max": {"type": "int"}}},
  "errorBudgetNotPositive": "Enter a budget above zero",
  "errorPromoMonthsRange": "Enter between 0 and {max} months",
  "@errorPromoMonthsRange": {"placeholders": {"max": {"type": "int"}}},

  "strategiesTitle": "Strategies",
  "strategiesEmpty": "Add a debt to compare strategies.",
  "strategyAvalanche": "Highest interest first",
  "strategyAvalancheDescription": "Minimums on everything, the rest to the highest-rate debt.",
  "strategyLowestAprFirst": "Lowest interest first",
  "strategyLowestAprFirstDescription": "Minimums on everything, the rest to the lowest-rate debt.",
  "strategyBoosted": "Pay 10% more",
  "strategyBoostedDescription": "Highest interest first, with a monthly budget 10% higher.",
  "strategyConsolidation": "Consolidation loan",
  "strategyConsolidationDescription": "One loan at {apr} replaces all your debts.",
  "@strategyConsolidationDescription": {"placeholders": {"apr": {"type": "String"}}},
  "strategyBalanceTransfer": "0% balance transfer",
  "strategyBalanceTransferDescription": "Move everything to a 0% card for {months} months ({fee} fee, then {apr}).",
  "@strategyBalanceTransferDescription": {"placeholders": {"months": {"type": "int"}, "fee": {"type": "String"}, "apr": {"type": "String"}}},
  "cheapest": "Cheapest",
  "debtFreeIn": "Debt-free in {duration}",
  "@debtFreeIn": {"placeholders": {"duration": {"type": "String"}}},
  "alreadyDebtFree": "Nothing left to pay.",
  "totalInterest": "Total interest",
  "totalPaid": "Total paid",
  "fees": "Fees",
  "infeasible": "Your budget is {shortfall} short of the minimum payments in month {month}.",
  "@infeasible": {"placeholders": {"shortfall": {"type": "String"}, "month": {"type": "int"}}},
  "neverClears": "Never pays off at this budget.",
  "plansError": "Couldn't calculate your plans. Check your debts and budget, then try again.",
  "months": "{count, plural, =1{1 month} other{{count} months}}",
  "@months": {"placeholders": {"count": {"type": "int"}}},
  "years": "{count, plural, =1{1 year} other{{count} years}}",
  "@years": {"placeholders": {"count": {"type": "int"}}},
  "yearsAndMonths": "{years} {months}",
  "@yearsAndMonths": {"placeholders": {"years": {"type": "String"}, "months": {"type": "String"}}},

  "tabSummary": "Summary",
  "tabChart": "Chart",
  "tabSchedule": "Schedule",
  "debtFreeBy": "Debt-free by {date}",
  "@debtFreeBy": {"placeholders": {"date": {"type": "String"}}},
  "payThisMonth": "Pay this month",
  "paymentPriority": "Payment priority",
  "paymentPriorityHint": "Extra money goes to the first debt that can take it.",
  "share": "Share",
  "exportCsv": "Spreadsheet (CSV)",
  "exportXlsx": "Excel workbook (XLSX)",
  "scheduleMonth": "Month",
  "scheduleTotal": "Total",
  "schedulePayment": "{name} payment",
  "@schedulePayment": {"placeholders": {"name": {"type": "String"}}},
  "scheduleBalance": "{name} balance",
  "@scheduleBalance": {"placeholders": {"name": {"type": "String"}}},
  "scheduleTotalPayment": "Total payment",
  "scheduleTotalBalance": "Total balance",
  "chartTitle": "Balance over time",
  "planUnavailable": "This plan isn't available for your current debts and budget.",
  "consolidationLoanName": "Consolidation loan",
  "balanceTransferCardName": "Balance transfer card",

  "settingsTitle": "Settings",
  "settingsCurrency": "Currency",
  "settingsBudget": "Monthly budget",
  "settingsConsolidation": "Consolidation loan",
  "settingsConsolidationApr": "Loan interest rate (APR %)",
  "settingsTransfer": "0% balance transfer",
  "settingsPromoMonths": "Interest-free months",
  "settingsTransferFee": "Transfer fee (% of balance)",
  "settingsRevertApr": "Interest rate afterwards (APR %)",
  "settingsSaved": "Saved",
  "privacyChoices": "Privacy choices",
  "privacyChoicesHint": "Change how ads use your data"
}
```

Replace `lib/main.dart` with:
```dart
import 'dart:async';
import 'dart:developer';

import 'package:debt_destroyer/app/app.dart';
import 'package:debt_destroyer/core/crash_reporter.dart';
import 'package:debt_destroyer/features/ads/presentation/ads_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  installErrorHandlers(container.read(crashReporterProvider));
  // Load settings before the first frame so the router knows whether to
  // show onboarding. If loading fails the app still starts; the screens show
  // the error and offer a retry.
  try {
    await container.read(settingsControllerProvider.future);
  } on Object catch (error, stackTrace) {
    log('Settings failed to load', error: error, stackTrace: stackTrace);
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const DebtDestroyerApp(),
    ),
  );
  // Ask for ads consent once the first screen is showing, so the consent
  // form appears over the app rather than a blank screen.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(container.read(adsServiceProvider).initialize()),
  );
}
```

- [ ] **Step 4: Generate code and run the tests**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`
Expected: `No issues found!`, format exits with 0, and `+152: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "feat(ads): banners on debts and strategies, privacy choices in settings"
```

---

### Task 4: Native configuration: flavours, AdMob ids, signing, iOS privacy keys

**Files:**
- Modify: `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `android/.gitignore`
- Modify: `ios/Flutter/Debug.xcconfig`, `ios/Flutter/Release.xcconfig`, `ios/.gitignore`, `ios/Runner/Info.plist`
- Add (created by the iOS build): `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`, `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

This task is configuration, not code, so its "tests" are builds plus checks of the built artefacts.

- [ ] **Step 1: Android**

Replace `android/app/build.gradle.kts` with:
```kotlin
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (never committed) with storeFile,
// storePassword, keyAlias and keyPassword. Without it, release builds are
// signed with the debug key so they still run locally.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

// Production AdMob app id: android/admob.properties (never committed) with
// admobAppId=ca-app-pub-...~... Without it, Google's test app id is used.
val admobProperties = Properties().apply {
    val file = rootProject.file("admob.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val testAdmobAppId = "ca-app-pub-3940256099942544~3347511713"

android {
    namespace = "com.dmt195.debt_destroyer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.dmt195.debt_destroyer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        resValues = true
    }

    // dev installs alongside prod with its own id and name, and always uses
    // Google's test AdMob app id.
    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "Debt Destroyer Dev")
            manifestPlaceholders["admobAppId"] = testAdmobAppId
        }
        create("prod") {
            dimension = "environment"
            resValue("string", "app_name", "Debt Destroyer")
            manifestPlaceholders["admobAppId"] =
                admobProperties.getProperty("admobAppId", testAdmobAppId)
        }
    }

    signingConfigs {
        if (!keystoreProperties.isEmpty) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (keystoreProperties.isEmpty) signingConfigs.getByName("debug")
                else signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
```

Replace `android/app/src/main/AndroidManifest.xml` with:
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="@string/app_name"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <!-- AdMob app id: set per flavor in android/app/build.gradle.kts. -->
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="${admobAppId}" />
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.

         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

Append `admob.properties` to `android/.gitignore`. That file already ignores `key.properties` and keystores.

- [ ] **Step 2: iOS**

Replace `ios/Flutter/Debug.xcconfig` with:
```
#include "Generated.xcconfig"

// AdMob app id. Google's test id unless ios/Flutter/AdMob.xcconfig (never
// committed) sets ADMOB_APP_ID to the production one.
ADMOB_APP_ID=ca-app-pub-3940256099942544~1458002511
#include? "AdMob.xcconfig"
```

Replace `ios/Flutter/Release.xcconfig` with:
```
#include "Generated.xcconfig"

// AdMob app id. Google's test id unless ios/Flutter/AdMob.xcconfig (never
// committed) sets ADMOB_APP_ID to the production one.
ADMOB_APP_ID=ca-app-pub-3940256099942544~1458002511
#include? "AdMob.xcconfig"
```

Append `Flutter/AdMob.xcconfig` to `ios/.gitignore`.

Replace `ios/Runner/Info.plist` with:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CADisableMinimumFrameDurationOnPhone</key>
	<true/>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>Debt Destroyer</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>debt_destroyer</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>UIApplicationSceneManifest</key>
	<dict>
		<key>UIApplicationSupportsMultipleScenes</key>
		<false/>
		<key>UISceneConfigurations</key>
		<dict>
			<key>UIWindowSceneSessionRoleApplication</key>
			<array>
				<dict>
					<key>UISceneClassName</key>
					<string>UIWindowScene</string>
					<key>UISceneConfigurationName</key>
					<string>flutter</string>
					<key>UISceneDelegateClassName</key>
					<string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
					<key>UISceneStoryboardFile</key>
					<string>Main</string>
				</dict>
			</array>
		</dict>
	</dict>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
	<key>UILaunchStoryboardName</key>
	<string>LaunchScreen</string>
	<key>UIMainStoryboardFile</key>
	<string>Main</string>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>GADApplicationIdentifier</key>
	<string>$(ADMOB_APP_ID)</string>
	<key>NSUserTrackingUsageDescription</key>
	<string>This lets ads be more relevant to you. Your debts never leave your device.</string>
	<key>SKAdNetworkItems</key>
	<array>
		<dict>
			<key>SKAdNetworkIdentifier</key>
			<string>cstr6suwn9.skadnetwork</string>
		</dict>
	</array>
</dict>
</plist>
```

- [ ] **Step 3: Build every variant and check the built values**

```bash
flutter build apk --debug --flavor dev
flutter build apk --release --flavor prod
flutter build ios --simulator --debug
plutil -p build/ios/iphonesimulator/Runner.app/Info.plist | grep GADApplicationIdentifier
```
Expected:
- `✓ Built build/app/outputs/flutter-apk/app-dev-debug.apk`
- `✓ Built build/app/outputs/flutter-apk/app-prod-release.apk`
- `✓ Built build/ios/iphonesimulator/Runner.app`
- `"GADApplicationIdentifier" => "ca-app-pub-3940256099942544~1458002511"` (Google's test iOS app id, because no `AdMob.xcconfig` exists)

With the Android SDK's `aapt2`, `dump badging` of the prod APK shows `package: name='com.dmt195.debt_destroyer'` and `application-label:'Debt Destroyer'`.

- [ ] **Step 4: Commit**

```bash
git add android ios
git status --short android ios   # expect nothing unstaged; no key or admob files
git commit -m "build: dev/prod flavors, AdMob app ids from ignored files, release signing, iOS privacy keys"
```

---

### Task 5: App icon

**Files:**
- Create: `flutter_launcher_icons.yaml`
- Generated and committed: Android `mipmap-*/ic_launcher.png`, `drawable-*/ic_launcher_foreground.png`, `mipmap-anydpi-v26/ic_launcher.xml`, `values/colors.xml`; iOS `AppIcon.appiconset/*`

- [ ] **Step 1: Configure and generate**

`flutter_launcher_icons.yaml`:
```yaml
# App icons from the artwork in legacy/resources. Regenerate with:
#   dart run flutter_launcher_icons
flutter_launcher_icons:
  image_path: "legacy/resources/artwork.png"
  android: true
  ios: true
  remove_alpha_ios: true
  background_color_ios: "#FFFFFF"
  adaptive_icon_background: "#FFFFFF"
  adaptive_icon_foreground: "legacy/resources/artwork.png"
  adaptive_icon_foreground_inset: 16
  min_sdk_android: 24
```
Run: `dart run flutter_launcher_icons`
Expected: `✓ Successfully generated launcher icons`.

- [ ] **Step 2: Undo the tool's project-file edit**

flutter_launcher_icons 0.14 rewrites `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` in `ios/Runner.xcodeproj/project.pbxproj`, which is not the app-icon setting. The icon set is already the default `AppIcon`, so revert it:
```bash
git checkout -- ios/Runner.xcodeproj/project.pbxproj
```

- [ ] **Step 3: Check the icons**

Open `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`. It should show the blue card from `legacy/resources/artwork.png` on white. Then run `flutter build ios --simulator --debug && flutter build apk --debug --flavor dev`. Expected: both succeed, and `Runner.app` contains `AppIcon60x60@2x.png`.

- [ ] **Step 4: Commit**

```bash
git add flutter_launcher_icons.yaml android/app/src/main/res ios/Runner/Assets.xcassets
git commit -m "build: app icon from the new artwork"
```

---

### Task 6: Privacy policy, release guide, CI and docs

**Files:**
- Create: `docs/privacy-policy.md`, `docs/release.md`
- Modify: `.github/workflows/app.yml` (pins Flutter 3.47.2; adds an Android build job), `CLAUDE.md`

- [ ] **Step 1: Documents**

`docs/privacy-policy.md`:
```markdown
# Debt Destroyer privacy policy

Effective 24 September 2026.

Debt Destroyer helps you compare ways to pay off your debts. This policy explains what happens to information when you use the app.

## Your debts and settings stay on your device

The debts, balances, interest rates, budget and settings you enter are stored only on your phone or tablet. They are never sent to us or to anyone else. Deleting the app deletes them. Files you export (CSV or Excel) go only where you choose to share them.

## Advertising

The app is free and shows banner ads from Google AdMob on some screens. To show and measure ads, Google may collect information such as your device's advertising identifier, IP address, and which ads you see and tap. Google's use of this information is described in its policy: https://policies.google.com/technologies/partner-sites

- **In the European Economic Area, the UK and Switzerland**, the app asks for your consent through Google's consent form before any ads are requested. You can change your choice at any time in **Settings → Privacy choices**.
- **On iPhone and iPad**, the app asks for permission to track through Apple's App Tracking Transparency prompt. If you decline, ads are not personalised using your device's identifier.
- If you don't consent to personalised ads, you may still see non-personalised ads.

## Crash information

If the app hits an unexpected error, details are written to your device's log to help fix problems during development. Nothing is sent from your device.

## Children

The app is not directed at children under 13, and we do not knowingly collect information from them.

## Changes

If this policy changes, the new version will be published at the same address with a new effective date.

## Contact

Use the contact details on the app's App Store or Google Play listing.
```

`docs/release.md`:
````markdown
# Releasing Debt Destroyer

What has to be in place before a store release, and how to build one. Everything secret stays out of git: the files named below are ignored.

## 1. AdMob

1. In AdMob, create an app for Android and one for iOS, and an **adaptive banner** unit for each. (The 2013 app's publisher account, `ca-app-pub-3611480488934998`, can hold them; the old unit `8084462063` belonged to the legacy app.)
2. In **Privacy & messaging**, publish a GDPR consent message and, for iOS, an IDFA explainer message. The app shows these through Google's User Messaging Platform.
3. Put the app ids where the native builds read them:
   - `android/admob.properties`: `admobAppId=ca-app-pub-XXXXXXXX~YYYYYYYY` (used by the `prod` flavor)
   - `ios/Flutter/AdMob.xcconfig`: `ADMOB_APP_ID=ca-app-pub-XXXXXXXX~ZZZZZZZZ`
4. Pass the banner unit ids at build time (below). Without them Google's test units are used and the ads say "Test Ad".
5. Publish an `app-ads.txt` on the developer website listed in the stores.

## 2. Android signing

```bash
keytool -genkey -v -keystore ~/debt-destroyer-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Create `android/key.properties`:

```properties
storeFile=/Users/you/debt-destroyer-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Without this file, release builds are signed with the debug key, which the Play Store rejects.

## 3. Build

Bump `version:` in `pubspec.yaml` first (`1.0.0+2`: name, then an ever-increasing build number).

```bash
./tool/codegen.sh
flutter build appbundle --release --flavor prod \
  --dart-define=ADS_ENABLED=true \
  --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-XXXXXXXX/NNNNNNNNNN
flutter build ipa --release \
  --dart-define=ADS_ENABLED=true \
  --dart-define=ADMOB_BANNER_IOS=ca-app-pub-XXXXXXXX/NNNNNNNNNN
```

Android has two flavors: `dev` (`com.dmt195.debt_destroyer.dev`, "Debt Destroyer Dev", always Google's test AdMob app id) and `prod`. iOS has no flavors yet: both builds use `com.dmt195.debt_destroyer`, and dev/prod differ only in the `--dart-define`s. Separate iOS schemes can be added later in Xcode (see https://docs.flutter.dev/deployment/flavors-ios).

## 4. Store listings

- **Privacy policy:** publish `docs/privacy-policy.md` at a public URL (for example with GitHub Pages) and link it from both listings.
- **Google Play data safety:** the app itself collects no data. Declare what the Google Mobile Ads SDK collects (device or other IDs, app interactions and diagnostics, used for advertising and analytics, shared with Google), and that users can ask for it to be deleted through Google.
- **App Store privacy details:** "Identifiers → Device ID" and "Usage Data → Advertising Data", used for third-party advertising, linked to tracking only when ATT permission is given.
- **Screenshots:** the images in `legacy/resources` show the 2013 app; take new ones from the current build.

## 5. Crash reporting (optional follow-up)

Errors currently go to `LogCrashReporter`, which only writes to the device log. To collect crashes remotely, create a Firebase project, run `flutterfire configure`, add a `CrashReporter` backed by `FirebaseCrashlytics`, and override `crashReporterProvider` with it in `lib/main.dart`, enabled only after the user's consent. Then update the privacy policy's "Crash information" section.
````

- [ ] **Step 2: CI**

Replace `.github/workflows/app.yml` with:
```yaml
name: app

on:
  pull_request:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.47.2
      - run: flutter pub get
      - run: dart format --output=none --set-exit-if-changed lib test
      - run: ./tool/codegen.sh
      - run: dart analyze --fatal-infos
      - run: flutter test

  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.47.2
      - run: ./tool/codegen.sh
      - run: flutter build apk --debug --flavor dev
```

- [ ] **Step 3: CLAUDE.md**

Replace `CLAUDE.md` with:
```markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project goal: Flutter rebuild

This repo is being migrated from a 2013 Android app ("Debt Destroyer") to a modern **Flutter app for iOS and Android, funded by ads, to be shipped to the app stores**. v1 recreates the original features with the known bugs fixed; it adds nothing new.

- **Design spec (source of truth):** `docs/superpowers/specs/2026-09-24-flutter-rebuild-design.md`. Read it before any Flutter work; if a decision here conflicts with it, the spec wins.
- **Implementation plans:** `docs/superpowers/plans/`.
- **Target architecture:** feature-first with clean layers (`lib/features/<feature>/{domain,data,presentation}`). State uses Riverpod with codegen, storage uses Drift (SQLite) plus shared_preferences for settings, navigation uses go_router, models use freezed, and charts use fl_chart. The payoff calculator lives in a pure-Dart package, `packages/payoff_engine/`, with no Flutter imports.
- **Money is never a float:** amounts are integer minor units (`Money`), APRs are integer basis points, and rounding is half-even, once per month.
- **Ads** go through the `AdsService` interface (a no-op version in tests and debug builds), behind UMP/ATT consent. Banners appear only on the Debts and Strategies screens.
- **TDD is mandatory:** write a failing test first, then the minimal code to pass it, then refactor. This applies to the engine, repositories, controllers and widgets.

### Migration status
- [x] Legacy code analysed, design spec approved
- [x] Full legacy Android project placed in `legacy/`
- [x] Plan 1: foundation and `payoff_engine` (`docs/superpowers/plans/2026-09-24-plan-1-foundation-payoff-engine.md`)
- [x] Plan 2: Flutter app shell, persistence (Drift, settings) and state (Riverpod)
- [x] Plan 3: screens (onboarding, debts, strategies, plan detail, settings) and CSV/XLSX export
- [x] Plan 4: ads and consent, crash reporting (local; Crashlytics set-up documented), Android flavors, icons, CI, release docs

Update this checklist as the phases complete.

## Commands

`payoff_engine` (run from `packages/payoff_engine/`):
- `dart pub get`, then `dart run build_runner build -d`. Run the build after a fresh checkout or after any freezed model change, because generated `*.freezed.dart` files are not committed.
- `dart test`: all tests. `dart test test/calculator_test.dart --plain-name "name"` runs one test.
- `dart analyze --fatal-infos` and `dart format lib test`. CI (`.github/workflows/payoff_engine.yml`) enforces both.
- Legacy reference figures: `java legacy/reference/LegacySolver.java` (from the repo root).

App (run from the repo root):
- `./tool/codegen.sh` generates code for `payoff_engine`, the app's translations (`flutter gen-l10n`) and then the app. Run it after a fresh checkout and after changing any freezed model, Riverpod provider or Drift table. Generated `*.g.dart`/`*.freezed.dart` files are not committed.
- `flutter test` runs all app tests. `flutter test test/path/to_test.dart --plain-name "name"` runs one test.
- `dart analyze --fatal-infos` and `dart format lib test`. CI (`.github/workflows/app.yml`) enforces both.
- `flutter run --flavor dev` runs the app on a connected device or simulator. Android needs a flavor (`dev` or `prod`); iOS has none yet, so omit it there.
- Ads: debug builds show none; `--dart-define=ADS_ENABLED=true` shows Google's test ads. Real AdMob ids, signing, store builds and the privacy policy are covered in `docs/release.md`.
- To change the Drift schema: bump `schemaVersion` in `lib/features/debts/data/app_database.dart` and write the migration. Then run `dart run drift_dev make-migrations` and commit `drift_schemas/` and the generated `test/drift/` tests.

Gotchas:
- Riverpod 3 pauses providers that have no listener, so a `StreamProvider` read without a listener never emits. In tests, call `container.listen(provider, (_, _) {})` before reading `.future`. To check that a write took effect, read the repository (`loadAll`), not the stream's latest value.
- `select`/`selectAsync` come from `flutter_riverpod`, not `riverpod_annotation`. `Override` is in `package:flutter_riverpod/misc.dart`.
- UI text lives in `lib/l10n/app_en.arb`, read through `context.l10n`. Money and percentages are formatted and parsed with `lib/core/money_format.dart`, using `formatLocaleProvider` (the device locale). Parsing is exact integer arithmetic; never convert money through `double` except for display.
- Widget tests use `pumpApp` (`test/helpers/pump_app.dart`): the whole app with an `InMemoryDebtRepository` and a synchronous `planCalculatorProvider`. Drift's streams and `compute` isolates don't run under the widget test clock, so never use the real ones in widget tests. After `tester.ensureVisible`, call `pumpAndSettle` before tapping.
- Errors found after Save are shown with `forceErrorText`. Clear a field's forced error in its `onChanged`, never at the start of Save: a stale forced error makes `validate()` fail silently.
- Ads and crash reporting go through `AdsService` (`lib/features/ads/`) and `CrashReporter` (`lib/core/crash_reporter.dart`). Widget tests that need ads override `adsServiceProvider` with `FakeAdsService`. Ads appear only on the Debts and Strategies screens, behind consent.
- Every amount is in minor units of the one app-wide currency (`AppSettings.currencyCode`). Change currency only through `SettingsController.setCurrency`, which rescales stored amounts when the number of decimal digits changes. The database records which currency its amounts are in (`DebtRepository.convertAmounts`, idempotent), and the controller reconciles it at startup, so an interrupted switch is repaired. Settings are saved as one JSON value under `SettingsKeys.settings`.

## Legacy Android app (reference only)

The original 2013 Android project (v1.1.3, package `com.dmt195.debtdestroyer`) lives in `legacy/`. It is a **read-only reference** for the original behaviour: don't modify it or try to build it (its Gradle 0.4 / SDK 17 build is long dead). When porting behaviour, check it against the calculator described below, and remember the bug fixes listed in spec §4.

- Java: `legacy/src/main/java/com/dmt195/debtdestroyer/`. Class paths below are relative to this directory.
- Resources: `legacy/src/main/res/`. Useful ones: `values/strings.xml` (UI copy), `xml/preferences.xml` (settings and their defaults, which the Flutter app uses), and `raw/intro1-3.html` (onboarding copy). The Resources screen (`raw/resources_main.html`) was an unfinished placeholder.
- Dependencies: the legacy Android SDK and support v4 library, AChartEngine, Apache POI HSSF and the old `com.google.ads` AdMob SDK (some jars are in `legacy/libs/`).
- `legacy/reference/LegacySolver.java` is a standalone port of the legacy calculator (bugs kept). `java legacy/reference/LegacySolver.java` prints the reference figures quoted in the `payoff_engine` tests.

### Legacy architecture

Package directories map to screens: `Debts/` (enter debts; launcher activity), `Solutions/` (list of repayment strategies), `Analysis/` (tabbed Facts/Graph/Next-actions view), `Details/` (per-solution graph and table/XLS export). Root-level files are shared dialogs and preferences.

#### Global static state
Activities share data through **static fields**, not Intents or a data layer:
- `DebtListAdapter.debtList` (static `ArrayList<DebtItem>`), accessed via `ManageDebtsActivity.DebtList`.
- `SolutionListAdapter.solutionList` (static `ArrayList<Solution>`). `AnalyseActivity.solList` and `ManageSolutionsActivity.solList` are separate adapter instances that **share the same static list**.
- User settings are cached as static fields on `ManageDebtsActivity` (`monthlyAmount`, `currencySym`, `consolidationAPR`, `revertAPR`, `ccTerm`, `ccTransferFee`, `loanActive`, `ccActive`, `settings`). These are re-read from default `SharedPreferences` in several `onResume()` methods, and each copy duplicates the preference keys and default values (`"monthly"`/250, `"loan_apr"`/4.0, `"cc_revert_apr"`/15.0, `"cc_term"`/15, `"cc_transfer_fee"`/4.0, …). These Java fallbacks disagree with `preferences.xml` (300, 5.0, 15.0, 12, 4.0), and `setDefaultValues` is never called, so the Java values applied until Settings was first opened. The Flutter app uses the XML values.

Consumers read solutions by index (e.g. `solList.getItem(0)` in the Analysis/Details graphs, or the `"solution"` Intent extra position in `DetailsActivity`). So the order solutions are added in matters.

#### Persistence
The debt list is serialised to JSON (`DebtListAdapter.getJSONArray()` / `convertJSONArrayToElements()`) and written to the private file `"default"` in `ManageDebtsActivity.onPause()`. It is read back when the list is empty in `onCreate`/`onResume`. Solutions are never persisted; they are recomputed.

#### Solver (`DebtListAdapter.solve(int solutionType, float monthly)`)
This month-by-month simulation is the core of the app. It returns a `Solution` with per-month balance and payment arrays (one column per active debt, in `paymentOrder`) plus the total cost, total interest, and months to clear.
- Solution types: 0 highest APR first, 1 lowest APR first, 2 lowest balance first, 3 highest balance first, 4 consolidation loan, 5 0% balance-transfer card. Named constants live in `AnalyseActivity`; `ManageSolutionsActivity.redoList()` uses raw ints.
- Each month: apply interest (`APR/1200`), pay every debt's minimum (`max(absolute, percent × balance)`), then pour the rest into debts in list order, but only where `canOverPay` is true.
- `solve()` **mutates the shared `debtList`**. It sorts the list in place. For types 4 and 5 it deactivates all debts (`activeInCalc = false`), appends a synthetic debt, and removes it at the end. For type 5 it also switches the synthetic card's APR to `revertAPR` after `ccTerm` months. Don't run `solve()` concurrently or keep indices into `debtList` across calls. `ManageDebtsActivity` guards its `AsyncTask` path with the `clear2continue` flag.
- If `monthly` is less than the total minimum payment, it returns an empty `Solution` (0 months).
- The APR comparators cast to `int` before multiplying (`(int)(a - b) * 100`), so APRs less than 1% apart compare as equal.

#### Flow
`ManageDebtsActivity` (add or edit debts with `FragmentAddDebtDialog`) → menu "see solutions" → `solveAllDirect()` fills `AnalyseActivity.solList` (in order: highest-first, lowest-first, highest-first at 110% of the monthly amount, consolidation, 0% card) → `AnalyseActivity`. If the first month's payable amount is more than the monthly budget, the app shows `FragmentMinPayments` instead. `TableViewActivity` exports a solution to `.xls` in the public Downloads directory and shares it.
```

- [ ] **Step 4: Final verification and commit**

Run: `dart analyze --fatal-infos && flutter test && (cd packages/payoff_engine && dart test)`
Expected: `No issues found!`, `+152: All tests passed!`, `+68: All tests passed!`.
```bash
git add docs .github CLAUDE.md
git commit -m "docs: privacy policy, release guide; ci: pin Flutter and build Android"
```
