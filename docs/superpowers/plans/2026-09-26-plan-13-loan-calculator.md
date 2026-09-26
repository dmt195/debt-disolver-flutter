# Plan 13: Loan Calculator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A full-screen loan calculator, opened from the Plans app bar. You choose what to work out (payment, amount, rate or term), fill in the other three, and see the answer with the totals and a balance chart. "Add as a debt" opens the debt form pre-filled.

**Architecture:**
- **The maths:** a pure `solveLoan` (`lib/features/loans/domain/loan_calculator.dart`) maps the chosen unknown and the three inputs onto Plan 11's solvers.
- **The screen:** `LoanCalculatorScreen` (`lib/features/loans/presentation/loan_calculator_screen.dart`) keeps its inputs in local state and recomputes on each edit. The solvers take under 2 ms at worst, so it doesn't debounce.
- **Its parts:** it reuses `RateField`, `HiVisBlock`, `BalanceLineChart` and `displayStyle`.
- **"Add as a debt":** pushes the debt form with a `DebtDraft`, a new route `extra`. The form pre-fills a new Loan from it.

**Tech Stack:** Flutter, go_router (`extra`), Riverpod, `payoff_engine` loan solvers, and the existing chart kit.

**Spec:** `docs/superpowers/specs/2026-09-26-rates-and-loans-design.md` §4 (this plan) and §5. Builds on Plans 11 (solvers) and 12 (`RateField`, `DebtForm`).

## Global Constraints

- The route is `/plans/loan-calculator`, full screen on the root navigator. It's declared before `/plans/:strategyId`, as `scenarios` is.
- The calculator has no ad banner: ads appear only on Debts and Plans.
- Nothing is saved. Leaving the screen clears it.
- Integer money and rates only. Use `double` only to hand chart values to `BalanceLineChart`, in major units, as `plan_series.dart` does.
- Motion: only the chart's `DrawIn`. The reveal doesn't replay while typing: keep the chart at the same tree position, keyed by nothing that changes.
- UI text in `app_en.arb`. Money, percentages and durations are formatted with `formatMoney`, `formatPercent` and `formatDuration`.
- TDD. `dart analyze --fatal-infos` and `dart format lib test` clean. Commits end with the usual two trailer lines.

## Reference values

From the integer-exact model, which agrees with the engine:

| Question | Answer |
|---|---|
| £10,000 at 12.9% over 5 years: payment | £223.43 a month; £13,405.70 repaid; £3,405.70 interest |
| £10,000 at 12.9%, paying £300 a month: term | 41 months (3 years 5 months) |
| £250 a month at 7.9% over 4 years: amount | £10,314.00 (the roundest with exactly that payment) |
| £10,000 over 5 years at £223.43: rate | 12.9% |
| £1,200 at 12%, paying £11.39 | never clears |

## Review Focus

1. **Switching the unknown keeps what was typed** in the other fields. The newly hidden field's value isn't used.
2. **Typing doesn't replay the chart's draw-in.** Switching between a result and a problem and back doesn't crash, and doesn't leave the old chart showing.
3. **Invalid or empty input:** the hero asks for the missing figures ("Fill in the other three"). It never shows a stale answer.
4. **Large text at 360 wide:** the switch with four segments, the hero figure and the totals row.
5. **"Add as a debt"** pre-fills a Loan whose helper would confirm the same figures, and saves nothing until Save.

---

### Task 1: The debt form takes a draft

**Files:**
- Create: `lib/features/debts/domain/debt_draft.dart`
- Modify: `lib/features/debts/presentation/debt_form_screen.dart` (take `DebtDraft? draft`, pre-fill a new debt from it)
- Modify: `lib/app/router.dart` (the `new` route passes `state.extra as DebtDraft?`)
- Test: `test/features/debts/debt_form_test.dart`

**Interfaces (produces):**

```dart
/// A new loan's figures, for the debt form to start from (the loan
/// calculator's "Add as a debt").
class DebtDraft {
  const DebtDraft({
    required this.balance,
    required this.aprBps,
    required this.payment,
    this.lastPaymentYearMonth,
  });
  final Money balance;
  final int aprBps;
  final Money payment;
  final int? lastPaymentYearMonth; // yyyymm
}
```

