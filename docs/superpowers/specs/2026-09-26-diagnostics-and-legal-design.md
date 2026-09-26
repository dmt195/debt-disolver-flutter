# Diagnostics, Consent and Legal Documents: Design

Builds on the earlier specs: v1 (`2026-09-24-flutter-rebuild-design.md`), v2, v3, and rates and loans. Where this spec is silent, they apply.

## 1. Intent

- **Diagnostics:** add Firebase Analytics and Firebase Crashlytics, so Countersunk can see how the app is used and fix crashes.
- **Consent first:** nothing is collected unless the user opts in, which they can do during setup or later in Settings.
- **Legal documents:** publish a Terms of use and a Privacy policy on countersunk.dev, in the style of the other Countersunk apps (All Wrapped Up), and link them from setup and Settings.

**What the user decided** (brainstorm, 26 Sep 2026):
- **One combined opt-in, off by default:** "Help improve Debt Destroyer", covering anonymous usage statistics and crash reports.
- **Firebase is stubbed for now:** no Firebase project exists yet. The app builds and runs without the config files, and `docs/release.md` says how to add them later.
- **Documents on countersunk.dev:** in `countersunkweb` at `apps/debt-destroyer/`, like All Wrapped Up.
- **Accepting the terms:** a line on the setup page, "By continuing you agree to the Terms of use and have read the Privacy policy", with no tick box.

**Out of scope**
- Creating the Firebase project, and adding its config files. The user does these later.
- A landing page for the app on countersunk.dev.
- Any change to ad consent (Google's consent form, Apple's App Tracking Transparency).
- Analytics of amounts, names, rates, dates or any free text.
- Remote Config, A/B tests, Performance Monitoring, push messaging.

**Success criteria**
- With the switch off (the default), no Firebase collection happens. That includes before the app has read the setting.
- With it on, screen views, the fixed event list and crash reports go to Firebase, once the config files exist.
- The app builds and passes all tests without the Firebase config files.
- The setup page and Settings link the Terms and the Privacy policy.
- The documents are published in `countersunkweb` and read like All Wrapped Up's.

## 2. Consent and data flow

### 2.1 The setting

- **`AppSettings.shareDiagnostics`:** a bool, default false, stored in the settings JSON under `shareDiagnostics`.
- **`SettingsController.setShareDiagnostics(bool)`:** saves the choice. The diagnostics layer (§2.2) listens to it and applies it at once.

### 2.2 Diagnostics layer

- **`DiagnosticsService`** (in `lib/core/diagnostics.dart`) has four jobs:
  - `setCollectionEnabled(bool)`;
  - `recordError(error, stack, {fatal, reason})`;
  - `logScreen(String name)`;
  - `logEvent(DiagnosticEvent event)`.
- **Two implementations:**
  - **`NoDiagnostics`** does nothing. It's used in tests, in debug builds, and whenever Firebase couldn't start.
  - **`FirebaseDiagnostics`** wraps `FirebaseAnalytics` and `FirebaseCrashlytics`.
