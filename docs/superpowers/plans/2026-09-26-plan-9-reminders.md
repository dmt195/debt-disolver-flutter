# Plan 9: Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Local notifications: a monthly pay-day reminder listing what to pay, and an optional nudge to check in. Both can be switched on in setup and managed in Settings, and tapping either opens Check in.

**Architecture:**
- **`NotificationsService`** (`lib/core/notifications.dart`) wraps `flutter_local_notifications` and `timezone`. A fake stands in for it in tests, the same pattern as `AdsService` and `CrashReporter`.
- **Pure scheduling maths:** `lib/features/reminders/domain/reminder_schedule.dart` works out the dates and what each notification says.
- **`ReminderScheduler`** is a keep-alive provider that the app watches. Whenever the followed plan, settings or history change, it recomputes the wanted notifications and replaces the scheduled set, only when it differs.
- **Taps** go to `/check-in` through the router.

**Tech Stack:** Flutter, Riverpod 3, `flutter_local_notifications` 22, `timezone`, `flutter_timezone`.

**Spec:** `docs/superpowers/specs/2026-09-25-v3-ux-redesign-design.md`: §7 (all), §4.1 step 2 (reminder switch in setup) and step 3 ("Add my first debt"/"I'll do it later"), and §4.11 (Settings › Reminders). Design: canvas lo-fi board "12 · Reminder + settings".

## Global Constraints

- **Local only.** Never use exact alarms (no `SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM`); use `AndroidScheduleMode.inexactAllowWhileIdle`.
- **Timing:**
  - Pay day is at 09:00 local on the chosen day (1–28, or "Last day").
  - The next **three** occurrences are scheduled individually. The first lists this month's payments; the second and third use the generic body.
  - Everything is rescheduled on app start and whenever the plan, settings or history change.
- **The nudge** comes at 09:00, *n* months after the last check-in (*n* = 1, 2 or 3; 0 = off).
- **Permission** is requested only when a reminder switch is turned on. A denial turns it back off and explains how to allow notifications in system settings.
- **Nothing is scheduled** when there are no uncleared debts or the followed plan isn't feasible. Anything pending is cancelled.
- **Copy and money:** all copy goes in `app_en.arb`, and amounts are formatted with `formatMoney` when scheduling.
- **Process:**
  - TDD for everything.
  - `./tool/codegen.sh` after provider or model changes.
  - `dart analyze --fatal-infos` and `dart format` clean.
  - Commit trailer as in earlier plans:
    ```
    Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01S3YJtSqzzA5Sf6buKinyKC
    ```

## Review Focus

1. **Day choices that don't exist every month:** "Last day" in February (including a leap year), and a chosen day already past this month. The first reminder is next month's. Test: Task 2.
2. **Scheduling churn and loops:** the scheduler must not reschedule when nothing has changed, and must not schedule while reminders are off. Test: Task 4.
3. **Permission denied:** the switch reverts, the setting is not saved as on, and nothing is scheduled. Test: Tasks 5 and 6.
4. **A tap while the app is closed:** the app opens on Check in after onboarding. If onboarding isn't complete, the existing redirect wins. Test: Task 4.
5. **Currency change or a cleared debt:** the scheduled body is rebuilt, never showing a cleared debt or stale amounts. Test: Task 4.

---

### Task 1: Dependencies and native set-up

**Files:** `pubspec.yaml` (`flutter_local_notifications`, `timezone`, `flutter_timezone`, already added), `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/AppDelegate.swift`

- [ ] **Android desugaring** (required by the plugin): in `compileOptions` add `isCoreLibraryDesugaringEnabled = true`, and add a `dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }` block.
- [ ] **Manifest:** add `<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>`, plus the two receivers inside `<application>`, as in the plugin README (`ScheduledNotificationReceiver`, and `ScheduledNotificationBootReceiver` with the BOOT_COMPLETED, MY_PACKAGE_REPLACED and QUICKBOOT_POWERON intent filters). `POST_NOTIFICATIONS` comes from the plugin's own manifest.
- [ ] **iOS:** in `AppDelegate.application(...)`, set `UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate` before `super` (plugin README), with `import UserNotifications`.
- [ ] **Verify:** `flutter build apk --flavor dev --debug` succeeds and `flutter test` still passes. There is no unit test for native config.
- [ ] **Commit:** `build: local notifications — desugaring, receivers, iOS delegate`.

