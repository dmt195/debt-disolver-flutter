# Plan 1: Foundation and Payoff Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tidy the repository around the legacy Android project, and build `packages/payoff_engine`: a pure-Dart, fully tested debt-payoff calculator that the Flutter app (Plans 2–4) will call.

**Architecture:** The engine is a standalone Dart package with no Flutter dependency. Immutable freezed models (`Debt`, `Strategy`, `PayoffResult`, `PayoffPlan`) sit alongside a hand-written `Money` value type, and one pure function, `calculate()`, simulates month-by-month repayment. All money is integer minor units, and all rates are integer basis points. A standalone Java port of the legacy calculator provides reference figures for the tests.

**Tech Stack:** Dart 3 (SDK `^3.9.0`, verified on 3.13.2), freezed 4 / freezed_annotation 3, build_runner, package:test, very_good_analysis 11, GitHub Actions, and Java 17 (only to run the legacy reference port).

**Spec:** `docs/superpowers/specs/2026-09-24-flutter-rebuild-design.md` (§3 domain model, §4 calculator rules, §9 development practices). Read it alongside this plan.

**This is Plan 1 of 4.** Plan 2 covers the app shell, persistence and state; Plan 3 the screens and export; Plan 4 ads, consent, crash reporting, full CI and release prep.

## Global Constraints

- The engine never uses floating-point money: amounts are `Money` (integer minor units plus an ISO 4217 code), and rates are `int` basis points (1995 = 19.95%).
- All rounding is half-to-even, via `divideHalfEven`. Interest is rounded once per debt per month.
- APR and minimum-percent inputs are valid only within 0–10000 bps. Amounts are valid only up to `kMaxAmountMinor` = 100,000,000,000 (1,000,000,000.00).
- Calculation stops after `kMaxMonths` = 1200 months. A balance above `kBalanceCeilingMinor` = 10,000,000,000,000 means the debts never clear.
- The default strategy parameters are the legacy Settings-screen values: consolidation APR 500 bps, transfer fee 400 bps, promo 12 months, revert APR 1500 bps, and boosted budget 110%.
- `packages/payoff_engine` must not depend on Flutter.
- TDD is mandatory: write the failing test, watch it fail, write the minimal code, watch it pass, then commit.
- Lints: `very_good_analysis`. `dart analyze --fatal-infos` must be clean, and `dart format` must leave no changes.
- Generated files (`*.freezed.dart`, `*.g.dart`) are **not committed**. Run `dart run build_runner build -d` after changing any freezed model and after a fresh checkout.
- Treat the `legacy/` directory as read-only: never edit files under it, except to add `legacy/reference/`.

## Review Focus

Inputs and conditions most likely to hurt a real user, each pinned by a test in the task shown:

1. **The budget covers the minimums at first but not later** (for example, when the minimum is a percentage and the balance grows): the result should be `Infeasible`, naming the month, and not a bogus plan. Covered in Task 6: "is infeasible in a later month…".
2. **Payments that can never outpace interest**: the result should be `NeverClears`, without looping for ever or overflowing 64-bit integers. Covered in Task 6: "never clears when payments cannot outpace interest" and "…at the maximum inputs without integer overflow".
3. **APRs less than 1% apart** (the legacy comparator bug): the higher APR must still be paid first. Covered in Task 4 and scenario S4 in Task 8.
4. **Debts in a different currency from the budget**: the engine should fail loudly with an `ArgumentError`, not return wrong numbers. Covered in Task 5: "rejects debts in a different currency from the budget".
5. **A debt that is never paid down** (no minimum, and no overpayment allowed): the result should be `NeverClears` at the month cap, not an infinite loop. Covered in Task 5: "never clears when a debt is never paid down".

---

### Task 1: Tidy the repository around the legacy project

The complete legacy Android project is now in `legacy/`. Its Java lives in `legacy/src/main/java/com/dmt195/debtdestroyer/`. The earlier root-level copies of the Java files (`Analysis/`, `Debts/`, `Details/`, `Solutions/`, `*.java`) are duplicates. Some have already been deleted from the working tree but not from git. This task removes the duplicates, commits `legacy/` without its build outputs or licensed assets, and adds the standalone legacy calculator port that the engine tests use for reference figures.

**Files:**
- Create: `.gitignore`
- Create: `legacy/reference/LegacySolver.java`
- Delete (from git): `Analysis/`, `Debts/`, `Details/`, `Solutions/`, `FirstTimeDialogFragment.java`, `FragmentMinPayments.java`, `FragmentPreferences.java`, `MyPreferenceActivity.java`, `ResourcesActivity.java`
- Add: `legacy/` (everything not ignored)

**Interfaces:**
- Produces: running `java legacy/reference/LegacySolver.java` from the repo root prints the legacy reference figures that Task 8 quotes.

- [ ] **Step 1: Confirm the root copies are exact duplicates of the legacy Java**

Run from the repo root:
```bash
B=legacy/src/main/java/com/dmt195/debtdestroyer
for f in $(git ls-files '*.java'); do cmp -s <(git show HEAD:$f) "$B/$f" && echo same || echo "DIFF $f"; done | sort | uniq -c
```
Expected: `24 same`, and no `DIFF` lines. If any `DIFF` appears, stop and ask the user which copy to keep.

- [ ] **Step 2: Create the root `.gitignore`**

```gitignore
.DS_Store

# Legacy Android project: build outputs, binaries and local config
legacy/build/
legacy/src/main/gen/
legacy/src/main/proguard_logs/
legacy/**/*.apk
legacy/**/*.jar
legacy/**/*.iml
legacy/**/local.properties

# Licensed third-party assets: keep locally, never commit
legacy/resources/shutterstock_*
legacy/resources/*.otf
legacy/resources/*.ttf
```

- [ ] **Step 3: Remove the root duplicates from git**

```bash
git rm -r -q --ignore-unmatch Analysis Debts Details Solutions FirstTimeDialogFragment.java FragmentMinPayments.java FragmentPreferences.java MyPreferenceActivity.java ResourcesActivity.java
git ls-files '*.java' | grep -v '^legacy/' || echo "no root java left"
```
Expected: `no root java left`. If `Analysis/` is still on disk after this, delete it (`git rm` already removed it from the index).

- [ ] **Step 4: Add the legacy calculator port**

Create `legacy/reference/LegacySolver.java`:
```java
// Standalone port of the legacy DebtListAdapter.solve() algorithm (Debts/DebtListAdapter.java),
// with Android dependencies removed. Logic, float arithmetic and comparator bugs are kept verbatim
// so its output can be used as a reference for the Flutter payoff_engine tests.
// Run: java LegacySolver.java
import java.util.*;

public class LegacySolver {
    static final int CREDIT_CARD = 0, LOAN = 1;
    static float consolidationAPR = 4.0f, revertAPR = 15.0f, ccTransferFee = 4.0f;
    static int ccTerm = 15;

    static class DebtItem {
        String name; float balance, apr, minPaymentPercent, minPaymentAbsolute, limit; int type;
        boolean canOverPay, activeInCalc = true; float tempBalance;
        DebtItem(String name, int type, float balance, float apr, float minAbs, float minPct, float limit, boolean canOverPay) {
            this.name = name; this.type = type; this.balance = balance; this.apr = apr; this.minPaymentAbsolute = minAbs;
            this.minPaymentPercent = minPct; this.limit = limit; this.canOverPay = canOverPay; this.tempBalance = balance;
        }
        float payMinimum() {
            if (tempBalance <= 0) return 0;
            float minPercent = minPaymentPercent * tempBalance / 100;
            float minToPay = minPaymentAbsolute > minPercent ? minPaymentAbsolute : minPercent;
            if (tempBalance > minToPay) { tempBalance -= minToPay; return minToPay; }
            float s = tempBalance; tempBalance = 0; return s;
        }
        float payAsMuchAsPossible(float cash) {
            if (tempBalance <= 0) return 0;
            if (tempBalance > cash) { tempBalance -= cash; return cash; }
            float s = tempBalance; tempBalance = 0; return s;
        }
    }

    final List<DebtItem> debtList = new ArrayList<>();

    float total(boolean temp) { float t = 0; for (DebtItem d : debtList) if (d.activeInCalc) t += temp ? d.tempBalance : d.balance; return t; }
    float totalMin() {
        float t = 0;
        for (DebtItem d : debtList) { d.tempBalance = d.balance; }
        for (DebtItem d : debtList) if (d.activeInCalc) { float p = d.minPaymentPercent * d.tempBalance / 100; t += Math.max(d.minPaymentAbsolute, p); }
        return t;
    }

    String solve(int type, float monthly) {
        for (DebtItem d : debtList) d.tempBalance = d.balance;
        int month = 0; float tempTotal = total(true), totalSpent = 0;
        switch (type) {
            case 0: debtList.sort((a, b) -> (int) (b.apr - a.apr) * 100); break;   // legacy bug kept
            case 1: debtList.sort((a, b) -> (int) (a.apr - b.apr) * 100); break;   // legacy bug kept
            case 4: for (DebtItem d : debtList) d.activeInCalc = false;
                    debtList.add(new DebtItem("Consolidation Loan", LOAN, tempTotal, consolidationAPR, monthly, 0, tempTotal, false)); break;
            case 5: for (DebtItem d : debtList) d.activeInCalc = false;
                    float m = ccTransferFee / 100 + 1;
                    debtList.add(new DebtItem("Interest Free CC", CREDIT_CARD, tempTotal * m, 0, monthly, 0, tempTotal * m, false)); break;
        }
        int n = debtList.size();
        if (monthly < totalMin()) return "infeasible";
        StringBuilder order = new StringBuilder();
        for (DebtItem d : debtList) if (d.activeInCalc) order.append(d.name).append(';');
        while (tempTotal > 0 && month < 1200) {
            float toSpend = monthly;
            for (DebtItem d : debtList) d.tempBalance *= d.apr / 1200 + 1;
            for (DebtItem d : debtList) if (d.activeInCalc) toSpend -= d.payMinimum();
            for (DebtItem d : debtList) if (d.activeInCalc && d.canOverPay) toSpend -= d.payAsMuchAsPossible(toSpend);
            if (month == ccTerm && type == 5) debtList.get(n - 1).apr = revertAPR;
            tempTotal = total(true);
            month++;
            totalSpent += monthly - toSpend;
        }
        if (type >= 4) { for (DebtItem d : debtList) d.activeInCalc = true; debtList.remove(n - 1); }
        float interest = totalSpent - total(false);
        return String.format("months=%d paid=%.2f interest=%.2f order=%s", month, totalSpent, interest, order);
    }

    static void run(String label, float monthly, DebtItem... debts) {
        String[] names = {"avalanche", "lowest", "boosted", "consolidation", "transfer"};
        int[] types = {0, 1, 0, 4, 5};
        for (int i = 0; i < 5; i++) {
            LegacySolver s = new LegacySolver();
            for (DebtItem d : debts) s.debtList.add(new DebtItem(d.name, d.type, d.balance, d.apr, d.minPaymentAbsolute, d.minPaymentPercent, d.limit, d.canOverPay));
            System.out.println(label + " " + names[i] + ": " + s.solve(types[i], i == 2 ? monthly * 1.1f : monthly));
        }
    }

    public static void main(String[] args) {
        run("S1", 250, new DebtItem("Card", CREDIT_CARD, 1000, 0, 0, 0, 0, true));
        run("S2", 100, new DebtItem("Card", CREDIT_CARD, 1200, 12, 25, 2, 0, true));
        run("S3", 450,
            new DebtItem("Card A", CREDIT_CARD, 2000, 19.9f, 25, 3, 0, true),
            new DebtItem("Card B", CREDIT_CARD, 1500, 9.9f, 25, 2, 0, true),
            new DebtItem("Car loan", LOAN, 3000, 6.5f, 150, 0, 0, false));
        run("S4", 300,
            new DebtItem("Alpha", CREDIT_CARD, 1000, 18.0f, 25, 0, 0, true),
            new DebtItem("Beta", CREDIT_CARD, 1000, 18.5f, 25, 0, 0, true));
    }
}
```

