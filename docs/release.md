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
