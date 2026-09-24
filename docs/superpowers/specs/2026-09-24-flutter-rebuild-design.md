# Debt Destroyer — Flutter Rebuild Design

Date: 2026-09-24
Status: Draft for review

## 1. Intent

Rebuild the 2013 Android app "Debt Destroyer" (Java sources in this repo) as a modern Flutter app and ship it to the **Google Play Store and Apple App Store**, monetised with **ads**.

**Scope for v1: faithful core + fixes.** Same features as the original, with its known bugs fixed and no new features.

**Assumptions** (confirmed by not being contested):
- Data is local-only on device; no accounts, cloud sync or backup.
- Currency and number formatting follow the device locale, with a currency override in settings.

**Success criteria**
- A user can enter their debts and a monthly budget, then compare the five payoff strategies, see charts and a month-by-month schedule, and export the schedule.
- The payoff calculations are deterministic and match hand-verified test scenarios.
- The app passes Play Store and App Store review with GDPR/ATT-compliant ads.

## 2. Repository layout

The complete legacy Android project lives in `legacy/` as a read-only reference for the original behaviour: Java in `legacy/src/main/java/com/dmt195/debtdestroyer/`, and resources (strings, preferences, layouts, onboarding HTML) in `legacy/src/main/res/`. Build outputs and binaries in it are git-ignored. The Flutter app lives at the repo root.

```
legacy/                     # original Android project (read-only reference)
legacy/reference/           # standalone port of the legacy calculator, for test reference values
packages/payoff_engine/     # pure Dart package: domain model + calculator (no Flutter dependency)
lib/
  app/                      # MaterialApp, go_router config, theme, bootstrap
  core/                     # money formatting, locale, AdsService, shared widgets
  features/
    debts/        {domain, data, presentation}
    strategies/   {presentation}
    analysis/     {presentation}   # plan detail: summary, chart, schedule, export
    settings/     {domain, data, presentation}
    onboarding/   {presentation}
test/, integration_test/
```

Each feature uses three layers: **domain** (models, repository interfaces), **data** (implementations) and **presentation** (widgets plus Riverpod controllers). Presentation never imports data directly. Wiring happens through providers.

## 3. Domain model (`payoff_engine`)

All types are immutable (freezed).

