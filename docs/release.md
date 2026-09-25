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

Android has two flavors: `dev` (`com.dmt195.debt_destroyer.dev`, "Debt Destroyer Dev", always Google's test AdMob app id) and `prod`. iOS has no flavors yet: both builds use `com.dmt195.debt_destroyer`, and dev/prod differ only in the `--dart-define`s. Separate iOS schemes can be added later in Xcode (see https://docs.flutter.dev/deployment/flavors-ios).

## 4. Store listings

- **Privacy policy:** publish `docs/privacy-policy.md` at a public URL (for example with GitHub Pages) and link it from both listings.
- **Google Play data safety:** the app itself collects no data. Declare what the Google Mobile Ads SDK collects, following Google's current guidance (https://developers.google.com/admob/android/privacy/play-data-disclosure): device or other IDs, approximate location (from IP address), app interactions, diagnostics and performance data, used for advertising and analytics and shared with Google. In the Play Console, answer **Yes** to the Advertising ID declaration: the SDK adds the `AD_ID` permission.
- **App Store privacy details:** follow Google's guidance (https://developers.google.com/admob/ios/privacy/data-disclosure): Identifiers (Device ID), Location (Coarse Location), Usage Data (Product Interaction, Advertising Data) and Diagnostics (Crash Data, Performance Data), used for third-party advertising and analytics; Device ID is used for tracking only when ATT permission is given.
- **Screenshots:** the images in `legacy/resources` show the 2013 app; take new ones from the current build.

## 5. Notifications

- **Local only:** reminders are scheduled on the device with `flutter_local_notifications`, and nothing is sent to a server.
- **No exact alarms:** the app asks for neither `SCHEDULE_EXACT_ALARM` nor `USE_EXACT_ALARM`, so the Play Console's exact-alarm declaration doesn't apply. It does use `RECEIVE_BOOT_COMPLETED`, to reschedule after a restart.
- **Permission** is asked only when someone switches a reminder on, in setup or Settings.
- **Testing on a device:**
  1. Set the pay day to tomorrow in Settings › Reminders, then check the reminder arrives at about 09:00 and that tapping it opens Check in.
  2. Restart the phone and confirm it's still scheduled.
  3. Deny permission once and check the switch turns itself off.

## 6. Crash reporting (optional follow-up)

Errors currently go to `LogCrashReporter`, which only writes to the device log. To collect crashes remotely, create a Firebase project, run `flutterfire configure`, add a `CrashReporter` backed by `FirebaseCrashlytics`, and override `crashReporterProvider` with it in `lib/main.dart`, enabled only after the user's consent. Then update the privacy policy's "Crash information" section.