- `DebtFormScreen({this.debtId, this.draft})`. With a draft, the form opens as a new Loan (`_type = DebtType.loan`):
  - Balance, rate (APR) and Monthly payment are filled in.
  - The Last payment month and year are set from `lastPaymentYearMonth`.
  - Name is empty.
- The router's `new` route becomes `builder: (context, state) => DebtFormScreen(draft: state.extra as DebtDraft?)`.

- [ ] **Step 1: Write the failing test** "a draft opens as a filled-in loan":
  - `pumpApp(tester, location: Routes.debts)`, then `app.container.read(routerProvider).push(Routes.newDebt, extra: DebtDraft(balance: Money(1000000, 'GBP'), aprBps: 1290, payment: Money(22343, 'GBP'), lastPaymentYearMonth: 203109))`, and `pumpAndSettle`.
  - Expect:
    - the `type-loan` tile is selected;
    - Balance reads `10000`, the rate `12.9` and the Monthly payment `223.43`;
    - the Month dropdown shows `September` and the Year `2031`;
    - there's no "Work it out" button, since all four are filled.
  - Enter a name and Save. The stored debt has `balance.minor == 1000000`, `aprBps == 1290`, `minPaymentFloor.minor == 22343` and `type == DebtType.loan`.
- [ ] **Step 2: Run it and watch it fail.**
  - Run: `flutter test test/features/debts/debt_form_test.dart --plain-name "draft"`
  - Expected: FAIL, because `DebtDraft` isn't defined.
- [ ] **Step 3: Implement.** In `_DebtFormState.initState`, when `widget.draft` is set and there's no existing debt:
  - fill `_controllers[_Field.balance]` with `formatAmountInput(draft.balance)`;
  - build the rate controller with `aprBps: draft.aprBps`;
  - fill `_Field.minFloor` with `formatAmountInput(draft.payment)`;
  - set `_type = DebtType.loan`, and `_allowsOverpayment = defaultAllowsOverpayment(DebtType.loan)`;
  - set `_lastYear` and `_lastMonth` from `lastPaymentYearMonth`.
  - Pass `draft` through `DebtFormScreen` → `_DebtForm`.
- [ ] **Step 4: Run it and watch it pass.** Then run the full suite. Commit `feat(debts): the debt form can start from a draft loan`.

### Task 2: `solveLoan`

**Files:**
- Create: `lib/features/loans/domain/loan_calculator.dart`
- Test: `test/features/loans/loan_calculator_test.dart`

**Interfaces (produces):**

```dart
enum LoanUnknown { payment, amount, rate, term }

/// Works out [unknown] from the other three; null while any of them is
/// missing. [months] is the term.
LoanResult? solveLoan({
  required LoanUnknown unknown,
  Money? amount,
  int? aprBps,
  Money? payment,
  int? months,
});

/// The balance after each month, in major units for the chart.
List<double> loanBalanceSeries(LoanSolved loan);
```

- **Mapping:**
  - `payment` → `loanPayment(balance: amount, aprBps, months)`;
  - `amount` → `loanBalance(aprBps, payment, months)`;
  - `rate` → `loanApr(balance: amount, payment, months)`;
  - `term` → `loanMonths(balance: amount, aprBps, payment)`.
- The input matching `unknown` is ignored even if given.
- `loanBalanceSeries` divides each of `loan.balances` by 10^`currencyDecimalDigits`.

- [ ] **Step 1: Write failing tests** using the reference values:
  - payment → £223.43, with `totalPaid` £13,405.70;
  - term → 41 months;
  - amount → £10,314.00;
  - rate → 1290;
  - never clears → `LoanImpossible(neverClears)`;
  - a missing input → null;
  - an ignored input: `unknown: payment` with a payment given still solves from the other three;
  - `loanBalanceSeries` starts at 10000.0, ends at 0.0, and has `months + 1` values.
- [ ] **Step 2: Run them and watch them fail.**
  - Run: `flutter test test/features/loans/loan_calculator_test.dart`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and watch them pass.** Commit `feat(loans): solve a loan for any one unknown`.

