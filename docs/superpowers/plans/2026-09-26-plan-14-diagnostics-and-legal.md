# Plan 14: Diagnostics, Consent and Legal Documents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Add Firebase Analytics and Crashlytics behind one opt-in, "Help improve Debt Destroyer", which is off by default. It's offered during setup and in Settings → Privacy.
- Publish a Privacy policy and Terms of use on countersunk.dev, in All Wrapped Up's style.

**Architecture:**
- **One interface:** everything goes through `DiagnosticsService` (`lib/core/diagnostics.dart`).
  - `NoDiagnostics` is the default. It's used in tests, in debug builds, and whenever Firebase can't start (as now, before the project exists).
  - `FirebaseDiagnostics` is a thin wrapper, chosen in `main.dart` only when `Firebase.initializeApp()` succeeds.
- **The switch:** `DiagnosticsSettingSync` applies the setting to Firebase's collection switches.
- **Crashes:** `ConsentingCrashReporter` logs locally and forwards errors.
- **Events:** a closed `DiagnosticEvent` catalogue carries only enum names.
- **Screen views:** a router listener records route templates.
- **Off by default:** the native manifests turn collection off until the app says otherwise.
- **Android build:** the Gradle plugins apply only when `google-services.json` exists.

**Tech Stack:**
- Flutter and Riverpod 3.
- New dependencies: `firebase_core`, `firebase_analytics`, `firebase_crashlytics` (the same major versions as All Wrapped Up: `^4.7.0`, `^12.3.0`, `^5.2.0`), plus `url_launcher` and `package_info_plus`.
- Static HTML in `~/development/countersunkweb`.

**Spec:** `docs/superpowers/specs/2026-09-26-diagnostics-and-legal-design.md` (all of it).

## Global Constraints

- **Consent:** nothing is collected unless `AppSettings.shareDiagnostics` is true. Native flags keep collection off before the app has read it.
- **Event data:** event parameters are enum names only. Never names, amounts, balances, rates, dates or free text.
- **No config files:** the app, its tests and its Android and iOS builds work without the Firebase config files. None are committed.
- **Tests:** they never touch Firebase. `NoDiagnostics` is the default, and `FakeDiagnostics` records calls.
- **Settings shape:** settings stay one JSON object under `SettingsKeys.settings`, with a new `shareDiagnostics` key (default false).
- **Text:** UI text lives in `app_en.arb`.
- **Process:** TDD; `dart analyze --fatal-infos` and `dart format lib test` clean; commits end with the two trailer lines.
- **countersunkweb:** work on a new branch `debt-destroyer-legal` there. Never on its main, and never push without asking.

## Review Focus

1. **Before the setting is known:**
   - the native flags are off (both manifests);
   - `FirebaseDiagnostics` starts with collection disabled;
   - `DiagnosticsSettingSync` applies the saved value on start.
2. **Switching off mid-session:** `setCollectionEnabled(false)` is called at once, and no event is logged afterwards (the fake records it).
3. **No personal data:** every event's parameter values are enum names, and screen names are templates without IDs.
4. **No config:** `startDiagnostics` falls back to `NoDiagnostics` when initialisation throws. The APK builds, and the app launches on the iOS simulator without `GoogleService-Info.plist`.
5. **Large text:** the new setup card, the terms line and the Settings Privacy section fit at 360 wide and 2×.

---

### Task 1: The `shareDiagnostics` setting

**Files:**
- Modify: `lib/features/settings/domain/app_settings.dart`, adding `@Default(false) bool shareDiagnostics`.
- Modify: `lib/features/settings/data/prefs_settings_repository.dart`: add the key `shareDiagnostics` and read and write it.
- Modify: `lib/features/settings/presentation/settings_controller.dart`: add `Future<void> setShareDiagnostics(bool on)`, following `setCheckInNudgeMonths`'s `_serialised` / `_save` pattern.
- Tests: `test/features/settings/prefs_settings_repository_test.dart` and `settings_controller_test.dart`.

**Interfaces:** Produces `AppSettings.shareDiagnostics`, `SettingsKeys.shareDiagnostics` and `SettingsController.setShareDiagnostics(bool on)`. The lint wants no positional bools, so call it as `setShareDiagnostics(on: true)`, using a named `required bool on`.

- [ ] **Step 1: Write failing tests:**
  - the default is false;
  - it saves true, then reads it back;
  - an unreadable stored value reads as false;
  - the controller's `setShareDiagnostics(on: true)` saves it.
- [ ] **Step 2: Watch them fail.**
  - Run: `flutter test test/features/settings`