- [ ] **Step 5: Run it and check the reference figures**

Run: `java legacy/reference/LegacySolver.java`
Expected output (exactly):
```
S1 avalanche: months=4 paid=1000.00 interest=0.00 order=Card;
S1 lowest: months=4 paid=1000.00 interest=0.00 order=Card;
S1 boosted: months=4 paid=1000.00 interest=0.00 order=Card;
S1 consolidation: months=5 paid=1008.42 interest=8.42 order=Consolidation Loan;
S1 transfer: months=5 paid=1040.00 interest=40.00 order=Interest Free CC;
S2 avalanche: months=13 paid=1284.78 interest=84.78 order=Card;
S2 lowest: months=13 paid=1284.78 interest=84.78 order=Card;
S2 boosted: months=12 paid=1277.11 interest=77.11 order=Card;
S2 consolidation: months=13 paid=1226.73 interest=26.73 order=Consolidation Loan;
S2 transfer: months=13 paid=1248.00 interest=48.00 order=Interest Free CC;
S3 avalanche: months=22 paid=6961.84 interest=461.84 order=Card A;Card B;Car loan;
S3 lowest: months=22 paid=7050.05 interest=550.05 order=Car loan;Card B;Card A;
S3 boosted: months=22 paid=6924.92 interest=424.92 order=Card A;Card B;Car loan;
S3 consolidation: months=15 paid=6672.90 interest=172.90 order=Consolidation Loan;
S3 transfer: months=16 paid=6760.00 interest=260.00 order=Interest Free CC;
S4 avalanche: months=8 paid=2125.72 interest=125.72 order=Alpha;Beta;
S4 lowest: months=8 paid=2125.72 interest=125.72 order=Alpha;Beta;
S4 boosted: months=7 paid=2115.44 interest=115.44 order=Alpha;Beta;
S4 consolidation: months=7 paid=2026.02 interest=26.02 order=Consolidation Loan;
S4 transfer: months=7 paid=2080.00 interest=80.00 order=Interest Free CC;
```

- [ ] **Step 6: Review what will be committed**

```bash
git add -n legacy .gitignore | grep -iE 'shutterstock|\.otf|\.ttf|\.apk|\.jar|\.iml|local\.properties|/build/|/gen/|\.DS_Store' || echo "nothing unwanted"
git add -n legacy | wc -l
```
Expected: `nothing unwanted`. The count is roughly 280 files. List any other files that look like third-party licensed material (stock images, fonts) or secrets (keystores, `*.jks`, passwords), and ask the user before committing them.

- [ ] **Step 7: Commit**

```bash
git add .gitignore legacy
git commit -m "chore: move legacy Android project to legacy/, add calculator reference port"
```

---

### Task 2: Package scaffold, rounding and Money

**Files:**
- Create: `packages/payoff_engine/pubspec.yaml`
- Create: `packages/payoff_engine/analysis_options.yaml`
- Create: `packages/payoff_engine/.gitignore`
- Create: `packages/payoff_engine/lib/payoff_engine.dart`
- Create: `packages/payoff_engine/lib/src/rounding.dart`
- Create: `packages/payoff_engine/lib/src/money.dart`
- Test: `packages/payoff_engine/test/rounding_test.dart`
- Test: `packages/payoff_engine/test/money_test.dart`

**Interfaces:**
- Produces:
  - `int divideHalfEven(int numerator, int denominator)`, which throws `ArgumentError` if `numerator < 0` or `denominator <= 0`.
  - `final class Money implements Comparable<Money>`, with:
    - `const Money(int minor, String currency)` and `const Money.zero(String currency)`
    - fields `minor` and `currency`
    - `isZero`, `isPositive`, `isNegative`
    - the operators `+`, `-`, `<`, `>`, `<=`, `>=` and `compareTo`, all of which throw `ArgumentError` on a currency mismatch
    - value `==` and `hashCode`

Run every command in this and later engine tasks from `packages/payoff_engine/`.

- [ ] **Step 1: Create the package files**

`pubspec.yaml`:
```yaml
name: payoff_engine
description: Pure-Dart debt payoff calculator for Debt Destroyer.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.9.0
dependencies:
  freezed_annotation: ^3.1.0
  meta: ^1.19.0
dev_dependencies:
  build_runner: ^2.16.1
  freezed: ^4.0.2
  test: ^1.32.0
  very_good_analysis: ^11.0.0
```

`analysis_options.yaml`:
```yaml
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  exclude:
    - "**/*.freezed.dart"

linter:
  rules:
    public_member_api_docs: false
```

`.gitignore`:
```gitignore
.dart_tool/
build/
*.freezed.dart
*.g.dart
```

`lib/payoff_engine.dart`:
```dart
/// Pure-Dart debt payoff calculator for Debt Destroyer.
library;

export 'src/money.dart';
export 'src/rounding.dart';
```

Then run: `dart pub get`
Expected: `Got dependencies!` (or `Changed N dependencies!`).

- [ ] **Step 2: Write the failing tests**

`test/rounding_test.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

void main() {
  group('divideHalfEven', () {
    test('divides exactly when there is no remainder', () {
      expect(divideHalfEven(100, 4), 25);
    });

    test('rounds down below half and up above half', () {
      expect(divideHalfEven(14, 10), 1);
      expect(divideHalfEven(16, 10), 2);
    });

    test('rounds exact halves to the even neighbour', () {
      expect(divideHalfEven(15, 10), 2);
      expect(divideHalfEven(25, 10), 2);
      expect(divideHalfEven(35, 10), 4);
    });

    test('rejects a negative numerator or non-positive denominator', () {
      expect(() => divideHalfEven(-1, 10), throwsArgumentError);
      expect(() => divideHalfEven(1, 0), throwsArgumentError);
    });
  });
}
```

`test/money_test.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Money', () {
    test('adds and subtracts in minor units', () {
      expect(
        const Money(150, 'GBP') + const Money(25, 'GBP'),
        const Money(175, 'GBP'),
      );
      expect(
        const Money(150, 'GBP') - const Money(200, 'GBP'),
        const Money(-50, 'GBP'),
      );
    });

    test('has value equality including currency', () {
      expect(const Money(100, 'GBP'), const Money(100, 'GBP'));
      expect(const Money(100, 'GBP'), isNot(const Money(100, 'USD')));
    });

    test('compares amounts', () {
      expect(const Money(1, 'GBP') < const Money(2, 'GBP'), isTrue);
      expect(const Money(2, 'GBP') >= const Money(2, 'GBP'), isTrue);
      expect(const Money(3, 'GBP').compareTo(const Money(2, 'GBP')), 1);
    });

    test('rejects arithmetic across currencies', () {
      expect(
        () => const Money(1, 'GBP') + const Money(1, 'USD'),
        throwsArgumentError,
      );
      expect(
        () => const Money(1, 'GBP') < const Money(1, 'USD'),
        throwsArgumentError,
      );
    });

    test('reports sign', () {
      expect(const Money.zero('GBP').isZero, isTrue);
      expect(const Money(1, 'GBP').isPositive, isTrue);
      expect(const Money(-1, 'GBP').isNegative, isTrue);
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `dart test`
Expected: FAIL. The tests fail to load because `lib/src/money.dart` and `lib/src/rounding.dart` don't exist yet.

- [ ] **Step 4: Implement**

`lib/src/rounding.dart`:
```dart
/// Divides [numerator] by [denominator], rounding half to even.
///
/// Both arguments must be non-negative and [denominator] must be positive.
int divideHalfEven(int numerator, int denominator) {
  if (numerator < 0) {
    throw ArgumentError.value(numerator, 'numerator', 'must be >= 0');
  }
  if (denominator <= 0) {
    throw ArgumentError.value(denominator, 'denominator', 'must be > 0');
  }
  final quotient = numerator ~/ denominator;
  final twiceRemainder = (numerator % denominator) * 2;
  if (twiceRemainder > denominator) return quotient + 1;
  if (twiceRemainder == denominator && quotient.isOdd) return quotient + 1;
  return quotient;
}
```

`lib/src/money.dart`:
```dart
import 'package:meta/meta.dart';

/// An amount of money in integer minor units (e.g. pence) of [currency].
@immutable
final class Money implements Comparable<Money> {
  const Money(this.minor, this.currency);

  const Money.zero(this.currency) : minor = 0;

  final int minor;

  /// ISO 4217 currency code, e.g. `GBP`.
  final String currency;