### Task 2: Reminder settings and schedule maths

**Files:**
- Modify: `lib/features/settings/domain/app_settings.dart`, `prefs_settings_repository.dart`, `settings_controller.dart`
- Create: `lib/features/reminders/domain/reminder_schedule.dart`
- Test: `test/features/settings/*`, `test/features/reminders/reminder_schedule_test.dart`

**Interfaces:**
- `AppSettings` gains:
  - `bool payDayReminder` (default false);
  - `int payDay` (1–28, or 0 for the last day; default 28);
  - `int checkInNudgeMonths` (0–3; default 2).

  Stored under the keys `payDayReminder`, `payDay` and `checkInNudgeMonths`. Out-of-range stored values read as the defaults.
- `SettingsController` gains:
  - `setPayDayReminder(bool on, {int? day})`;
  - `setCheckInNudgeMonths(int months)`.

  Both validate their input (`ArgumentError` when out of range).
- `reminder_schedule.dart`:

```dart
/// 0 means the last day of the month.
const kLastDay = 0;

/// The next [count] pay days at 09:00 on or after [now] (strictly after, if
/// today's 09:00 has passed). Day 0 is each month's last day.
List<DateTime> nextPayDays(DateTime now, int day, {int count = 3});

/// The check-in nudge: [months] after [lastCheckIn] at 09:00, or null when
/// off (0) or there is no check-in. A nudge already past is null.
DateTime? nudgeAt(DateTime? lastCheckIn, int months, DateTime now);

/// One scheduled notification.
typedef Reminder = ({int id, DateTime at, String title, String body});
```

- [ ] **Tests** (write them failing first):
  - The prefs round trip, and bad values read as defaults.
  - The controller setters validate.
  - `nextPayDays`:
    - from 24 Sep 2026 with day 28 → 28 Sep, 28 Oct, 28 Nov (09:00);
    - from 28 Sep 2026 10:00 with day 28 → starts at 28 Oct;
    - day 0 from 2 Feb 2028 → 29 Feb 2028 (leap year), 31 Mar, 30 Apr;
    - day 0 from 2 Feb 2027 → 28 Feb 2027;
    - day 1 from 31 Dec 2026 → 1 Jan 2027.
  - `nudgeAt`:
    - 3 Sep 2026 + 2 months → 3 Nov 2026 09:00;
    - 31 Jan + 1 month → 28 Feb (clamped);
    - off → null;
    - no check-in → null;
    - already past → null.
- [ ] **Implement.** For each month, use `DateTime(y, m, day == 0 ? lastDay : day, 9)`, where `lastDay = DateTime(y, m + 1, 0).day`. For the nudge, clamp the day to the target month's last day.
- [ ] **Commit:** `feat(reminders): settings and schedule maths`.

### Task 3: `NotificationsService`

