# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project goal: Flutter rebuild

This repo is being migrated from a 2013 Android app ("Debt Destroyer") to a modern **Flutter app for iOS and Android, funded by ads, to be shipped to the app stores**. v1 recreates the original features with the known bugs fixed; it adds nothing new.

- **Design spec (source of truth):** `docs/superpowers/specs/2026-09-24-flutter-rebuild-design.md`. Read it before any Flutter work; if a decision here conflicts with it, the spec wins.
- **v2 spec:** docs/superpowers/specs/2026-09-24-v2-planning-design.md (builds on the v1 spec).
- **v3 spec:** `docs/superpowers/specs/2026-09-25-v3-ux-redesign-design.md`: three-tab navigation, charts first, illustrations, progress check-ins, reminders (builds on v1 and v2).
- **Rates and loans spec:** `docs/superpowers/specs/2026-09-26-rates-and-loans-design.md`: compound APR, rate entry per year or per month, the loan helper and the loan calculator.
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
- [x] Plan 5: v2 better planning — snowball, your order, minimums-only baseline, promos, realistic transfer and consolidation, pay-more slider, saved scenarios (`docs/superpowers/plans/2026-09-24-plan-5-v2-planning.md`, spec `docs/superpowers/specs/2026-09-24-v2-planning-design.md`)

- [x] Plan 7: v3 shell and charts — three tabs (Home, Debts, Plans), Direction A theme and fonts, chart kit, chart-first Debts/Plans/Plan detail/Scenarios (`docs/superpowers/plans/2026-09-25-plan-7-shell-and-charts.md`, spec `docs/superpowers/specs/2026-09-25-v3-ux-redesign-design.md`)
- [x] Plan 8: progress — followed plan, check-ins, starting points, restart, cleared debts, celebration (`docs/superpowers/plans/2026-09-26-plan-8-progress.md`)
- [x] Plan 9: reminders (local notifications) (`docs/superpowers/plans/2026-09-26-plan-9-reminders.md`)
- [x] Plan 10: illustrations and motion — brick wall, welcome pages, debt-type tiles, empty states, check-in count-up, wrecking-ball celebration, charts drawing in (`docs/superpowers/plans/2026-09-26-plan-10-illustrations.md`). v3 is complete.

- [x] Plan 11: compound APR and loan solvers (`docs/superpowers/plans/2026-09-26-plan-11-compound-interest-and-loan-solvers.md`)
- [ ] Plan 12: rate field (per year / per month) and the loan helper in the debt form
- [ ] Plan 13: the loan calculator

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
- Widget tests use `pumpApp` (`test/helpers/pump_app.dart`): the whole app with an `InMemoryDebtRepository` and a synchronous `planCalculatorProvider`. Drift's streams and `compute` isolates don't run under the widget test clock, so never use the real ones in widget tests. After `tester.ensureVisible`, call `pumpAndSettle` before tapping. `pumpApp` opens Debts by default. It takes a `clock`, because Riverpod rejects a second `clockProvider` override, and `AppHarness.progress` is the in-memory progress repository. The default 800×600 test surface builds little of a long list: `useTallScreen(tester)` gives a 390×2400 phone. Strategy names also appear in the race chart's legend, so find a strategy's card by `ValueKey(StrategyId)`.
- Errors found after Save are shown with `forceErrorText`. Clear a field's forced error in its `onChanged`, never at the start of Save: a stale forced error makes `validate()` fail silently.
- Illustrations are `CustomPainter`s in `lib/core/illustrations/` built from `kit.dart` (fixed Direction A inks, `fitDesign` to draw in a design box at any size) and wrapped in `Illustration` (decorative unless labelled). Animated ones take a `progress` (0–1); widgets drive it with one `AnimationController` started once in `didChangeDependencies`, and reduced motion (`MediaQuery.disableAnimationsOf`) jumps to 1. Nothing loops, so `pumpAndSettle` always ends. Charts draw in once through `DrawIn` (`lib/core/charts/draw_in.dart`).
- Reminders (`lib/features/reminders/`, `lib/core/notifications.dart`):
  - **Service:** local notifications go through `NotificationsService`. `pumpApp` and `createTestContainer` override it with `FakeNotificationsService` (set `granted`/`launch`, read `scheduled`, simulate a `tap`).
  - **Scheduling:** `reminderSchedulerProvider` (watched by the app) replaces the scheduled set whenever the plan, settings or history change, and only if the wanted list differs. Scheduling waits for `notificationsReadyProvider`.
  - **Taps and launch:** a tap, or a launch from a reminder (`openLaunchReminder` in `main.dart`), goes to `/check-in`.
  - **Times** are wall-clock times built in `tz.local`, and scheduled inexactly (no exact-alarm permission).
  - **Android** needs core library desugaring and the plugin's two receivers in the manifest.