- [ ] **Step 3: Implement.** Run `./tool/codegen.sh` for freezed.
- [ ] **Step 4: Watch them pass.** Commit `feat(settings): a shareDiagnostics setting, off by default`.

### Task 2: The diagnostics core

**Files:**
- Create: `lib/core/diagnostics.dart`
- Modify: `lib/core/crash_reporter.dart` (`crashReporterProvider` returns a `ConsentingCrashReporter`)
- Modify: `lib/app/app.dart` (watch `diagnosticsSettingSyncProvider`)
- Create: `test/helpers/fake_diagnostics.dart`
- Modify: `test/helpers/test_container.dart` and `test/helpers/pump_app.dart` (optional `diagnostics` override)
- Test: `test/core/diagnostics_test.dart`

**Interfaces (produces):**

```dart
/// One anonymous usage event (spec §2.3): a fixed name and parameters that
/// are only ever enum names.
final class DiagnosticEvent {
  const DiagnosticEvent._(this.name, [this.parameters = const {}]);
  DiagnosticEvent.debtAdded(DebtType type) : this._('debt_added', {'type': type.name});
  DiagnosticEvent.planFollowed(StrategyId s) : this._('plan_followed', {'strategy': s.name});
  static const checkInSaved = DiagnosticEvent._('check_in_saved');
  static const debtCleared = DiagnosticEvent._('debt_cleared');
  DiagnosticEvent.loanHelperUsed(LoanFigure f) : this._('loan_helper_used', {'figure': f.name});
  DiagnosticEvent.loanCalculatorUsed(LoanUnknown u) : this._('loan_calculator_used', {'unknown': u.name});
  static const remindersTurnedOn = DiagnosticEvent._('reminders_turned_on');
  DiagnosticEvent.scheduleExported(ExportFormat f) : this._('schedule_exported', {'format': f.name});
  final String name;
  final Map<String, String> parameters;
  static const names = {'debt_added','plan_followed','check_in_saved','debt_cleared','loan_helper_used','loan_calculator_used','reminders_turned_on','schedule_exported'};
}

abstract interface class DiagnosticsService {
  Future<void> setCollectionEnabled(bool enabled);
  void recordError(Object error, StackTrace stack, {bool fatal = false, String? reason});
  void logScreen(String name);
  void logEvent(DiagnosticEvent event);
  /// The analytics app instance ID (for deletion requests); null when
  /// there's no analytics.
  Future<String?> appInstanceId();
}

class NoDiagnostics implements DiagnosticsService { /* every method does nothing; appInstanceId → null */ }

@Riverpod(keepAlive: true)
DiagnosticsService diagnostics(Ref ref) => NoDiagnostics();

/// Applies the saved choice to the service at start and on each change.
@Riverpod(keepAlive: true)
void diagnosticsSettingSync(Ref ref) { /* listen settingsControllerProvider.select(shareDiagnostics), fireImmediately → setCollectionEnabled */ }

class ConsentingCrashReporter implements CrashReporter {
  ConsentingCrashReporter(this._local, this._diagnostics);
  // recordError → _local.recordError(...) then _diagnostics.recordError(...)
}
```

- If importing `ExportFormat` or the loan enums into `core` causes a layering complaint, move `DiagnosticEvent` to `lib/app/diagnostic_events.dart`. Say so in a Ruling. `core` must not import features. Put `DiagnosticsService`, `NoDiagnostics` and the providers in `core`, and the event catalogue in `lib/app/diagnostic_events.dart`, with `logEvent` taking any `DiagnosticEventLike { String get name; Map<String,String> get parameters; }` defined in core.
- `FakeDiagnostics` (test helper) records `enabled` (a list of each call), `events` (a list), `screens` (a list) and `errors` (a list). It returns `appId` from `appInstanceId()`.

- [ ] **Step 1: Write failing tests:**
  - `DiagnosticsSettingSync` calls `setCollectionEnabled(false)` on start with default settings, then `true` after `setShareDiagnostics(on: true)`, then `false` after turning it off;
  - `ConsentingCrashReporter` forwards to both;
  - the catalogue:
    - every constructor, across every enum value, gives parameter values in that enum's `.name`s;
    - every event name is in `DiagnosticEvent.names`;
    - `names` has exactly the 8 events of spec §2.3.
- [ ] **Step 2: Watch them fail.**
- [ ] **Step 3: Implement.** Add `diagnostics` to `testOverrides` and to `pumpApp`'s parameters (default `NoDiagnostics()`); tests pass a `FakeDiagnostics` when they need to look. In `DebtDestroyerApp.build`, add `..watch(diagnosticsSettingSyncProvider)`.
- [ ] **Step 4: Watch them pass, then run the full suite.** Commit `feat: diagnostics behind the user's choice — events, crash forwarding, the setting applied`.