**Files:**
- Create: `lib/core/notifications.dart` (interface, `LocalNotificationsService`, `notificationsServiceProvider`)
- Create: `test/helpers/fake_notifications_service.dart`
- Modify: `test/helpers/pump_app.dart` (override with the fake by default), `test/helpers/test_container.dart` (same)
- Test: `test/core/notifications_test.dart` (the fake's contract), and a `LocalNotificationsService` test that uses a mocked `FlutterLocalNotificationsPlugin` via a thin seam (constructor-injected plugin), checking that `replaceAll` cancels and then schedules with `inexactAllowWhileIdle`

**Interfaces:**

```dart
abstract interface class NotificationsService {
  /// Sets up the plugin and time zone. [onTap] gets a notification's payload.
  Future<void> initialize({required void Function(String? payload) onTap});

  /// Asks the OS for permission; true if granted.
  Future<bool> requestPermission();

  /// Replaces everything scheduled with [reminders] (empty cancels all).
  Future<void> replaceAll(List<Reminder> reminders);

  /// The payload of the notification that launched the app, if any.
  Future<String?> launchPayload();
}
```

- Payload `'check-in'` for both kinds.
- Android channel `reminders`, "Reminders", importance default.
- iOS: `DarwinNotificationDetails()`.
- `replaceAll` → `cancelAll()` then `zonedSchedule` for each one, with `tz.TZDateTime.from(at, tz.local)`.
- `initialize`:
  - `tz.initializeTimeZones()`;
  - `tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier))`, falling back to UTC on error;
  - plugin `initialize` with `AndroidInitializationSettings('@mipmap/ic_launcher')` and `DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false)`.
- `requestPermission`: Android `requestNotificationsPermission()`, iOS `requestPermissions(alert: true, sound: true)`; `false` when null.
- `FakeNotificationsService`:
  - `granted` (settable);
  - `scheduled` (the last list);
  - `replaceCount`;
  - `requests` (the count);
  - `launch` (settable payload);
  - `tap(payload)` calls the registered `onTap`.

- [ ] **Steps:** failing tests → implement → run the tests plus the whole suite → **commit** `feat(core): NotificationsService over flutter_local_notifications`.

### Task 4: Reminder scheduler and notification taps

**Files:**
- Create: `lib/features/reminders/presentation/reminder_scheduler.dart`
- Modify: `lib/app/app.dart` (watch it), `lib/main.dart` (`initialize` with an `onTap` that calls `router.go(Routes.checkIn)`; after the first frame, if `launchPayload()` is `'check-in'`, go there too)
- Modify: `lib/l10n/app_en.arb`
- Test: `test/features/reminders/reminder_scheduler_test.dart` (unit, `createTestContainer` + fake), `test/features/reminders/reminder_tap_test.dart` (widget)

**Interfaces:**
- `@Riverpod(keepAlive: true) class ReminderScheduler`:
  - Its `build()` listens to `homePlanProvider`, `settingsControllerProvider` and `progressHistoryProvider`, and calls `_reschedule()`.
  - Keeps the last list sent; it doesn't call the service again when the new list is equal.
  - Serialises its work with a busy/again flag, as the reconciler does.
- `List<Reminder> wantedReminders({required AppSettings settings, required HomePlan home, required ProgressHistory history, required DateTime now, required AppLocalizations l10n, required String locale})`:
  - A pure top-level function in the same file.
  - Pay days: ids 1–3.
    - First body: `reminderPayDayBody(list)`, where `list` is `"{name} {amount}"` for each `firstMonthPayments` entry of the followed plan, joined with " · ".
    - The others: `reminderPayDayGeneric`.
    - Title: `reminderPayDayTitle(total)`: "Pay day: {total} across your debts".
  - Nudge: id 10, `reminderNudgeTitle` / `reminderNudgeBody(months)`.
  - Empty unless `home is HomeFollowing`.
- `main.dart` wiring:
  - Read `notificationsServiceProvider` from the container and initialize it.
  - `onTap` routes to `Routes.checkIn`.
  - Launch payload: after the first frame, if the payload is `'check-in'`, `router.go(Routes.checkIn)`. The router's onboarding redirect still applies.
  - Keep this logic in a testable function, `handleReminderTap(ProviderContainer, String? payload)`, in `reminder_scheduler.dart`.

- [ ] **Tests:**
  - With reminders on and a feasible plan, three pay days and a nudge are scheduled, and the first body lists the payments with their amounts.
  - With reminders off, only the nudge is scheduled (when `checkInNudgeMonths > 0` and there's a check-in). With both off, nothing is scheduled.
  - Infeasible (budget below the minimums): nothing is scheduled.
  - Unchanged inputs don't reschedule: `replaceCount` stays the same after an unrelated settings save (`setStrategyParameters` with equal values).
  - After a check-in clears a debt, the rebuilt body leaves it out.
  - After `setCurrency('JPY')`, the amounts show in yen.
  - Widget: `fake.tap('check-in')` on Home opens `CheckInScreen`. `handleReminderTap` with onboarding incomplete lands on onboarding.
- [ ] **Implement, run and commit:** `feat(reminders): schedule pay-day reminders and the check-in nudge; taps open Check in`.

### Task 5: Settings › Reminders

**Files:** `lib/features/settings/presentation/settings_screen.dart` (+ a new `reminders_section.dart`), `lib/l10n/app_en.arb`. Test: `test/features/settings/reminders_section_test.dart`.

**Behaviour:** an `OutlinedCard` titled "Reminders" (`remindersTitle`) containing:
- **The pay-day switch** (`SwitchListTile`, `remindersPayDay` / `remindersPayDayHint`).
  - Turning it on calls `service.requestPermission()`.
  - If granted, `setPayDayReminder(true)`.
  - If denied, the switch stays off and an inline message shows `remindersDenied` ("Notifications are off for Debt Destroyer. Turn them on in your phone's settings to get reminders.").
  - Turning it off doesn't ask for permission.
- **Day of the month:** a `DropdownButtonFormField<int>` (`isExpanded`), with 1st–28th via `ordinal` and "Last day" (`remindersLastDay`). It's enabled only while the switch is on.
- **Check-in nudge:** a `DropdownButtonFormField<int>`: Off, "Every month", "Every 2 months", "Every 3 months" (`remindersNudge*`). Changing it from Off to a value asks for permission the same way.
- `remindersLocalOnly` in small text: "Local notifications only: nothing leaves your phone."

- [ ] **Tests** (`pumpApp` at `Routes.settings`, fake service):
  - Grant: the switch turns on and is saved.
  - Deny: the switch stays off, the message shows, and the setting isn't saved.
  - Choosing "Last day" saves 0.
  - Turning the nudge off saves 0 and leaves only pay days scheduled.
  - Large text: no overflow.
- [ ] **Implement, run and commit:** `feat(settings): reminders section`.

### Task 6: Setup — reminder switch, and add the first debt

**Files:** `lib/features/onboarding/presentation/onboarding_screen.dart`, `lib/l10n/app_en.arb`. Test: `test/features/onboarding/onboarding_screen_test.dart`.

**Behaviour** (spec §4.1 steps 2–3; the illustrated welcome pages are Plan 10):
- Below the budget field, an `OutlinedCard` with the pay-day switch (default on, `setupRemindMe`: "Remind me to pay each month") and the day dropdown (default 28th).
- **Buttons:** replace "Get started" with:
  - **"Add my first debt"** (`FilledButton`, `setupAddFirstDebt`): validates, saves the currency and budget, then saves the reminder (with the switch on, it asks for permission first; if denied, it saves it off and shows the message, but still continues), completes onboarding, and goes to `Routes.newDebt`.
  - **"I'll do it later"** (`OutlinedButton`, `setupLater`): the same, but goes to `Routes.home`.

- [ ] **Tests:**
  - "Add my first debt" opens the debt form, and the reminder is saved on (granted).
  - "I'll do it later" opens Home.
  - Denied: the reminder is saved off and onboarding still completes.
  - Invalid budget: stays put.
  - Update the existing onboarding tests from "Get started" to "I'll do it later".
- [ ] **Implement, run and commit:** `feat(onboarding): reminder switch; add your first debt or do it later`.

### Task 7: Docs and verification

- [ ] **`CLAUDE.md`:**
  - Tick Plan 9.
  - Gotchas:
    - `NotificationsService` has a fake (`FakeNotificationsService`, overridden in `pumpApp` and `createTestContainer`);
    - `ReminderScheduler` is watched by the app;
    - taps route to `/check-in`;
    - Android needs desugaring and the receivers.
- [ ] **`docs/release.md`:** a Notifications section covering the Play Console declaration (no exact alarms), and testing on a device (set the pay day to tomorrow; boot rescheduling).
- [ ] **Full verification:** `./tool/codegen.sh && dart format lib test && dart analyze --fatal-infos && flutter test && (cd packages/payoff_engine && dart test)`, plus `flutter build apk --flavor dev --debug`. On the iOS simulator, screenshot Settings (the Reminders section) and setup (onboarding with a fresh install: `xcrun simctl uninstall`).
- [ ] **Commit:** `docs: Plan 9 reminders`.
