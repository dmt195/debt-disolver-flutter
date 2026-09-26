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
6. In **Blocking controls → Sensitive categories**, block *Gambling & betting* and anything covering payday loans, high-interest lending or get-out-of-debt schemes, for both apps. These ads appear next to people's own debts and would read as predatory. Review the blocked advertiser categories again after launch.

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

Android has two flavors: `dev` (`dev.countersunk.debt_destroyer.dev`, "Debt Destroyer Dev", always Google's test AdMob app id) and `prod`. iOS has no flavors yet: both builds use `dev.countersunk.debtDestroyer`, and dev/prod differ only in the `--dart-define`s. Separate iOS schemes can be added later in Xcode (see https://docs.flutter.dev/deployment/flavors-ios).

## 4. Store listings

- **Privacy policy and terms:** hosted on countersunk.dev (`countersunkweb` repo, `apps/debt-destroyer/`): https://countersunk.dev/apps/debt-destroyer/privacy-policy/ and https://countersunk.dev/apps/debt-destroyer/tos/. Link the privacy policy from both listings. The app links both from setup and Settings (`LegalLinks`).
- **Google Play data safety:**
  - **Ads (always):** declare what the Google Mobile Ads SDK collects, following Google's current guidance (https://developers.google.com/admob/android/privacy/play-data-disclosure): device or other IDs, approximate location (from IP address), app interactions, and diagnostics and performance data, used for advertising and analytics and shared with Google. Answer **Yes** to the Advertising ID declaration: the SDK adds the `AD_ID` permission.
  - **Optional diagnostics (only with the user's consent):** Firebase Analytics collects app interactions and device or other IDs (the app instance ID), and Firebase Crashlytics collects crash logs and diagnostics. Mark them optional (the user can choose), used for analytics and app functionality, not shared except with Google as processor, and never containing financial information.
- **App Store privacy details:**
  - **Ads:** follow Google's guidance (https://developers.google.com/admob/ios/privacy/data-disclosure): Identifiers (Device ID), Location (Coarse Location), Usage Data (Product Interaction, Advertising Data) and Diagnostics (Crash Data, Performance Data), used for third-party advertising and analytics. Device ID is used for tracking only when ATT permission is given.
  - **Optional diagnostics:** Usage Data (Product Interaction) and Identifiers (User ID: the app instance ID) for analytics, and Diagnostics (Crash Data) for app functionality. They're not linked to identity, not used for tracking, and collected only when the user opts in.
- **Screenshots:** the images in `legacy/resources` show the 2013 app; take new ones from the current build.

## 5. Notifications

- **Local only:** reminders are scheduled on the device with `flutter_local_notifications`, and nothing is sent to a server.
- **No exact alarms:** the app asks for neither `SCHEDULE_EXACT_ALARM` nor `USE_EXACT_ALARM`, so the Play Console's exact-alarm declaration doesn't apply. It does use `RECEIVE_BOOT_COMPLETED`, to reschedule after a restart.
- **Permission** is asked only when someone switches a reminder on, in setup or Settings.
- **Testing on a device:**
  1. Set the pay day to tomorrow in Settings › Reminders, then check the reminder arrives at about 09:00 and that tapping it opens Check in.
  2. Restart the phone and confirm it's still scheduled.
  3. Deny permission once and check the switch turns itself off.

## 6. Firebase (analytics and crash reports)

The app is built for Firebase Analytics and Crashlytics but runs without them. Until the config files exist, `startDiagnostics` (`lib/core/firebase_diagnostics.dart`) falls back to `NoDiagnostics`, and nothing is sent. Nothing is ever sent unless the user turns on **Help improve Debt Destroyer** (in setup or Settings → Privacy). Collection is off in both native manifests until the app applies that choice.

To set it up:

1. **Create the project:** in the Firebase console, create a project and enable Analytics and Crashlytics. In the Google Analytics property:
   - set data retention to 14 months or less;
   - turn **Google signals** off;
   - accept the Google Analytics and Firebase data processing terms (Admin → Account settings);
   - turn off the data-sharing options for Google products and services, so Google acts as our processor, as the privacy policy says.

   Don't link the Firebase project to AdMob. The app also turns off the advertising ID, ad personalisation and automatic screen reporting, in both manifests, and sets Analytics consent to analytics storage only.
2. **Configure the apps:** `dart pub global activate flutterfire_cli`, then `flutterfire configure --project=<project-id>`. Then download `google-services.json` from the console's project settings, so that it includes both Android apps. A file generated for one package makes the other flavor's build fail with "No matching client found". Register:
   - Android `dev.countersunk.debt_destroyer` and `dev.countersunk.debt_destroyer.dev`;
   - iOS `dev.countersunk.debtDestroyer`.

   This writes `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`. The app starts Firebase from these files, so the generated `firebase_options.dart` isn't needed and can be deleted.
3. **Check the iOS file is in the target:** make sure `GoogleService-Info.plist` is added to the Runner target in Xcode, with "Copy items if needed" ticked.
4. **Nothing else to change:** the Google Services and Crashlytics Gradle plugins apply automatically once `google-services.json` exists (`android/app/build.gradle.kts`).
5. **Test in debug:** `flutter run --flavor dev --dart-define=DIAGNOSTICS_ENABLED=true` (debug builds send nothing without it). Enable Firebase DebugView (`adb shell setprop debug.firebase.analytics.app dev.countersunk.debt_destroyer.dev`). Check that:
   - nothing arrives with the switch off;
   - screen views and the events in `lib/app/diagnostic_events.dart` arrive with it on, and none carry an amount or a name.
6. **Keep the config out of the repo:** whether to commit the two config files is your call. They aren't secret, but they're project-specific. If you keep them out, add them to `.gitignore` and to your release checklist.
