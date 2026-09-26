# Plan 11: Compound Interest and Loan Solvers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `payoff_engine` charge interest at the true monthly rate implied by a (compounded) APR, and add four integer-only loan solvers.

**Architecture:**
- **Conversion:** a new `interest.dart` converts APR basis points to a monthly rate in parts per million, and back. Both directions use exact `BigInt` arithmetic, and the forward direction is memoised.
- **Interest function:** `interest.dart` also hands out the monthly-interest function for the current `InterestMode`. The mode is a zone value, `InterestMode.compound` unless a test runs code inside `runWithInterestMode(InterestMode.nominal, …)`. Nominal mode is APR ÷ 12, the 2013 app's maths.
- **Where it's used:** `simulate` and `fixedLoanPayment` charge interest through that function. The ranking estimates use monthly rates directly.
- **Loans:** a new `loan.dart` holds the four solvers, all built on one fixed-payment simulation.

**Tech Stack:** pure Dart (`dart:async` zones, `BigInt`), `package:test`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-26-rates-and-loans-design.md`, §2 (this plan), §5 (testing). §3 and §4 are later plans.

## Global Constraints

- Money is integer minor units. Rates are integer basis points (APR) or parts per million (monthly). Rounding is half-even, once a month. No `double` anywhere in `lib/`.
- `payoff_engine` stays pure Dart: no Flutter imports.
- APRs stay stored and validated as basis points, 0–100%.
- TDD: a failing test first, every time.
- `dart analyze --fatal-infos` and `dart format lib test` must be clean, in both `packages/payoff_engine` and the app.
- Every commit ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01S3YJtSqzzA5Sf6buKinyKC
  ```

## Reference values

Computed with an independent, integer-exact Python model of the functions below, and checked against floating point for every APR from 0 to 10,000 bps (identical, round trip exact). Use them as given.

| Input | Value |
|---|---|
| `monthlyRatePpm(0)` | 0 |
| `monthlyRatePpm(1)` | 8 |
| `monthlyRatePpm(600)` | 4,868 |
| `monthlyRatePpm(1200)` | 9,489 |
| `monthlyRatePpm(1268)` | 9,998 |
| `monthlyRatePpm(2530)` | 18,973 |
| `monthlyRatePpm(3000)` | 22,104 |
| `monthlyRatePpm(10000)` | 59,463 |
| `aprBpsFromMonthlyPpm(10000)` | 1,268 |
| 1,200.00 at 12%, month-1 interest / closing after 100.00 / month-2 interest | 11.39 / 1,111.39 / 10.55 |
| `fixedLoanPayment(120000, 1200, 12)` | 10,628 |
| `fixedLoanPayment(500000, 600, 60)` | 9,630 |
| `fixedLoanPayment(6000000000000, 10000, 120)` | 357,126,760,330 |
| 1,200.00 at 12% after a 2-month 0% promo, paying 100.00: interest in months 3 and 4 | 9.49, 8.63 |
| paying 106.28 on 1,200.00 at 12% | 12 months, 1,275.30 repaid |
| paying 100.00 on 1,200.00 at 12% | 13 months, 1,280.12 repaid |
| largest balance 106.28 a month clears in 12 months at 12% | 1,200.06 |
| highest APR at which 106.28 a month clears 1,200.00 in 12 months | 1,201 bps |
| paying 11.40 on 1,200.00 at 12% | 720 months |
| paying 2.97 on 1,200.00 at 3% (2.96 first interest) | 2,311 months (beyond `kMaxMonths`) |
| `loanPayment` for (100, 0%, 1), (1,200.00, 12%, 12), (25,000.00, 29.9%, 60), (99,999.99, 100%, 120), (500.00, 0.01%, 1200) | 100, 10,628, 755.14, 5,952.12, 0.42 (the last clears in 1,191 months); none of these payments would also clear at 100.01% |

## Review Focus

1. **The zone:** code that reads the mode outside a `runWithInterestMode` zone must get compound. Nested zones take the innermost mode.
2. **Overflow:**
   - `balance × ppm` at the 10¹³ balance ceiling and 100% APR is about 6×10¹⁷, inside 64-bit.
   - The solvers must use the same ceiling rule as `fixedLoanPayment`: once the balance passes the ceiling, the payment can't clear.
