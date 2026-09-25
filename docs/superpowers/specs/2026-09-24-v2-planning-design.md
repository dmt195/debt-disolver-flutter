# Debt Destroyer v2: Better Planning, Design

Date: 2026-09-24
Status: Draft for review
Builds on: `2026-09-24-flutter-rebuild-design.md` (the v1 spec). Where this spec says nothing, v1 still applies.

## 1. Intent

v1 recreated the 2013 app. v2 makes the comparison **more useful and more honest**:
- It adds the strategies people actually look for.
- It models promotional rates and fixed-payment loans.
- It makes balance transfer and consolidation realistic.
- It shows what each plan saves compared with paying only the minimums.

It also adds a "pay more" what-if and saved scenarios.

**In scope**
- Strategies: add snowball, your own order, and a minimum-payments-only baseline; remove lowest APR first and boosted.
- Debt model: more kinds of debt, per-debt promotional rates, fixed-payment loans, and a named "minimums only" option.
- A realistic balance transfer (eligible balances only, credit limit, partial transfers) and consolidation (term, arrangement fee, fixed payment).
- A "pay £X more a month" slider.
- Saved scenarios (what-if settings) and a scenario comparison.

**Out of scope**
- Logging payments, tracking progress, reminders. These get their own spec later.
- One-off lump sums, and budgets that change over time.
- Early-repayment charges, per-debt fees, daily interest.
- Letting users combine strategies (for example "transfer, then snowball").
- Everything already out of scope in v1 §10: sync, accounts, in-app purchases, other languages.

**Unchanged constraints:** local-only data, integer money (minor units and basis points, half-even rounding once a month), `payoff_engine` stays pure Dart, TDD is mandatory, and banners appear only on the Debts and Strategies screens.

**Success criteria**
- v1 users upgrade with their debts and settings intact, and plans with no promos give the same avalanche figures as v1.
- Every plan satisfies `totalPaid == Σ starting balances + totalInterest + totalFees`.
- A user can see, for each strategy, how much it saves compared with paying only the minimums, and can save and compare what-if scenarios.

## 2. Debt model

### 2.1 Kinds of debt

`DebtType` is stored by name, so existing values keep their names: `creditCard`, `loan`, `personal` (shown as "Friends & family"). v2 adds `storeCard` (store card or buy-now-pay-later), `overdraft`, `studentLoan`, `mortgage` and `other`.

The kind decides eligibility and the default for extra payments:

| Kind | Transferable to a card | Consolidatable | Default for extra payments |
|---|---|---|---|
| `creditCard`, `storeCard` | yes | yes | allowed |
| `loan`, `overdraft` | no | yes | allowed |
| `personal`, `other` | no | no | allowed |
| `studentLoan`, `mortgage` | no | no | **minimums only** |

The engine exposes this as `bool isTransferable(DebtType)` and `bool isConsolidatable(DebtType)` in `payoff_engine`.

### 2.2 Minimums only

This is the existing `allowsOverpayment` flag. The form now shows it as a "Minimums only" switch, the reverse of the flag. For student loans and mortgages it defaults to on, with a note: overpaying these is usually not the best use of money, because student loans are income-contingent and written off, and mortgage rates are usually low. The user can override it.

### 2.3 Fixed-payment loans

The engine already supports these: a fixed payment is `minPaymentPercentBps = 0` with `minPaymentFloor = payment`. For `loan` debts the form shows one "Monthly payment" field instead of the percentage and floor fields, and stores it that way. Editing a v1 loan whose percentage is not 0 shows the percentage and floor fields, so existing data is never reinterpreted.

### 2.4 Promotional rates

`Debt` gains an optional `promo: Promo?`:
- `Promo.aprBps`: the rate during the promo (usually 0), 0–10000.
- `Promo.months`: whole months the promo still applies, counting the first simulated month as month 1. It must be at least 1.

Month `m` of a simulation charges `promo.aprBps` if `m <= promo.months`, and `debt.aprBps` otherwise.

**Dates stay out of the engine.** The app stores the promo's last month as a calendar month (`promoEndsYearMonth`, an integer `yyyymm`). At calculation time it converts that to `months = (end − current month) + 1`, where the current month comes from an injectable `clockProvider`. If `months < 1` the promo has expired: the repository reads it as no promo, so the engine and the form never see it, and the next save of that debt clears it.

