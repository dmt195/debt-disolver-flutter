# Rates and Loans: Design

Builds on the v1, v2 and v3 specs (`2026-09-24-flutter-rebuild-design.md`, `2026-09-24-v2-planning-design.md`, `2026-09-25-v3-ux-redesign-design.md`). Where this spec is silent, they still apply.

## 1. Intent

People should be able to enter their real debts accurately, using the figures they actually have, and try out a loan before taking one.

- **Rates as printed:** statements show an APR, a monthly rate, or both. Either should be enterable, and the app's interest should match what the lender charges.
- **Loans from what you know:** a loan agreement shows the payment, the term and usually the APR; the balance is often unknown. Any three of balance, rate, payment and last payment should give the fourth.
- **"What if I borrowed…":** a loan calculator shows the monthly payment, total interest and total repaid for an amount, rate and term. Any of those can be the unknown, and the result can become a debt.

**What the user decided** (brainstorm, 26 Sep 2026):
- Build the form helper and a standalone calculator, sharing one set of maths.
- APR means the true, compounded UK APR. The engine charges (1 + APR)^(1/12) − 1 each month instead of APR ÷ 12.
- The helper works out whichever of the four loan figures is missing.
- The calculator covers the loan on its own, plus "Add as a debt". Comparing a loan against your plan comes later, if at all.

**Out of scope**
- Comparing a calculator loan against your plan. The consolidation option on Plans stays as it is.
- Saving calculator inputs, or keeping a history of calculations.
- Fees, early-repayment charges, and loans whose rate changes over the term.
- Anything else from the "still missing" list: backup/export-import, lump sums, changing budgets, iOS distribution.

**Unchanged constraints:**
- Money is integer minor units and rates are integer basis points (APR) or parts per million (monthly), with half-even rounding once a month.
- The engine is pure Dart.
- TDD.
- Ads appear only on Debts and Plans.
- Borrowing alternatives are never marked cheapest.

**Success criteria**
- A 25.3% APR card is charged about 1.90% a month (18,973 ppm), not 2.11%.
- A debt can be entered with a monthly rate, and it saves as the equivalent APR.
- Given any three of balance, rate, monthly payment and last payment, the loan helper fills in the fourth, and the plans then clear that loan in the month the helper said.
- The calculator's payment for an amount, rate and term matches what the plans charge for the same loan, to the penny.

## 2. Interest maths (engine)

### 2.1 Monthly rate

- `monthlyRatePpm(int aprBps) → int`: the whole number of parts per million `r` with (1 + r/10⁶)¹² closest to 1 + aprBps/10⁴.
  - Computed with integers only: a binary search over `r`, raising to the 12th power with `BigInt` at fixed precision. No floating point.
  - 0 → 0. Monotonic: a higher APR never gives a lower monthly rate.
  - Reference pairs, pinned in tests:
    - 25.3% → 18,973 (1.90% a month);
    - 100% → 59,463 (5.95% a month);
    - 1.00% a month (10,000 ppm) → 12.68% APR (`aprBpsFromMonthlyPpm(10000) == 1268`).
  - Checked against floating-point references before being pinned.
- `aprBpsFromMonthlyPpm(int ppm) → int`: the inverse, rounded half-even to the nearest basis point. It's used when a monthly rate is entered.
- Memoise the conversion per APR value: the engine asks for the same few rates thousands of times.

### 2.2 Where it applies

Every place the engine charges or estimates interest uses the monthly rate:
- the monthly interest in `simulate` (today `balance × aprBps / 120000`, becomes `balance × ppm / 10⁶`, half-even);
- `fixedLoanPayment` (consolidation);
- promo rates, the revert rate after a promo, transfer offers' promo rates, the consolidation and transfer rates in strategy parameters;
- the ranking estimates in `debt_ordering` and the card-transfer "year saved" screen.

APRs stay stored and validated as basis points (0–100%), so the Drift schema and settings don't change.

### 2.3 Legacy reference figures

`legacy_scenarios_test.dart` and parts of `strategy_test.dart` compare against the 2013 app's figures, which used APR ÷ 12.
- The engine gets a test-only switch, `InterestMode.nominal` (APR ÷ 12). Its default is `InterestMode.compound`.
- The legacy comparisons run in nominal mode, so they keep checking the original bug fixes against the original numbers.
- Every other expected figure is recalculated under compound interest and reviewed. The plan lists each changed expectation with its old and new values.

The app hasn't shipped, so no stored projections or check-in history need converting.

### 2.4 Loan solvers

The four solvers are pure, integer-only functions. Each one simulates a fixed-payment loan with the same monthly interest and rounding as `simulate`.

| Function | Given | Returns |
|---|---|---|
| `loanPayment` | balance, APR, months | the smallest whole payment that clears it in that many months (as `fixedLoanPayment` does today) |
| `loanMonths` | balance, APR, payment | the number of payments to clear it; the last one may be smaller |
| `loanBalance` | APR, payment, months | the largest balance that this payment clears in that many months |
| `loanApr` | balance, payment, months | the APR, in basis points, at which this payment clears the balance in exactly that many months (a binary search) |

