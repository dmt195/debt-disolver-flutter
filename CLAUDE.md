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
- [ ] Plan 3: screens (onboarding, debts, strategies, plan detail, settings) and CSV/XLSX export
- [ ] Plan 4: ads and consent, Crashlytics, full CI, store release prep

Update this checklist as the phases complete.

## Commands

`payoff_engine` (run from `packages/payoff_engine/`):
- `dart pub get`, then `dart run build_runner build -d`. Run the build after a fresh checkout or after any freezed model change, because generated `*.freezed.dart` files are not committed.
- `dart test`: all tests. `dart test test/calculator_test.dart --plain-name "name"` runs one test.
- `dart analyze --fatal-infos` and `dart format lib test`. CI (`.github/workflows/payoff_engine.yml`) enforces both.
- Legacy reference figures: `java legacy/reference/LegacySolver.java` (from the repo root).

App (run from the repo root):
- `./tool/codegen.sh` generates code for `payoff_engine` and then the app. Run it after a fresh checkout and after changing any freezed model, Riverpod provider or Drift table. Generated `*.g.dart`/`*.freezed.dart` files are not committed.
- `flutter test` runs all app tests. `flutter test test/path/to_test.dart --plain-name "name"` runs one test.
- `dart analyze --fatal-infos` and `dart format lib test`. CI (`.github/workflows/app.yml`) enforces both.
- `flutter run` runs the app on a connected device or simulator.
- To change the Drift schema: bump `schemaVersion` in `lib/features/debts/data/app_database.dart` and write the migration. Then run `dart run drift_dev make-migrations` and commit `drift_schemas/` and the generated `test/drift/` tests.

Gotchas:
- Riverpod 3 pauses providers that have no listener, so a `StreamProvider` read without a listener never emits. In tests, call `container.listen(provider, (_, _) {})` before reading `.future`. To check that a write took effect, read the repository (`loadAll`), not the stream's latest value.
- `select`/`selectAsync` come from `flutter_riverpod`, not `riverpod_annotation`. `Override` is in `package:flutter_riverpod/misc.dart`.
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