- Ads and crash reporting go through `AdsService` (`lib/features/ads/`) and `CrashReporter` (`lib/core/crash_reporter.dart`). Widget tests that need ads override `adsServiceProvider` with `FakeAdsService`. Ads appear only on the Debts and Plans screens (anchored above the bottom nav, never between list items), behind consent.
- Every amount is in minor units of the one app-wide currency (`AppSettings.currencyCode`). Change currency only through `SettingsController.setCurrency`, which rescales stored amounts when the number of decimal digits changes. The database records which currency its amounts are in (`DebtRepository.convertAmounts`, idempotent), and the controller reconciles it at startup, so an interrupted switch is repaired. Settings are saved as one JSON value under `SettingsKeys.settings`.
- Interest: an APR is the true, compounded rate. The engine charges `monthlyRatePpm(apr)` parts per million a month (`packages/payoff_engine/lib/src/interest.dart`, exact integer maths), not APR ÷ 12. The 2013 figures, and engine tests whose figures were worked out that way, run inside `runWithInterestMode(InterestMode.nominal, …)` (test helper `nominal`). Loan maths (any one of payment, months, balance or APR from the other three) go through `loanPayment`/`loanMonths`/`loanBalance`/`loanApr` (`lib/src/loan.dart`), which return `LoanSolved` or `LoanImpossible`.
- The engine runs in three stages: `restructure` (transfer/consolidation turn the user's debts into the debts actually paid), `allocationOrder` (avalanche-style strategies re-rank every month by the interest a pound saves from that month to the end of the plan, so a short 0% promo doesn't delay paying a debt that will cost more later; the calculator finds the end month in a few passes and keeps the cheapest plan) and `simulate`. `PayoffPlan.debts` is in the order debts are *cleared*, not the priority order.
- Promotions are stored as their last calendar month (`promoEndsYearMonth`, `yyyymm`) and read as "months left" using the repository's clock; an ended promo reads back as none. Widget tests fix the clock at 24 Sep 2026.
- Navigation (`lib/app/router.dart`): a `StatefulShellRoute` with three branches, Home (`/`), Debts (`/debts`) and Plans (`/plans`), in `AppShell`. The debt form, Settings and onboarding use the root navigator (full screen, no tabs). `/plans/scenarios` is declared before `/plans/:strategyId`. User-facing copy says "Plans"; code keeps `StrategyId`, `strategies/` and `StrategiesScreen`.
- Theme (`lib/app/theme.dart`): Direction A tokens live in the `DestroyerColors` extension (`context.colors`). Headings and big numbers use `displayStyle(size)` (Bricolage Grotesque 800); body text is Atkinson Hyperlegible. Both are bundled in `assets/fonts/`. Hi-vis yellow (`hiVis`) is never a text colour.
- Charts (`lib/core/charts/`) only draw. Their data comes from pure functions in `lib/features/analysis/domain/plan_series.dart` (totals, stacks, milestones, money split, grouped payments). A debt's colour is `debtColor(colors, id, listOrderIds)`: its position in the user's list, with card-transfer portions (`<card>#from-<source>`) merged into their card (`baseDebtId`, `groupPlanDebts`).
- Home uses `homePlanProvider`: the followed plan (`AppSettings.followedStrategy`), or the cheapest pay-off method until one is chosen, on Current settings (`currentPlansProvider`), ignoring saved scenarios and the slider. Its states also include `HomeFollowedUnavailable` and `HomeAllCleared`. Switch plans through `ProgressController.follow`.
- Progress (`lib/features/progress/`):
  - **Cleared debts:** a cleared debt keeps its row with `clearedAt` and balance 0. `DebtRepository.watchAll`/`loadAll`/`reorder` only cover uncleared debts, so the engine never sees cleared ones. List them with `watchCleared` (`clearedDebtsProvider`) and bring one back with `reopen`.
  - **Check-ins:** `ProgressRepository.saveCheckIn` updates the debts' balances in the same transaction (a zero clears the debt).
  - **Starting points** are recorded by `progressReconcilerProvider`, which the app watches for its whole life. It decides with `nextStart` from freshly loaded data: the first run, a debt added or reopened, a debt deleted, or a plan switch. It records nothing while the followed plan is infeasible.
  - **Widget tests** therefore always have a starting point after the first frame. Check-ins in tests must be dated at or after the test clock, or they sort before that start.
  - **History order:** check-ins are ordered by time and then by insertion; `aheadBehind` counts by position.
  - **Deleted debts:** a deleted debt's `check_in_balances` rows are kept (names included), so a deletion can be detected and labelled. `paidOff` ignores them.
