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
- [ ] Implementation plan written
- [ ] Legacy sources moved to `legacy/android/`
- [ ] Flutter project scaffolded, and `payoff_engine` built and tested
- [ ] Persistence, state, screens, ads, export, CI, store release

Update this checklist as the phases complete. Once the Flutter project exists, add its build, test and codegen commands here: `flutter test`, a single test via `flutter test path/to_test.dart --plain-name "name"`, `dart run build_runner build -d`, and `dart test` inside `packages/payoff_engine`.

## Legacy Android app (reference only)

The legacy Java sources are currently at the repo root and will move to `legacy/android/`. They are a **read-only reference** for the original behaviour; don't modify or try to build them. When porting behaviour, check it against the calculator described below, and remember the bug fixes listed in spec §4.

The repo holds **only the Java sources** (package `com.dmt195.debtdestroyer`). There's no Gradle/Ant build, `AndroidManifest.xml`, `res/` or `libs/`, so the code can't be built and `R.*` references can't be resolved. It depends on the legacy Android SDK and support v4 library, AChartEngine, Apache POI HSSF and the old `com.google.ads` AdMob SDK.

### Legacy architecture

Package directories map to screens: `Debts/` (enter debts; launcher activity), `Solutions/` (list of repayment strategies), `Analysis/` (tabbed Facts/Graph/Next-actions view), `Details/` (per-solution graph and table/XLS export). Root-level files are shared dialogs and preferences.

#### Global static state
Activities share data through **static fields**, not Intents or a data layer:
- `DebtListAdapter.debtList` (static `ArrayList<DebtItem>`), accessed via `ManageDebtsActivity.DebtList`.
- `SolutionListAdapter.solutionList` (static `ArrayList<Solution>`). `AnalyseActivity.solList` and `ManageSolutionsActivity.solList` are separate adapter instances that **share the same static list**.
- User settings are cached as static fields on `ManageDebtsActivity` (`monthlyAmount`, `currencySym`, `consolidationAPR`, `revertAPR`, `ccTerm`, `ccTransferFee`, `loanActive`, `ccActive`, `settings`). These are re-read from default `SharedPreferences` in several `onResume()` methods, and each copy duplicates the preference keys and default values (`"monthly"`/250, `"loan_apr"`/4.0, `"cc_revert_apr"`/15.0, `"cc_term"`/15, `"cc_transfer_fee"`/4.0, …). If you change a key or default, update every copy.

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
