# Plan 12: Rate Field and Loan Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Every rate input can be entered per year (APR) or per month, and always saves the true APR.
- A loan's form works out whichever of balance, rate, monthly payment and last payment is missing.

**Architecture:**
- **Engine:** `loanBalance` returns the roundest balance that gives exactly the payment, as `loanApr` already does for rates, so the helper never shows £5,000.31 for a £5,000 loan.
- **Pure helpers** (unit-tested): monthly-rate formatting and parsing in `money_format.dart`, month arithmetic in `promo_dates.dart`, and a `workOutLoan` function in `lib/features/debts/domain/loan_helper.dart`.
- **`RateController` and `RateField`:**
  - `RateController` extends `TextEditingController` and knows its unit. It gives the APR in basis points whichever unit is showing, and converts the typed number when the unit switches. Switching back without editing restores the exact text, so rates never drift.
  - `RateField` (in `lib/core/widgets/rate_field.dart`) wraps it with a "a year / a month" switch and the converted figure underneath.
- **Where they go:**
  - The debt form uses `RateField` for its three rates.
  - `ParameterFields` uses it for the consolidation and revert rates.
  - The debt form's fixed-payment section gains a Last payment month (Month and Year dropdowns) and a Work it out button.

**Tech Stack:** Flutter, Riverpod 3, `intl`, `payoff_engine` (Plan 11's `monthlyRatePpm`, `aprBpsFromMonthlyPpm` and `loan*` solvers).

**Spec:** `docs/superpowers/specs/2026-09-26-rates-and-loans-design.md` §3 (this plan) and §5. It builds on Plan 11: `loan.dart`, `interest.dart`.

## Global Constraints

- **Integers only:** money is minor units, APR is basis points, and monthly rates are ppm. No `double` except in `formatPercent`'s existing display path.
- **Text:** UI text lives in `lib/l10n/app_en.arb`; run `flutter gen-l10n` (or `./tool/codegen.sh`) after changes.
- **Forced errors** use `forceErrorText`, cleared in the field's `onChanged`, never at the start of Save.
- **Monthly rates** accept up to 3 decimal places, and display up to 3 (1.897%). APR stays at up to 2 (spec §3.1).
- **Last payment** is only an input: nothing about it is stored, and the Drift schema doesn't change.
- **Rules:** TDD; `dart analyze --fatal-infos` and `dart format lib test` clean in the app and the engine.
- **Commits** end with:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01S3YJtSqzzA5Sf6buKinyKC
  ```

## Reference values

From the integer-exact Python model used for Plan 11, which agrees with the engine.

| Input | Value |
|---|---|
| 1.9% a month (19,000 ppm) → APR | 2,534 bps (25.34%) |
| 25.3% APR → monthly | 18,973 ppm, shown "1.897" |
| 1.897% a month (18,970 ppm) → APR | 2,530 bps |
| 19.9% APR → monthly | 15,239 ppm, shown "1.524" |
| 100% APR → monthly | 59,463 ppm (the highest valid, shown "5.946") |
| £5,000.00 at 6.9% over 36 months | £153.69 a month |
| £5,000.00 at 6.9% paying £200.00 | 27 months |
| the balance £153.69 clears at 6.9% in 36 months | largest £5,000.31; roundest with exactly that payment £5,000.00 |
| £1,200.00-loan payment £106.28 at 12% over 12 months → balance | £1,200.00 (it was £1,200.06); exact-payment range £1,199.95–£1,200.06 |
| 0.5% a month (5,000 ppm) → APR | 617 bps |
| 25.34% APR (2,534 bps) → monthly | 19,000 ppm, shown "1.9" |

## Review Focus

1. **Unit switching doesn't drift.**
   - Switching year → month → year without editing restores the exact text.
   - After an edit in month mode, switching converts the new value.
   - Empty or invalid text is left alone when switching.
2. **Saving is always APR bps.**
   - A monthly entry saves `aprBpsFromMonthlyPpm`.
   - A monthly rate above 5.946% (over 100% APR) shows a monthly-worded error on that field.
   - A reopened debt shows APR.
3. **The helper's inputs:**
   - Exactly three filled in (non-empty) enables Work it out. Invalid text in a filled field shows its own validation error, not a solver error.
   - A Last payment this month or earlier can't be picked.
4. **The helper's outputs:**
   - Each `LoanProblem` lands on the right field with the right words.
   - The "Worked out" note clears when any of the four is edited.
5. **Large text at phone width (360, 2×):**
   - the rate field's switch and converted line;
   - the Month and Year dropdowns;
   - the Work it out button.

---

### Task 1: `loanBalance` gives the roundest balance

**Files:**
- Modify: `packages/payoff_engine/lib/src/loan.dart` (`loanBalance`)
- Test: `packages/payoff_engine/test/loan_test.dart`

**Interfaces:** Produces the same `loanBalance` signature. The meaning changes: of all the balances for which `payment` is exactly the payment for `months`, it returns the roundest. That is a multiple of 100,000, 10,000, 1,000 or 100 minor units, tried in that order, and otherwise the middle of the range. If no balance has exactly this payment (the payment is more than needed even for the largest balance), it returns the largest.

- [ ] **Step 1: Write the failing tests.** In `loan_test.dart`, group `loanBalance`:
  - change "the largest balance the payment clears in the term" to "the roundest balance with exactly this payment", expecting `gbp(120000)` (was `gbp(120006)`);
  - add:

```dart
    test('a £5,000 loan reads back as £5,000', () {
      expect(
        solved(loanBalance(aprBps: 690, payment: gbp(15369), months: 36))
            .balance,
        gbp(500000),
      );
    });
```

  In "agree with each other", replace the `loanBalance(...) >= balance` expectation with:

```dart
        final byBalance = solved(
          loanBalance(aprBps: apr, payment: byPayment.payment, months: months),
        );
        expect(
          solved(
            loanPayment(balance: byBalance.balance, aprBps: apr, months: months),
          ).payment,
          byPayment.payment,
        );
```

- [ ] **Step 2: Run to watch it fail.**
  - Run: `cd packages/payoff_engine && dart test test/loan_test.dart`
  - Expected: FAIL: 120006 ≠ 120000, and 500031 ≠ 500000.
- [ ] **Step 3: Implement.** In `loanBalance`, after finding `largest` (today's `low`):
  1. **Clamp the search:** `high` = `min(payment × months, kMaxAmountMinor + 1)`. This also settles Plan 11's deferred 64-bit minor.
  2. **Find the smallest balance with exactly this payment:** the smallest `b` at which `payment − 1` no longer clears within `months`. It's monotone, so use a binary search over `[0, largest]`. If `payment − 1 == 0`, it's 1.
  3. **Choose:** if that smallest balance is greater than `largest`, return `largest`. Otherwise return the roundest in `[smallest, largest]`, using a private `_roundestAmount(low, high)` that tries steps 100000, 10000, 1000, 100 (the first multiple ≥ low that is ≤ high), and otherwise returns the midpoint.
  4. **Keep the checks:** `outOfRange` if the result is outside `_amountOk`.
- [ ] **Step 4: Run to watch it pass.**
  - Run: `dart test test/loan_test.dart`, then `dart test`.
  - Expected: all pass.
- [ ] **Step 5: Commit** `fix(engine): loanBalance gives the roundest balance for the payment`.

### Task 2: Monthly-rate text and month arithmetic

**Files:**
- Modify: `lib/core/money_format.dart`
- Modify: `lib/features/debts/domain/promo_dates.dart`
- Test: `test/core/money_format_test.dart`, `test/features/debts/promo_dates_test.dart`

**Interfaces (produces):**
- `String formatMonthlyRateInput(int ppm, String locale)`: ppm → percent with up to 3 decimals, half-even on the 4th. 18973 → `1.897`; 19000 → `1.9`; 0 → `0`.
- `String formatMonthlyRate(int ppm, String locale)`: the same, as a display percentage: `1.897%`.
- `int? parseMonthlyRatePpm(String text, String locale)`: `_parseScaled(maxFractionDigits: 3, allowGrouping: false)` × 10. `1.9` → 19000; `1.8975` → null (4 decimals).
- `int monthsUntil(int yearMonth, DateTime now)`: `_index(yearMonth) − _index(yearMonthOf(now))`. Next month → 1, this month → 0.
- `int yearMonthAfter(int months, DateTime now)`: the `yyyymm` that is `months` after now's month. With 12 from Sep 2026 → 202709.

- [ ] **Step 1: Write failing tests** for each function, with the values above:
  - `formatMonthlyRateInput(15239, 'en_GB') == '1.524'`;
  - `formatMonthlyRateInput(59463, 'en_GB') == '5.946'`;
  - `parseMonthlyRatePpm('1,9', 'de_DE') == 19000`;
  - `parseMonthlyRatePpm('', 'en_GB') == null`;
  - `monthsUntil(202609, DateTime(2026, 9, 24)) == 0`;
  - `yearMonthAfter(4, DateTime(2026, 9, 24)) == 202701`.
- [ ] **Step 2: Run to watch them fail.**
  - Run: `flutter test test/core/money_format_test.dart test/features/debts/promo_dates_test.dart`
  - Expected: FAIL, the functions aren't defined.
- [ ] **Step 3: Implement.**
  - Formatting: `divideHalfEven(ppm, 10)` gives thousandths of a percent. Then use `_plainNumber(value, digits: 3, locale: locale)` for input, and `NumberFormat.percentPattern(locale)..maximumFractionDigits = 3` on `value / 100000` for display.
  - Add `yearMonthAfter` and `monthsUntil` next to `promoEndYearMonth`, using the private `_index`. `yearMonthAfter(m, now) = promoEndYearMonth(m + 1, now)`.
- [ ] **Step 4: Run to watch them pass.** Then commit `feat: monthly-rate text and month arithmetic`.

### Task 3: `RateController` and `RateField`

**Files:**
- Create: `lib/core/widgets/rate_field.dart`
- Modify: `lib/l10n/app_en.arb`
- Test: `test/core/rate_field_test.dart`

**Interfaces (produces):**

```dart
enum RateUnit { year, month }

class RateController extends TextEditingController {
  RateController({int? aprBps, required String locale});
  RateUnit get unit;
  /// The typed rate as APR basis points, whichever unit is showing; null if
  /// the text isn't a rate.
  int? aprBps(String locale);
  /// Shows the rate in [to], converting the typed number; switching back
  /// before any edit restores the exact earlier text.
  void switchTo(RateUnit to, String locale);
  /// Replaces the text with [aprBps] in the current unit (used by the loan
  /// helper).
  void setAprBps(int aprBps, String locale);
}

class RateField extends ConsumerWidget {
  const RateField({
    required this.controller,
    required this.aprLabel,       // e.g. l10n.fieldApr
    required this.monthlyLabel,   // e.g. l10n.fieldAprMonthly
    required this.fieldKey,       // the TextFormField's key (tests find it)
    this.required = true,
    this.forceErrorText,
    this.helperText,              // e.g. "Worked out" from the loan helper
    this.onChanged,
    super.key,
  });
}
```

- **Behaviour:**
  - The `TextFormField`, labelled `aprLabel` or `monthlyLabel` by unit.
  - Below it, a `Wrap` holds the converted figure and a compact `SegmentedButton<RateUnit>` with segments "a year" / "a month", keyed `ValueKey('$fieldKey-unit')`.
  - The converted figure reads "= 1.897% a month" (`rateAsMonthly`) in year mode, or "= 25.34% APR" (`rateAsApr`) in month mode. It's empty while the text isn't a rate.
  - The validator is the field's own:
    - empty and required → `errorInvalidRate` with an example in the current unit ("Enter a rate, e.g. 19.9" / "… e.g. 1.9");
    - above 100% APR → in year mode `errorRateRange`, in month mode `errorRateRangeMonthly` ("That's more than 100% APR. Enter up to 5.946% a month.").
- **ARB keys:**
  - `rateUnitYear` "a year", `rateUnitMonth` "a month";
  - `rateAsMonthly` "= {rate} a month", `rateAsApr` "= {rate} APR";
  - `errorInvalidRate` "Enter a rate, e.g. {example}", `errorRateRangeMonthly` "That's more than 100% APR. Enter up to {max} a month.";
  - `fieldAprMonthly` "Interest rate (% a month)", `fieldPromoAprMonthly` "Promotional rate (% a month)", `fieldOfferPromoAprMonthly` "Offer rate (% a month)";
  - `settingsConsolidationAprMonthly` "Loan interest rate (% a month)", `settingsRevertAprMonthly` "Interest rate afterwards (% a month)".

- [ ] **Step 1: Write the failing test** `test/core/rate_field_test.dart`. Host the field in a `MaterialApp` with the app theme, localizations and a `ProviderScope` (as `plan_schedule_table_test.dart` does), inside a `Form`. The tests:
  - **Opens in APR:** `RateController(aprBps: 2530, locale: 'en_GB')` shows `25.3`, `unit == year`, and the converted line reads `= 1.897% a month`.
  - **Switching converts, and switching back restores:** tap "a month"; the text is `1.897` and the label is the monthly one. Tap "a year"; the text is `25.3`, not `25.296`.
  - **An edit in month mode is converted on the way back:** enter `1.9` in month mode; `aprBps == 2534`. Switch to year; the text is `25.34`.
  - **Empty or invalid text is left alone:** type `abc`, switch; it's still `abc` and `aprBps` is null.
  - **Validation:**
    - in month mode, `6` → `errorRateRangeMonthly` text;
    - `abc` → `Enter a rate, e.g. 1.9`;
    - in year mode, `abc` → `Enter a rate, e.g. 19.9`.
  - **`setAprBps(1268)`** in month mode shows `1`; in year mode, `12.68`.
  - **Large text:** at 360 wide and 2× text, no overflow.
- [ ] **Step 2: Run to watch it fail.**
  - Run: `flutter test test/core/rate_field_test.dart`
  - Expected: FAIL, the names aren't defined.
- [ ] **Step 3: Implement.**
  - `RateController` stores `_unit` and a `_restore` record of (unit, text) taken at each switch. It clears `_restore` when the text changes other than by a switch: override the `value` setter, or add a listener that compares with the text set at the switch.
  - `switchTo`:
    - if `_restore` is for `to` and the text hasn't changed since, restore that text;
    - otherwise parse in the current unit; if that works, set the text in the new unit (year → `formatMonthlyRateInput(monthlyRatePpm(bps))`, month → `formatPercentInput(aprBpsFromMonthlyPpm(ppm))`);
    - then record `_restore = (fromUnit, oldText)`.
  - `RateField` rebuilds on the controller (use `ListenableBuilder`) for the label and the converted line.
- [ ] **Step 4: Run to watch it pass.** Then `flutter test`. Commit `feat: rate field — enter a rate per year or per month`.

### Task 4: Rate fields in the debt form and parameters

**Files:**
- Modify: `lib/features/debts/presentation/debt_form_screen.dart` (`_Field.apr`, `promoApr`, `offerPromoApr` become `RateController`s shown with `RateField`; `_save` reads `aprBps`; `_showErrors` words the range error by unit)
- Modify: `lib/features/settings/presentation/parameter_fields.dart` (`consolidationApr` and `revertApr` become `RateController`s shown with `RateField`; `parse` reads `aprBps`)
- Test: `test/features/debts/debt_form_test.dart`, `test/features/settings/settings_screen_test.dart` (or wherever the parameter fields are tested: `grep -rl ParameterField test`)

**Interfaces:** Consumes Task 3. Field keys stay `ValueKey(_Field.apr)` etc. and `ValueKey(ParameterField.consolidationApr)`, so existing finders keep working. The APR labels are unchanged.

- [ ] **Step 1: Write failing tests.**
  - `debt_form_test.dart`:
    - **"a rate entered per month saves as its APR":** fill the form, tap `a month` under the rate (`find.byKey(ValueKey('${_Field.apr}-unit'))` descendant text `a month`), enter `1.9` in "Interest rate (% a month)", Save. The stored `aprBps` is 2534.
    - **"reopening shows the APR":** edit a debt stored at 2534; the rate field shows `25.34` and the converted line `= 1.9% a month`.
    - **"over 100% APR per month is refused on the field":** a monthly `6` shows "That's more than 100% APR. Enter up to 5.946% a month."
  - Settings test: **"the consolidation rate can be entered per month":** switch its unit, enter `0.5`, save. `consolidationAprBps == 617` (`aprBpsFromMonthlyPpm(5000)`).
- [ ] **Step 2: Run to watch them fail.**
- [ ] **Step 3: Implement.**
  - **The debt form:** in `_controllers`, create `RateController(aprBps: d?.aprBps, locale: locale)` for `_Field.apr` (empty for a new debt), and likewise for `promoApr` (default 0) and `offerPromoApr`.
  - **Building the form:** where it builds these three fields, use `RateField(controller: _controllers[f]! as RateController, fieldKey: ValueKey(f), aprLabel: …, monthlyLabel: …, forceErrorText: _errors[f], onChanged: …clear error…)`.
  - **`_save`:** `rate(_Field f) => (_controllers[f]! as RateController).aprBps(locale) ?? 0`.
  - **`_showErrors`:** for `aprOutOfRange`, `promoAprOutOfRange` and `offerPromoAprOutOfRange`, choose the message by that controller's unit.
  - **`ParameterFields`:** the same for its two rate fields. Keep the percent validator for the fee fields.
- [ ] **Step 4: Run to watch them pass.**
  - Run: `flutter test test/features/debts test/features/settings test/features/scenarios`
  - Then the full suite. Commit `feat: rates per year or per month in the debt form and parameters`.

### Task 5: The loan helper's logic

**Files:**
- Create: `lib/features/debts/domain/loan_helper.dart`
- Test: `test/features/debts/loan_helper_test.dart`

**Interfaces (produces):**

```dart
enum LoanFigure { balance, rate, payment, lastPayment }

/// What the loan helper worked out: the missing figure's new value (one of
/// the four set, the rest null), or the problem.
sealed class LoanWorkedOut { const LoanWorkedOut(); }
final class LoanFilled extends LoanWorkedOut {
  const LoanFilled(this.figure, {this.balance, this.aprBps, this.payment, this.lastPaymentYearMonth});
  final LoanFigure figure;
  final Money? balance; final int? aprBps; final Money? payment; final int? lastPaymentYearMonth;
}
final class LoanNotPossible extends LoanWorkedOut {
  const LoanNotPossible(this.figure, this.problem);
  final LoanFigure figure;   // the field the message belongs on
  final LoanProblem problem;
}

/// The one missing figure of balance, APR, payment and last payment
/// (yyyymm), worked out from the other three; null unless exactly one is
/// missing.
LoanWorkedOut? workOutLoan({
  Money? balance,
  int? aprBps,
  Money? payment,
  int? lastPaymentYearMonth,
  required DateTime now,
});
```

- **Behaviour:**
  - months = `monthsUntil(lastPaymentYearMonth, now)`; a value < 1 is `LoanNotPossible(lastPayment, outOfRange)`.
  - Balance missing → `loanBalance`; rate → `loanApr`; payment → `loanPayment`; last payment → `loanMonths`, then `yearMonthAfter(months, now)`.
  - Where each problem goes:
    - `neverClears` → payment;
    - `rateTooHigh` → rate;
    - `rateBelowZero` → payment;
    - `outOfRange` → the missing figure's field.

- [ ] **Step 1: Write failing tests.** With `now = DateTime(2026, 9, 24)` and GBP:
  - payment missing: £5,000.00, 690, last payment 202909 (36 months) → `LoanFilled(payment, payment: £153.69)`;
  - last payment missing: £5,000.00, 690, £200.00 → `lastPaymentYearMonth: 202812` (27 months after Sep 2026);
  - balance missing: 690, £153.69, 202909 → £5,000.00;
  - rate missing: £5,000.00, £153.69, 202909 → 690;
  - two missing → null; none missing → null;
  - £1,200.00, 1200, £11.39, missing last payment → `LoanNotPossible(payment, neverClears)`;
  - last payment 202609 (this month) with the rate missing → `LoanNotPossible(lastPayment, outOfRange)`;
  - £1,200.00, £99.99 over 12 months (202709), rate missing → `LoanNotPossible(payment, rateBelowZero)`.
- [ ] **Step 2: Run to watch them fail.**
  - Run: `flutter test test/features/debts/loan_helper_test.dart`
- [ ] **Step 3: Implement** the function as specified.
- [ ] **Step 4: Run to watch them pass.** Commit `feat(debts): work out a loan's missing figure`.

### Task 6: The loan helper in the form

**Files:**
- Modify: `lib/features/debts/presentation/debt_form_screen.dart`
- Modify: `lib/l10n/app_en.arb`
- Test: `test/features/debts/debt_form_test.dart`

**Behaviour** (spec §3.2), shown only when `_fixedPayment`:
- **Fields:**
  - After the monthly payment field: **Last payment**, as two dropdowns in a `Wrap`.
    - Month is `ValueKey('lastPaymentMonth')`: January–December, with the hint "Month".
    - Year is `ValueKey('lastPaymentYear')`: this year to this year + 100, with the hint "Year".
    - Both start empty. A picked pair earlier than next month is refused with `loanLastPaymentTooSoon` on the Year dropdown ("Pick a month after this one").
  - Below them, a hint `loanHelperHint`: "Know three of these? Work out the fourth."
- **The button:** an `OutlinedButton` labelled `loanWorkItOut` "Work it out", keyed `ValueKey('workItOut')`.
  - Enabled when exactly three of balance, rate, payment and last payment are non-empty (last payment counts only when both month and year are picked).
  - Otherwise disabled, with the label `loanFillAnyThree` "Fill in any three".
  - Hidden when all four are filled.
- **Tapping it:**
  - First validate the three filled fields with their own validators. If any fail, stop.
  - Then call `workOutLoan`.
  - **`LoanFilled`:** write the figure into its field, and set `_workedOut = figure`, which shows the helper text `loanWorkedOut` "Worked out" on that field. The rate uses `setAprBps`, in the current unit. Last payment sets both dropdowns.
  - **`LoanNotPossible`:** put the message in `_errors` for that field. The messages:
    - `loanNeverClears` "This payment never clears the balance at this rate.";
    - `loanRateTooHigh` "That works out above 100% APR. Check the figures.";
    - `loanRateBelowZero` "The payments add up to less than the balance.";
    - `loanOutOfRange` "That works out beyond what the app can plan. Check the figures.".
  - Last payment errors show on the Year dropdown, via `forceErrorText`.
- **Editing:** changing any of the four clears `_workedOut`, and that field's forced error, in its `onChanged`.
- **Saving:** nothing about last payment is saved. Balance, APR and payment save as before.

- [ ] **Step 1: Write failing tests.** Use a new Loan: tap the `type-loan` tile; the Name field is required, so fill it.
  - **"works out the monthly payment":** balance `5000`, rate `6.9`, Last payment September 2029 → Work it out. The payment field reads `153.69` with "Worked out" under it.
  - **"works out when it ends":** balance, rate, payment `200`. The dropdowns read December 2028.
  - **"works out the balance"** → `5000`. **"works out the rate"** → `6.9`.
  - **"asks for three":** with two filled, the button reads "Fill in any three" and is disabled. With all four filled, there's no button.
  - **"a payment too small never clears":** `1200`, `12`, `11.39` → the payment field shows the neverClears message.
  - **"editing clears Worked out".**
  - **"cards don't get the helper":** no `lastPaymentMonth` for a credit card.
  - **"the loan it saves clears when it said":** work out the payment for Sep 2029 and save. Home's "Debt-free by" shows September 2029: `pumpApp` clock 24 Sep 2026, budget large enough; open `Routes.home` after saving.
  - **Large text:** 360 wide at 2× with the loan section open: no overflow.
- [ ] **Step 2: Run to watch them fail.**
  - Run: `flutter test test/features/debts/debt_form_test.dart`
- [ ] **Step 3: Implement** as described. Keep the fixed-payment section's four inputs and the button together, in the order balance, rate, payment, last payment, then the button.
  - Balance and rate are already above the payment field, so the Last payment row and the button go straight after the payment field.
- [ ] **Step 4: Run to watch them pass.** Then run the full suite. Commit `feat(debts): the loan helper — work out a loan's missing figure`.

### Task 7: Docs and verification

- [ ] **`CLAUDE.md`:**
  - Tick Plan 12.
  - Gotcha: "Rates are entered through `RateField` (`lib/core/widgets/rate_field.dart`) and its `RateController`: per year or per month, always read with `aprBps(locale)`, never `parsePercentBps` on the text. The loan helper's logic is `workOutLoan` (`lib/features/debts/domain/loan_helper.dart`); last payment is an input only, never stored."
- [ ] **Full verification:** `./tool/codegen.sh && dart format lib test && dart analyze --fatal-infos && flutter test && (cd packages/payoff_engine && dart test)`, plus `flutter build apk --flavor dev --release --split-per-abi`.
- [ ] **Device check:** install on the Android emulator. Add a loan with the helper, and switch a rate to monthly. Take screenshots.
- [ ] **Commit** `docs: Plan 12 rate field and loan helper`.