### Task 3: The loan calculator screen

**Files:**
- Create: `lib/features/loans/presentation/loan_calculator_screen.dart`
- Modify:
  - `lib/app/router.dart`: add `Routes.loanCalculator = '/plans/loan-calculator'`. Add a `GoRoute(path: 'loan-calculator', parentNavigatorKey: rootKey, builder: …)` under Plans, before `:strategyId`.
  - `lib/features/strategies/presentation/strategies_screen.dart`: an app-bar `IconButton(Icons.calculate_outlined, tooltip: l10n.loanCalculatorTitle)` before the scenarios icon, opening `context.push(Routes.loanCalculator)`.
  - `lib/l10n/app_en.arb`.
- Test: `test/features/loans/loan_calculator_screen_test.dart`

**Layout (spec §4), top to bottom, in a `ListView`:**
1. **The unknown switch:** a `SegmentedButton<LoanUnknown>`, `ValueKey('unknown')`, with segments Payment · Amount · Rate · Term (`calcPayment`, `calcAmount`, `calcRate`, `calcTerm`). It sits under a label, "Work out" (`calcWorkOut`), and defaults to Payment. At 2× text it scrolls sideways: wrap it in a horizontal `SingleChildScrollView`.
2. **The hero:** a `HiVisBlock`, `ValueKey('hero')`.
   - **When solved:** the answer big, in `displayStyle(44)`, with a small caption:
     - payment: `formatMoney(payment)` / "a month" (`calcPerMonth`);
     - amount: `formatMoney(balance)` / "you can borrow" (`calcCanBorrow`);
     - rate: `formatPercent(aprBps)` / "APR" (`calcApr`), with the monthly rate under it (`rateAsMonthly`);
     - term: `formatDuration(l10n, months)` / "to pay it off" (`calcToPayOff`).
   - **When impossible:** the §3.2 message (`loanNeverClears`, `loanRateTooHigh`, `loanRateBelowZero`, `loanOutOfRange`).
   - **When inputs are missing:** "Fill in the other three to see the answer." (`calcFillIn`).
3. **The inputs:** only the three not being worked out, in the order amount, rate, term, payment.
   - Amount: `TextFormField`, `ValueKey('calcAmount')`, labelled "Amount" (`fieldAmount`).
   - Rate: `RateField`, `fieldKey: ValueKey('calcRate')`, with the labels `fieldApr` / `fieldAprMonthly`.
   - Term: a number field, `ValueKey('calcTerm')`, labelled "Term" (`fieldTerm`), with a "years / months" `SegmentedButton<bool>`, `ValueKey('calcTermUnit')`, using `termYears` "years" and `termMonths` "months". It defaults to years.
   - Payment: `TextFormField`, `ValueKey('calcPayment')`, labelled "Monthly payment" (`fieldMonthlyPayment`).
   - Each `onChanged` calls `setState` to recompute.
   - Parsing: `parseAmountMinor` for money (in the app currency, `settingsControllerProvider`), `RateController.aprBps` for the rate, and `parseWholeNumber` for the term (× 12 in years).
4. **When solved:**
   - A row of totals: "Total interest" (`calcTotalInterest`) and "Total repaid" (`calcTotalRepaid`), with `formatMoney` values.
   - `BalanceLineChart(lines: [ChartLine(values: loanBalanceSeries(loan), color: c.ink, width: 3)], semanticLabel: l10n.calcChartLabel(formatMoney(balance), formatDuration(months)), startLabel: this month, endLabel: the last payment month)`. It sits in a `OutlinedCard` titled "How the balance falls" (`calcChartTitle`).
   - Keep the card in the tree whenever solved, so the `DrawIn` state survives typing. Build it in the same position in the list every time. When not solved, show `SizedBox.shrink()` in that slot, not a different widget type.
5. **"Add as a debt":** a `FilledButton` (`calcAddAsDebt`), enabled only when solved. On tap: `context.push(Routes.newDebt, extra: DebtDraft(balance, aprBps, payment, lastPaymentYearMonth: yearMonthAfter(months, now)))`.
6. **No `AdBanner`.**