## 3. Strategies

### 3.1 Lineup

```dart
enum StrategyId { avalanche, snowball, customOrder, consolidation, balanceTransfer, minimumsOnly }
```

| Id | Restructure (§4) | Who receives extra money |
|---|---|---|
| `avalanche` | none | most interest saved **by the end of the plan**, re-ranked every month (§3.2) |
| `snowball` | none | smallest **starting** balance (fixed order) |
| `customOrder` | none | the Debts screen order (`sortIndex`) |
| `consolidation` | eligible debts become one loan | as avalanche |
| `balanceTransfer` | eligible card balances move to a promo card | as avalanche |
| `minimumsOnly` | none | nobody: minimums only, the leftover budget goes unspent |

`lowestAprFirst` and `boosted` are removed. Strategy ids are not stored anywhere; they appear only in labels and in the `/strategies/:strategyId` route, which already redirects an unknown id to the Strategies screen. So no data migration is needed.

`minimumsOnly` is the **baseline**. `standardStrategies(parameters)` returns the five ranked strategies in display order, and `calculateAll` runs them, as in v1. `calculateBaseline(debts, monthlyBudget)` runs `minimumsOnly`.

### 3.2 Ordering rules

- **Current APR** of a debt in month `m` is the rate §2.4 charges in that month.
- Ties are broken by name, then id, as in v1.
- Avalanche, consolidation and transfer re-rank at the start of each month's allocation by **interest saved to the end of the plan**: for the month `h` the plan clears in, a debt's score in month `m` is the sum of its current APR over months `m..h` (`aprMonthsUntil`). A pound paid off a debt keeps saving until the plan ends, so this is what it is worth. Ties go to the higher current APR, then name, then id.
  - A promo that ends well before the plan does counts at its full rate afterwards, so that debt can be paid first even while it is at 0%.
  - A promo that outlasts the plan never charges interest, so that debt gets only its minimum.
- The end month depends on the order, so the calculator first ranks by current APR alone, then re-ranks using the end month found, repeating (at most 4 passes) until the end month stops changing. It keeps the cheapest plan seen (then the quickest), so looking ahead is never worse than ranking by the current APR.
- *Revision (after v2 shipped):* the first version ranked by the current APR alone. That is myopic: with a Visa at 0% for 3 more months then 15.5% and an Amex at 12.7%, it paid the Amex first and cost £2.73 more than paying the Visa first.
- Snowball sorts once by starting balance, ascending. Custom order uses the input list order, and the app passes debts in `sortIndex` order.
- With no promos and no restructure, every rule gives the same order every month, so v1 avalanche figures are unchanged.

### 3.3 Payoff order

`PayoffPlan.debts` is listed in **the order the debts are cleared**. Ties go to the order they were allocated in that month, and debts that never clear go last. `payoffOrder` follows the same order. Columns in `MonthRow` use the same order as `PayoffPlan.debts`.

### 3.4 "Pay more" slider

The slider adds an extra amount to the budget passed to `calculate`. The engine needs no change.

## 4. Engine: restructure, order, simulate

`calculate` becomes three internal stages, each a pure function with its own tests:

1. **`restructure(debts, strategy) → Restructured`**: `{debts, fees: Money, change: PlanChange?}`. It is the identity for avalanche, snowball, custom order and minimums only.
2. **`orderFor(strategy)`**: a function `(debts, month, balances) → allocation order`.
3. **`simulate(restructured, budget, order, allowExtra)`**: the month loop, with no strategy-specific branches. Each month it:
   1. adds interest at each debt's current APR
   2. checks the ceiling (`NeverClears`, as in v1)
   3. works out the minimums (v1 rule) and checks feasibility (`Infeasible`, as in v1)
   4. if `allowExtra` is set, spends what is left in allocation order on debts that allow overpayment, carrying any remainder to the next debt within the month

   `minimumsOnly` runs with `allowExtra = false`.

Validation and the 1,200-month cap are unchanged.

### 4.1 Balance transfer

Its parameters are `feeBps`, `promoMonths`, `revertAprBps` and `creditLimit: Money?` (new).