3. **Boundaries:**
   - APR 0%.
   - APR exactly 100%: allowed. It's "rate too high" only if the payment would also clear above 100%.
   - A one-month term.
   - `kMaxMonths`.
   - A one-penny balance.
   - A payment exactly equal to the first month's interest: never clears.
4. **Solvers agree with the plans:** a loan entered with `loanPayment`'s payment clears in `calculate` in the same number of months.
5. **Only the rate formula changed:** every existing test that failed on the switch must pass unchanged in nominal mode before its compound figures are accepted.

---

### Task 1: Monthly rates and the interest mode

**Files:**
- Create: `packages/payoff_engine/lib/src/interest.dart`
- Modify: `packages/payoff_engine/lib/payoff_engine.dart` (export it)
- Test: `packages/payoff_engine/test/interest_test.dart`

**Interfaces:**
- Produces:
  - `enum InterestMode { compound, nominal }`
  - `R runWithInterestMode<R>(InterestMode mode, R Function() body)`
  - `InterestMode get currentInterestMode`
  - `int monthlyRatePpm(int aprBps)`
  - `int aprBpsFromMonthlyPpm(int ppm)`
  - `typedef MonthlyInterest = int Function(int balanceMinor, int aprBps)`
  - `MonthlyInterest monthlyInterest([InterestMode? mode])`: for the given mode, or the current one when null.

- [ ] **Step 1: Write the failing test** `test/interest_test.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

void main() {
  group('monthlyRatePpm', () {
    test('pinned values', () {
      expect(monthlyRatePpm(0), 0);
      expect(monthlyRatePpm(1), 8);
      expect(monthlyRatePpm(600), 4868);
      expect(monthlyRatePpm(1200), 9489);
      expect(monthlyRatePpm(1268), 9998);
      expect(monthlyRatePpm(2530), 18973);
      expect(monthlyRatePpm(3000), 22104);
      expect(monthlyRatePpm(10000), 59463);
    });

    test('never falls as the APR rises', () {
      var previous = 0;
      for (var bps = 0; bps <= 10000; bps++) {
        final ppm = monthlyRatePpm(bps);
        expect(ppm, greaterThanOrEqualTo(previous), reason: '$bps');
        previous = ppm;
      }
    });

    test('rejects a negative APR', () {
      expect(() => monthlyRatePpm(-1), throwsArgumentError);
    });
  });

  group('aprBpsFromMonthlyPpm', () {
    test('1% a month is 12.68% APR', () {
      expect(aprBpsFromMonthlyPpm(10000), 1268);
      expect(aprBpsFromMonthlyPpm(0), 0);
    });

    test('round-trips every APR exactly', () {
      for (var bps = 0; bps <= 10000; bps++) {
        expect(aprBpsFromMonthlyPpm(monthlyRatePpm(bps)), bps, reason: '$bps');
      }
    });

    test('rejects a negative rate', () {
      expect(() => aprBpsFromMonthlyPpm(-1), throwsArgumentError);
    });
  });

  group('interest mode', () {
    test('compound outside any zone', () {
      expect(currentInterestMode, InterestMode.compound);
      expect(monthlyInterest()(120000, 1200), 1139);
    });

    test('nominal inside its zone, innermost wins', () {
      runWithInterestMode(InterestMode.nominal, () {
        expect(currentInterestMode, InterestMode.nominal);
        expect(monthlyInterest()(120000, 1200), 1200);
        runWithInterestMode(InterestMode.compound, () {
          expect(monthlyInterest()(120000, 1200), 1139);
        });
      });
    });

    test('rounds half-even', () {
      // 12% nominal: 1% a month. 50 × 1% = 0.5 → 0; 150 × 1% = 1.5 → 2.
      final nominal = monthlyInterest(InterestMode.nominal);
      expect(nominal(50, 1200), 0);
      expect(nominal(150, 1200), 2);
    });

    test('stays in 64-bit at the balance ceiling and 100% APR', () {
      expect(
        monthlyInterest()(kBalanceCeilingMinor, 10000),
        594630000000, // 10^13 × 59,463 / 10^6
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to watch it fail.**
  - Run: `cd packages/payoff_engine && dart test test/interest_test.dart`
  - Expected: FAIL, a compile error: `monthlyRatePpm` isn't defined.

- [ ] **Step 3: Implement** `lib/src/interest.dart`:

```dart
import 'dart:async';