**ARB keys:**
- **Screen and switch:** `loanCalculatorTitle` "Loan calculator", `calcWorkOut` "Work out", `calcPayment` "Payment", `calcAmount` "Amount", `calcRate` "Rate", `calcTerm` "Term".
- **Inputs:** `fieldAmount` "Amount", `fieldTerm` "Term", `termYears` "years", `termMonths` "months".
- **Captions:** `calcPerMonth` "a month", `calcCanBorrow` "you can borrow", `calcApr` "APR", `calcToPayOff` "to pay it off".
- **Messages and results:** `calcFillIn` "Fill in the other three to see the answer.", `calcTotalInterest` "Total interest", `calcTotalRepaid` "Total repaid", `calcChartTitle` "How the balance falls", `calcChartLabel` "The balance falls from {amount} to nothing over {duration}", `calcAddAsDebt` "Add as a debt".

- [ ] **Step 1: Write failing tests.** Open with `pumpApp(tester, location: Routes.loanCalculator)` and `useTallScreen`:
  - **"opens from Plans":** from `Routes.plans` with a debt, tap the calculator icon (tooltip "Loan calculator"). The location is `/plans/loan-calculator`, and there's no `AdBanner` in the tree.
  - **"works out the payment":** Amount `10000`, rate `12.9`, term `5` (years). The hero shows `£223.43` and "a month". The totals show `£3,405.70` and `£13,405.70`, and a `BalanceLineChart` is shown.
  - **"works out the term":** tap Term; Amount `10000`, rate `12.9`, payment `300`. The hero shows "3 years 5 months".
  - **"works out the amount":** tap Amount; rate `7.9`, term `4`, payment `250`. The hero shows `£10,314.00`.
  - **"works out the rate":** tap Rate; amount `10000`, term `5`, payment `223.43`. The hero shows `12.9%`.
  - **"switching the unknown keeps the other figures":** after "works out the payment", tap Term and enter payment `300`. Amount still reads `10000` and the rate `12.9`, and the hero shows "3 years 5 months".
  - **"asks for the missing figures":** with only an amount, the hero shows "Fill in the other three to see the answer.", and Add as a debt is disabled.
  - **"says when it can't be done":** tap Term; amount `1200`, rate `12`, payment `11.39` → the neverClears message.
  - **"typing doesn't replay the chart":** after a solve, read the `DrawIn`'s reveal factor (as `charts_test.dart` does) and see it reach 1 after `pumpAndSettle`. Change the term to `4` and `pump()` once: the factor is still 1.
  - **"add as a debt opens the form filled in":** after "works out the payment", tap Add as a debt. `DebtFormScreen` shows Balance `10000`, the rate `12.9` and Monthly payment `223.43`, with the `type-loan` tile selected. Nothing is stored yet.
  - **"large text fits":** 360 wide, 2× text, a solved payment → `tester.takeException()` is null.
- [ ] **Step 2: Run them and watch them fail.**
  - Run: `flutter test test/features/loans/loan_calculator_screen_test.dart`
- [ ] **Step 3: Implement** as laid out above.
- [ ] **Step 4: Run them and watch them pass.** Then run the full suite. Commit `feat(loans): the loan calculator`.

### Task 4: Docs and verification

- [ ] **`CLAUDE.md`:**
  - Tick Plan 13.
  - Add a gotcha: "The loan calculator (`lib/features/loans/`) keeps no state beyond the screen. `solveLoan` maps its unknown onto the engine's loan solvers. 'Add as a debt' pushes `Routes.newDebt` with a `DebtDraft` as `extra`."
  - Mark the rates-and-loans spec as done.
- [ ] **Full verification:** `./tool/codegen.sh && dart format lib test && dart analyze --fatal-infos && flutter test && (cd packages/payoff_engine && dart test)`, then `flutter build apk --flavor dev --release --split-per-abi`.
- [ ] **Screenshots:**
  - iOS simulator: `flutter run --route=/plans/loan-calculator` with seeded settings (onboarding complete). Take shots in light and dark, and compare them with the spec.
  - Send the APK to the user.
- [ ] **Commit:** `docs: Plan 13 loan calculator; rates and loans complete`.