  bool get isZero => minor == 0;
  bool get isPositive => minor > 0;
  bool get isNegative => minor < 0;

  Money operator +(Money other) => Money(minor + _check(other).minor, currency);

  Money operator -(Money other) => Money(minor - _check(other).minor, currency);

  bool operator <(Money other) => minor < _check(other).minor;
  bool operator >(Money other) => minor > _check(other).minor;
  bool operator <=(Money other) => minor <= _check(other).minor;
  bool operator >=(Money other) => minor >= _check(other).minor;

  Money _check(Money other) {
    if (other.currency != currency) {
      throw ArgumentError('Currency mismatch: $currency vs ${other.currency}');
    }
    return other;
  }

  @override
  int compareTo(Money other) => minor.compareTo(_check(other).minor);

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => 'Money($minor $currency)';
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `dart test && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test`
Expected: `+9: All tests passed!`, then `No issues found!`, and format exits with 0.

- [ ] **Step 6: Commit**

```bash
git add packages/payoff_engine
git commit -m "feat(engine): scaffold payoff_engine with Money and half-even rounding"
```
`pubspec.lock` is committed; `.dart_tool/` is ignored.

---

### Task 3: Debt model and validation

**Files:**
- Create: `packages/payoff_engine/lib/src/debt.dart`
- Create: `packages/payoff_engine/lib/src/validation.dart`
- Modify: `packages/payoff_engine/lib/payoff_engine.dart`
- Create: `packages/payoff_engine/test/helpers.dart`
- Test: `packages/payoff_engine/test/validation_test.dart`

**Interfaces:**
- Consumes: `Money` (Task 2).
- Produces:
  - `enum DebtType { creditCard, loan, personal }`
  - freezed `Debt({required String id, required String name, required DebtType type, required Money balance, required int aprBps, required int minPaymentPercentBps, required Money minPaymentFloor, required bool allowsOverpayment})`, with `copyWith`
  - `const int kMaxAmountMinor = 100000000000`
  - `enum DebtValidationError { nameEmpty, balanceNotPositive, balanceTooLarge, aprOutOfRange, minPaymentPercentOutOfRange, minPaymentFloorNegative, minPaymentFloorTooLarge }`
  - `enum BudgetValidationError { notPositive, tooLarge }`
  - `Set<DebtValidationError> validateDebt(Debt)` and `Set<BudgetValidationError> validateBudget(Money)`
  - Test helpers: `Money gbp(int minor)`, and `Debt debt({required String id, required int balance, String? name, DebtType type, int aprBps, int minPaymentPercentBps, int minPaymentFloor, bool allowsOverpayment = true})`. Its amounts are in pence, and `name` defaults to `id`.

- [ ] **Step 1: Write the test helpers and the failing test**

`test/helpers.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';

/// Money in GBP minor units (pence).
Money gbp(int minor) => Money(minor, 'GBP');

Debt debt({
  required String id,
  required int balance,
  String? name,
  DebtType type = DebtType.creditCard,
  int aprBps = 0,
  int minPaymentPercentBps = 0,
  int minPaymentFloor = 0,
  bool allowsOverpayment = true,
}) => Debt(
  id: id,
  name: name ?? id,
  type: type,
  balance: gbp(balance),
  aprBps: aprBps,
  minPaymentPercentBps: minPaymentPercentBps,
  minPaymentFloor: gbp(minPaymentFloor),
  allowsOverpayment: allowsOverpayment,
);
```

`test/validation_test.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final valid = debt(
    id: 'a',
    name: 'Card',
    balance: 100000,
    aprBps: 1990,
    minPaymentPercentBps: 300,
    minPaymentFloor: 2500,
  );

  group('validateDebt', () {
    test('accepts a valid debt', () {
      expect(validateDebt(valid), isEmpty);
    });

    test('rejects a blank name', () {
      expect(validateDebt(valid.copyWith(name: '   ')), {
        DebtValidationError.nameEmpty,
      });
    });

    test('rejects zero, negative and oversized balances', () {
      expect(validateDebt(valid.copyWith(balance: gbp(0))), {
        DebtValidationError.balanceNotPositive,
      });
      expect(validateDebt(valid.copyWith(balance: gbp(-1))), {
        DebtValidationError.balanceNotPositive,
      });
      expect(validateDebt(valid.copyWith(balance: gbp(kMaxAmountMinor + 1))), {
        DebtValidationError.balanceTooLarge,
      });
      expect(
        validateDebt(valid.copyWith(balance: gbp(kMaxAmountMinor))),
        isEmpty,
      );
    });

    test('accepts APR 0-100% and rejects outside it', () {
      expect(validateDebt(valid.copyWith(aprBps: 0)), isEmpty);
      expect(validateDebt(valid.copyWith(aprBps: 10000)), isEmpty);
      expect(validateDebt(valid.copyWith(aprBps: -1)), {
        DebtValidationError.aprOutOfRange,
      });
      expect(validateDebt(valid.copyWith(aprBps: 10001)), {
        DebtValidationError.aprOutOfRange,
      });
    });

    test('rejects a minimum percent outside 0-100%', () {
      expect(validateDebt(valid.copyWith(minPaymentPercentBps: -1)), {
        DebtValidationError.minPaymentPercentOutOfRange,
      });
      expect(validateDebt(valid.copyWith(minPaymentPercentBps: 10001)), {
        DebtValidationError.minPaymentPercentOutOfRange,
      });
    });

    test('rejects a negative or oversized minimum floor', () {
      expect(validateDebt(valid.copyWith(minPaymentFloor: gbp(-1))), {
        DebtValidationError.minPaymentFloorNegative,
      });
      expect(
        validateDebt(valid.copyWith(minPaymentFloor: gbp(kMaxAmountMinor + 1))),
        {DebtValidationError.minPaymentFloorTooLarge},
      );
    });

    test('reports every problem at once', () {
      final bad = valid.copyWith(name: '', balance: gbp(0), aprBps: -5);
      expect(validateDebt(bad), {
        DebtValidationError.nameEmpty,
        DebtValidationError.balanceNotPositive,
        DebtValidationError.aprOutOfRange,
      });
    });
  });

  group('validateBudget', () {
    test('accepts a positive budget up to the maximum', () {
      expect(validateBudget(gbp(25000)), isEmpty);
      expect(validateBudget(gbp(kMaxAmountMinor)), isEmpty);
    });

    test('rejects zero, negative and oversized budgets', () {
      expect(validateBudget(gbp(0)), {BudgetValidationError.notPositive});
      expect(validateBudget(gbp(-100)), {BudgetValidationError.notPositive});
      expect(validateBudget(gbp(kMaxAmountMinor + 1)), {
        BudgetValidationError.tooLarge,
      });
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/validation_test.dart`
Expected: FAIL to load, because `Debt`, `validateDebt` and the other new names are undefined.

- [ ] **Step 3: Implement**

`lib/src/debt.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/src/money.dart';

part 'debt.freezed.dart';

enum DebtType { creditCard, loan, personal }

@freezed
abstract class Debt with _$Debt {
  const factory Debt({
    required String id,
    required String name,
    required DebtType type,
    required Money balance,

    /// Annual percentage rate in basis points (1995 = 19.95%).
    required int aprBps,

    /// Minimum payment as a share of the balance, in basis points.
    required int minPaymentPercentBps,

    /// The minimum payment is never less than this (unless the balance is).
    required Money minPaymentFloor,

    /// Whether payments above the minimum are allowed.
    required bool allowsOverpayment,
  }) = _Debt;
}
```

`lib/src/validation.dart`:
```dart
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/money.dart';

/// Largest accepted amount: 1,000,000,000.00 in a two-decimal currency.
const int kMaxAmountMinor = 100000000000;

enum DebtValidationError {
  nameEmpty,
  balanceNotPositive,
  balanceTooLarge,
  aprOutOfRange,
  minPaymentPercentOutOfRange,
  minPaymentFloorNegative,
  minPaymentFloorTooLarge,
}

enum BudgetValidationError { notPositive, tooLarge }

Set<DebtValidationError> validateDebt(Debt debt) => {
  if (debt.name.trim().isEmpty) DebtValidationError.nameEmpty,
  if (!debt.balance.isPositive) DebtValidationError.balanceNotPositive,
  if (debt.balance.minor > kMaxAmountMinor) DebtValidationError.balanceTooLarge,
  if (debt.aprBps < 0 || debt.aprBps > 10000) DebtValidationError.aprOutOfRange,
  if (debt.minPaymentPercentBps < 0 || debt.minPaymentPercentBps > 10000)
    DebtValidationError.minPaymentPercentOutOfRange,
  if (debt.minPaymentFloor.isNegative)
    DebtValidationError.minPaymentFloorNegative,
  if (debt.minPaymentFloor.minor > kMaxAmountMinor)
    DebtValidationError.minPaymentFloorTooLarge,
};

Set<BudgetValidationError> validateBudget(Money budget) => {
  if (!budget.isPositive) BudgetValidationError.notPositive,
  if (budget.minor > kMaxAmountMinor) BudgetValidationError.tooLarge,
};
```

Replace `lib/payoff_engine.dart` with:
```dart
/// Pure-Dart debt payoff calculator for Debt Destroyer.
library;

export 'src/debt.dart';
export 'src/money.dart';
export 'src/rounding.dart';
export 'src/validation.dart';
```

Then generate the freezed code: `dart run build_runner build -d`
Expected: `Built with build_runner`, and `lib/src/debt.freezed.dart` exists (git ignores it).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `dart test && dart analyze --fatal-infos`
Expected: `+18: All tests passed!`, then `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add packages/payoff_engine
git commit -m "feat(engine): add Debt model and input validation"
```

---

### Task 4: Strategies and debt ordering

**Files:**
- Create: `packages/payoff_engine/lib/src/strategy.dart`
- Create: `packages/payoff_engine/lib/src/debt_ordering.dart`
- Modify: `packages/payoff_engine/lib/payoff_engine.dart`
- Test: `packages/payoff_engine/test/strategy_test.dart`
- Test: `packages/payoff_engine/test/debt_ordering_test.dart`

**Interfaces:**
- Consumes: `Debt` (Task 3).
- Produces:
  - `enum StrategyId { avalanche, lowestAprFirst, boosted, consolidation, balanceTransfer }`. The declaration order is the display order.
  - A sealed freezed `Strategy`, with the variants:
    - `Avalanche` (`Strategy.avalanche()`)
    - `LowestAprFirst` (`Strategy.lowestAprFirst()`)
    - `Boosted` (`Strategy.boosted({int budgetPercent = 110})`)
    - `Consolidation` (`Strategy.consolidation({required int aprBps})`)
    - `BalanceTransfer` (`Strategy.balanceTransfer({required int feeBps, required int promoMonths, required int revertAprBps})`)