### Task 3: Screen views

**Files:**
- Create: `lib/app/screen_names.dart` (`String screenNameFor(String? routeTemplate)` and `diagnosticsScreenTrackerProvider`)
- Modify: `lib/app/app.dart` (watch the tracker)
- Test: `test/app/screen_names_test.dart`

**Behaviour:**
- **Templates to names:**

  | Route template | Screen name |
  |---|---|
  | `/` | `home` |
  | `/debts` | `debts` |
  | `/debts/new` | `debt_new` |
  | `/debts/:debtId` | `debt_edit` |
  | `/plans` | `plans` |
  | `/plans/scenarios` | `scenarios` |
  | `/plans/scenarios/:scenarioId` | `scenario_edit` |
  | `/plans/loan-calculator` | `loan_calculator` |
  | `/plans/:strategyId` | `plan_detail` |
  | `/settings` | `settings` |
  | `/onboarding` | `onboarding` |
  | `/check-in` | `check_in` |
  | `/check-in/result` | `check_in_result` |
  | `/cleared/:debtId` | `celebration` |
  | `/debt-free` | `debt_free` |
  | anything else | `other` |

- **The tracker:**
  - It adds a listener to `routerProvider`'s `routerDelegate`.
  - On each change, it reads `router.routerDelegate.currentConfiguration.fullPath` (the template), maps it, and calls `logScreen` when the name differs from the last one logged.
  - It removes the listener on dispose.

- [ ] **Step 1: Write failing tests:**
  - every row of the table;
  - a widget test: `pumpApp` with a `FakeDiagnostics`, go to `Routes.plan(StrategyId.avalanche)` → `screens` ends with `plan_detail`, never a strategy name or ID;
  - go to `Routes.editDebt('abc')` → `debt_edit`.
- [ ] **Step 2: Watch them fail.** **Step 3: Implement.** **Step 4: Watch them pass.** Commit `feat: screen views by route, never by id`.

### Task 4: The eight events

**Files:** modify the call sites, and test each in its existing feature test file with a `FakeDiagnostics`.

| Event | Where it's logged |
|---|---|
| `debtAdded(type)` | `DebtActions.add` (`lib/features/debts/presentation/debts_providers.dart:61`), on `DebtSaved` |
| `planFollowed(id)` | `ProgressController.follow` |
| `checkInSaved` | `ProgressController.saveCheckIn`, once saved |
| `debtCleared` | `ProgressController.saveCheckIn`, once for each cleared debt |
| `loanHelperUsed(figure)` | the debt form's `_workItOut`, on `LoanFilled` |
| `loanCalculatorUsed(unknown)` | `LoanCalculatorScreen`, the first time each unknown is solved in a visit (a `Set<LoanUnknown>` in the state), so there's no event per keystroke |
| `remindersTurnedOn` | `SettingsController.setPayDayReminder`, when `on` and it was off |
| `scheduleExported(format)` | where the plan detail screen calls `planExporter.export` (after it succeeds) |

- Read the service with `ref.read(diagnosticsProvider)` at the point of the event.

- [ ] **Step 1: Write failing tests**, one per row. Each asserts the recorded event's `name` and `parameters`:
  - add a card debt → `debt_added {type: creditCard}`;
  - a check-in clearing two debts → one `check_in_saved`, two `debt_cleared`;
  - the calculator solved three times for Payment → one `loan_calculator_used {unknown: payment}`.
- [ ] **Step 2: Watch them fail.** **Step 3: Implement.** **Step 4: Watch them pass, then run the full suite.** Commit `feat: log the eight usage events`.

### Task 5: Firebase, stubbed until configured

**Files:**
- `pubspec.yaml`: add the Firebase dependencies (`flutter pub add firebase_core firebase_analytics firebase_crashlytics`, checking the majors match the Tech Stack).
- Create: `lib/core/firebase_diagnostics.dart` (`FirebaseDiagnostics` and `Future<DiagnosticsService> startDiagnostics({Future<void> Function()? initialize, bool enabled = …})`)
- Modify: `lib/main.dart`
  - `final diagnostics = await startDiagnostics();`
  - `ProviderContainer(overrides: [diagnosticsProvider.overrideWithValue(diagnostics)])`
  - `installErrorHandlers` still reads `crashReporterProvider`, now consent-aware.
