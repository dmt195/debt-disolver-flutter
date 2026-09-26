import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Nothing is collected before the app applies the user's choice, and
/// Analytics never uses advertising IDs or personalisation signals
/// (diagnostics spec §2.2, and the privacy policy).
void main() {
  test('Android keeps collection and ad signals off', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    for (final key in [
      'firebase_analytics_collection_enabled',
      'firebase_crashlytics_collection_enabled',
      'google_analytics_adid_collection_enabled',
      'google_analytics_default_allow_ad_personalization_signals',
      'google_analytics_automatic_screen_reporting_enabled',
    ]) {
      expect(
        RegExp('android:name="$key"\\s+android:value="false"')
            .hasMatch(manifest),
        isTrue,
        reason: key,
      );
    }
  });

  test('iOS keeps collection and ad signals off', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    for (final key in [
      'FIREBASE_ANALYTICS_COLLECTION_ENABLED',
      'FirebaseCrashlyticsCollectionEnabled',
      'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS',
      'FirebaseAutomaticScreenReportingEnabled',
      'GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED',
    ]) {
      expect(
        RegExp('<key>$key</key>\\s*<false/>').hasMatch(plist),
        isTrue,
        reason: key,
      );
    }
  });
}