    Each variant exposes `StrategyId get id`.
  - freezed `StrategyParameters({int consolidationAprBps = 500, int transferFeeBps = 400, int promoMonths = 12, int revertAprBps = 1500})`
  - `List<Strategy> standardStrategies(StrategyParameters)`
  - `int compareHighestAprFirst(Debt, Debt)` and `int compareLowestAprFirst(Debt, Debt)`, which break ties by name, then id.

- [ ] **Step 1: Write the failing tests**

`test/strategy_test.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

void main() {
  test('each strategy reports its id', () {
    expect(const Strategy.avalanche().id, StrategyId.avalanche);
    expect(const Strategy.lowestAprFirst().id, StrategyId.lowestAprFirst);
    expect(const Strategy.boosted().id, StrategyId.boosted);
    expect(
      const Strategy.consolidation(aprBps: 400).id,
      StrategyId.consolidation,
    );
    expect(
      const Strategy.balanceTransfer(
        feeBps: 400,
        promoMonths: 15,
        revertAprBps: 1500,
      ).id,
      StrategyId.balanceTransfer,
    );
  });

  test('default parameters match the legacy Settings-screen defaults', () {
    const p = StrategyParameters();
    expect(p.consolidationAprBps, 500);
    expect(p.transferFeeBps, 400);
    expect(p.promoMonths, 12);
    expect(p.revertAprBps, 1500);
  });

  test('standardStrategies lists all five in display order', () {
    final ids = standardStrategies(const StrategyParameters()).map((s) => s.id);
    expect(ids, StrategyId.values);
  });

  test('boosted defaults to 110% of the budget', () {
    const boosted = Strategy.boosted() as Boosted;
    expect(boosted.budgetPercent, 110);
  });
}
```

`test/debt_ordering_test.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // Legacy bug: `(int) (a - b) * 100` made APRs < 1% apart compare equal.
  final low = debt(id: 'a', name: 'Alpha', balance: 100, aprBps: 1800);
  final high = debt(id: 'b', name: 'Beta', balance: 100, aprBps: 1850);

  test('highest-first separates APRs less than 1% apart', () {
    expect([low, high]..sort(compareHighestAprFirst), [high, low]);
  });

  test('lowest-first separates APRs less than 1% apart', () {
    expect([high, low]..sort(compareLowestAprFirst), [low, high]);
  });

  test('ties break by name, then id', () {
    final b = debt(id: '2', name: 'Bravo', balance: 100, aprBps: 1000);
    final a1 = debt(id: '1', name: 'Alpha', balance: 100, aprBps: 1000);
    final a0 = debt(id: '0', name: 'Alpha', balance: 100, aprBps: 1000);
    expect([b, a1, a0]..sort(compareHighestAprFirst), [a0, a1, b]);
    expect([b, a1, a0]..sort(compareLowestAprFirst), [a0, a1, b]);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `dart test test/strategy_test.dart test/debt_ordering_test.dart`
Expected: FAIL to load, because `Strategy`, `StrategyId` and `compareHighestAprFirst` are undefined.

- [ ] **Step 3: Implement**

`lib/src/strategy.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'strategy.freezed.dart';

enum StrategyId {
  avalanche,
  lowestAprFirst,
  boosted,
  consolidation,
  balanceTransfer,
}

@freezed
sealed class Strategy with _$Strategy {
  /// Pay the highest-APR debt first.
  const factory Strategy.avalanche() = Avalanche;

  /// Pay the lowest-APR debt first.
  const factory Strategy.lowestAprFirst() = LowestAprFirst;

  /// Avalanche with the budget raised to [budgetPercent] percent.
  const factory Strategy.boosted({@Default(110) int budgetPercent}) = Boosted;

  /// Replace all debts with one loan at [aprBps]; the whole budget is the
  /// fixed monthly payment.
  const factory Strategy.consolidation({required int aprBps}) = Consolidation;

  /// Move all debts to a 0% card, adding a [feeBps] transfer fee. Interest at
  /// [revertAprBps] starts in month `promoMonths + 1`.
  const factory Strategy.balanceTransfer({
    required int feeBps,
    required int promoMonths,
    required int revertAprBps,
  }) = BalanceTransfer;

  const Strategy._();

  StrategyId get id => switch (this) {
    Avalanche() => StrategyId.avalanche,
    LowestAprFirst() => StrategyId.lowestAprFirst,
    Boosted() => StrategyId.boosted,
    Consolidation() => StrategyId.consolidation,
    BalanceTransfer() => StrategyId.balanceTransfer,
  };
}

/// Defaults are the legacy app's Settings-screen values (preferences.xml).
@freezed
abstract class StrategyParameters with _$StrategyParameters {
  const factory StrategyParameters({
    @Default(500) int consolidationAprBps,
    @Default(400) int transferFeeBps,
    @Default(12) int promoMonths,
    @Default(1500) int revertAprBps,
  }) = _StrategyParameters;
}

/// The five strategies compared by the app, in display order.
List<Strategy> standardStrategies(StrategyParameters p) => [
  const Strategy.avalanche(),
  const Strategy.lowestAprFirst(),
  const Strategy.boosted(),
  Strategy.consolidation(aprBps: p.consolidationAprBps),
  Strategy.balanceTransfer(
    feeBps: p.transferFeeBps,
    promoMonths: p.promoMonths,
    revertAprBps: p.revertAprBps,
  ),
];
```

`lib/src/debt_ordering.dart`:
```dart
import 'package:payoff_engine/src/debt.dart';

/// Highest APR first; ties broken by name, then id.
int compareHighestAprFirst(Debt a, Debt b) {
  final byApr = b.aprBps.compareTo(a.aprBps);
  return byApr != 0 ? byApr : _byNameThenId(a, b);
}

/// Lowest APR first; ties broken by name, then id.
int compareLowestAprFirst(Debt a, Debt b) {
  final byApr = a.aprBps.compareTo(b.aprBps);
  return byApr != 0 ? byApr : _byNameThenId(a, b);
}

int _byNameThenId(Debt a, Debt b) {
  final byName = a.name.compareTo(b.name);
  return byName != 0 ? byName : a.id.compareTo(b.id);
}
```

Replace `lib/payoff_engine.dart` with:
```dart
/// Pure-Dart debt payoff calculator for Debt Destroyer.
library;

export 'src/debt.dart';
export 'src/debt_ordering.dart';
export 'src/money.dart';
export 'src/rounding.dart';
export 'src/strategy.dart';
export 'src/validation.dart';
```

Then run: `dart run build_runner build -d`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `dart test && dart analyze --fatal-infos`
Expected: `+25: All tests passed!`, then `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add packages/payoff_engine
git commit -m "feat(engine): add strategies and exact APR ordering"
```

---

### Task 5: Payoff results and the core calculator

This task implements the monthly loop for the three direct strategies (avalanche, lowest-APR-first and boosted), including the 1200-month cap. The consolidation and balance-transfer strategies throw `UnimplementedError` until Task 7. Budget checks and overflow protection come in Task 6.

**Files:**
- Create: `packages/payoff_engine/lib/src/payoff_result.dart`
- Create: `packages/payoff_engine/lib/src/calculator.dart`
- Modify: `packages/payoff_engine/lib/payoff_engine.dart`
- Modify: `packages/payoff_engine/test/helpers.dart` (add `planOf`)
- Test: `packages/payoff_engine/test/calculator_test.dart`

**Interfaces:**
- Consumes: `Money`, `divideHalfEven`, `Debt`, `Strategy` and its variants, `compareHighestAprFirst`, `compareLowestAprFirst`.
- Produces:
  - A sealed freezed `PayoffResult` with three variants. `strategyId` is common to all of them.
    - `Feasible({StrategyId strategyId, PayoffPlan plan})`
    - `Infeasible({StrategyId strategyId, Money shortfall, int month})`
    - `NeverClears({StrategyId strategyId})`
  - freezed `PlanDebt({String id, String name, Money startingBalance})`
  - freezed `MonthRow({int month, List<Money> interest, List<Money> payments, List<Money> closingBalances})`. The lists are indexed like `PayoffPlan.debts`.
  - freezed `PayoffPlan({List<PlanDebt> debts, List<MonthRow> months, Money totalPaid, Money totalInterest, Money totalFees})`, with the getters `int monthsToClear` and `List<String> payoffOrder`.
  - `const int kMaxMonths = 1200`
  - `PayoffResult calculate({required List<Debt> debts, required Money monthlyBudget, required Strategy strategy})`
  - Test helper: `PayoffPlan planOf(PayoffResult)`, which throws if the result isn't `Feasible`.

- [ ] **Step 1: Add `planOf` to the test helpers**

Append to `test/helpers.dart`:
```dart
PayoffPlan planOf(PayoffResult result) => switch (result) {
  Feasible(:final plan) => plan,
  _ => throw StateError('Expected a feasible result, got $result'),
};
```

- [ ] **Step 2: Write the failing test**

`test/calculator_test.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const avalanche = Strategy.avalanche();

  PayoffResult run(List<Debt> debts, int budget, [Strategy s = avalanche]) =>
      calculate(debts: debts, monthlyBudget: gbp(budget), strategy: s);