import 'package:payoff_engine/src/rounding.dart';

/// How a debt's APR becomes a monthly charge.
enum InterestMode {
  /// The APR is the true, compounded UK APR: each month charges
  /// (1 + APR)^(1/12) − 1 (spec §2.1). The engine's default.
  compound,

  /// APR ÷ 12, as the 2013 app did. Only for tests that check the legacy
  /// app's own figures.
  nominal,
}

const _modeKey = #payoffEngineInterestMode;

/// Runs [body] with interest charged the [mode] way.
R runWithInterestMode<R>(InterestMode mode, R Function() body) =>
    runZoned(body, zoneValues: {_modeKey: mode});

/// The mode for the code running now: compound unless inside
/// [runWithInterestMode].
InterestMode get currentInterestMode =>
    Zone.current[_modeKey] as InterestMode? ?? InterestMode.compound;

final _million = BigInt.from(1000000);
final _bps = BigInt.from(10000);
final _tenTo72 = BigInt.from(10).pow(72);
final _ppmByApr = <int, int>{};

/// (1 + ppm/10⁶)¹², scaled by 10⁷⁶ (10⁷² for the power, 10⁴ for basis
/// points).
BigInt _yearFactor(int ppm) =>
    (_million + BigInt.from(ppm)).pow(12) * _bps;

/// The monthly rate, in parts per million, that compounds to [aprBps] over
/// twelve months: the whole number whose twelfth power is closest (ties go
/// to the lower rate). Exact integer arithmetic; memoised.
int monthlyRatePpm(int aprBps) {
  if (aprBps < 0) {
    throw ArgumentError.value(aprBps, 'aprBps', 'must be >= 0');
  }
  return _ppmByApr[aprBps] ??= _solvePpm(aprBps);
}