- `plansProvider` gives a `PlanSet` (`ranked` plus the minimums-only `baseline`) for the *active scenario* (the selected saved scenario, or Current = Settings) plus the slider's `extraPaymentProvider`, which resets when the currency or the selection changes.
- `DriftDebtRepository.convertAmounts` also rescales saved scenarios and progress history (check-in totals and balances, and starting points' projected totals), in the same transaction. In tests, `InMemoryProgressRepository` rescales through `InMemoryDebtRepository.onConvert`. The in-memory repositories don't rescale scenarios.
- Consolidation and balance transfer are *borrowing alternatives* (`isBorrowingAlternative` in `lib/features/strategies/domain/strategy_groups.dart`): shown in their own section with a caveat, and never marked cheapest or picked as the best plan (`bestPayOffMethod`).
- Strategy-parameter fields (Settings and the scenario editor) come from `ParameterFields` in `lib/features/settings/presentation/parameter_fields.dart`; add new parameters there once.
- Card transfers (`Strategy.cardTransfers`): `calculate` runs a greedy search (`cardMoveCandidates`, `applyCardMoves`, at most `kMaxCardMoves`, each round shortlisted to `kCardMoveShortlist` candidates and screened with one cheap simulation before the winner is confirmed with a full one) over the look-ahead avalanche. Moved money becomes a *portion* debt (`<card>#from-<source>`) grouped with its card: `simulate(groups:)` works out one minimum on the card total (lowest rate first) and pays extra highest current rate first within a card (the UK rule). Offers live on `Debt.transferOffer` (schema 3); if the no-move plan isn't feasible, a move that makes it feasible is kept even though it doesn't lower `totalPaid`.

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
- The Flutter app no longer offers lowest-APR-first or the 110% "boosted" plan (v2 spec §3.1).

#### Flow
`ManageDebtsActivity` (add or edit debts with `FragmentAddDebtDialog`) → menu "see solutions" → `solveAllDirect()` fills `AnalyseActivity.solList` (in order: highest-first, lowest-first, highest-first at 110% of the monthly amount, consolidation, 0% card) → `AnalyseActivity`. If the first month's payable amount is more than the monthly budget, the app shows `FragmentMinPayments` instead. `TableViewActivity` exports a solution to `.xls` in the public Downloads directory and shares it.