  group('calculate — monthly mechanics', () {
    test('clears an interest-free debt in budget-sized steps', () {
      final plan = planOf(run([debt(id: 'a', balance: 100000)], 25000));
      expect(plan.monthsToClear, 4);
      expect(plan.totalPaid, gbp(100000));
      expect(plan.totalInterest, gbp(0));
      expect(plan.months.last.closingBalances, [gbp(0)]);
    });

    test('adds interest before paying, rounded half-even to the penny', () {
      // 1200.00 at 12% APR: 1% a month = 12.00; then 100.00 paid.
      final plan = planOf(
        run([debt(id: 'a', balance: 120000, aprBps: 1200)], 10000),
      );
      final first = plan.months.first;
      expect(first.month, 1);
      expect(first.interest, [gbp(1200)]);
      expect(first.payments, [gbp(10000)]);
      expect(first.closingBalances, [gbp(111200)]);
      // Month 2: 1112.00 * 1% = 11.12.
      expect(plan.months[1].interest, [gbp(1112)]);
    });

    test('the final payment is only what is owed', () {
      final plan = planOf(run([debt(id: 'a', balance: 30000)], 25000));
      expect(plan.months.last.payments, [gbp(5000)]);
      expect(plan.totalPaid, gbp(30000));
    });

    test('pays every minimum, then overpays in priority order', () {
      final plan = planOf(
        run([
          debt(id: 'low', balance: 50000, aprBps: 1200, minPaymentFloor: 1000),
          debt(id: 'high', balance: 50000, aprBps: 2400, minPaymentFloor: 1000),
        ], 10000),
      );
      expect(plan.payoffOrder, ['high', 'low']);
      // Month 1: minimums 10.00 each; the remaining 80.00 goes to 'high'.
      expect(plan.months.first.payments, [gbp(9000), gbp(1000)]);
    });

    test('the minimum is the larger of the floor and the percentage', () {
      final plan = planOf(
        run([
          debt(
            id: 'a',
            balance: 100000,
            minPaymentPercentBps: 300,
            minPaymentFloor: 2500,
            allowsOverpayment: false,
          ),
        ], 10000),
      );
      expect(plan.months[0].payments, [gbp(3000)]); // 3% of 1000.00
      // Once 3% falls below 25.00, the floor applies.
      final floorMonth = plan.months.firstWhere(
        (r) => r.payments.single == gbp(2500),
      );
      expect(floorMonth.month, greaterThan(1));
    });

    test('non-overpayable debts get only their minimum', () {
      final plan = planOf(
        run([
          debt(
            id: 'loan',
            balance: 30000,
            minPaymentFloor: 10000,
            allowsOverpayment: false,
          ),
        ], 50000),
      );
      expect(plan.months.first.payments, [gbp(10000)]);
      expect(plan.monthsToClear, 3);
    });

    test('money freed by clearing a debt moves on in the same month', () {
      final plan = planOf(
        run([
          debt(id: 'a', name: 'A', balance: 3000, aprBps: 2000),
          debt(id: 'b', name: 'B', balance: 50000, aprBps: 1000),
        ], 10000),
      );
      // Month 1: A (30.00 + 0.50 interest) is cleared; the other 69.50
      // goes to B.
      final first = plan.months.first;
      expect(first.payments[0], gbp(3050));
      expect(first.payments[1], gbp(6950));
      expect(first.closingBalances[0], gbp(0));
    });

    test('does not modify the input list or its order', () {
      final input = [
        debt(id: 'low', balance: 1000, aprBps: 100),
        debt(id: 'high', balance: 1000, aprBps: 2000),
      ];
      final copy = [...input];
      run(input, 500, const Strategy.lowestAprFirst());
      run(input, 500);
      expect(input, copy);
    });

    test('rejects debts in a different currency from the budget', () {
      final usd = debt(
        id: 'a',
        balance: 1000,
      ).copyWith(balance: const Money(1000, 'USD'));
      expect(() => run([usd], 500), throwsArgumentError);
    });

    test('no debts gives an empty feasible plan', () {
      for (final s in standardStrategies(const StrategyParameters())) {
        final plan = planOf(run([], 10000, s));
        expect(plan.monthsToClear, 0);
        expect(plan.debts, isEmpty);
        expect(plan.totalPaid, gbp(0));
      }
    });
  });

  group('calculate — strategies', () {
    final debts = [
      debt(
        id: 'x',
        name: 'Alpha',
        balance: 100000,
        aprBps: 1800,
        minPaymentFloor: 2500,
      ),
      debt(
        id: 'y',
        name: 'Beta',
        balance: 100000,
        aprBps: 1850,
        minPaymentFloor: 2500,
      ),
    ];

    test('lowestAprFirst orders ascending by APR', () {
      final plan = planOf(run(debts, 30000, const Strategy.lowestAprFirst()));
      expect(plan.payoffOrder, ['x', 'y']);
    });

    test('boosted raises the budget by 10%', () {
      final plan = planOf(run(debts, 30000, const Strategy.boosted()));
      final firstMonthTotal = plan.months.first.payments.fold(
        gbp(0),
        (a, b) => a + b,
      );
      expect(firstMonthTotal, gbp(33000));
      expect(plan.payoffOrder, ['y', 'x']);
    });
  });