1. **Candidates:** debts with `isTransferable(type)` and a current APR in month 1 greater than 0. They are sorted by current APR, highest first (ties by name, then id).
2. **Limit:** if `creditLimit` is null, the effective limit is the sum over candidates of `balance + fee(balance)`, so every candidate fits exactly. (A single fee on the total could round a penny below the sum of the per-debt fees and strand the last penny.) The plan records `limitAssumed = true`.
3. **Moving balances**, in candidate order, while the limit has room:
   - The amount moved `x` is the largest whole amount with `x + fee(x) ≤ room`, where `fee(x) = halfEven(x × feeBps / 10000)`. It is found with an integer search, and it is capped at the debt's balance.
   - The debt keeps `balance − x`. If that is 0, the debt is removed from the plan.
   - The card's balance grows by `x + fee(x)`, and `fees` grows by `fee(x)`.
4. **The card** is an ordinary `Debt`:
   - id `kBalanceTransferDebtId`
   - type `creditCard`
   - `aprBps = revertAprBps`, `promo = Promo(aprBps: 0, months: promoMonths)`
   - minimum payment 3% of the balance (`minPaymentPercentBps = 300`) with a floor of 0
   - overpayment allowed

   The card goes first in the restructured list. Its name is a label key the app localises; the engine uses a fixed English fallback.
5. **Nothing moved:** if there are no candidates, or the limit is too small to move anything, the result is `NotApplicable(reason: noTransferableBalances)`.
6. **`PlanChange.transfer`** records `movedFrom: List<(debtId, name, amount)>`, `fee`, `creditLimit`, `limitAssumed` and `promoMonths`.

### 4.2 Consolidation

Its parameters are `aprBps`, `termMonths` (new, default 60, range 6–120) and `feeBps` (new, arrangement fee, default 0, range 0–2000).