- **`diagnosticsProvider`:** kept alive, and overridden in `main.dart` with `FirebaseDiagnostics` only when `Firebase.initializeApp()` succeeds. It fails when the native config files are missing, which is caught.
- **Applying the setting:** `DiagnosticsSettingSync`, a kept-alive provider watched by the app, calls `setCollectionEnabled(settings.shareDiagnostics)` on start and whenever the setting changes.
- **Crash reports:** `CrashReporter` stays. `crashReporterProvider` becomes a `ConsentingCrashReporter`, which:
  - always logs locally, as `LogCrashReporter` does now;
  - also forwards to `diagnosticsProvider.recordError`.

  (Corrected after review: Crashlytics doesn't drop reports while collection is off; it stores them on the device and sends them once it's on. So `GatedDiagnostics` stops them reaching Firebase at all while off, sends only an error's type (never its message) and its stack trace, and opting in, off to on, first deletes any stored reports with `deleteUnsentReports`.)
- **Off before the app has read the setting**, set in the native config:
  - iOS `Info.plist`: `FIREBASE_ANALYTICS_COLLECTION_ENABLED` false, and `FirebaseCrashlyticsCollectionEnabled` false.
  - Android `AndroidManifest.xml`: meta-data `firebase_analytics_collection_enabled` false, and `firebase_crashlytics_collection_enabled` false.
- **The Android build without config:** the `com.google.gms.google-services` and `com.google.firebase.crashlytics` Gradle plugins are applied only when `android/app/google-services.json` exists, so the build works without it.

### 2.3 What is sent

- **Screen views:** the route's name, such as `home`, `debts`, `plans`, `plan_detail`, `check_in`, `loan_calculator` or `settings`. Never IDs, and never query strings.
- **Events:** `DiagnosticEvent` is a closed set, and its parameters can only be enum names.

  | Event | Parameter |
  |---|---|
  | `debt_added` | `type` (a `DebtType` name) |
  | `plan_followed` | `strategy` (a `StrategyId` name) |
  | `check_in_saved` | none |
  | `debt_cleared` | none |
  | `loan_helper_used` | `figure` (a `LoanFigure` name) |
  | `loan_calculator_used` | `unknown` (a `LoanUnknown` name) |
  | `reminders_turned_on` | none |
  | `schedule_exported` | `format` (`csv` or `xlsx`) |

- **Never sent:** names, amounts, balances, rates, dates or any other free text. A unit test runs every `DiagnosticEvent` and checks that each parameter value comes from its enum's names.
- **Firebase adds its own data:** an app instance ID, device model, OS and app version, and (for Crashlytics) stack traces.

## 3. Onboarding and Settings

- **Setup page** (after the reminders card):
  - An `OutlinedCard` holds a `SwitchListTile`: "Help improve Debt Destroyer". The subtitle reads "Share anonymous usage statistics and crash reports. Never your debts, amounts or names." It's off by default, and saved with the other setup choices.
  - Above the two buttons: "By continuing you agree to the Terms of use and have read the Privacy policy." "Terms of use" and "Privacy policy" are links.
- **Settings:** a Privacy section, after Reminders.
  - The same switch, which applies immediately, as Reminders does.
  - Under it, once Firebase is configured and the switch is on: "Your app ID: …", the Analytics app instance ID. It's selectable text, for deletion requests.
  - The existing "Privacy choices" for ads, shown only when Google's consent form applies.
  - Two links: "Privacy policy" and "Terms of use".
  - The app's version: "Version 0.1.0 (2001)", from `package_info_plus`.
- **Links:**
  - `LegalLinks.privacyPolicy` is `https://countersunk.dev/apps/debt-destroyer/privacy-policy/`, and `LegalLinks.terms` is `…/tos/`.
  - They open through `LinkOpener` (`url_launcher`, external application), which is a provider so tests can record the URLs.
  - If a link fails to open, a SnackBar shows the address instead.

## 4. The documents

Both are HTML in `~/development/countersunkweb/apps/debt-destroyer/`, as `privacy-policy.html` and `tos.html`, on a new branch there. They copy the markup, the inline styles and the section structure of `apps/all-wrapped-up/privacy-policy.html` and `tos.html`: the title and effective date, "At a Glance" cards, "The Details", and "Contact Us" with info@countersunk.dev.

**Privacy policy**
- **At a glance:**
  - "Your debts stay on your device";
  - "Nothing shared unless you choose";
  - "Ads, with your consent";
  - "You're in control".
- **The details:**
  - **Who we are:** Countersunk Development Ltd (company number 15961178) is the data controller.
  - **What stays on the device:** debts, balances, rates, check-ins, settings, and reminder schedules (local notifications). The device's own backups may include them.
  - **Optional diagnostics** (§2.3), sent only with the switch on:
    - what Analytics and Crashlytics collect;
    - that the lawful basis is consent, and switching it off stops collection;
    - retention: analytics data up to 14 months, crash data about 90 days (Google's defaults).
  - **Advertising:** AdMob, Google's partner-sites policy, the consent form in the EEA, UK and Switzerland, App Tracking Transparency on iOS, and that non-personalised ads may still show.
  - **Exports:** CSV or Excel files go only where the user shares them.
  - **Your rights (UK GDPR):**
    - access, erasure, and withdrawing consent;
    - making a request to info@countersunk.dev with the app ID shown in Settings;
    - complaining to the ICO.
  - **Children:** the app isn't directed at children under 13.
  - **Changes:** a new version goes at the same address, with a new effective date.

**Terms of use**
- **At a glance:**
  - "Free, supported by ads";
  - "Estimates, not financial advice";
  - "Your data, your device";
  - "Fair use".
- **The details:**
  - a personal, non-commercial licence to use the app;
  - **not advice:** plans are projections from the figures entered, not financial, legal or tax advice, and real interest, fees and dates may differ, so check with your lender;
  - accuracy, and limitation of liability to the extent UK law allows (nothing limits liability that can't lawfully be limited);
  - ads and third-party services (Google);
  - availability, changes, and ending the terms;
  - governing law and courts: England and Wales;
  - contact.

**In this repo**
- `docs/privacy-policy.md` becomes a short pointer to the hosted pages.
- `docs/release.md` gets:
  - **Firebase set-up:**
    - create the project;
    - run `flutterfire configure` for `dev.countersunk.debt_destroyer`, `.dev` and `dev.countersunk.debtDestroyer`;
    - where `google-services.json` and `GoogleService-Info.plist` go;
    - the plugins apply automatically once the file exists;
    - check that nothing is collected with the switch off.
  - **Updated store answers:** Play data safety and App Store privacy details, now covering optional analytics and crash data, collected only with consent.

## 5. Testing

- **The setting:** its default, saving, and reading back.
- **`DiagnosticsSettingSync`:** calls `setCollectionEnabled` with the saved value at start and on each change (with a fake `DiagnosticsService`).
- **`ConsentingCrashReporter`:** forwards to the diagnostics service, and still logs locally.
- **The event catalogue:** every parameter value is an enum name.
- **Screen views:** they're logged by route name, and never include IDs.
- **Setup:** the switch is off by default and saved with setup; the terms line's links open the right URLs (with a fake `LinkOpener`).
- **Settings:** the switch applies at once; the links open; the version shows.
- **Start-up without Firebase config:** `main`'s set-up falls back to `NoDiagnostics` when initialisation throws (tested through the extracted function).
- **Review focus:**
  - Nothing is collected before the setting is read (native flags).
  - Turning the switch off mid-session stops collection.
  - No PII in events.
  - The build and tests pass without config files.
  - Large text on the new setup card and the Settings section.

## 6. Delivery

Two plans:
1. **App (Plan 14):** §2 and §3, plus the `docs/` changes in this repo.
2. **Documents:** §4, in `countersunkweb`, on its own branch. It's small, so it can be done within Plan 14's last task or as its own short plan.