  group('calculate — month cap', () {
    test('never clears when a debt is never paid down', () {
      final result = run([
        debt(id: 'a', balance: 1000, allowsOverpayment: false),
      ], 50000);
      expect(
        result,
        const PayoffResult.neverClears(strategyId: StrategyId.avalanche),
      );
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `dart test test/calculator_test.dart`
Expected: FAIL to load, because `PayoffResult`, `calculate` and `PayoffPlan` are undefined.

- [ ] **Step 4: Implement the result types**

`lib/src/payoff_result.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/strategy.dart';

part 'payoff_result.freezed.dart';

@freezed
sealed class PayoffResult with _$PayoffResult {
  const factory PayoffResult.feasible({
    required StrategyId strategyId,
    required PayoffPlan plan,
  }) = Feasible;

  /// The budget can't cover the minimum payments in [month] (1-based);
  /// it is [shortfall] short.
  const factory PayoffResult.infeasible({
    required StrategyId strategyId,
    required Money shortfall,
    required int month,
  }) = Infeasible;

  /// The debts are not cleared within [kMaxMonths] months.
  const factory PayoffResult.neverClears({required StrategyId strategyId}) =
      NeverClears;
}

/// A debt as it appears in a plan: a column in every [MonthRow].
@freezed
abstract class PlanDebt with _$PlanDebt {
  const factory PlanDebt({
    required String id,
    required String name,
    required Money startingBalance,
  }) = _PlanDebt;
}

@freezed
abstract class MonthRow with _$MonthRow {
  /// Lists are indexed like [PayoffPlan.debts].
  const factory MonthRow({
    required int month,
    required List<Money> interest,
    required List<Money> payments,
    required List<Money> closingBalances,
  }) = _MonthRow;
}

@freezed
abstract class PayoffPlan with _$PayoffPlan {
  const factory PayoffPlan({
    /// In payoff priority order.
    required List<PlanDebt> debts,
    required List<MonthRow> months,
    required Money totalPaid,
    required Money totalInterest,

    /// One-off fees, e.g. a balance-transfer fee.
    required Money totalFees,
  }) = _PayoffPlan;

  const PayoffPlan._();

  int get monthsToClear => months.length;

  List<String> get payoffOrder => [for (final d in debts) d.id];
}

/// Calculation stops after this many months (100 years).
const int kMaxMonths = 1200;
```

- [ ] **Step 5: Implement the calculator**

`lib/src/calculator.dart`:
```dart
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/debt_ordering.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/rounding.dart';
import 'package:payoff_engine/src/strategy.dart';

/// Simulates paying off [debts] with [monthlyBudget] using [strategy].
///
/// Each month: add interest, pay every minimum, then spend what is left on
/// overpayable debts in priority order. Pure: [debts] is not modified.
PayoffResult calculate({
  required List<Debt> debts,
  required Money monthlyBudget,
  required Strategy strategy,
}) {
  final currency = monthlyBudget.currency;
  final zero = Money.zero(currency);
  final originalTotal = debts.fold(zero, (sum, d) => sum + d.balance);

  final budget = switch (strategy) {
    Boosted(:final budgetPercent) => Money(
      divideHalfEven(monthlyBudget.minor * budgetPercent, 100),
      currency,
    ),
    _ => monthlyBudget,
  };

  final ordered = _debtsFor(strategy, debts, originalTotal, budget);
  final fees = ordered.fold(zero, (sum, d) => sum + d.balance) - originalTotal;
  final n = ordered.length;
  final balances = [for (final d in ordered) d.balance.minor];

  final rows = <MonthRow>[];
  var month = 0;
  while (balances.any((b) => b > 0)) {
    if (month == kMaxMonths) {
      return PayoffResult.neverClears(strategyId: strategy.id);
    }
    month++;

    final interest = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      if (balances[i] <= 0) continue;
      final apr = ordered[i].aprBps;
      interest[i] = divideHalfEven(balances[i] * apr, 120000);
      balances[i] += interest[i];
    }

    final payments = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      if (balances[i] <= 0) continue;
      final d = ordered[i];
      final byPercent = divideHalfEven(
        balances[i] * d.minPaymentPercentBps,
        10000,
      );
      final minimum = byPercent > d.minPaymentFloor.minor
          ? byPercent
          : d.minPaymentFloor.minor;
      payments[i] = minimum < balances[i] ? minimum : balances[i];
    }
    final minimumsTotal = payments.fold(0, (a, b) => a + b);

    var remaining = budget.minor - minimumsTotal;
    for (var i = 0; i < n; i++) {
      balances[i] -= payments[i];
      if (remaining > 0 && ordered[i].allowsOverpayment && balances[i] > 0) {
        final extra = remaining < balances[i] ? remaining : balances[i];
        payments[i] += extra;
        balances[i] -= extra;
        remaining -= extra;
      }
    }

    rows.add(
      MonthRow(
        month: month,
        interest: [for (final v in interest) Money(v, currency)],
        payments: [for (final v in payments) Money(v, currency)],
        closingBalances: [for (final v in balances) Money(v, currency)],
      ),
    );
  }

  Money sum(List<Money> Function(MonthRow) column) =>
      rows.fold(zero, (total, row) => column(row).fold(total, (t, m) => t + m));

  return PayoffResult.feasible(
    strategyId: strategy.id,
    plan: PayoffPlan(
      debts: [
        for (final d in ordered)
          PlanDebt(id: d.id, name: d.name, startingBalance: d.balance),
      ],
      months: rows,
      totalPaid: sum((r) => r.payments),
      totalInterest: sum((r) => r.interest),
      totalFees: fees,
    ),
  );
}

List<Debt> _debtsFor(
  Strategy strategy,
  List<Debt> debts,
  Money total,
  Money budget,
) {
  if (total.isZero) return const [];
  return switch (strategy) {
    Avalanche() || Boosted() => [...debts]..sort(compareHighestAprFirst),
    LowestAprFirst() => [...debts]..sort(compareLowestAprFirst),
    Consolidation() || BalanceTransfer() => throw UnimplementedError(
      'Consolidation and balance transfer are added in Task 7',
    ),
  };
}
```

Replace `lib/payoff_engine.dart` with:
```dart
/// Pure-Dart debt payoff calculator for Debt Destroyer.
library;

export 'src/calculator.dart';
export 'src/debt.dart';
export 'src/debt_ordering.dart';
export 'src/money.dart';
export 'src/payoff_result.dart';
export 'src/rounding.dart';
export 'src/strategy.dart';
export 'src/validation.dart';
```

Then run: `dart run build_runner build -d`

- [ ] **Step 6: Run the tests to verify they pass**

Run: `dart test && dart analyze --fatal-infos`
Expected: `+38: All tests passed!`, then `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add packages/payoff_engine
git commit -m "feat(engine): add payoff results and monthly repayment simulation"
```

---

### Task 6: Unpayable budgets and overflow protection

**Files:**
- Modify: `packages/payoff_engine/lib/src/calculator.dart`
- Test: `packages/payoff_engine/test/calculator_unpayable_test.dart`

**Interfaces:**
- Consumes: `calculate`, `PayoffResult`, `kMaxAmountMinor`.
- Produces:
  - `const int kBalanceCeilingMinor = 10000000000000`.
  - `calculate` now returns `Infeasible` in the first month (1-based) whose minimums exceed the budget. It returns `NeverClears` if any balance goes above the ceiling after interest.

- [ ] **Step 1: Write the failing test**

`test/calculator_unpayable_test.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const avalanche = Strategy.avalanche();

  PayoffResult run(List<Debt> debts, int budget, [Strategy s = avalanche]) =>
      calculate(debts: debts, monthlyBudget: gbp(budget), strategy: s);

  group('calculate — unpayable budgets and overflow', () {
    test('is infeasible when the minimums exceed the budget', () {
      final result = run([
        debt(id: 'a', balance: 100000, aprBps: 1200, minPaymentFloor: 2500),
        debt(id: 'b', balance: 100000, aprBps: 1200, minPaymentFloor: 2500),
      ], 4000);
      expect(
        result,
        PayoffResult.infeasible(
          strategyId: StrategyId.avalanche,
          shortfall: gbp(1000),
          month: 1,
        ),
      );
    });

    test(
      'is infeasible in a later month if the minimums grow past the budget',
      () {
        // The minimum (2% of balance) is below the interest (3% a month),
        // so the balance and its minimum both keep growing.
        final result = run([
          debt(
            id: 'a',
            balance: 100000,
            aprBps: 3600,
            minPaymentPercentBps: 200,
            allowsOverpayment: false,
          ),
        ], 2500);
        expect(result, isA<Infeasible>());
        expect((result as Infeasible).month, greaterThan(1));
      },
    );

    test('never clears when payments cannot outpace interest', () {
      // 2% a month on 10,000.00 is 200.00; the fixed minimum is 100.00.
      final result = run([
        debt(
          id: 'a',
          balance: 1000000,
          aprBps: 2400,
          minPaymentFloor: 10000,
          allowsOverpayment: false,
        ),
      ], 50000);
      expect(
        result,
        const PayoffResult.neverClears(strategyId: StrategyId.avalanche),
      );
    });

    test('never clears at the maximum inputs without integer overflow', () {
      final result = run([
        debt(
          id: 'a',
          balance: kMaxAmountMinor,
          aprBps: 10000,
          minPaymentFloor: 1,
          allowsOverpayment: false,
        ),
      ], 100);
      expect(
        result,
        const PayoffResult.neverClears(strategyId: StrategyId.avalanche),
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/calculator_unpayable_test.dart`
Expected: `-4: Some tests failed.` All four tests fail. Without the checks, the calculator overpays past the budget or overflows 64-bit integers and returns nonsense.

- [ ] **Step 3: Add the ceiling constant**

In `lib/src/calculator.dart`, insert this directly above the `/// Simulates paying off` doc comment:
```dart
/// A balance above this (in minor units) means the debt is growing without
/// bound; it also keeps `balance * aprBps` well inside 64-bit integers.
const int kBalanceCeilingMinor = 10000000000000;
```

- [ ] **Step 4: Stop when a balance runs away**

In the interest loop, replace:
```dart
      balances[i] += interest[i];
    }
```
with:
```dart
      balances[i] += interest[i];
      if (balances[i] > kBalanceCeilingMinor) {
        return PayoffResult.neverClears(strategyId: strategy.id);
      }    }
```

- [ ] **Step 5: Return `Infeasible` when the minimums exceed the budget**

Directly after the line `    final minimumsTotal = payments.fold(0, (a, b) => a + b);`, insert:
```dart
    if (minimumsTotal > budget.minor) {
      return PayoffResult.infeasible(
        strategyId: strategy.id,
        shortfall: Money(minimumsTotal - budget.minor, currency),
        month: month,
      );
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `dart test && dart analyze --fatal-infos`
Expected: `+42: All tests passed!`, then `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add packages/payoff_engine
git commit -m "feat(engine): detect infeasible budgets and runaway balances"
```

---

### Task 7: Consolidation and balance-transfer strategies

**Files:**
- Modify: `packages/payoff_engine/lib/src/calculator.dart`
- Test: `packages/payoff_engine/test/calculator_synthetic_test.dart`

**Interfaces:**
- Consumes: `calculate`, `Strategy.consolidation`, `Strategy.balanceTransfer`, `standardStrategies`.
- Produces:
  - `const String kConsolidationDebtId = 'consolidation'` and `const String kBalanceTransferDebtId = 'balance-transfer'`. These are the ids of the synthetic debts, and Plan 3's UI maps them to localised names.
  - `List<PayoffResult> calculateAll({required List<Debt> debts, required Money monthlyBudget, required StrategyParameters parameters})`, which returns one result per strategy in `standardStrategies` order.
  - Balance-transfer interest is 0 in months 1..`promoMonths` and `revertAprBps` from month `promoMonths + 1`. This fixes the legacy off-by-one, which gave one extra free month.

- [ ] **Step 1: Write the failing test**

`test/calculator_synthetic_test.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const avalanche = Strategy.avalanche();

  PayoffResult run(List<Debt> debts, int budget, [Strategy s = avalanche]) =>
      calculate(debts: debts, monthlyBudget: gbp(budget), strategy: s);

  group('calculate — synthetic strategies', () {
    final debts = [
      debt(
        id: 'x',
        name: 'Alpha',
        balance: 100000,
        aprBps: 1800,
        minPaymentFloor: 2500,
      ),
      debt(
        id: 'y',
        name: 'Beta',
        balance: 100000,
        aprBps: 1850,
        minPaymentFloor: 2500,
      ),
    ];

    test('consolidation replaces all debts with one fixed-payment loan', () {
      final plan = planOf(
        run(debts, 30000, const Strategy.consolidation(aprBps: 400)),
      );
      expect(plan.payoffOrder, [kConsolidationDebtId]);
      expect(plan.debts.single.startingBalance, gbp(200000));
      expect(plan.months.first.payments, [gbp(30000)]);
      expect(plan.totalFees, gbp(0));
    });

    test(
      'balance transfer adds the fee and is interest-free for the promo period',
      () {
        final plan = planOf(
          run(
            [debt(id: 'a', balance: 1000000, minPaymentFloor: 2500)],
            50000,
            const Strategy.balanceTransfer(
              feeBps: 400,
              promoMonths: 15,
              revertAprBps: 1500,
            ),
          ),
        );
        expect(plan.payoffOrder, [kBalanceTransferDebtId]);
        expect(plan.debts.single.startingBalance, gbp(1040000));
        expect(plan.totalFees, gbp(40000));
        for (final row in plan.months.take(15)) {
          expect(row.interest, [gbp(0)], reason: 'month ${row.month}');
        }
        // Legacy off-by-one gave 16 free months; interest now starts in
        // month 16.
        expect(plan.months[15].interest.single.isPositive, isTrue);
      },
    );
  });

  test('calculateAll returns one result per standard strategy, in order', () {
    final results = calculateAll(
      debts: [debt(id: 'a', balance: 100000)],
      monthlyBudget: gbp(25000),
      parameters: const StrategyParameters(),
    );
    expect(results.map((r) => r.strategyId), StrategyId.values);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `dart test test/calculator_synthetic_test.dart`
Expected: FAIL to load, because `kConsolidationDebtId` and `calculateAll` are undefined.

- [ ] **Step 3: Add the synthetic debt ids**

In `lib/src/calculator.dart`, insert this directly after the imports:
```dart
const String kConsolidationDebtId = 'consolidation';
const String kBalanceTransferDebtId = 'balance-transfer';
```

- [ ] **Step 4: Use a per-strategy APR**

Replace:
```dart
      final apr = ordered[i].aprBps;
```
with:
```dart
      final apr = _aprFor(strategy, ordered[i], month);
```

- [ ] **Step 5: Build the synthetic debts**

In `_debtsFor`, replace:
```dart
    Consolidation() || BalanceTransfer() => throw UnimplementedError(
      'Consolidation and balance transfer are added in Task 7',
    ),
```
with:
```dart
    Consolidation(:final aprBps) => [
      Debt(
        id: kConsolidationDebtId,
        name: 'Consolidation loan',
        type: DebtType.loan,
        balance: total,
        aprBps: aprBps,
        minPaymentPercentBps: 0,
        minPaymentFloor: budget,
        allowsOverpayment: false,
      ),
    ],
    BalanceTransfer(:final feeBps) => [
      Debt(
        id: kBalanceTransferDebtId,
        name: 'Balance transfer card',
        type: DebtType.creditCard,
        balance:
            total +
            Money(divideHalfEven(total.minor * feeBps, 10000), total.currency),
        aprBps: 0,
        minPaymentPercentBps: 0,
        minPaymentFloor: budget,
        allowsOverpayment: false,
      ),
    ],
```

- [ ] **Step 6: Add `calculateAll` and `_aprFor`**

Insert `calculateAll` directly above `List<Debt> _debtsFor(`:
```dart
/// Runs every strategy in [standardStrategies], in that order.
List<PayoffResult> calculateAll({
  required List<Debt> debts,
  required Money monthlyBudget,
  required StrategyParameters parameters,
}) => [
  for (final strategy in standardStrategies(parameters))
    calculate(debts: debts, monthlyBudget: monthlyBudget, strategy: strategy),
];
```

Then append `_aprFor` to the end of the file:
```dart
int _aprFor(Strategy strategy, Debt debt, int month) => switch (strategy) {
  BalanceTransfer(:final promoMonths, :final revertAprBps) =>
    month <= promoMonths ? 0 : revertAprBps,
  _ => debt.aprBps,
};
```

- [ ] **Step 7: Check the full file**

Run: `dart format lib test && git diff --stat`
Compare `lib/src/calculator.dart` with the reference below. It should now match exactly:
```dart
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/debt_ordering.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/rounding.dart';
import 'package:payoff_engine/src/strategy.dart';

const String kConsolidationDebtId = 'consolidation';
const String kBalanceTransferDebtId = 'balance-transfer';

/// A balance above this (in minor units) means the debt is growing without
/// bound; it also keeps `balance * aprBps` well inside 64-bit integers.
const int kBalanceCeilingMinor = 10000000000000;

/// Simulates paying off [debts] with [monthlyBudget] using [strategy].
///
/// Each month: add interest, pay every minimum, then spend what is left on
/// overpayable debts in priority order. Pure: [debts] is not modified.
PayoffResult calculate({
  required List<Debt> debts,
  required Money monthlyBudget,
  required Strategy strategy,
}) {
  final currency = monthlyBudget.currency;
  final zero = Money.zero(currency);
  final originalTotal = debts.fold(zero, (sum, d) => sum + d.balance);

  final budget = switch (strategy) {
    Boosted(:final budgetPercent) => Money(
      divideHalfEven(monthlyBudget.minor * budgetPercent, 100),
      currency,
    ),
    _ => monthlyBudget,
  };

  final ordered = _debtsFor(strategy, debts, originalTotal, budget);
  final fees = ordered.fold(zero, (sum, d) => sum + d.balance) - originalTotal;
  final n = ordered.length;
  final balances = [for (final d in ordered) d.balance.minor];

  final rows = <MonthRow>[];
  var month = 0;
  while (balances.any((b) => b > 0)) {
    if (month == kMaxMonths) {
      return PayoffResult.neverClears(strategyId: strategy.id);
    }
    month++;

    final interest = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      if (balances[i] <= 0) continue;
      final apr = _aprFor(strategy, ordered[i], month);
      interest[i] = divideHalfEven(balances[i] * apr, 120000);
      balances[i] += interest[i];
      if (balances[i] > kBalanceCeilingMinor) {
        return PayoffResult.neverClears(strategyId: strategy.id);
      }
    }

    final payments = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      if (balances[i] <= 0) continue;
      final d = ordered[i];
      final byPercent = divideHalfEven(
        balances[i] * d.minPaymentPercentBps,
        10000,
      );
      final minimum = byPercent > d.minPaymentFloor.minor
          ? byPercent
          : d.minPaymentFloor.minor;
      payments[i] = minimum < balances[i] ? minimum : balances[i];
    }
    final minimumsTotal = payments.fold(0, (a, b) => a + b);
    if (minimumsTotal > budget.minor) {
      return PayoffResult.infeasible(
        strategyId: strategy.id,
        shortfall: Money(minimumsTotal - budget.minor, currency),
        month: month,
      );
    }

    var remaining = budget.minor - minimumsTotal;
    for (var i = 0; i < n; i++) {
      balances[i] -= payments[i];
      if (remaining > 0 && ordered[i].allowsOverpayment && balances[i] > 0) {
        final extra = remaining < balances[i] ? remaining : balances[i];
        payments[i] += extra;
        balances[i] -= extra;
        remaining -= extra;
      }
    }

    rows.add(
      MonthRow(
        month: month,
        interest: [for (final v in interest) Money(v, currency)],
        payments: [for (final v in payments) Money(v, currency)],
        closingBalances: [for (final v in balances) Money(v, currency)],
      ),
    );
  }

  Money sum(List<Money> Function(MonthRow) column) =>
      rows.fold(zero, (total, row) => column(row).fold(total, (t, m) => t + m));

  return PayoffResult.feasible(
    strategyId: strategy.id,
    plan: PayoffPlan(
      debts: [
        for (final d in ordered)
          PlanDebt(id: d.id, name: d.name, startingBalance: d.balance),
      ],
      months: rows,
      totalPaid: sum((r) => r.payments),
      totalInterest: sum((r) => r.interest),
      totalFees: fees,
    ),
  );
}

/// Runs every strategy in [standardStrategies], in that order.
List<PayoffResult> calculateAll({
  required List<Debt> debts,
  required Money monthlyBudget,
  required StrategyParameters parameters,
}) => [
  for (final strategy in standardStrategies(parameters))
    calculate(debts: debts, monthlyBudget: monthlyBudget, strategy: strategy),
];

List<Debt> _debtsFor(
  Strategy strategy,
  List<Debt> debts,
  Money total,
  Money budget,
) {
  if (total.isZero) return const [];
  return switch (strategy) {
    Avalanche() || Boosted() => [...debts]..sort(compareHighestAprFirst),
    LowestAprFirst() => [...debts]..sort(compareLowestAprFirst),
    Consolidation(:final aprBps) => [
      Debt(
        id: kConsolidationDebtId,
        name: 'Consolidation loan',
        type: DebtType.loan,
        balance: total,
        aprBps: aprBps,
        minPaymentPercentBps: 0,
        minPaymentFloor: budget,
        allowsOverpayment: false,
      ),
    ],
    BalanceTransfer(:final feeBps) => [
      Debt(
        id: kBalanceTransferDebtId,
        name: 'Balance transfer card',
        type: DebtType.creditCard,
        balance:
            total +
            Money(divideHalfEven(total.minor * feeBps, 10000), total.currency),
        aprBps: 0,
        minPaymentPercentBps: 0,
        minPaymentFloor: budget,
        allowsOverpayment: false,
      ),
    ],
  };
}

int _aprFor(Strategy strategy, Debt debt, int month) => switch (strategy) {
  BalanceTransfer(:final promoMonths, :final revertAprBps) =>
    month <= promoMonths ? 0 : revertAprBps,
  _ => debt.aprBps,
};
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `dart test && dart analyze --fatal-infos`
Expected: `+45: All tests passed!`, then `No issues found!`.

- [ ] **Step 9: Commit**

```bash
git add packages/payoff_engine
git commit -m "feat(engine): add consolidation and balance-transfer strategies"
```

---

### Task 8: Legacy reference scenarios and invariant tests

These tests pin the engine against the legacy figures from Task 1's `LegacySolver`, and check its invariants over 300 random inputs. They should **pass on the first run**, because they characterise behaviour that's already built. If one fails, don't edit the expected numbers. Use superpowers:systematic-debugging to find out whether the engine or the test is wrong, check the figure with `java legacy/reference/LegacySolver.java` and spec §4, and report back.

**Files:**
- Test: `packages/payoff_engine/test/legacy_scenarios_test.dart`
- Test: `packages/payoff_engine/test/invariants_test.dart`

**Interfaces:**
- Consumes: `calculateAll`, `calculate`, `standardStrategies`, `StrategyParameters`, `planOf`, `debt`, `gbp`, `divideHalfEven`, `kMaxMonths`.

- [ ] **Step 1: Write the scenario tests**

`test/legacy_scenarios_test.dart`:
```dart
// Reference scenarios cross-checked against the legacy Android algorithm.
// Run `java legacy/reference/LegacySolver.java` from the repo root to
// reproduce the legacy figures quoted in the comments. Differences are
// either float rounding (a few pence) or deliberate bug fixes, noted inline.
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // LegacySolver uses the Java fallback settings (4% loan, 15-month promo).
  const params = StrategyParameters(consolidationAprBps: 400, promoMonths: 15);

  Map<StrategyId, PayoffPlan> runAll(List<Debt> debts, int budget) => {
    for (final r in calculateAll(
      debts: debts,
      monthlyBudget: gbp(budget),
      parameters: params,
    ))
      r.strategyId: planOf(r),
  };

  void expectPlan(
    PayoffPlan plan, {
    required int months,
    required int paid,
    required int interest,
    int fees = 0,
    List<String>? order,
  }) {
    expect(plan.monthsToClear, months, reason: 'months');
    expect(plan.totalPaid, gbp(paid), reason: 'totalPaid');
    expect(plan.totalInterest, gbp(interest), reason: 'totalInterest');
    expect(plan.totalFees, gbp(fees), reason: 'totalFees');
    if (order != null) expect(plan.payoffOrder, order, reason: 'order');
  }

  test('S1: one interest-free card, 1000.00 at 250.00 a month', () {
    final p = runAll([debt(id: 'card', balance: 100000)], 25000);
    // Legacy: 4 months, 1000.00, for all three direct strategies.
    expectPlan(p[StrategyId.avalanche]!, months: 4, paid: 100000, interest: 0);
    expectPlan(
      p[StrategyId.lowestAprFirst]!,
      months: 4,
      paid: 100000,
      interest: 0,
    );
    expectPlan(p[StrategyId.boosted]!, months: 4, paid: 100000, interest: 0);
    // Legacy: 5 months, 1008.42 (interest 8.42).
    expectPlan(
      p[StrategyId.consolidation]!,
      months: 5,
      paid: 100842,
      interest: 842,
    );
    // Legacy: 5 months, 1040.00, but it reported the 40.00 fee as interest.
    expectPlan(
      p[StrategyId.balanceTransfer]!,
      months: 5,
      paid: 104000,
      interest: 0,
      fees: 4000,
    );
  });

  test('S2: one 12% card, 1200.00, min 25.00 or 2%, at 100.00 a month', () {
    final p = runAll([
      debt(
        id: 'card',
        balance: 120000,
        aprBps: 1200,
        minPaymentPercentBps: 200,
        minPaymentFloor: 2500,
      ),
    ], 10000);
    // Legacy: 13 months, 1284.78.
    expectPlan(
      p[StrategyId.avalanche]!,
      months: 13,
      paid: 128478,
      interest: 8478,
    );
    expectPlan(
      p[StrategyId.lowestAprFirst]!,
      months: 13,
      paid: 128478,
      interest: 8478,
    );
    // Legacy: 12 months, 1277.11.
    expectPlan(
      p[StrategyId.boosted]!,
      months: 12,
      paid: 127711,
      interest: 7711,
    );
    // Legacy: 13 months, 1226.73.
    expectPlan(
      p[StrategyId.consolidation]!,
      months: 13,
      paid: 122673,
      interest: 2673,
    );
    // Legacy: 13 months, 1248.00 (fee reported as interest).
    expectPlan(
      p[StrategyId.balanceTransfer]!,
      months: 13,
      paid: 124800,
      interest: 0,
      fees: 4800,
    );
  });

  test('S3: two cards and a fixed-payment loan at 450.00 a month', () {
    final p = runAll([
      debt(
        id: 'c1',
        name: 'Card A',
        balance: 200000,
        aprBps: 1990,
        minPaymentPercentBps: 300,
        minPaymentFloor: 2500,
      ),
      debt(
        id: 'c2',
        name: 'Card B',
        balance: 150000,
        aprBps: 990,
        minPaymentPercentBps: 200,
        minPaymentFloor: 2500,
      ),
      debt(
        id: 'l1',
        name: 'Car loan',
        type: DebtType.loan,
        balance: 300000,
        aprBps: 650,
        minPaymentFloor: 15000,
        allowsOverpayment: false,
      ),
    ], 45000);
    // Legacy: 22 months, 6961.84 (float rounding: 3p lower).
    expectPlan(
      p[StrategyId.avalanche]!,
      months: 22,
      paid: 696187,
      interest: 46187,
      order: ['c1', 'c2', 'l1'],
    );
    // Legacy: 22 months, 7050.05 (2p lower).
    expectPlan(
      p[StrategyId.lowestAprFirst]!,
      months: 22,
      paid: 705007,
      interest: 55007,
      order: ['l1', 'c2', 'c1'],
    );
    // Legacy: 22 months, 6924.92 (3p lower).
    expectPlan(
      p[StrategyId.boosted]!,
      months: 22,
      paid: 692495,
      interest: 42495,
    );
    // Legacy: 15 months, 6672.90 (1p lower).
    expectPlan(
      p[StrategyId.consolidation]!,
      months: 15,
      paid: 667291,
      interest: 17291,
    );
    // Legacy: 16 months, 6760.00. It gave 16 interest-free months instead of
    // 15 (the off-by-one fix adds 0.12 of interest in month 16) and counted
    // the 260.00 fee as interest.
    expectPlan(
      p[StrategyId.balanceTransfer]!,
      months: 16,
      paid: 676012,
      interest: 12,
      fees: 26000,
    );
  });

  test('S4: APRs 0.5% apart are ordered correctly (legacy comparator bug)', () {
    final p = runAll([
      debt(
        id: 'x',
        name: 'Alpha',
        balance: 100000,
        aprBps: 1800,
        minPaymentFloor: 2500,
      ),
      debt(
        id: 'y',
        name: 'Beta',
        balance: 100000,
        aprBps: 1850,
        minPaymentFloor: 2500,
      ),
    ], 30000);
    // Legacy paid Alpha (18.0%) first: 8 months, 2125.72. Beta first is
    // cheaper.
    expectPlan(
      p[StrategyId.avalanche]!,
      months: 8,
      paid: 212424,
      interest: 12424,
      order: ['y', 'x'],
    );
    // Legacy treated the APRs as equal, so lowest-first matched avalanche.
    expectPlan(
      p[StrategyId.lowestAprFirst]!,
      months: 8,
      paid: 212572,
      interest: 12572,
      order: ['x', 'y'],
    );
    // Legacy: 7 months, 2115.44 (Alpha first).
    expectPlan(
      p[StrategyId.boosted]!,
      months: 7,
      paid: 211412,
      interest: 11412,
      order: ['y', 'x'],
    );
    // Legacy: 7 months, 2026.02 (1p lower).
    expectPlan(
      p[StrategyId.consolidation]!,
      months: 7,
      paid: 202603,
      interest: 2603,
    );
    expectPlan(
      p[StrategyId.balanceTransfer]!,
      months: 7,
      paid: 208000,
      interest: 0,
      fees: 8000,
    );
  });
}
```

- [ ] **Step 2: Write the invariant tests**

`test/invariants_test.dart`:
```dart
// Randomised checks of properties every plan must satisfy.
import 'dart:math';

import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const cases = 300;
  final strategies = standardStrategies(const StrategyParameters());

  List<Debt> randomDebts(Random r) => [
    for (var i = 0; i < 1 + r.nextInt(5); i++)
      debt(
        id: 'd$i',
        balance: 1 + r.nextInt(1000000),
        aprBps: r.nextInt(3001),
        minPaymentPercentBps: r.nextInt(501),
        minPaymentFloor: r.nextInt(5001),
        allowsOverpayment: r.nextInt(4) != 0,
      ),
  ];

  Money sum(Iterable<Money> xs) => xs.fold(gbp(0), (a, b) => a + b);

  test('every result satisfies the plan invariants', () {
    final r = Random(42);
    var feasible = 0;
    for (var c = 0; c < cases; c++) {
      final debts = randomDebts(r);
      final budget = gbp(1 + r.nextInt(200000));
      for (final s in strategies) {
        final result = calculate(
          debts: debts,
          monthlyBudget: budget,
          strategy: s,
        );
        final label = 'case $c, ${s.id}';
        switch (result) {
          case Infeasible(:final shortfall, :final month):
            expect(shortfall.isPositive, isTrue, reason: label);
            expect(month, inInclusiveRange(1, kMaxMonths), reason: label);
          case NeverClears():
            break;
          case Feasible(:final plan):
            feasible++;
            final effectiveBudget = s is Boosted
                ? gbp(divideHalfEven(budget.minor * 110, 100))
                : budget;
            final starting = sum(plan.debts.map((d) => d.startingBalance));
            expect(
              starting,
              sum(debts.map((d) => d.balance)) + plan.totalFees,
              reason: label,
            );
            expect(
              plan.totalPaid,
              starting + plan.totalInterest,
              reason: label,
            );
            expect(
              plan.monthsToClear,
              lessThanOrEqualTo(kMaxMonths),
              reason: label,
            );
            for (final (i, row) in plan.months.indexed) {
              expect(row.month, i + 1, reason: label);
              expect(
                row.closingBalances.every((b) => !b.isNegative),
                isTrue,
                reason: label,
              );
              expect(
                row.payments.every((p) => !p.isNegative),
                isTrue,
                reason: label,
              );
              expect(
                sum(row.payments) <= effectiveBudget,
                isTrue,
                reason: label,
              );
            }
            expect(
              plan.months.last.closingBalances.every((b) => b.isZero),
              isTrue,
              reason: label,
            );
            final aprs = [
              for (final id in plan.payoffOrder)
                debts
                    .firstWhere((d) => d.id == id, orElse: () => debts.first)
                    .aprBps,
            ];
            if (s is Avalanche || s is Boosted) {
              for (var i = 1; i < aprs.length; i++) {
                expect(aprs[i - 1] >= aprs[i], isTrue, reason: label);
              }
            }
            if (s is LowestAprFirst) {
              for (var i = 1; i < aprs.length; i++) {
                expect(aprs[i - 1] <= aprs[i], isTrue, reason: label);
              }
            }
        }
      }
    }
    // Guard against a generator that never exercises the feasible path.
    expect(feasible, greaterThan(cases));
  });
}
```

- [ ] **Step 3: Run the full suite**

Run: `dart test && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test`
Expected: `+50: All tests passed!`, then `No issues found!`, and format exits with 0.

- [ ] **Step 4: Commit**

```bash
git add packages/payoff_engine
git commit -m "test(engine): pin legacy reference scenarios and plan invariants"
```

---

### Task 9: CI and developer docs

**Files:**
- Create: `.github/workflows/payoff_engine.yml`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add the workflow**

`.github/workflows/payoff_engine.yml`:
```yaml
name: payoff_engine

on:
  pull_request:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: packages/payoff_engine
    steps:
      - uses: actions/checkout@v5
      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable
      - run: dart pub get
      - run: dart format --output=none --set-exit-if-changed lib test
      - run: dart run build_runner build -d
      - run: dart analyze --fatal-infos
      - run: dart test
```
The format check runs before code generation, so generated files aren't checked.

- [ ] **Step 2: Reproduce the CI steps locally from a clean state**

```bash
cd packages/payoff_engine
git clean -xdf -n .   # preview: .dart_tool/ and *.freezed.dart should be listed
git clean -xdf .
dart pub get && dart format --output=none --set-exit-if-changed lib test && dart run build_runner build -d && dart analyze --fatal-infos && dart test
```
Expected: every step succeeds, ending in `+50: All tests passed!`.

- [ ] **Step 3: Document the commands in CLAUDE.md**

In `CLAUDE.md`, replace the paragraph starting `Update this checklist as the phases complete.` with:
```markdown
Update this checklist as the phases complete.

## Commands

`payoff_engine` (run from `packages/payoff_engine/`):
- `dart pub get`, then `dart run build_runner build -d`. Run the build after a fresh checkout or after any freezed model change, because generated `*.freezed.dart` files are not committed.
- `dart test`: all tests. `dart test test/calculator_test.dart --plain-name "name"` runs one test.
- `dart analyze --fatal-infos` and `dart format lib test`. CI (`.github/workflows/payoff_engine.yml`) enforces both.
- Legacy reference figures: `java legacy/reference/LegacySolver.java` (from the repo root).

Once the Flutter app exists (Plan 2), add its commands here: `flutter test`, a single test via `flutter test path/to_test.dart --plain-name "name"`, and `dart run build_runner build -d`.
```
In the migration checklist, tick `Plan 1: foundation and payoff_engine`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/payoff_engine.yml CLAUDE.md
git commit -m "ci: run payoff_engine format, analyze and tests on PRs"
```