- Modify: `ios/Runner/Info.plist`: add `FIREBASE_ANALYTICS_COLLECTION_ENABLED` = false and `FirebaseCrashlyticsCollectionEnabled` = false.
- Modify: `android/app/src/main/AndroidManifest.xml`: add `<meta-data android:name="firebase_analytics_collection_enabled" android:value="false"/>` and `<meta-data android:name="firebase_crashlytics_collection_enabled" android:value="false"/>` inside `<application>`.
- Modify: `android/settings.gradle.kts` (declare the plugins with `apply false`) and `android/app/build.gradle.kts`, applying them only when `file("google-services.json").exists()`:

```kotlin
// Firebase: only once flutterfire configure has added google-services.json
// (docs/release.md). Without it the app builds and runs with diagnostics off.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
}
```

  Use the plugin versions FlutterFire currently documents; `flutterfire configure` would add the same ones.
- Test: `test/core/firebase_diagnostics_test.dart` (only `startDiagnostics`'s choice).

**Behaviour of `startDiagnostics`:**
- It returns `NoDiagnostics` if `enabled` is false. The default comes from `const bool.fromEnvironment('DIAGNOSTICS_ENABLED', defaultValue: kReleaseMode)`: off in debug unless `--dart-define=DIAGNOSTICS_ENABLED=true`.
- It also returns `NoDiagnostics` if `initialize` throws. The default `initialize` is `Firebase.initializeApp` with no options, which reads the native config and throws when it's missing.
- Otherwise it returns a `FirebaseDiagnostics` whose collection has been set to false first. `DiagnosticsSettingSync` turns it on if the user opted in.
- **`FirebaseDiagnostics`:**
  - `setCollectionEnabled` calls both `setAnalyticsCollectionEnabled` and `setCrashlyticsCollectionEnabled`.
  - `logEvent` is `FirebaseAnalytics.instance.logEvent(name:, parameters:)`, and `logScreen` is `logScreenView(screenName:)`.
  - `recordError` is `FirebaseCrashlytics.instance.recordError(…, fatal:, reason:)`.
  - `appInstanceId` comes from analytics.

- [ ] **Step 1: Write failing tests:**
  - `startDiagnostics(enabled: false)` → `NoDiagnostics`;
  - `startDiagnostics(enabled: true, initialize: () async => throw Exception('no config'))` → `NoDiagnostics`.
- [ ] **Step 2: Watch them fail.** **Step 3: Implement.**
- [ ] **Step 4: Watch them pass.** Then:
  - the full suite;
  - `flutter build apk --flavor dev --release --split-per-abi`, which must succeed without `google-services.json`;
  - `flutter run` on the iOS simulator, which must reach the first screen with no `GoogleService-Info.plist` (take a screenshot).
- [ ] **Step 5: Commit** `feat: Firebase Analytics and Crashlytics, off until configured and chosen`.

### Task 6: Setup, Settings and the links

**Files:**
- `pubspec.yaml`: `flutter pub add url_launcher package_info_plus`.
- Create:
  - `lib/core/links.dart`, with `LegalLinks` (the two URLs) and the `LinkOpener` interface. `UrlLauncherLinkOpener` uses `launchUrl(uri, mode: LaunchMode.externalApplication)` and returns false on failure. `linkOpenerProvider` holds it.
  - `lib/core/app_version.dart`, with `appVersionProvider` (a `FutureProvider<String>` of "0.1.0 (2001)" via `PackageInfo.fromPlatform()`). Tests override it with a fixed value.
  - `lib/features/settings/presentation/privacy_section.dart`.
- Modify:
  - `onboarding_screen.dart`: the diagnostics card after the reminders card, and the agreement line above the buttons; `_start` saves `setShareDiagnostics(on: _share)`.
  - `settings_screen.dart`: the `PrivacySection` after Reminders, with the existing "Privacy choices" tile moving into it.
  - `app_en.arb`.
- Create: `test/helpers/fake_link_opener.dart` (records the URIs; `succeed` flag).
- Tests: `onboarding_screen_test.dart`, `settings_screen_test.dart`, `test/core/links_test.dart`.

**ARB keys:**
- `diagnosticsTitle` "Help improve Debt Destroyer"
- `diagnosticsHint` "Share anonymous usage statistics and crash reports. Never your debts, amounts or names."
- `setupAgreement` "By continuing you agree to the Terms of use and have read the Privacy policy."
- `termsOfUse` "Terms of use"
- `privacyPolicy` "Privacy policy"
- `settingsPrivacy` "Privacy"
- `appInstanceId` "Your app ID: {id}"
- `appVersion` "Version {version}"
- `linkOpenFailed` "Couldn't open the page. It's at {url}"

**Behaviour:**
- **The agreement line:** the `setupAgreement` text, then a `Wrap` of two `TextButton`s, "Terms of use" and "Privacy policy". They're keyed `ValueKey('termsLink')` and `ValueKey('privacyLink')`, and open through `LinkOpener`.
- **Failure:** if `open` returns false, a SnackBar shows `linkOpenFailed(url)`.
- **The Privacy section, top to bottom:**
  1. A heading, "Privacy".
  2. The `SwitchListTile` (`ValueKey('shareDiagnostics')`), which applies immediately via `setShareDiagnostics`.
  3. When on and `appInstanceId()` returns an ID, a `SelectableText(appInstanceId(id))`.
  4. The ads "Privacy choices" tile, when required.
  5. Two `ListTile`s: "Privacy policy" and "Terms of use", with an open-in-new icon.
  6. `Text(appVersion(version))`.

- [ ] **Step 1: Write failing tests:**
  - **Setup:**
    - the switch is off by default;
    - turned on and "I'll do it later" → `shareDiagnostics` is true;
    - left off → false;
    - tapping "Terms of use" records `LegalLinks.terms`, and "Privacy policy" records `LegalLinks.privacyPolicy`;
    - a failed open shows the SnackBar with the URL.
  - **Settings:**
    - the switch saves at once;
    - with a `FakeDiagnostics` whose `appId` is `'abc123'` and the switch on → "Your app ID: abc123";
    - the links open;
    - "Version 0.1.0 (2001)" shows, with `appVersionProvider` overridden.
  - **Large text:** 360 wide at 2× on the setup page (scrolled to the buttons) and on Settings (scrolled to the version) → no exception.
- [ ] **Step 2: Watch them fail.** **Step 3: Implement.**
- [ ] **Step 4: Watch them pass, then run the full suite.** Commit `feat: the diagnostics choice in setup and Settings, with the terms and privacy links`.

### Task 7: The documents and the release notes

**Files:**
- In `~/development/countersunkweb`, on a new branch `debt-destroyer-legal` from its current branch:
  - create `apps/debt-destroyer/privacy-policy.html` and `apps/debt-destroyer/tos.html`;
  - read `apps/all-wrapped-up/privacy-policy.html` and `tos.html` in full first, and copy their markup, the `<style>` block and the section structure exactly;
  - replace only the content, with spec §4's sections;
  - the effective date is the day of writing, in All Wrapped Up's date style;
  - the page `<title>`s are "Debt Destroyer - Privacy Policy" and "Debt Destroyer - Terms of Service".
- In this repo:
  - `docs/privacy-policy.md` becomes a short pointer to the hosted pages;
  - `docs/release.md` gets:
    - a "Firebase" section: create the project; run `flutterfire configure --project=<id>` for the three app IDs; where the files go; the plugins apply once the json exists; `--dart-define=DIAGNOSTICS_ENABLED=true` to try it in debug; and a check, with the Firebase DebugView, that nothing arrives with the switch off;
    - rewritten store-disclosure bullets: Play data safety and App Store privacy details, now including optional analytics (app interactions, and device or other IDs via the app instance ID) and crash logs and diagnostics, collected only with consent, not used for tracking, and not shared except with Google as the processor;
    - the Crashlytics paragraph at line 68, which is now done.
  - `CLAUDE.md`:
    - add a Plan 14 checklist line and the spec link;
    - add a Gotcha: "Diagnostics go through `DiagnosticsService` (`lib/core/diagnostics.dart`): nothing is collected unless `AppSettings.shareDiagnostics`; events are the closed `DiagnosticEvent` catalogue (enum names only, never amounts or names); screen views are route templates. Firebase is optional — `startDiagnostics` falls back to `NoDiagnostics` without config files, and tests use `FakeDiagnostics`."
    - update the "Ads and crash reporting" gotcha.
- **Content checks** against spec §4:
  - Countersunk Development Ltd, company number 15961178, as data controller;
  - info@countersunk.dev;
  - the retention figures;
  - the ICO;
  - England and Wales;
  - the "not financial advice" wording.
- [ ] **Step 1:** Write the two HTML files. Open each locally (`python3 -m http.server` in countersunkweb) and screenshot them with the browser tool, or render them headless, to check they look like All Wrapped Up's.
- [ ] **Step 2:** Commit in countersunkweb on `debt-destroyer-legal`: `feat: Debt Destroyer privacy policy and terms of service`. Don't push.
- [ ] **Step 3:** Update the docs in this repo. Run the full verification:
  - `./tool/codegen.sh && dart format lib test && dart analyze --fatal-infos && flutter test && (cd packages/payoff_engine && dart test)`;
  - the APK build;
  - the simulator launch.
- [ ] **Step 4:** Commit `docs: Plan 14 diagnostics and legal documents`.