Each returns a result or a reason it can't be done:
- **Never clears:** the payment doesn't even cover the first month's interest.
- **Rate too high:** the implied APR is over 100%.
- **Rate below zero:** the payments total less than the balance.
- **Out of range:** longer than the engine's `kMaxMonths`, or amounts over `kMaxAmountMinor`.

Every solver also returns the totals: total repaid and total interest.

## 3. The debt form

### 3.1 The rate field

- **One `RateField` for every rate input:**
  - the debt form's main rate;
  - the promo rate;
  - a transfer offer's promo rate;
  - the rates in `ParameterFields` (Settings and the scenario editor: consolidation rate and revert rate).
- **Switching units:**
  - A two-way switch beside the field: "a year" (APR, the default) or "a month".
  - Under the field, the other form shows live: "= 1.90% a month" or "= 25.3% APR".
  - Switching units converts the number already typed, so the rate doesn't change.
- **Saving:** it always saves APR basis points (a monthly entry goes through `aprBpsFromMonthlyPpm`). Validation stays 0–100% APR.
- **Reopening:** a debt opens in "a year", with the monthly figure shown underneath. The unit isn't remembered.
- **Parsing:** through `money_format.dart`, as today. A monthly rate accepts up to three decimal places.

### 3.2 The loan helper

For debts paid at a fixed monthly payment (`DebtType.loan`, the types where the form asks for "Monthly payment"):
- **The loan section shows four figures together:** balance, rate, monthly payment, and a new **Last payment** month.
  - The Last payment month uses the same month picker as the promo end month. It can't be earlier than next month.
  - Months = months from now until then, using the repository's clock.
- **The button:**
  - With exactly three of the four filled in, a **Work it out** button fills in the fourth using the §2.4 solvers.
  - The filled figure shows a small "Worked out" note and stays editable. Editing any of the four clears the note.
  - With two or fewer filled in, the button is disabled and says "Fill in any three".
  - With all four filled in, it's hidden.
- **Errors** appear on the relevant field, using `forceErrorText` (cleared in `onChanged`, as elsewhere):
  - "This payment never clears the balance at this rate."
  - "That works out above 100% APR. Check the figures."
  - "The payments add up to less than the balance."
- **Saving:** the debt saves balance, APR and payment exactly as today. The Last payment month is only an input; it isn't stored, because the plans already work out when a loan clears and a stored date could disagree after later edits.
- **Editing a saved loan:** the Last payment month starts empty. The other three are filled in, so "Work it out" can show when it would clear.

## 4. The loan calculator

- **Where:** a calculator icon (tooltip "Loan calculator") in the Plans app bar opens `/plans/loan-calculator`, full screen on the root navigator, like Settings. It has no ad banner.
- **Choosing the unknown:** a segmented switch at the top, "Work out: Payment · Amount · Rate · Term". The chosen one is hidden from the inputs.
- **Inputs:**
  - Amount.
  - Rate: the §3.1 `RateField`.
  - Term: a number with a "years / months" switch. Maximum `kMaxMonths`.
  - Monthly payment.
- **Results** update as you type (debounced), with no button:
  - A hi-vis hero block shows the worked-out figure big (`displayStyle`): "£312.40 a month", "£9,850.00", "12.9% APR" or "4 years 2 months".
  - Below it: total interest and total repaid.
  - A `BalanceLineChart` of the balance falling. It draws in once, and the reveal doesn't replay as inputs change.
  - An impossible case replaces the hero with the §2.4 reason, in the §3.2 wording.
- **Add as a debt:** opens the debt form as a new Loan, pre-filled with the balance, APR and payment. The Last payment is filled in too, so the helper can confirm it. Nothing is saved until Save.
- **Memory:** nothing is saved; leaving the screen clears it.
- **Motion:** only the chart's draw-in, and none with reduced motion.

## 5. Testing

- **Engine:**
  - Conversion pairs and monotonicity.
  - Round trips: APR → ppm → APR within 1 basis point.
  - Each solver against hand-checked cases and against each other: loanBalance(loanPayment(b)) ≈ b, and so on.
  - Every impossible case.
  - Nominal mode keeps the legacy figures.
  - The existing invariants tests (money conserved, balances never negative) run under compound interest.
- **App:**
  - `RateField` unit switching and saving.
  - The helper filling each of the four, with each error.
  - A loan filled in by the helper clears in the plans in the month the helper said.
  - The calculator's four modes, impossible cases, "Add as a debt" pre-filling the form, no ad on the screen, and large text at phone width.
- **Review focus:**
  - Rates near 0% and 100%.
  - One-month and `kMaxMonths` terms.
  - Balances of a penny and at `kMaxAmountMinor`.
  - Currencies with 0 and 3 decimal places.
  - Switching units repeatedly without the rate drifting.

## 6. Delivery

Three plans, each shippable on its own:
1. **Engine:** §2, compound interest and the loan solvers. The app picks up the corrected interest with no UI change.
2. **Form:** §3, `RateField` everywhere, and the loan helper.
3. **Calculator:** §4.