- **`Money`**: an integer amount in minor units plus an ISO currency code. There are no floating-point amounts anywhere. Interest is computed with exact rational/decimal arithmetic and rounded to minor units once per month (banker's rounding, half-even).
- **`Debt`**:
  - `id`: UUID
  - `name`
  - `type`: `creditCard | loan | personal`
  - `balance`: Money
  - `apr`: integer basis points, 0–10000
  - `minPaymentPercent`: basis points
  - `minPaymentFloor`: Money
  - `allowsOverpayment`: bool

  The legacy unused `limit` field is dropped.
- **`Strategy`**: a sealed class with one variant per plan:
  - `Avalanche`: highest APR first
  - `LowestAprFirst`
  - `Boosted`: avalanche at 110% of the budget
  - `Consolidation(apr)`: all debts replaced by one loan at the configured APR
  - `BalanceTransfer(feeBps, promoMonths, revertApr)`: all debts moved to a 0% card with a transfer fee; the APR reverts after the promo period

  Each variant has a stable `StrategyId`.
- **`PayoffResult`**: a sealed class:
  - `Feasible(PayoffPlan)`
  - `Infeasible(shortfall: Money)`: the budget is below the total minimum payments
  - `NeverClears`: the calculation hit the 1,200-month cap
- **`PayoffPlan`**:
  - `strategyId`
  - `payoffOrder: List<DebtId>`
  - `months: List<MonthRow>`, where each `MonthRow` holds the balance and payment for every debt
  - `monthsToClear`
  - `totalPaid`
  - `totalInterest`

## 4. Calculator rules

`PayoffResult calculate(List<Debt> debts, Money monthlyBudget, Strategy strategy)` is a pure function. It never changes its input.

Each month it does the following:
1. Apply interest to every open balance: `balance × apr / 12`, rounded.
2. Pay each open debt's minimum: `min(balance, max(floor, percent × balance))`.
3. Allocate the remaining budget to debts in strategy order. Only debts with `allowsOverpayment` receive extra. Money left after a debt is cleared cascades to the next debt in the same month.
4. Record a `MonthRow`.

**Strategy specifics**
- For Consolidation and BalanceTransfer, the calculator builds a single synthetic debt from the total balance. The consolidation loan's minimum payment is the full budget. The transfer card's balance is `total × (1 + fee)` and it reverts to `revertApr` after `promoMonths`.
- If the budget is below the total first-month minimums, the result is `Infeasible` with the shortfall.

**Legacy bugs fixed**
- The APR comparator cast to `int` before scaling, so rates less than 1% apart tied. Sorting now compares the exact values, with ties broken by name and then id.
- The calculator mutated the shared debt list (sorting it and adding and removing synthetic debts). The new calculator is pure.
- Money was stored as `float`. It is now integer minor units.
- There was no cap on iterations. The calculator now stops at 1,200 months and returns `NeverClears`.
- An infeasible budget returned a 0-month "solution". It now returns an explicit `Infeasible` result.

## 5. Data and state

**Persistence**
- **Drift (SQLite)** stores the `debts` table: the `Debt` fields as integers, plus `sortIndex`, `createdAt` and `updatedAt`. Drift migrations are versioned from schema v1.
- **Settings** are stored in shared_preferences behind `SettingsRepository`:
  - monthly budget
  - currency code
  - consolidation APR
  - transfer fee, promo months and revert APR
  - whether onboarding is complete

  All keys and defaults are defined in one place. The defaults are the legacy Settings-screen values from `legacy/src/main/res/xml/preferences.xml`: budget 300, consolidation APR 5%, transfer fee 4%, 12 promo months, revert APR 15%. The legacy Java code had different fallbacks (250, 4%, 15 months) that applied until Settings was first opened; that inconsistency is not carried over.
- The domain layer defines the `DebtRepository` interface. `DriftDebtRepository` implements it.

**State (Riverpod with codegen)**
- `debtsProvider`: a stream of debts from Drift. Every change is written immediately; the legacy app saved in `onPause`, which could lose data.
- `settingsProvider`: an `AsyncNotifier`.
- `plansProvider`: derived from debts and settings. It runs all five strategies in a background isolate (`compute`) and returns the results sorted by total cost. It recalculates automatically whenever its inputs change.
- `planProvider(StrategyId)`: looks up a plan by id, never by list position.

## 6. Screens and navigation (go_router)

1. **Onboarding** (first launch only): an explanation, then currency and monthly budget. The explanation copy is adapted from the legacy intro pages (`legacy/src/main/res/raw/intro1-3.html`). The legacy Resources screen was an unfinished placeholder and is not ported.
2. **Debts** (home route):
   - List of debts with add, edit, delete and drag-to-reorder.
   - Header showing total debt and total minimum payments.
   - A "Compare strategies" call to action, disabled when there are no debts.
   - A banner warning when the budget is below the minimums, showing the shortfall.
3. **Strategies**: a card for each plan showing time to clear, total interest and total paid. The cheapest plan is highlighted; infeasible or never-clearing plans are shown as such.
4. **Plan detail**, with three tabs:
   - *Summary*: key figures and this month's payments.
   - *Chart*: stacked balances over time (fl_chart).
   - *Schedule*: a month-by-month table.

   A **share** action exports CSV or XLSX to temporary storage and opens the system share sheet. No storage permissions are needed.
5. **Settings**: all strategy parameters, currency, and privacy options (to reopen the consent form).

## 7. Ads and privacy

- **`AdsService` interface** in `core`:
  - `AdMobAdsService` uses `google_mobile_ads`.
  - `NoopAdsService` is used for tests, debug and screenshots.
- **Consent:**
  - The Google UMP consent form runs at startup (GDPR, UK and EU).
  - iOS shows the ATT prompt.
  - If the user declines, ads are non-personalised.
- **Placement:** an adaptive banner at the bottom of the Debts and Strategies screens only. There are none on forms, onboarding or plan detail, and no interstitials.
- **Ad unit IDs** come from `--dart-define`. Google's test IDs are used in debug builds.
- A privacy policy page is required before store submission.

## 8. Error handling

- **Form validation** lives in the domain layer:
  - name is not empty
  - balance > 0
  - APR is 0–100%
  - minimum percent is 0–100%
  - minimum floor ≥ 0

  Messages are localised.
- The `Infeasible` and `NeverClears` results have dedicated UI explaining what to change.
- Repository failures show a snackbar and are logged.
- Crash reporting uses Firebase Crashlytics and is only enabled after consent.

## 9. Development practices

**Test-driven development is mandatory.** Every behaviour change starts with a failing test (red), then the minimal code to pass it (green), then refactoring. No production code is written without a failing test that needs it. This applies to the engine, repositories, controllers and widgets alike.

**Test layers**
- **`payoff_engine` unit tests.** Hand-verified scenarios with fixed expected outputs. Reference values come from running the legacy Java calculation on a few scenarios; the test comments document the expected differences caused by the bug fixes. There are also property-based tests:
  - balances are never negative
  - `totalPaid == Σ starting balances + totalInterest` (plus the transfer fee for BalanceTransfer)
  - the months are monotonic
  - the payoff order is consistent with the strategy
- **Repository tests** run against an in-memory Drift database.
- **Controller and provider tests** use `ProviderContainer` with overrides.
- **Widget tests** cover each screen's states: empty, loading, data, error, infeasible.
- **Golden tests** cover the plan-detail tabs.
- **One `integration_test`**: onboarding → add debts → compare → open plan → export.

**Tooling**
- Flutter stable and Dart 3.
- `very_good_analysis` lints.
- `build_runner` for freezed, riverpod_generator and drift.
- `intl` with ARB files; English for v1.
- Separate dev and prod flavours, with different app IDs and ad IDs.

**CI:** GitHub Actions runs `dart format --set-exit-if-changed`, `flutter analyze` and `flutter test` (including the `payoff_engine` package) on every PR.

**Release:** manual store submission for v1. Fastlane is deferred.

## 10. Out of scope for v1

- Cloud sync or backup, and accounts.
- New strategies (for example snowball by balance), custom extra payments, reminders, and saved scenarios.
- Paid ad removal or in-app purchases.
- Localisations other than English.