1. **Candidates:** every debt with `isConsolidatable(type)`. None → `NotApplicable(reason: nothingToConsolidate)`.
2. **Principal:** `P = Σ candidate balances`, and the fee is `halfEven(P × feeBps / 10000)`. The loan balance is `P + fee`, and `fees` grows by the fee. Candidates are removed from the plan.
3. **Fixed payment:** the smallest whole amount `pay` (in minor units) such that simulating the loan alone clears it within `termMonths`. That simulation uses the engine's own interest and rounding: each month, interest is `halfEven(balance × apr / 120000)`, then the payment is `min(pay, balance)`. A binary search runs between `ceil(balance / term)` and `balance + first month's interest` (which clears the loan in month 1). This is exact integer arithmetic with no floating-point formula.
4. **The loan** is an ordinary `Debt`:
   - id `kConsolidationDebtId`
   - type `loan`
   - `aprBps`
   - `minPaymentPercentBps = 0`, `minPaymentFloor = pay`
   - overpayment allowed (UK consumer credit gives a right to repay early; charges are out of scope)

   It goes first in the restructured list.
5. **`PlanChange.consolidation`** records `replaced: List<(debtId, name, amount)>`, `fee`, `monthlyPayment`, `termMonths` and `aprBps`.
6. If the loan payment plus the other minimums exceed the budget, the result is the usual `Infeasible`.

### 4.3 Results

`PayoffResult` gains `NotApplicable(strategyId, reason)`, where `reason` is `noTransferableBalances` or `nothingToConsolidate`. `PayoffPlan` gains `change: PlanChange?`. `totalFees` includes both the transfer and consolidation fees; fees are never counted as interest.

Everything else in `PayoffPlan` and `MonthRow` keeps its v1 meaning.

## 5. Scenarios and settings

### 5.1 Current settings

`StrategyParameters` gains:
- `consolidationTermMonths` (60)
- `consolidationFeeBps` (0)
- `transferCreditLimit: Money?` (null)

`AppSettings` keeps the budget and parameters. Together they are the **Current** scenario, which always exists, can't be deleted, and is edited on the Settings screen.

The settings JSON gains the keys `consolidationTermMonths`, `consolidationFeeBps` and `transferCreditLimitMinor`. They are read with the defaults above when missing, as the v1 keys are, so v1 settings load unchanged. `SettingsController.setCurrency` rescales `transferCreditLimit` along with the budget.

### 5.2 Saved scenarios

A saved scenario is **what-if settings applied to the one real debt list**. It never holds its own debts.

```dart
@freezed Scenario { String id; String name; Money monthlyBudget; StrategyParameters parameters; DateTime createdAt; }
```

Scenarios are stored in a new Drift table, `scenarios`:
- `id`, `name` (unique, not empty), `createdAt`
- `monthlyBudgetMinor`
- `consolidationAprBps`, `consolidationTermMonths`, `consolidationFeeBps`
- `transferFeeBps`, `promoMonths`, `revertAprBps`, `transferCreditLimitMinor` (nullable)

`ScenarioRepository` provides `watchAll`, `save`, `rename`, `delete`. `DriftDebtRepository.convertAmounts` also rescales `monthlyBudgetMinor` and `transferCreditLimitMinor` in all scenarios, in the same transaction, so debts and scenarios always share one currency.

**Deviation (implementation):** name uniqueness is enforced in the domain (`ScenarioNameError.duplicate`, compared case- and space-insensitively via `name.trim().toLowerCase()`), not by a database `UNIQUE` constraint on the `scenarios` table.

### 5.3 Providers

- `selectedScenarioProvider`: `current`, or a scenario id. It is kept for the session only and resets to `current` on launch.
- `extraPaymentProvider`: the slider amount, for the session only. It resets when the scenario changes.
- `plansProvider`: now derived from the debts, the selected scenario's budget plus the extra, its parameters, and the clock (for promo months). It returns `(ranked, baseline)`, with the ranked list sorted by total cost. `NotApplicable`, `Infeasible` and `NeverClears` sort last, as v1 does for non-feasible results. It still runs in a `compute` isolate. The slider's changes are debounced by 250 ms.
- `scenarioComparisonProvider`: the best feasible ranked plan for each scenario, Current included.

## 6. Screens

**Debt form**
- A picker with all the kinds of debt.
- For `loan`: a "Monthly payment" field (§2.3).
- A "Minimums only" switch with its note (§2.2).
- An optional "Promotional rate" section: promo APR, and an "Until" month picker, from this month up to 10 years ahead (120 months).

**Strategies**, from top to bottom:
1. **Scenario picker**: "Current", then saved scenarios by name. **Deviation (implementation):** the picker is hidden until a scenario has been saved (there is nothing to pick between otherwise), has no "Manage scenarios" item, and the Scenarios screen is opened instead from an app-bar icon on the Strategies screen.
2. **Slider**: "Pay £X more a month", from £0 up to the scenario budget, in 60 steps. Each step is rounded to a round number of major units (1, 2 or 5 × 10ⁿ), so the slider moves by, say, £5 on a £300 budget, and by a sensible amount in currencies with or without decimals. The resulting total is shown.
3. **Baseline line**: "Minimums only: 14 yrs 2 mths · £9,840 interest". If minimums never clear the debts: "Paying only the minimums would never clear these debts". If minimums aren't affordable, the v1 infeasible banner shows instead. Tapping the line opens the baseline's plan detail (`/strategies/minimumsOnly`).
4. **Strategy cards**, as in v1, with the cheapest highlighted. They add:
   - "Saves £X · Y months sooner than minimums only". This is omitted when the baseline doesn't clear, and replaced by "Clears your debts" instead.
   - `NotApplicable` cards, with a one-line reason.
   - The transfer card's "Assumes a £6,200 limit. Set yours", linking to the credit-limit setting of the scenario being viewed.
5. **"Save as scenario"**: shown when the slider is above £0 or Current is selected. It asks for a name and saves `budget + extra` with the selected scenario's parameters.

The banner position is unchanged.

*Revision (after v2 shipped): strategy guidance.* The strategy cards are split into two sections:
- **"Ways to pay off your debts"**: highest interest first, smallest balance first and your order.
- **"Alternatives if you can borrow"**: consolidation and balance transfer. Their note reads: *"These mean taking on new credit. They only help if you stop adding to your debts, and lenders may turn you down if your credit rating is poor."*

Only a way to pay off can be marked **Cheapest**, and the Compare tab's best plan ignores the alternatives too. The app shouldn't nudge people towards more borrowing.

Each card shows its nickname (*The avalanche method*, *The snowball method*) and a "best for" line. Plan detail shows the nickname under the title.

**Scenarios page**, from the picker:
- A list of scenarios with rename, edit and delete. Delete asks for confirmation inside the page, with no system dialog.
- Edit reuses the Settings form's budget and strategy fields.
- A **Compare** tab: one row per scenario, showing its best strategy, time to clear and total interest, with the cheapest marked.
- No ads.

**Plan detail**
- Shows the scenario name.
- The Summary tab's "Payment priority" list becomes "Payoff order" (the order debts are cleared, §3.3).
- The Summary tab gains a "What changes" block for transfer and consolidation plans (§4.1 step 6, §4.2 step 5).
- The CSV and XLSX exports put the scenario name and the "What changes" lines above the schedule.

**Settings:** gains a consolidation term and arrangement fee, and a transfer credit limit (optional; clearing it means "assume enough").

All new text goes in `app_en.arb`. Money and percentages use `money_format.dart`.

## 7. Data migration (schema 1 → 2)

- `debts` gains two nullable columns: `promoAprBps` and `promoEndsYearMonth`.
- The `scenarios` table is created.
- v1 kinds are unchanged. v1 rows get no promo.
- The settings JSON needs no migration (defaults are read in, §5.1).
- `schemaVersion` becomes 2, and the migration is written with Drift's step-by-step API. Run `dart run drift_dev make-migrations`, and commit `drift_schemas/` and the generated migration tests. The tests check that v1 data survives.

## 8. Validation and errors

Validation lives in the domain and is localised:
- **Promo:** APR 0–100%, and the end month is this month or later when saved.
- **Consolidation:** term 6–120 months, fee 0–20%.
- **Credit limit:** greater than 0 when set.
- **Scenario name:** not empty, and unique ignoring case.
- **Slider:** the extra is between 0 and the budget.

`NotApplicable` is shown on its card, not as an error. Repository failures are handled as in v1: a snackbar and a log entry.

## 9. Testing

TDD as in v1 §9. The new or changed tests are:

**Engine**
- **restructure/transfer:**
  - everything moves when there is no limit
  - a partial move at the limit
  - the fee counts against the limit
  - 0%-promo debts are skipped
  - non-card kinds are excluded
  - nothing movable gives `NotApplicable`
- **restructure/consolidation:**
  - only eligible kinds are replaced
  - the fee is added
  - the payment search returns the minimal payment, with an exact expected figure: the loan clears in the term, and a payment 1 minor unit lower does not
  - 0% APR gives `ceil(P / term)`
- **order:**
  - avalanche pays a promo debt first when its promo ends well before the plan does, and last when the promo outlasts the plan
  - snowball uses starting balances
  - custom order keeps the input order
- **simulate:** the promo rate applies for `months`, then the normal APR; `allowExtra = false` pays only the minimums.
- **Regression:** the v1 avalanche, consolidation-free and transfer-free reference scenarios give identical figures. The tests for the removed strategies are deleted.
- **Invariants,** for all six strategies with generated inputs (including promos and limits):
  - `totalPaid == Σ starting + interest + fees`
  - no negative balances
  - months increase
  - the transferred amount plus fees is within the limit
  - the consolidation loan clears within its term when the budget covers the minimums and `allowExtra` is false

**App**
- **Repositories:** scenario CRUD and name uniqueness; `convertAmounts` rescales scenarios and is idempotent; promo columns round-trip.
- **Migration:** the generated v1 → v2 tests.
- **Controllers:**
  - promo-month conversion with a fixed clock, including an expired promo
  - plans recalculate when the scenario or extra changes
  - comparison picks the best plan per scenario
  - `setCurrency` rescales the credit limit
- **Widgets:**
  - debt form: kinds, loan payment field, minimums-only default, promo entry and expiry
  - Strategies: baseline line (normal, never clears), savings text, `NotApplicable` card, assumed-limit note, slider recalculation, Save as scenario
  - Scenarios: rename, edit, delete confirmation, Compare tab
  - Plan detail: the "What changes" block
  - Export: header lines
- **End-to-end widget test** (the repo has no `integration_test/`): with `pumpApp`, add a debt with a promo, compare strategies, move the slider, save a scenario, and open its plan.

## 10. Order of work (for the plan)

1. Engine: the restructure, order and simulate split with no behaviour change (the v1 tests stay green).
2. Engine: promos, the new kinds and eligibility, snowball, custom order, the baseline, and removing the two old strategies.
3. Engine: the realistic transfer and consolidation, `NotApplicable` and `PlanChange`.
4. App: the schema 2 migration, the promo columns, the debt form.
5. App: settings fields, the Strategies screen (baseline, savings, slider).
6. App: scenarios (repository, providers, page, compare), and plan detail and export additions.