int _solvePpm(int aprBps) {
  final target = BigInt.from(10000 + aprBps) * _tenTo72;
  // 100% a month (1,000,000 ppm) compounds to 409,500% APR: far beyond
  // anything valid.
  var low = 0;
  var high = 1000000;
  while (low < high) {
    final mid = low + (high - low) ~/ 2;
    if (_yearFactor(mid) >= target) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  if (low > 0 &&
      target - _yearFactor(low - 1) <= _yearFactor(low) - target) {
    return low - 1;
  }
  return low;
}

/// The APR, in basis points (half-even), that a monthly rate of [ppm]
/// compounds to.
int aprBpsFromMonthlyPpm(int ppm) {
  if (ppm < 0) throw ArgumentError.value(ppm, 'ppm', 'must be >= 0');
  final numerator = _yearFactor(ppm) - _bps * _tenTo72;
  final quotient = numerator ~/ _tenTo72;
  final twice = (numerator % _tenTo72) * BigInt.two;
  final roundUp = twice > _tenTo72 || (twice == _tenTo72 && quotient.isOdd);
  return (roundUp ? quotient + BigInt.one : quotient).toInt();
}

/// One month's interest on a balance at an APR, in minor units.
typedef MonthlyInterest = int Function(int balanceMinor, int aprBps);

/// The monthly interest for [mode] (the current mode when null). Read it
/// once per calculation, not per month: looking up the zone isn't free.
MonthlyInterest monthlyInterest([InterestMode? mode]) =>
    switch (mode ?? currentInterestMode) {
      InterestMode.compound => (balance, apr) =>
          divideHalfEven(balance * monthlyRatePpm(apr), 1000000),
      InterestMode.nominal => (balance, apr) =>
          divideHalfEven(balance * apr, 120000),
    };
```

  Add `export 'src/interest.dart';` to `lib/payoff_engine.dart`, in alphabetical order after `fixed_loan_payment.dart`.

- [ ] **Step 4: Run the test to watch it pass.**
  - Run: `dart test test/interest_test.dart`
  - Expected: PASS, 11 tests.
  - The kBalanceCeiling test needs `kBalanceCeilingMinor` exported from `simulate.dart`, which it already is.

- [ ] **Step 5: Analyze, format, commit.**

```bash
dart format lib test && dart analyze --fatal-infos
git add lib/src/interest.dart lib/payoff_engine.dart test/interest_test.dart
git commit -m "feat(engine): monthly rates from compounded APRs, and a test-only nominal mode"
```

### Task 2: Charge compound interest everywhere

**Files:**
- Modify: `packages/payoff_engine/lib/src/simulate.dart` (monthly interest, around lines 86-90)
- Modify: `packages/payoff_engine/lib/src/fixed_loan_payment.dart` (both `120000` divisions)
- Modify: `packages/payoff_engine/lib/src/debt_ordering.dart` (`aprMonthsUntil` returns ppm-months)
- Modify: `packages/payoff_engine/lib/src/card_transfers.dart` (`shortlistCardMoves` estimate in ppm)
- Modify: `packages/payoff_engine/test/helpers.dart` (a `nominal` helper)
- Modify tests:
  - engine: `legacy_scenarios_test.dart`, `calculator_test.dart`, `promo_test.dart`, `consolidation_test.dart`, `debt_ordering_test.dart`, `transfer_test.dart`, `calculator_unpayable_test.dart`, `simulate_test.dart`;
  - app: the five tests listed in Step 6.

**Interfaces:**
- Consumes: Task 1's `monthlyInterest`, `monthlyRatePpm`, `runWithInterestMode`.
- Produces:
  - `T nominal<T>(T Function() body)`, in the engine's test `helpers.dart`.
  - `aprMonthsUntil`'s unit changes from bps-months to ppm-months. The name stays, to keep the churn small; update its doc comment.

- [ ] **Step 1: Write the failing tests.** These are the tests whose subject *is* the interest formula; set them to the compound reference values.
  - `calculator_test.dart` › "adds interest before paying, rounded half-even to the penny":
    - comment: `// 1200.00 at 12% APR: 9,489 ppm a month = 11.39; then 100.00 paid.`
    - `first.interest` → `[gbp(1139)]`;
    - `first.closingBalances` → `[gbp(111139)]`;
    - `plan.months[1].interest` → `[gbp(1055)]`, with the comment updated to match.
  - `promo_test.dart` › "the calculator charges the promo rate, then the normal APR":
    - expected list → `[gbp(0), gbp(0), gbp(949), gbp(863)]`;
    - comment: `// Months 1-2 are free; month 3 charges 9,489 ppm of 1,000; month 4 of 909.49.`
  - `consolidation_test.dart`:
    - "uses the engine's own monthly interest and rounding": 10662 → **10628**, and 9667 → **9630**.
    - "stays within 64-bit arithmetic at the largest loan": 500033693531 → **357126760330**. Its checking loop must charge interest the engine's way: replace `divideHalfEven(balance * aprBps, 120000)` with `monthlyInterest()(balance, aprBps)`. The comment's reference is now the plan's integer-exact model; say so.
    - "is the smallest payment that clears within the term": `loanPaying(10628).monthsToClear` is 12, and `loanPaying(10627).monthsToClear` is 13.
  - `debt_ordering_test.dart` (the `aprMonthsUntil` test):
    - `aprMonthsUntil(promo, 1, 5)` → **66312** (3 × 22,104);
    - `aprMonthsUntil(promo, 4, 5)` → **44208** (2 × 22,104);
    - 0 stays 0;
    - comments: "in ppm-months".
  - Add to `test/helpers.dart`:

```dart
/// Runs [body] with the 2013 app's APR ÷ 12 interest: for tests whose
/// figures were worked out that way and whose subject isn't the rate.
T nominal<T>(T Function() body) =>
    runWithInterestMode(InterestMode.nominal, body);
```

- [ ] **Step 2: Run to watch them fail.**
  - Run: `dart test test/calculator_test.dart test/promo_test.dart test/consolidation_test.dart test/debt_ordering_test.dart`
  - Expected: FAIL on the changed figures. The old values (1200, 10662, 9000, …) are still produced.

- [ ] **Step 3: Implement.**
  - **`simulate.dart`:** read `final interestOn = monthlyInterest();` once, just before the month loop. Replace the interest line with `interest[i] = interestOn(balances[i], aprInMonth(debts[i], month));`.
  - **`fixed_loan_payment.dart`:** read `final interestOn = monthlyInterest();` at the top of `fixedLoanPayment`. Use `interestOn(balance, aprBps)` in `clears`, and `interestOn(balanceMinor, aprBps)` for `high`. Update the comment "keeps `balance * aprBps`" to "keeps `balance × rate`".
  - **`debt_ordering.dart`:** in `aprMonthsUntil`, return `atPromo * monthlyRatePpm(promoRate) + (months - atPromo) * monthlyRatePpm(debt.aprBps)`. Update the doc to "in parts-per-million-months". The ranking uses the true monthly rate in both modes: without promos the order is the same either way, and the legacy scenarios have none.
  - **`card_transfers.dart`** (`shortlistCardMoves` › `estimate`):
    - `final cut = monthlyRatePpm(aprInMonth(from, m)) - monthlyRatePpm(_movedRate(to, move.promo, m));`
    - `final yearSaved = divideHalfEven(rateMonths * move.amount.minor, 1000000);`
    - Update the doc comment's units.

- [ ] **Step 4: Run the four files to watch them pass.**
  - Run: `dart test test/calculator_test.dart test/promo_test.dart test/consolidation_test.dart test/debt_ordering_test.dart`
  - Expected: those tests pass. Other tests in these files may fail; Step 5 handles them.

- [ ] **Step 5: Sort out the remaining engine failures.**
  - Run: `dart test 2>&1 | grep '\[E\]'`
  - A spike on 26 Sep 2026 found these (besides Step 1's):
    - `legacy_scenarios_test.dart`: S1–S4;
    - `transfer_test.dart`: "pays the other debts first while the card is at 0%", "a partial transfer leaves the rest on the original card";
    - `calculator_unpayable_test.dart`: "is infeasible in a later month if the minimums grow past the budget";
    - `calculator_test.dart`: "money freed by clearing a debt moves on in the same month", "avalanche beats smallest-balance-first on a short promo", "snowball pays the smallest starting balance first", "custom order follows the list";
    - `consolidation_test.dart`: "consolidation replaces eligible debts with a fixed-payment loan", "consolidation overpays the loan with what the budget has left";
    - `simulate_test.dart`: "lists debts in the order they are cleared", "cards made of portions one minimum on the card total, lowest rate first".
  - For each failing test:
    1. Wrap its body: `test('…', () => nominal(() { … }));`. Async bodies work the same way, because the zone carries through the awaits.
    2. Run it. It must pass **unchanged**. That proves only the rate formula moved. If it doesn't pass, stop: it's a real regression. Use superpowers:systematic-debugging.
    3. Decide whether the test's subject is behaviour (an order, which plan is cheaper, when something is infeasible) rather than exact figures. If so, also check that the behaviour still holds under compound: duplicate the test without `nominal`, keeping only its behavioural assertions. If a behaviour flips under compound, stop and ledger it as a finding, not a ruling.
    4. Leave a one-line comment on the wrapped test: `// Figures worked out with APR ÷ 12; the subject isn't the rate.`
  - Wrap the whole of `legacy_scenarios_test.dart`, since each of its tests quotes `LegacySolver.java`. Change every `test('S…', () {` to `test('S…', () => nominal(() {` and close with `}));`. Add a file-level comment: `// The 2013 app charged APR ÷ 12; these figures come from LegacySolver.java, so they run in nominal mode.`
  - Expected at the end: `dart test` → all pass.

- [ ] **Step 6: The app's tests.**
  - Run: `cd ../.. && flutter test 2>&1 | grep '\[E\]'`
  - The spike found five:
    - `progress_providers_test.dart` "a check-in clears a debt without restarting";
    - `plans_providers_test.dart` "includes the minimums-only baseline";
    - `strategies_screen_test.dart` "compares each plan with paying only the minimums" and "opens the baseline plan";
    - `scenarios_screen_test.dart` "compares the best plan in each scenario".
  - For each: read the assertion. If it's a hard-coded figure or date, recompute the expected value from the engine and update it:
    - write a throwaway `dart run` script in the scratchpad calling `calculate` on the test's debts;
    - check that the change goes the right way (compound charges less than nominal at any APR above 0);
    - ledger every changed value as old → new.
  - If the assertion is behavioural and it fails, treat it as Step 5.3 does.
  - Expected: `flutter test` → all pass.

- [ ] **Step 7: Analyze, format, commit.**

```bash
cd packages/payoff_engine && dart format lib test && dart analyze --fatal-infos && dart test
cd ../.. && dart format lib test && dart analyze --fatal-infos && flutter test
git add -A packages/payoff_engine test lib
git commit -m "feat(engine): charge the true monthly rate of a compounded APR

Legacy figures and tests whose subject isn't the rate run in nominal mode;
the interest-formula tests use the new compound values."
```

### Task 3: Loan solvers

**Files:**
- Create: `packages/payoff_engine/lib/src/loan.dart`
- Modify: `packages/payoff_engine/lib/src/fixed_loan_payment.dart` (delegate to `loan.dart`'s search)
- Modify: `packages/payoff_engine/lib/payoff_engine.dart` (export `src/loan.dart`)
- Test: `packages/payoff_engine/test/loan_test.dart`

**Interfaces:**
- Consumes: Task 1's `monthlyInterest`; `kBalanceCeilingMinor` (`simulate.dart`); `kMaxMonths` (`payoff_result.dart`); `kMaxAmountMinor` (`validation.dart`).
- Produces (plans 12 and 13 rely on these exact names):

```dart
enum LoanProblem { neverClears, rateTooHigh, rateBelowZero, outOfRange }

sealed class LoanResult { const LoanResult(); }

final class LoanSolved extends LoanResult {
  const LoanSolved({
    required this.balance,
    required this.aprBps,
    required this.payment,
    required this.months,
    required this.balances,
  });
  final Money balance;   // amount borrowed / owed now
  final int aprBps;
  final Money payment;   // the regular monthly payment
  final int months;      // number of payments; the last may be smaller
  /// Opening balance, then the balance after each payment: months + 1
  /// values, the last zero.
  final List<Money> balances;
  Money get totalPaid;   // sum of the actual payments made
  Money get totalInterest; // totalPaid - balance
}

final class LoanImpossible extends LoanResult {
  const LoanImpossible(this.problem);
  final LoanProblem problem;
}

LoanResult loanPayment({required Money balance, required int aprBps, required int months});
LoanResult loanMonths({required Money balance, required int aprBps, required Money payment});
LoanResult loanBalance({required int aprBps, required Money payment, required int months});
LoanResult loanApr({required Money balance, required Money payment, required int months});
```

- **Semantics:**
  - All four simulate with `monthlyInterest()` (read once per call), paying `min(payment, balance)` each month. A balance past `kBalanceCeilingMinor` means the payment can't clear.
  - **`loanPayment`:** the smallest whole payment that clears within `months`. This is today's `fixedLoanPayment` search; `fixedLoanPayment` becomes `(loanPayment(…) as LoanSolved).payment.minor`.
  - **`loanMonths`:** simulate until cleared.
    - `neverClears` if the payment ≤ the first month's interest.
    - `outOfRange` if not cleared within `kMaxMonths`.
  - **`loanBalance`:** the largest balance, in [0, payment × months], that clears within `months`, found by binary search. `outOfRange` if it exceeds `kMaxAmountMinor`.
  - **`loanApr`:** the highest APR in basis points, in [0, 10000], at which the payment clears within `months`, found by binary search.
    - `rateBelowZero` if it doesn't clear even at 0% (payment × months < balance).
    - `rateTooHigh` if it still clears at 10,001 bps (the implied rate is above 100%).
    - Clearing at exactly 10,000 and not at 10,001 returns 10,000.
  - **Input checks, all solvers:**
    - `outOfRange` for `months` < 1 or > `kMaxMonths`.
    - `outOfRange` for a balance or payment ≤ 0 or > `kMaxAmountMinor`.
    - `outOfRange` for an APR outside 0–10000.

- [ ] **Step 1: Write the failing test** `test/loan_test.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

LoanSolved solved(LoanResult r) => r as LoanSolved;

void main() {
  group('loanPayment', () {
    test('the smallest payment that clears within the term', () {
      final r = solved(
        loanPayment(balance: gbp(120000), aprBps: 1200, months: 12),
      );
      expect(r.payment, gbp(10628));
      expect(r.months, 12);
      expect(r.totalPaid, gbp(127530));
      expect(r.totalInterest, gbp(7530));
      expect(r.balances.first, gbp(120000));
      expect(r.balances.last, gbp(0));
      expect(r.balances, hasLength(13));
    });

    test('0% is the balance shared out, rounded up', () {
      expect(
        solved(loanPayment(balance: gbp(1000), aprBps: 0, months: 3)).payment,
        gbp(334),
      );
    });

    test('fixedLoanPayment agrees', () {
      expect(
        fixedLoanPayment(balanceMinor: 120000, aprBps: 1200, termMonths: 12),
        10628,
      );
    });

    test('a loan at this payment clears in the plans in the same month', () {
      final r = solved(
        loanPayment(balance: gbp(500000), aprBps: 690, months: 36),
      );
      final plan = planOf(
        calculate(
          debts: [
            debt(
              id: 'loan',
              type: DebtType.loan,
              balance: 500000,
              aprBps: 690,
              minPaymentFloor: r.payment.minor,
              allowsOverpayment: false,
            ),
          ],
          monthlyBudget: r.payment,
          strategy: const Strategy.avalanche(),
        ),
      );
      expect(plan.monthsToClear, 36);
      expect(plan.totalPaid, r.totalPaid);
    });
  });

  group('loanMonths', () {
    test('counts the payments, the last smaller', () {
      final r = solved(
        loanMonths(balance: gbp(120000), aprBps: 1200, payment: gbp(10000)),
      );
      expect(r.months, 13);
      expect(r.totalPaid, gbp(128012));
    });

    test('a payment no bigger than the first interest never clears', () {
      expect(
        loanMonths(balance: gbp(120000), aprBps: 1200, payment: gbp(1139)),
        isA<LoanImpossible>().having(
          (i) => i.problem,
          'problem',
          LoanProblem.neverClears,
        ),
      );
    });

    test('longer than the engine plans is out of range', () {
      // 1,200.00 at 3% charges 2.96 the first month; paying 2.97 clears,
      // but only after 2,311 months, beyond kMaxMonths.
      expect(
        (loanMonths(balance: gbp(120000), aprBps: 300, payment: gbp(297))
                as LoanImpossible)
            .problem,
        LoanProblem.outOfRange,
      );
    });
  });

  group('loanBalance', () {
    test('the largest balance the payment clears in the term', () {
      final r = solved(
        loanBalance(aprBps: 1200, payment: gbp(10628), months: 12),
      );
      expect(r.balance, gbp(120006));
      expect(r.months, lessThanOrEqualTo(12));
    });

    test('at 0% it is payment × months', () {
      expect(
        solved(loanBalance(aprBps: 0, payment: gbp(10000), months: 12)).balance,
        gbp(120000),
      );
    });
  });

  group('loanApr', () {
    test('the highest APR at which the payment clears in the term', () {
      expect(
        solved(
          loanApr(balance: gbp(120000), payment: gbp(10628), months: 12),
        ).aprBps,
        1201,
      );
    });

    test('0% when the payments exactly add up to the balance', () {
      expect(
        solved(
          loanApr(balance: gbp(120000), payment: gbp(10000), months: 12),
        ).aprBps,
        0,
      );
    });

    test('payments that add up to less than the balance', () {
      expect(
        (loanApr(balance: gbp(120000), payment: gbp(9999), months: 12)
                as LoanImpossible)
            .problem,
        LoanProblem.rateBelowZero,
      );
    });

    test('a rate above 100%', () {
      // 1,000.00 repaid as 2,000.00 next month is 100% a month.
      expect(
        (loanApr(balance: gbp(100000), payment: gbp(200000), months: 1)
                as LoanImpossible)
            .problem,
        LoanProblem.rateTooHigh,
      );
    });
  });

  group('agree with each other', () {
    for (final (balance, apr, months) in [
      (100, 0, 1),
      (120000, 1200, 12),
      (2500000, 2990, 60),
      (9999999, 10000, 120),
      (50000, 1, 1200),
    ]) {
      test('$balance at $apr over $months', () {
        final byPayment = solved(
          loanPayment(balance: gbp(balance), aprBps: apr, months: months),
        );
        expect(
          solved(
            loanMonths(
              balance: gbp(balance),
              aprBps: apr,
              payment: byPayment.payment,
            ),
          ).months,
          byPayment.months,
        );
        expect(
          solved(
            loanBalance(aprBps: apr, payment: byPayment.payment, months: months),
          ).balance.minor,
          greaterThanOrEqualTo(balance),
        );
        expect(
          solved(
            loanApr(
              balance: gbp(balance),
              payment: byPayment.payment,
              months: months,
            ),
          ).aprBps,
          greaterThanOrEqualTo(apr),
        );
      });
    }
  });

  group('inputs out of range', () {
    test('term, amounts and rate', () {
      LoanProblem problem(LoanResult r) => (r as LoanImpossible).problem;
      expect(
        problem(loanPayment(balance: gbp(100), aprBps: 0, months: 0)),
        LoanProblem.outOfRange,
      );
      expect(
        problem(
          loanPayment(balance: gbp(100), aprBps: 0, months: kMaxMonths + 1),
        ),
        LoanProblem.outOfRange,
      );
      expect(
        problem(loanPayment(balance: gbp(0), aprBps: 0, months: 12)),
        LoanProblem.outOfRange,
      );
      expect(
        problem(
          loanPayment(
            balance: gbp(kMaxAmountMinor + 1),
            aprBps: 0,
            months: 12,
          ),
        ),
        LoanProblem.outOfRange,
      );
      expect(
        problem(loanPayment(balance: gbp(100), aprBps: 10001, months: 12)),
        LoanProblem.outOfRange,
      );
    });
  });
}
```

- [ ] **Step 2: Run to watch it fail.**
  - Run: `dart test test/loan_test.dart`
  - Expected: FAIL, a compile error: `loanPayment` isn't defined.

- [ ] **Step 3: Implement** `lib/src/loan.dart`:
  - **The shared simulation:** a private `_run(int balance, int aprBps, int payment, int maxMonths, MonthlyInterest interestOn) → List<int>?`. It returns the balances (opening, then after each payment), or null if the loan hasn't cleared by `maxMonths` or passes `kBalanceCeilingMinor`.
  - **The four solvers** follow the semantics above. `loanPayment`'s search bounds are the current `fixedLoanPayment`'s: low is `ceil(balance / months)`, high is `balance + first month's interest`.
  - **`fixedLoanPayment`:** keep the name and signature, and delegate to `loanPayment`.
  - Export `src/loan.dart` from `payoff_engine.dart`.

- [ ] **Step 4: Run to watch it pass.**
  - Run: `dart test test/loan_test.dart`
  - Expected: PASS.
  - A reference value that doesn't match means the implementation differs from the model: debug it, don't edit the value. The 64-bit `fixedLoanPayment` test in `consolidation_test.dart` must still pass.
  - Then run all engine tests: `dart test`.

- [ ] **Step 5: Analyze, format, commit.**

```bash
dart format lib test && dart analyze --fatal-infos && dart test
git add lib/src/loan.dart lib/src/fixed_loan_payment.dart lib/payoff_engine.dart test/loan_test.dart
git commit -m "feat(engine): loan solvers — payment, months, balance or rate from the other three"
```

### Task 4: Docs and verification

**Files:** `CLAUDE.md`.

- [ ] **`CLAUDE.md`:**
  - Add a migration line: `- [x] Plan 11: compound APR and loan solvers (docs/superpowers/plans/2026-09-26-plan-11-compound-interest-and-loan-solvers.md, spec docs/superpowers/specs/2026-09-26-rates-and-loans-design.md)`.
  - Add a spec bullet for the rates-and-loans spec.
  - Add a Gotcha: "Interest: an APR is the true compounded rate. The engine charges `monthlyRatePpm(apr)` parts per million a month (`lib/src/interest.dart`), not APR ÷ 12. The 2013 figures (and tests whose figures were worked out that way) run inside `runWithInterestMode(InterestMode.nominal, …)`, through the test helper `nominal`. Loan maths go through `loanPayment`/`loanMonths`/`loanBalance`/`loanApr` (`lib/src/loan.dart`)."
- [ ] **Full verification:** `./tool/codegen.sh && dart format lib test && dart analyze --fatal-infos && flutter test && (cd packages/payoff_engine && dart format lib test && dart analyze --fatal-infos && dart test)`. Then run `java legacy/reference/LegacySolver.java` and check the figures it prints still match the (now nominal-mode) legacy tests.
- [ ] **Commit:** `docs: Plan 11 compound interest and loan solvers`.
