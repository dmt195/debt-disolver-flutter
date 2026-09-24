# Plan 2: App Shell, Persistence and State — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the Flutter app around `payoff_engine`. It gets on-device storage for debts (Drift) and settings (SharedPreferences), Riverpod state that recalculates every strategy off the UI thread, and a navigable app shell with the onboarding redirect. Plan 3 replaces the placeholder screens with real ones.

**Architecture:** The app is organised by feature: `lib/features/<feature>/{domain,data,presentation}` plus `lib/app/` (dependencies, router, theme) and `lib/core/`.
- **Domain:** each feature defines its repository interfaces there. The data layer implements them with Drift and SharedPreferences.
- **Presentation:** Riverpod providers (with code generation) expose validated actions and derived state.
- **Currency:** there is one app-wide currency. Debts are stored as minor units, and the currency label comes from settings. Changing to a currency with a different number of decimal digits rescales every stored amount.

**Tech Stack:**
- Flutter 3.47.2 stable, Dart 3.13.2
- flutter_riverpod 3.4 with riverpod_annotation/riverpod_generator 4
- drift 2.35 with drift_flutter 0.3
- shared_preferences 2.5 (`SharedPreferencesAsync`)
- go_router 18, freezed 4, intl 0.20, uuid 4
- very_good_analysis 11

**Spec:** `docs/superpowers/specs/2026-09-24-flutter-rebuild-design.md` (§2 layout, §5 data and state, §6 navigation, §8 validation, §9 practices). Read it alongside this plan. This plan also covers the findings deferred from Plan 1's final review.

**This is Plan 2 of 4.** Plan 3 covers the screens and export; Plan 4 covers ads, consent, crash reporting, build flavours and release.

## Global Constraints

- **Toolchain:** Flutter stable 3.47.2 / Dart 3.13.2. The app's `environment.sdk` is `^3.13.2`; `packages/payoff_engine` stays on `^3.9.0` and must not depend on Flutter.
- **App identity:** the project name is `debt_destroyer`, the org is `com.dmt195`, and the platforms are **android and ios only**.
- **Money is never a float.** Debts are stored as integer minor units of the app-wide currency (`AppSettings.currencyCode`). Rates are integer basis points.
- **Defaults** are the legacy Settings-screen values: budget 300 major units, consolidation 500 bps, fee 400 bps, promo 12 months, revert 1500 bps. They come from `AppSettings.defaults` and `StrategyParameters()` only.
- **Validation:** nothing invalid reaches storage or the calculator. Use `validateDebt`, `validateDebtList`, `validateBudget` and `validateStrategyParameters` from `payoff_engine`.
- **Riverpod 3 pauses providers that have no listener.** A `StreamProvider` read without a listener never emits. Tests must call `container.listen(provider, (_, _) {})` before reading `.future`. `select`/`selectAsync` come from `flutter_riverpod`, and `Override` from `package:flutter_riverpod/misc.dart`.
- **Generated code** (`*.g.dart`, `*.freezed.dart`) is not committed. Run `./tool/codegen.sh`, which builds the engine and then the app. The app imports the engine's generated freezed classes, so the order matters.
- **Lints:** `very_good_analysis`, with `public_member_api_docs` and `unnecessary_type_name_in_constructor` disabled. `dart analyze --fatal-infos` must be clean, and `dart format` must leave no changes.
- **TDD is mandatory:** write the failing test, watch it fail, write the minimal code, watch it pass, then commit.
- **Out of scope here:**
  - Build flavours (dev/prod, spec §9) and ads move to Plan 4, because they are release concerns that need Xcode scheme work.
  - Localised strings (ARB files) come with the real screens in Plan 3. Placeholder titles are plain English.

## Review Focus

1. **Switching currency to or from one with different decimal digits** (GBP ↔ JPY): amounts should keep their face value (1,234.56 → ¥1,235 → 1,235.00), never jump 100×. Covered in Task 5 ("rescales the budget and debts when decimal digits differ") and Task 6 ("relabels and rescales after a currency change").
2. **Corrupt or out-of-range stored settings** (for example after a downgrade or a manual edit): these should fall back to defaults instead of crashing or feeding the calculator bad values. Covered in Task 3 ("falls back to defaults for bad stored values").
3. **The app is killed right after a debt is added:** the debt must already be on disk. Covered in Task 4 ("data survives closing and reopening the database file").
4. **Saving an invalid debt, or a 51st one:** it should be rejected with reasons and nothing stored. Covered in Task 6 ("add rejects an invalid debt…", "…beyond the maximum count").
5. **A stale link to an unknown strategy** (`/strategies/nonsense`): it should land on the strategies list, not crash. Covered in Task 8 ("an unknown strategy id falls back to the strategies list").

---

### Task 1: Harden payoff_engine input validation

Plan 1's final review deferred five input-checking findings to this plan. This task adds the missing checks: the floor's currency, list-level rules (count, duplicate ids, mixed currencies), strategy-parameter ranges, and a guard in `calculate` so unvalidated input fails loudly. It also tightens one test.

**Files:**
- Modify: `packages/payoff_engine/lib/src/validation.dart` (full replacement below)
- Modify: `packages/payoff_engine/lib/src/calculator.dart` (three inserts)
- Modify: `packages/payoff_engine/test/calculator_unpayable_test.dart` (one assertion)
- Test: `packages/payoff_engine/test/debt_list_validation_test.dart`
- Test: `packages/payoff_engine/test/calculator_guard_test.dart`

**Interfaces:**
- Produces, all exported from `package:payoff_engine/payoff_engine.dart`:
  - `const int kMaxDebts = 50` and `const int kMaxPromoMonths = 120`
  - a new `DebtValidationError.floorCurrencyMismatch` value
  - `enum DebtListValidationError { tooMany, duplicateId, mixedCurrencies }` with `Set<DebtListValidationError> validateDebtList(List<Debt>)`
  - `enum StrategyParametersValidationError { consolidationAprOutOfRange, transferFeeOutOfRange, promoMonthsOutOfRange, revertAprOutOfRange }` with `Set<StrategyParametersValidationError> validateStrategyParameters(StrategyParameters)`
  - `calculate(...)` now throws `ArgumentError` for a negative budget, or for debts that fail `validateDebt` or `validateDebtList`.

Run the commands in this task from `packages/payoff_engine/`.

- [ ] **Step 1: Write the failing tests**

`test/debt_list_validation_test.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('validateDebt — currency', () {
    test('rejects a minimum floor in a different currency', () {
      final d = debt(
        id: 'a',
        balance: 1000,
      ).copyWith(minPaymentFloor: const Money(500, 'USD'));
      expect(validateDebt(d), {DebtValidationError.floorCurrencyMismatch});
    });
  });

  group('validateDebtList', () {
    test('accepts up to kMaxDebts debts with unique ids', () {
      final debts = [
        for (var i = 0; i < kMaxDebts; i++) debt(id: 'd$i', balance: 100),
      ];
      expect(validateDebtList(debts), isEmpty);
      expect(validateDebtList(const []), isEmpty);
    });

    test('rejects more than kMaxDebts debts', () {
      final debts = [
        for (var i = 0; i <= kMaxDebts; i++) debt(id: 'd$i', balance: 100),
      ];
      expect(validateDebtList(debts), {DebtListValidationError.tooMany});
    });

    test('rejects duplicate ids', () {
      final debts = [debt(id: 'a', balance: 100), debt(id: 'a', balance: 200)];
      expect(validateDebtList(debts), {DebtListValidationError.duplicateId});
    });

    test('rejects debts in different currencies', () {
      final usd = debt(id: 'b', balance: 100).copyWith(
        balance: const Money(100, 'USD'),
        minPaymentFloor: const Money(0, 'USD'),
      );
      expect(validateDebtList([debt(id: 'a', balance: 100), usd]), {
        DebtListValidationError.mixedCurrencies,
      });
    });
  });

  group('validateStrategyParameters', () {
    test('accepts the defaults and the range limits', () {
      expect(validateStrategyParameters(const StrategyParameters()), isEmpty);
      expect(
        validateStrategyParameters(
          const StrategyParameters(
            consolidationAprBps: 0,
            transferFeeBps: 0,
            promoMonths: 0,
            revertAprBps: 0,
          ),
        ),
        isEmpty,
      );
      expect(
        validateStrategyParameters(
          const StrategyParameters(
            consolidationAprBps: 10000,
            transferFeeBps: 10000,
            promoMonths: kMaxPromoMonths,
            revertAprBps: 10000,
          ),
        ),
        isEmpty,
      );
    });

    test('rejects each out-of-range value', () {
      expect(
        validateStrategyParameters(
          const StrategyParameters(
            consolidationAprBps: -1,
            transferFeeBps: 10001,
            promoMonths: kMaxPromoMonths + 1,
            revertAprBps: -5,
          ),
        ),
        {
          StrategyParametersValidationError.consolidationAprOutOfRange,
          StrategyParametersValidationError.transferFeeOutOfRange,
          StrategyParametersValidationError.promoMonthsOutOfRange,
          StrategyParametersValidationError.revertAprOutOfRange,
        },
      );
      expect(
        validateStrategyParameters(const StrategyParameters(promoMonths: -1)),
        {StrategyParametersValidationError.promoMonthsOutOfRange},
      );
    });
  });
}
```

`test/calculator_guard_test.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  PayoffResult run(List<Debt> debts, int budget) => calculate(
    debts: debts,
    monthlyBudget: gbp(budget),
    strategy: const Strategy.avalanche(),
  );

  group('calculate rejects unvalidated input', () {
    test('a negative balance cannot cancel out a real debt', () {
      final debts = [
        debt(id: 'a', balance: 10000),
        debt(id: 'b', balance: -10000),
      ];
      expect(() => run(debts, 5000), throwsArgumentError);
    });

    test('duplicate debt ids', () {
      final debts = [debt(id: 'a', balance: 100), debt(id: 'a', balance: 100)];
      expect(() => run(debts, 5000), throwsArgumentError);
    });

    test('more than kMaxDebts debts', () {
      final debts = [
        for (var i = 0; i <= kMaxDebts; i++) debt(id: 'd$i', balance: 100),
      ];
      expect(() => run(debts, 5000), throwsArgumentError);
    });

    test('a negative budget', () {
      expect(() => run([debt(id: 'a', balance: 100)], -1), throwsArgumentError);
    });
  });

  test('a zero budget is allowed and is infeasible', () {
    final result = run([debt(id: 'a', balance: 100, minPaymentFloor: 10)], 0);
    expect(result, isA<Infeasible>());
  });

  test('the maximum portfolio consolidates without overflow', () {
    final debts = [
      for (var i = 0; i < kMaxDebts; i++)
        debt(id: 'd$i', balance: kMaxAmountMinor, aprBps: 10000),
    ];
    final result = calculate(
      debts: debts,
      monthlyBudget: gbp(kMaxAmountMinor),
      strategy: const Strategy.consolidation(aprBps: 10000),
    );
    expect(result, isA<NeverClears>());
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `dart test test/debt_list_validation_test.dart test/calculator_guard_test.dart`
Expected: FAIL to load, because `kMaxDebts`, `validateDebtList` and `floorCurrencyMismatch` are undefined.

- [ ] **Step 3: Replace `lib/src/validation.dart`**

```dart
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/strategy.dart';

/// Largest accepted amount: 1,000,000,000.00 in a two-decimal currency.
const int kMaxAmountMinor = 100000000000;

/// Most debts one person can enter. Keeps a consolidated total below the
/// calculator's overflow ceiling.
const int kMaxDebts = 50;

/// Longest accepted 0% promotional period.
const int kMaxPromoMonths = 120;

enum DebtValidationError {
  nameEmpty,
  balanceNotPositive,
  balanceTooLarge,
  aprOutOfRange,
  minPaymentPercentOutOfRange,
  minPaymentFloorNegative,
  minPaymentFloorTooLarge,
  floorCurrencyMismatch,
}

enum DebtListValidationError { tooMany, duplicateId, mixedCurrencies }

enum StrategyParametersValidationError {
  consolidationAprOutOfRange,
  transferFeeOutOfRange,
  promoMonthsOutOfRange,
  revertAprOutOfRange,
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
  if (debt.minPaymentFloor.currency != debt.balance.currency)
    DebtValidationError.floorCurrencyMismatch,
};

Set<BudgetValidationError> validateBudget(Money budget) => {
  if (!budget.isPositive) BudgetValidationError.notPositive,
  if (budget.minor > kMaxAmountMinor) BudgetValidationError.tooLarge,
};

/// Checks rules that span the whole list; validate each debt with
/// [validateDebt] as well.
Set<DebtListValidationError> validateDebtList(List<Debt> debts) => {
  if (debts.length > kMaxDebts) DebtListValidationError.tooMany,
  if (debts.map((d) => d.id).toSet().length != debts.length)
    DebtListValidationError.duplicateId,
  if (debts.map((d) => d.balance.currency).toSet().length > 1)
    DebtListValidationError.mixedCurrencies,
};

Set<StrategyParametersValidationError> validateStrategyParameters(
  StrategyParameters p,
) => {
  if (!_isRate(p.consolidationAprBps))
    StrategyParametersValidationError.consolidationAprOutOfRange,
  if (!_isRate(p.transferFeeBps))
    StrategyParametersValidationError.transferFeeOutOfRange,
  if (p.promoMonths < 0 || p.promoMonths > kMaxPromoMonths)
    StrategyParametersValidationError.promoMonthsOutOfRange,
  if (!_isRate(p.revertAprBps))
    StrategyParametersValidationError.revertAprOutOfRange,
};

bool _isRate(int bps) => bps >= 0 && bps <= 10000;
```

- [ ] **Step 4: Guard `calculate` against unvalidated input**

In `lib/src/calculator.dart`, add this import after `import 'package:payoff_engine/src/strategy.dart';`:
```dart
import 'package:payoff_engine/src/validation.dart';
```
Directly after the doc line `/// overpayable debts in priority order. Pure: [debts] is not modified.`, add:
```dart
///
/// Throws [ArgumentError] if any debt fails [validateDebt], the list fails
/// [validateDebtList], or [monthlyBudget] is negative.
```
Then insert these lines as the first statements of `calculate`'s body, before `final currency = monthlyBudget.currency;`:
```dart
  if (monthlyBudget.isNegative) {
    throw ArgumentError.value(monthlyBudget, 'monthlyBudget', 'is negative');
  }
  if (validateDebtList(debts).isNotEmpty ||
      debts.any((d) => validateDebt(d).isNotEmpty)) {
    throw ArgumentError.value(debts, 'debts', 'contains invalid debts');
  }
```

- [ ] **Step 5: Pin the later-month infeasible case exactly**

In `test/calculator_unpayable_test.dart`, replace:
```dart
        expect(result, isA<Infeasible>());
        expect((result as Infeasible).month, greaterThan(1));
```
with:
```dart
        // Month 22 is the first whose 2% minimum exceeds 25.00: 25.07.
        expect(
          result,
          PayoffResult.infeasible(
            strategyId: StrategyId.avalanche,
            shortfall: gbp(7),
            month: 22,
          ),
        );
```
This strengthens an existing test against behaviour that already exists, so it passes straight away. It closes Plan 1's deferred "test only asserts month > 1" finding.

- [ ] **Step 6: Run the whole engine suite**

Run: `dart run build_runner build -d && dart test && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test`
Expected: `+63: All tests passed!`, then `No issues found!`, and format exits with 0. Every earlier test still passes: the random invariants, the legacy scenarios, and the currency test (which now also fails validation).

- [ ] **Step 7: Commit**

```bash
git add packages/payoff_engine
git commit -m "feat(engine): validate debt lists and strategy parameters; guard calculate"
```

---

### Task 2: Flutter app scaffold and currency helpers

**Files:**
- Create (with `flutter create`): `android/`, `ios/`, `lib/main.dart`, `.metadata`, `README.md`
- Modify: `.gitignore` (append the Flutter entries)
- Create: `pubspec.yaml` (replacing the generated one), `analysis_options.yaml`, `tool/codegen.sh`
- Create: `lib/core/currency.dart`
- Test: `test/core/currency_test.dart`

**Interfaces:**
- Produces (in `package:debt_destroyer/core/currency.dart`):
  - `const String kFallbackCurrencyCode = 'GBP'`
  - `bool isCurrencyCode(String)`
  - `String currencyCodeForLocale(String locale)`
  - `int currencyDecimalDigits(String currencyCode)`
  - `int rescaleMinor(int minor, {required int fromDigits, required int toDigits})`
- Produces: `./tool/codegen.sh`, which every later task runs after changing annotated code.

Run the commands in this task and every later task from the repo root.

- [ ] **Step 1: Generate the Flutter project in the repo root**

```bash
flutter create . --project-name debt_destroyer --org com.dmt195 --platforms android,ios --empty
```
Expected: `Your empty application code is in ./lib/main.dart.` The existing root `.gitignore`, `CLAUDE.md`, `docs/`, `legacy/` and `packages/` are left untouched. `flutter create` doesn't overwrite existing files, which is why Step 2 adds the Flutter ignore rules by hand.

- [ ] **Step 2: Append the Flutter ignore rules to `.gitignore`**

```gitignore
# Flutter / Dart
.dart_tool/
.flutter-plugins-dependencies
build/
coverage/
.idea/
*.iml

# Generated code: run tool/codegen.sh
*.g.dart
*.freezed.dart
```
Then check with `git status --short | grep -E '\.idea|\.iml|\.dart_tool|build/' || echo clean`. Expected: `clean`.

- [ ] **Step 3: Replace `pubspec.yaml`**

```yaml
name: debt_destroyer
description: "Compare debt payoff strategies and plan your way to debt freedom."
publish_to: none
version: 0.1.0+1

environment:
  sdk: ^3.13.2

dependencies:
  drift: ^2.35.0
  drift_flutter: ^0.3.1
  flutter:
    sdk: flutter
  flutter_riverpod: ^3.4.3
  freezed_annotation: ^3.1.0
  go_router: ^18.0.1
  intl: ^0.20.3
  payoff_engine:
    path: packages/payoff_engine
  riverpod_annotation: ^4.0.7
  shared_preferences: ^2.5.5
  uuid: ^4.6.0

dev_dependencies:
  build_runner: ^2.16.1
  drift_dev: ^2.35.0
  flutter_test:
    sdk: flutter
  freezed: ^4.0.2
  riverpod_generator: ^4.0.9
  shared_preferences_platform_interface: ^2.4.2
  very_good_analysis: ^11.0.0

flutter:
  uses-material-design: true
```

- [ ] **Step 4: Replace `analysis_options.yaml`**

```yaml
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  exclude:
    - build/**
    - android/**
    - ios/**
    - legacy/**
    - packages/**
    - "**/*.g.dart"
    - "**/*.freezed.dart"

linter:
  rules:
    public_member_api_docs: false
    # Keep `const factory Name(...)` style, matching packages/payoff_engine
    # (Dart 3.9) and freezed's documented syntax.
    unnecessary_type_name_in_constructor: false
```

- [ ] **Step 5: Add the codegen script**

`tool/codegen.sh`:
```bash
#!/usr/bin/env bash
# Generates all build_runner code: the payoff_engine package first (the app
# imports its generated freezed classes), then the app.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd packages/payoff_engine && dart pub get && dart run build_runner build -d)
flutter pub get
dart run build_runner build -d
```
Run: `chmod +x tool/codegen.sh && ./tool/codegen.sh`
Expected: it finishes with `Built with build_runner`. The app has no annotated code yet, so it writes 0 outputs.

- [ ] **Step 6: Write the failing test**

`test/core/currency_test.dart`:
```dart
import 'package:debt_destroyer/core/currency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognises ISO currency codes', () {
    expect(isCurrencyCode('GBP'), isTrue);
    expect(isCurrencyCode('gbp'), isFalse);
    expect(isCurrencyCode('£'), isFalse);
    expect(isCurrencyCode('EURO'), isFalse);
  });

  test('derives the currency from the locale', () {
    expect(currencyCodeForLocale('en_GB'), 'GBP');
    expect(currencyCodeForLocale('en_US'), 'USD');
    expect(currencyCodeForLocale('ja_JP'), 'JPY');
    expect(currencyCodeForLocale('de_DE'), 'EUR');
  });

  test('falls back to GBP for an unknown locale', () {
    expect(currencyCodeForLocale('xx_YY'), kFallbackCurrencyCode);
  });

  test('knows how many decimal digits a currency uses', () {
    expect(currencyDecimalDigits('GBP'), 2);
    expect(currencyDecimalDigits('JPY'), 0);
    expect(currencyDecimalDigits('KWD'), 3);
  });

  group('rescaleMinor', () {
    test('keeps the amount when digits match', () {
      expect(rescaleMinor(12345, fromDigits: 2, toDigits: 2), 12345);
    });

    test('adds digits when the new currency has more', () {
      expect(rescaleMinor(1235, fromDigits: 0, toDigits: 2), 123500);
    });

    test('drops digits with half-even rounding', () {
      expect(rescaleMinor(123456, fromDigits: 2, toDigits: 0), 1235);
      expect(rescaleMinor(250, fromDigits: 2, toDigits: 0), 2);
      expect(rescaleMinor(350, fromDigits: 2, toDigits: 0), 4);
    });
  });
}
```

- [ ] **Step 7: Run it to verify it fails**

Run: `flutter test test/core/currency_test.dart`
Expected: FAIL to load, because `package:debt_destroyer/core/currency.dart` doesn't exist.

- [ ] **Step 8: Implement**

`lib/core/currency.dart`:
```dart
import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Currency used when the device locale has no recognisable currency.
const String kFallbackCurrencyCode = 'GBP';

final RegExp _currencyCode = RegExp(r'^[A-Z]{3}$');

/// Whether [code] looks like an ISO 4217 code (three capital letters).
bool isCurrencyCode(String code) => _currencyCode.hasMatch(code);

/// The ISO 4217 currency of [locale] (e.g. `en_GB` → `GBP`), or
/// [kFallbackCurrencyCode] if the locale isn't recognised.
String currencyCodeForLocale(String locale) {
  final verified = Intl.verifiedLocale(
    locale,
    NumberFormat.localeExists,
    onFailure: (_) => null,
  );
  if (verified == null) return kFallbackCurrencyCode;
  final code = NumberFormat.simpleCurrency(locale: verified).currencyName;
  return code != null && isCurrencyCode(code) ? code : kFallbackCurrencyCode;
}

/// Number of minor-unit digits for [currencyCode] (GBP 2, JPY 0).
int currencyDecimalDigits(String currencyCode) =>
    NumberFormat.currency(name: currencyCode).decimalDigits ?? 2;

/// Converts a non-negative [minor] amount between currencies with different
/// numbers of decimal digits, keeping the same major-unit value. Rounds half
/// to even when digits are dropped.
int rescaleMinor(int minor, {required int fromDigits, required int toDigits}) {
  if (toDigits >= fromDigits) return minor * _pow10(toDigits - fromDigits);
  return divideHalfEven(minor, _pow10(fromDigits - toDigits));
}

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`
Expected: `No issues found!`, format exits with 0, and `+7: All tests passed!`.

- [ ] **Step 10: Commit**

```bash
git add .gitignore .metadata README.md pubspec.yaml pubspec.lock analysis_options.yaml tool lib test android ios
git status --short | grep -v '^A ' || echo "all staged"   # expect: all staged
git commit -m "feat(app): scaffold Flutter app with currency helpers"
```

---

### Task 3: Settings model and SharedPreferences repository

**Files:**
- Create: `lib/features/settings/domain/app_settings.dart`
- Create: `lib/features/settings/domain/settings_repository.dart`
- Create: `lib/features/settings/data/prefs_settings_repository.dart`
- Test: `test/features/settings/prefs_settings_repository_test.dart`

**Interfaces:**
- Consumes: `currencyDecimalDigits`, `rescaleMinor`, `isCurrencyCode` (Task 2); `Money`, `StrategyParameters`, `validateBudget`, `validateStrategyParameters` (engine).
- Produces:
  - `const int kDefaultMonthlyBudgetMajor = 300`
  - freezed `AppSettings({required String currencyCode, required Money monthlyBudget, required StrategyParameters strategyParameters, required bool onboardingComplete})`, with `factory AppSettings.defaults(String currencyCode)`
  - `abstract interface class SettingsRepository { Future<AppSettings> load(); Future<void> save(AppSettings settings); }`
  - `abstract final class SettingsKeys`, with the string constants `currencyCode`, `monthlyBudgetMinor`, `consolidationAprBps`, `transferFeeBps`, `promoMonths`, `revertAprBps` and `onboardingComplete`
  - `class PrefsSettingsRepository implements SettingsRepository`, with `PrefsSettingsRepository(SharedPreferencesAsync prefs, {required String defaultCurrencyCode})`

- [ ] **Step 1: Write the failing test**

`test/features/settings/prefs_settings_repository_test.dart`:
```dart
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  PrefsSettingsRepository repositoryWith(Map<String, Object> stored) {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(stored);
    return PrefsSettingsRepository(
      SharedPreferencesAsync(),
      defaultCurrencyCode: 'GBP',
    );
  }

  test(
    'loads the legacy Settings-screen defaults when nothing is stored',
    () async {
      final settings = await repositoryWith({}).load();
      expect(settings, AppSettings.defaults('GBP'));
      expect(settings.monthlyBudget, const Money(30000, 'GBP'));
      expect(settings.strategyParameters, const StrategyParameters());
      expect(settings.onboardingComplete, isFalse);
    },
  );

  test('default budget is 300 major units in the default currency', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repo = PrefsSettingsRepository(
      SharedPreferencesAsync(),
      defaultCurrencyCode: 'JPY',
    );
    expect((await repo.load()).monthlyBudget, const Money(300, 'JPY'));
  });

  test('saves and loads every field', () async {
    final repo = repositoryWith({});
    const saved = AppSettings(
      currencyCode: 'USD',
      monthlyBudget: Money(45050, 'USD'),
      strategyParameters: StrategyParameters(
        consolidationAprBps: 399,
        transferFeeBps: 250,
        promoMonths: 18,
        revertAprBps: 2290,
      ),
      onboardingComplete: true,
    );
    await repo.save(saved);
    expect(await repo.load(), saved);
  });

  group('falls back to defaults for bad stored values', () {
    test('an invalid currency code', () async {
      final s = await repositoryWith({SettingsKeys.currencyCode: 'pounds'})
          .load();
      expect(s.currencyCode, 'GBP');
    });

    test('a non-positive budget', () async {
      final s = await repositoryWith({SettingsKeys.monthlyBudgetMinor: -500})
          .load();
      expect(s.monthlyBudget, const Money(30000, 'GBP'));
    });

    test('any out-of-range strategy parameter resets them all', () async {
      final s = await repositoryWith({
        SettingsKeys.consolidationAprBps: 700,
        SettingsKeys.promoMonths: -3,
      }).load();
      expect(s.strategyParameters, const StrategyParameters());
    });

    test('a value stored with the wrong type', () async {
      final s = await repositoryWith({
        SettingsKeys.monthlyBudgetMinor: 'lots',
        SettingsKeys.onboardingComplete: 'yes',
      }).load();
      expect(s.monthlyBudget, const Money(30000, 'GBP'));
      expect(s.onboardingComplete, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/settings/prefs_settings_repository_test.dart`
Expected: FAIL to load, because the settings files don't exist.

- [ ] **Step 3: Implement the model**

`lib/features/settings/domain/app_settings.dart`:
```dart
import 'package:debt_destroyer/core/currency.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/payoff_engine.dart';

part 'app_settings.freezed.dart';

/// Default monthly budget in major units (legacy Settings-screen value).
const int kDefaultMonthlyBudgetMajor = 300;

@freezed
abstract class AppSettings with _$AppSettings {
  const factory AppSettings({
    required String currencyCode,
    required Money monthlyBudget,
    required StrategyParameters strategyParameters,
    required bool onboardingComplete,
  }) = _AppSettings;

  factory AppSettings.defaults(String currencyCode) => AppSettings(
    currencyCode: currencyCode,
    monthlyBudget: Money(
      rescaleMinor(
        kDefaultMonthlyBudgetMajor,
        fromDigits: 0,
        toDigits: currencyDecimalDigits(currencyCode),
      ),
      currencyCode,
    ),
    strategyParameters: const StrategyParameters(),
    onboardingComplete: false,
  );
}
```

`lib/features/settings/domain/settings_repository.dart`:
```dart
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';

abstract interface class SettingsRepository {
  /// Stored settings. Missing or invalid values fall back to defaults.
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}
```

- [ ] **Step 4: Implement the repository**

`lib/features/settings/data/prefs_settings_repository.dart`:
```dart
import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/domain/settings_repository.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preference keys. Every key the app stores is listed here.
abstract final class SettingsKeys {
  static const currencyCode = 'settings.currencyCode';
  static const monthlyBudgetMinor = 'settings.monthlyBudgetMinor';
  static const consolidationAprBps = 'settings.consolidationAprBps';
  static const transferFeeBps = 'settings.transferFeeBps';
  static const promoMonths = 'settings.promoMonths';
  static const revertAprBps = 'settings.revertAprBps';
  static const onboardingComplete = 'settings.onboardingComplete';
}

class PrefsSettingsRepository implements SettingsRepository {
  PrefsSettingsRepository(this._prefs, {required this.defaultCurrencyCode});

  final SharedPreferencesAsync _prefs;

  /// Used until the user picks a currency.
  final String defaultCurrencyCode;

  @override
  Future<AppSettings> load() async {
    final storedCode = await _string(SettingsKeys.currencyCode);
    final currencyCode = storedCode != null && isCurrencyCode(storedCode)
        ? storedCode
        : defaultCurrencyCode;
    final defaults = AppSettings.defaults(currencyCode);

    final budgetMinor = await _int(SettingsKeys.monthlyBudgetMinor);
    final budget = budgetMinor == null
        ? defaults.monthlyBudget
        : Money(budgetMinor, currencyCode);

    const d = StrategyParameters();
    final parameters = StrategyParameters(
      consolidationAprBps:
          await _int(SettingsKeys.consolidationAprBps) ?? d.consolidationAprBps,
      transferFeeBps:
          await _int(SettingsKeys.transferFeeBps) ?? d.transferFeeBps,
      promoMonths: await _int(SettingsKeys.promoMonths) ?? d.promoMonths,
      revertAprBps: await _int(SettingsKeys.revertAprBps) ?? d.revertAprBps,
    );

    return AppSettings(
      currencyCode: currencyCode,
      monthlyBudget: validateBudget(budget).isEmpty
          ? budget
          : defaults.monthlyBudget,
      strategyParameters: validateStrategyParameters(parameters).isEmpty
          ? parameters
          : defaults.strategyParameters,
      onboardingComplete: await _bool(SettingsKeys.onboardingComplete) ?? false,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final p = settings.strategyParameters;
    await _prefs.setString(SettingsKeys.currencyCode, settings.currencyCode);
    await _prefs.setInt(
      SettingsKeys.monthlyBudgetMinor,
      settings.monthlyBudget.minor,
    );
    await _prefs.setInt(
      SettingsKeys.consolidationAprBps,
      p.consolidationAprBps,
    );
    await _prefs.setInt(SettingsKeys.transferFeeBps, p.transferFeeBps);
    await _prefs.setInt(SettingsKeys.promoMonths, p.promoMonths);
    await _prefs.setInt(SettingsKeys.revertAprBps, p.revertAprBps);
    await _prefs.setBool(
      SettingsKeys.onboardingComplete,
      settings.onboardingComplete,
    );
  }

  // A value stored with the wrong type reads as missing.
  Future<String?> _string(String key) => _read(() => _prefs.getString(key));
  Future<int?> _int(String key) => _read(() => _prefs.getInt(key));
  Future<bool?> _bool(String key) => _read(() => _prefs.getBool(key));

  Future<T?> _read<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } on Object {
      return null;
    }
  }
}
```

- [ ] **Step 5: Generate code and run the tests**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+14: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings test/features/settings
git commit -m "feat(settings): persist settings with safe fallbacks to defaults"
```

---

### Task 4: Drift database and debt repository

**Files:**
- Create: `build.yaml`
- Create: `lib/features/debts/data/app_database.dart`
- Create: `lib/features/debts/domain/debt_repository.dart`
- Create: `lib/features/debts/data/drift_debt_repository.dart`
- Create: `test/helpers/debts.dart`
- Test: `test/features/debts/drift_debt_repository_test.dart`
- Generated and committed: `drift_schemas/app_database/drift_schema_v1.json`

**Interfaces:**
- Consumes: `rescaleMinor` (Task 2); `Debt`, `DebtType` and `Money` (engine).
- Produces:
  - `class AppDatabase extends _$AppDatabase`, with `AppDatabase(QueryExecutor e)`, `factory AppDatabase.open()` and `schemaVersion == 1`. It has one table, `debts`, whose Dart class is `DebtRows` and whose row class is `DebtRow`.
  - `abstract interface class DebtRepository`:
    ```dart
    Stream<List<Debt>> watchAll(String currencyCode);
    Future<List<Debt>> loadAll(String currencyCode);
    Future<void> add(Debt debt);
    Future<void> update(Debt debt); // throws StateError if the id is missing
    Future<void> delete(String id);
    Future<void> reorder(List<String> idsInOrder); // ArgumentError unless every stored id appears exactly once
    Future<void> rescaleAmounts({required int fromDigits, required int toDigits});
    ```
  - `class DriftDebtRepository implements DebtRepository`, with `DriftDebtRepository(AppDatabase db, {DateTime Function()? now})`
  - Test helper: `Debt testDebt({required String id, String? name, int balance = 100000, int aprBps = 1990, int minPaymentPercentBps = 300, int minPaymentFloor = 2500, bool allowsOverpayment = true, DebtType type = DebtType.creditCard, String currency = 'GBP'})`

- [ ] **Step 1: Write the test helper and the failing test**

`test/helpers/debts.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';

/// A valid credit-card debt in [currency] with amounts in minor units.
Debt testDebt({
  required String id,
  String? name,
  int balance = 100000,
  int aprBps = 1990,
  int minPaymentPercentBps = 300,
  int minPaymentFloor = 2500,
  bool allowsOverpayment = true,
  DebtType type = DebtType.creditCard,
  String currency = 'GBP',
}) => Debt(
  id: id,
  name: name ?? 'Debt $id',
  type: type,
  balance: Money(balance, currency),
  aprBps: aprBps,
  minPaymentPercentBps: minPaymentPercentBps,
  minPaymentFloor: Money(minPaymentFloor, currency),
  allowsOverpayment: allowsOverpayment,
);
```

`test/features/debts/drift_debt_repository_test.dart`:
```dart
import 'dart:io';

import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/debts/data/drift_debt_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';

void main() {
  late AppDatabase db;
  late DriftDebtRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftDebtRepository(db);
  });
  tearDown(() => db.close());

  Future<List<Debt>> all([String currency = 'GBP']) =>
      repo.watchAll(currency).first;

  test('starts empty', () async {
    expect(await all(), isEmpty);
  });

  test('stores every field and appends in insertion order', () async {
    final a = testDebt(id: 'a', name: 'Card A');
    final b = testDebt(
      id: 'b',
      name: 'Car loan',
      type: DebtType.loan,
      balance: 300000,
      aprBps: 650,
      minPaymentPercentBps: 0,
      minPaymentFloor: 15000,
      allowsOverpayment: false,
    );
    await repo.add(a);
    await repo.add(b);
    expect(await all(), [a, b]);
  });

  test('loadAll reads the same list once', () async {
    await repo.add(testDebt(id: 'a'));
    await repo.add(testDebt(id: 'b'));
    expect(await repo.loadAll('GBP'), await all());
  });

  test('labels amounts with the requested currency', () async {
    await repo.add(testDebt(id: 'a', balance: 5000));
    final debts = await all('USD');
    expect(debts.single.balance, const Money(5000, 'USD'));
    expect(debts.single.minPaymentFloor.currency, 'USD');
  });

  test('emits again after each change', () async {
    final lengths = <int>[];
    final sub = repo.watchAll('GBP').listen((d) => lengths.add(d.length));
    addTearDown(sub.cancel);
    // Let each query run before the next change so no emission is merged.
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    await settle();
    await repo.add(testDebt(id: 'a'));
    await settle();
    await repo.add(testDebt(id: 'b'));
    await settle();
    await repo.delete('a');
    await settle();
    expect(lengths, [0, 1, 2, 1]);
  });

  test('updates a debt in place, keeping its position', () async {
    await repo.add(testDebt(id: 'a'));
    await repo.add(testDebt(id: 'b'));
    final changed = testDebt(id: 'a', name: 'Renamed', balance: 1);
    await repo.update(changed);
    expect(await all(), [changed, testDebt(id: 'b')]);
  });

  test('updating a missing debt throws', () async {
    expect(() => repo.update(testDebt(id: 'nope')), throwsStateError);
  });

  test('deleting a missing debt does nothing', () async {
    await repo.add(testDebt(id: 'a'));
    await repo.delete('nope');
    expect(await all(), hasLength(1));
  });

  test('reorders to the given id order', () async {
    for (final id in ['a', 'b', 'c']) {
      await repo.add(testDebt(id: id));
    }
    await repo.reorder(['c', 'a', 'b']);
    expect((await all()).map((d) => d.id), ['c', 'a', 'b']);
    await repo.add(testDebt(id: 'd'));
    expect((await all()).map((d) => d.id), ['c', 'a', 'b', 'd']);
  });

  test('reorder rejects a list that is not exactly the stored ids', () async {
    await repo.add(testDebt(id: 'a'));
    await repo.add(testDebt(id: 'b'));
    expect(() => repo.reorder(['a']), throwsArgumentError);
    expect(() => repo.reorder(['a', 'a']), throwsArgumentError);
    expect(() => repo.reorder(['a', 'x']), throwsArgumentError);
    expect((await all()).map((d) => d.id), ['a', 'b']);
  });

  test('rescales balances and floors between decimal-digit counts', () async {
    await repo.add(testDebt(id: 'a', balance: 123456, minPaymentFloor: 2550));
    await repo.rescaleAmounts(fromDigits: 2, toDigits: 0);
    final debt = (await all('JPY')).single;
    expect(debt.balance, const Money(1235, 'JPY'));
    expect(debt.minPaymentFloor, const Money(26, 'JPY'));
  });

  test('data survives closing and reopening the database file', () async {
    final dir = await Directory.systemTemp.createTemp('debts');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/debts.sqlite');

    final first = AppDatabase(NativeDatabase(file));
    await DriftDebtRepository(first).add(testDebt(id: 'a'));
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final reopened = await DriftDebtRepository(second).watchAll('GBP').first;
    expect(reopened, [testDebt(id: 'a')]);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/debts/drift_debt_repository_test.dart`
Expected: FAIL to load, because `AppDatabase` and `DriftDebtRepository` don't exist.

- [ ] **Step 3: Configure Drift's schema tooling**

`build.yaml`:
```yaml
targets:
  $default:
    builders:
      drift_dev:
        options:
          databases:
            app_database: lib/features/debts/data/app_database.dart
          schema_dir: drift_schemas/
          test_dir: test/drift/
```

- [ ] **Step 4: Implement the database, interface and repository**

`lib/features/debts/data/app_database.dart`:
```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:payoff_engine/payoff_engine.dart';

part 'app_database.g.dart';

/// Debts, with money in minor units of the app-wide currency (see settings).
@DataClassName('DebtRow')
class DebtRows extends Table {
  @override
  String get tableName => 'debts';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => textEnum<DebtType>()();
  IntColumn get balanceMinor => integer()();
  IntColumn get aprBps => integer()();
  IntColumn get minPaymentPercentBps => integer()();
  IntColumn get minPaymentFloorMinor => integer()();
  BoolColumn get allowsOverpayment => boolean()();

  /// Position in the user's own list order (0 first).
  IntColumn get sortIndex => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [DebtRows])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// The on-device database file.
  factory AppDatabase.open() =>
      AppDatabase(driftDatabase(name: 'debt_destroyer'));

  @override
  int get schemaVersion => 1;
}
```

`lib/features/debts/domain/debt_repository.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';

abstract interface class DebtRepository {
  /// All debts in the user's order, re-emitted after every change. Amounts
  /// are labelled with [currencyCode].
  Stream<List<Debt>> watchAll(String currencyCode);

  /// The current debts, read once. Use this rather than the latest stream
  /// value when a decision must see the effect of a write just made.
  Future<List<Debt>> loadAll(String currencyCode);

  /// Appends [debt] to the end of the list.
  Future<void> add(Debt debt);

  /// Replaces the stored debt with the same id. Throws [StateError] if there
  /// is none.
  Future<void> update(Debt debt);

  /// Removes the debt with [id], if it exists.
  Future<void> delete(String id);

  /// Sets the list order. [idsInOrder] must contain every stored id exactly
  /// once, or [ArgumentError] is thrown.
  Future<void> reorder(List<String> idsInOrder);

  /// Converts every stored amount between currencies with different numbers
  /// of decimal digits, keeping the same major-unit values.
  Future<void> rescaleAmounts({required int fromDigits, required int toDigits});
}
```

`lib/features/debts/data/drift_debt_repository.dart`:
```dart
import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/debts/domain/debt_repository.dart';
import 'package:drift/drift.dart';
import 'package:payoff_engine/payoff_engine.dart';

class DriftDebtRepository implements DebtRepository {
  DriftDebtRepository(this._db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  @override
  Stream<List<Debt>> watchAll(String currencyCode) => _ordered().watch().map(
    (rows) => [for (final row in rows) _toDebt(row, currencyCode)],
  );

  @override
  Future<List<Debt>> loadAll(String currencyCode) async => [
    for (final row in await _ordered().get()) _toDebt(row, currencyCode),
  ];

  SimpleSelectStatement<$DebtRowsTable, DebtRow> _ordered() =>
      _db.select(_db.debtRows)..orderBy([
        (t) => OrderingTerm(expression: t.sortIndex),
        (t) => OrderingTerm(expression: t.createdAt),
      ]);

  @override
  Future<void> add(Debt debt) => _db.transaction(() async {
    final max = _db.debtRows.sortIndex.max();
    final query = _db.selectOnly(_db.debtRows)..addColumns([max]);
    final last = await query.map((r) => r.read(max)).getSingle();
    final now = _now();
    await _db
        .into(_db.debtRows)
        .insert(
          _toCompanion(debt).copyWith(
            sortIndex: Value((last ?? -1) + 1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  });

  @override
  Future<void> update(Debt debt) async {
    final changed =
        await (_db.update(_db.debtRows)..where((t) => t.id.equals(debt.id)))
            .write(_toCompanion(debt).copyWith(updatedAt: Value(_now())));
    if (changed == 0) throw StateError('No debt with id ${debt.id}');
  }

  @override
  Future<void> delete(String id) =>
      (_db.delete(_db.debtRows)..where((t) => t.id.equals(id))).go();

  @override
  Future<void> reorder(List<String> idsInOrder) => _db.transaction(() async {
    final stored = await _db.select(_db.debtRows).map((r) => r.id).get();
    if (idsInOrder.length != stored.length ||
        !stored.toSet().containsAll(idsInOrder) ||
        idsInOrder.toSet().length != idsInOrder.length) {
      throw ArgumentError.value(
        idsInOrder,
        'idsInOrder',
        'must list every stored debt id exactly once',
      );
    }
    for (final (index, id) in idsInOrder.indexed) {
      await (_db.update(_db.debtRows)..where((t) => t.id.equals(id))).write(
        DebtRowsCompanion(sortIndex: Value(index)),
      );
    }
  });

  @override
  Future<void> rescaleAmounts({
    required int fromDigits,
    required int toDigits,
  }) => _db.transaction(() async {
    int rescale(int minor) =>
        rescaleMinor(minor, fromDigits: fromDigits, toDigits: toDigits);
    final rows = await _db.select(_db.debtRows).get();
    for (final row in rows) {
      await (_db.update(_db.debtRows)..where((t) => t.id.equals(row.id))).write(
        DebtRowsCompanion(
          balanceMinor: Value(rescale(row.balanceMinor)),
          minPaymentFloorMinor: Value(rescale(row.minPaymentFloorMinor)),
        ),
      );
    }
  });

  Debt _toDebt(DebtRow row, String currencyCode) => Debt(
    id: row.id,
    name: row.name,
    type: row.type,
    balance: Money(row.balanceMinor, currencyCode),
    aprBps: row.aprBps,
    minPaymentPercentBps: row.minPaymentPercentBps,
    minPaymentFloor: Money(row.minPaymentFloorMinor, currencyCode),
    allowsOverpayment: row.allowsOverpayment,
  );

  DebtRowsCompanion _toCompanion(Debt debt) => DebtRowsCompanion(
    id: Value(debt.id),
    name: Value(debt.name),
    type: Value(debt.type),
    balanceMinor: Value(debt.balance.minor),
    aprBps: Value(debt.aprBps),
    minPaymentPercentBps: Value(debt.minPaymentPercentBps),
    minPaymentFloorMinor: Value(debt.minPaymentFloor.minor),
    allowsOverpayment: Value(debt.allowsOverpayment),
  );
}
```

- [ ] **Step 5: Generate code and run the tests**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+26: All tests passed!`.

- [ ] **Step 6: Snapshot schema v1**

Run: `dart run drift_dev make-migrations`
Expected: `INFO: app_database: Creating schema file for version 1`, and the new file `drift_schemas/app_database/drift_schema_v1.json`. Migration tests are generated from version 2 onwards. The steps for a future schema change are documented in CLAUDE.md in Task 9.

- [ ] **Step 7: Commit**

```bash
git add build.yaml drift_schemas lib/features/debts test/helpers test/features/debts
git commit -m "feat(debts): store debts in Drift with ordered, rescalable repository"
```

---

### Task 5: App dependencies and the settings controller

**Files:**
- Create: `lib/app/dependencies.dart`
- Create: `lib/features/settings/presentation/settings_controller.dart`
- Create: `test/helpers/test_container.dart`
- Test: `test/features/settings/settings_controller_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `DriftDebtRepository`, `PrefsSettingsRepository`, `currencyCodeForLocale`, `currencyDecimalDigits`, `rescaleMinor`, `isCurrencyCode`, and the engine validators.
- Produces (all generated keepAlive providers):
  - `appDatabaseProvider`, which provides `AppDatabase` and is overridden in tests
  - `defaultCurrencyCodeProvider`, which provides a `String` and is overridden in tests
  - `settingsRepositoryProvider` (`SettingsRepository`)
  - `debtRepositoryProvider` (`DebtRepository`)
  - `settingsControllerProvider`, which provides `AsyncValue<AppSettings>`. Its notifier `SettingsController` has these methods:
    - `Future<Set<BudgetValidationError>> setMonthlyBudget(int minor)`
    - `Future<Set<StrategyParametersValidationError>> setStrategyParameters(StrategyParameters)`
    - `Future<void> setCurrency(String code)`, which throws `ArgumentError` for a malformed code and rescales the budget and debts when the decimal digits differ
    - `Future<void> completeOnboarding()`
- Test helpers: `List<Override> testOverrides({Map<String, Object> prefs})` and `ProviderContainer createTestContainer({Map<String, Object> prefs})`.

- [ ] **Step 1: Write the test helper and the failing test**

`test/helpers/test_container.dart`:
```dart
import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Test doubles for the app's platform dependencies: in-memory preferences
/// seeded with [prefs], an in-memory database, and GBP as the device
/// currency. Pass the result to a [ProviderContainer] or [ProviderScope].
List<Override> testOverrides({Map<String, Object> prefs = const {}}) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(prefs);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return [
    appDatabaseProvider.overrideWithValue(db),
    defaultCurrencyCodeProvider.overrideWithValue('GBP'),
  ];
}

/// A container with [testOverrides], disposed after the test. Failing
/// providers are not retried, so errors surface immediately.
ProviderContainer createTestContainer({Map<String, Object> prefs = const {}}) =>
    ProviderContainer.test(
      overrides: testOverrides(prefs: prefs),
      retry: (_, _) => null,
    );
```

`test/features/settings/settings_controller_test.dart`:
```dart
import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/test_container.dart';

void main() {
  late ProviderContainer container;
  SettingsController controller() =>
      container.read(settingsControllerProvider.notifier);
  Future<AppSettings> settings() =>
      container.read(settingsControllerProvider.future);
  Future<AppSettings> reloaded() =>
      container.read(settingsRepositoryProvider).load();

  setUp(() => container = createTestContainer());

  test('starts from the stored or default settings', () async {
    expect(await settings(), AppSettings.defaults('GBP'));
  });

  group('setMonthlyBudget', () {
    test('saves a valid budget', () async {
      expect(await controller().setMonthlyBudget(45000), isEmpty);
      expect((await settings()).monthlyBudget, const Money(45000, 'GBP'));
      expect((await reloaded()).monthlyBudget, const Money(45000, 'GBP'));
    });

    test('rejects a non-positive budget and keeps the old one', () async {
      expect(await controller().setMonthlyBudget(0), {
        BudgetValidationError.notPositive,
      });
      expect((await settings()).monthlyBudget, const Money(30000, 'GBP'));
    });
  });

  group('setStrategyParameters', () {
    const custom = StrategyParameters(
      consolidationAprBps: 299,
      promoMonths: 24,
    );

    test('saves valid parameters', () async {
      expect(await controller().setStrategyParameters(custom), isEmpty);
      expect((await settings()).strategyParameters, custom);
      expect((await reloaded()).strategyParameters, custom);
    });

    test('rejects invalid parameters', () async {
      final errors = await controller().setStrategyParameters(
        const StrategyParameters(transferFeeBps: -1),
      );
      expect(errors, {StrategyParametersValidationError.transferFeeOutOfRange});
      expect((await settings()).strategyParameters, const StrategyParameters());
    });
  });

  group('setCurrency', () {
    Future<List<Debt>> debts() async {
      final code = (await settings()).currencyCode;
      return await container.read(debtRepositoryProvider).loadAll(code);
    }

    setUp(() async {
      await container.read(settingsControllerProvider.future);
      await container
          .read(debtRepositoryProvider)
          .add(testDebt(id: 'a', balance: 123456, minPaymentFloor: 2550));
    });

    test('relabels amounts when decimal digits match', () async {
      await controller().setCurrency('USD');
      expect((await settings()).monthlyBudget, const Money(30000, 'USD'));
      expect((await debts()).single.balance, const Money(123456, 'USD'));
    });

    test('rescales the budget and debts when decimal digits differ', () async {
      await controller().setCurrency('JPY');
      expect((await settings()).monthlyBudget, const Money(300, 'JPY'));
      final debt = (await debts()).single;
      expect(debt.balance, const Money(1235, 'JPY'));
      expect(debt.minPaymentFloor, const Money(26, 'JPY'));

      await controller().setCurrency('GBP');
      expect((await settings()).monthlyBudget, const Money(30000, 'GBP'));
      expect((await debts()).single.balance, const Money(123500, 'GBP'));
    });

    test('keeps a tiny budget above zero after rounding', () async {
      await controller().setMonthlyBudget(40);
      await controller().setCurrency('JPY');
      expect((await settings()).monthlyBudget, const Money(1, 'JPY'));
    });

    test('rejects a malformed code', () async {
      expect(() => controller().setCurrency('pounds'), throwsArgumentError);
    });
  });

  test('completeOnboarding is remembered', () async {
    await controller().completeOnboarding();
    expect((await settings()).onboardingComplete, isTrue);
    expect((await reloaded()).onboardingComplete, isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/settings/settings_controller_test.dart`
Expected: FAIL to load, because `package:debt_destroyer/app/dependencies.dart` and the controller don't exist.

- [ ] **Step 3: Implement the dependency providers**

`lib/app/dependencies.dart`:
```dart
import 'dart:ui';

import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/debts/data/drift_debt_repository.dart';
import 'package:debt_destroyer/features/debts/domain/debt_repository.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/domain/settings_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'dependencies.g.dart';

/// The on-device database. Tests override this with an in-memory one.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
}

/// Currency used until the user chooses one: the device locale's.
@Riverpod(keepAlive: true)
String defaultCurrencyCode(Ref ref) =>
    currencyCodeForLocale(PlatformDispatcher.instance.locale.toString());

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) => PrefsSettingsRepository(
  SharedPreferencesAsync(),
  defaultCurrencyCode: ref.watch(defaultCurrencyCodeProvider),
);

@Riverpod(keepAlive: true)
DebtRepository debtRepository(Ref ref) =>
    DriftDebtRepository(ref.watch(appDatabaseProvider));
```

- [ ] **Step 4: Implement the controller**

`lib/features/settings/presentation/settings_controller.dart`:
```dart
import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_controller.g.dart';

/// The app's settings. Every change is validated, saved, then published.
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  @override
  Future<AppSettings> build() => ref.watch(settingsRepositoryProvider).load();

  /// Sets the monthly budget, in minor units of the current currency.
  /// Returns the problems found; nothing is saved unless it is empty.
  Future<Set<BudgetValidationError>> setMonthlyBudget(int minor) async {
    final current = await future;
    final budget = Money(minor, current.currencyCode);
    final errors = validateBudget(budget);
    if (errors.isEmpty) await _save(current.copyWith(monthlyBudget: budget));
    return errors;
  }

  Future<Set<StrategyParametersValidationError>> setStrategyParameters(
    StrategyParameters parameters,
  ) async {
    final errors = validateStrategyParameters(parameters);
    if (errors.isEmpty) {
      await _save((await future).copyWith(strategyParameters: parameters));
    }
    return errors;
  }

  /// Switches currency. Amounts keep their major-unit values: when the
  /// number of decimal digits changes (e.g. GBP → JPY) the budget and every
  /// stored debt are rescaled. Throws [ArgumentError] for a malformed code.
  Future<void> setCurrency(String currencyCode) async {
    if (!isCurrencyCode(currencyCode)) {
      throw ArgumentError.value(currencyCode, 'currencyCode');
    }
    final current = await future;
    if (currencyCode == current.currencyCode) return;
    final fromDigits = currencyDecimalDigits(current.currencyCode);
    final toDigits = currencyDecimalDigits(currencyCode);
    if (fromDigits != toDigits) {
      await ref
          .read(debtRepositoryProvider)
          .rescaleAmounts(fromDigits: fromDigits, toDigits: toDigits);
    }
    final budgetMinor = rescaleMinor(
      current.monthlyBudget.minor,
      fromDigits: fromDigits,
      toDigits: toDigits,
    );
    await _save(
      current.copyWith(
        currencyCode: currencyCode,
        // Never let rounding push a valid budget to zero.
        monthlyBudget: Money(budgetMinor < 1 ? 1 : budgetMinor, currencyCode),
      ),
    );
  }

  Future<void> completeOnboarding() async {
    await _save((await future).copyWith(onboardingComplete: true));
  }

  Future<void> _save(AppSettings next) async {
    await ref.read(settingsRepositoryProvider).save(next);
    state = AsyncData(next);
  }
}
```

- [ ] **Step 5: Generate code and run the tests**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+36: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add lib/app lib/features/settings test/helpers test/features/settings
git commit -m "feat(settings): validated settings controller with currency rescaling"
```

---

### Task 6: Debts stream and validated debt actions

**Files:**
- Create: `lib/features/debts/presentation/debts_providers.dart`
- Test: `test/features/debts/debts_provider_test.dart`
- Test: `test/features/debts/debt_actions_test.dart`

**Interfaces:**
- Consumes: `settingsControllerProvider`, `debtRepositoryProvider`, `validateDebt`, `validateDebtList`.
- Produces:
  - `debtsProvider`, which provides `AsyncValue<List<Debt>>` in the user's order and current currency, and rebuilds when settings change
  - a freezed sealed `DebtSaveOutcome` with two variants: `DebtSaved(Debt debt)` and `DebtRejected({Set<DebtValidationError> errors, Set<DebtListValidationError> listErrors})`
  - `debtActionsProvider`, whose notifier `DebtActions` has these methods:
    - `Future<DebtSaveOutcome> add(Debt draft)`, which assigns a UUID and ignores the draft's id
    - `Future<DebtSaveOutcome> update(Debt debt)`
    - `Future<void> delete(String id)`
    - `Future<void> reorder(List<String> idsInOrder)`

- [ ] **Step 1: Write the failing tests**

`test/features/debts/debts_provider_test.dart`:
```dart
import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/test_container.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    // A StreamProvider with no listener is paused and never emits.
    container = createTestContainer()..listen(debtsProvider, (_, _) {});
  });

  test('streams the stored debts once settings have loaded', () async {
    await container.read(debtRepositoryProvider).add(testDebt(id: 'a'));
    expect(await container.read(debtsProvider.future), [testDebt(id: 'a')]);
  });

  test('relabels and rescales after a currency change', () async {
    await container.read(settingsControllerProvider.future);
    await container
        .read(debtRepositoryProvider)
        .add(testDebt(id: 'a', balance: 123456));
    await container
        .read(settingsControllerProvider.notifier)
        .setCurrency('JPY');
    final debts = await container.read(debtsProvider.future);
    expect(debts.single.balance, const Money(1235, 'JPY'));
  });
}
```

`test/features/debts/debt_actions_test.dart`:
```dart
import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/test_container.dart';

void main() {
  late ProviderContainer container;
  DebtActions actions() => container.read(debtActionsProvider.notifier);
  Future<List<Debt>> debts() =>
      container.read(debtRepositoryProvider).loadAll('GBP');

  setUp(() => container = createTestContainer());

  test('add assigns a fresh id and stores the debt', () async {
    final outcome = await actions().add(testDebt(id: '', name: 'Card'));
    final saved = (outcome as DebtSaved).debt;
    expect(saved.id, isNotEmpty);
    expect(await debts(), [saved]);
  });

  test('add rejects an invalid debt without storing it', () async {
    final outcome = await actions().add(
      testDebt(id: '', name: ' ', balance: 0),
    );
    expect(
      outcome,
      const DebtSaveOutcome.rejected(
        errors: {
          DebtValidationError.nameEmpty,
          DebtValidationError.balanceNotPositive,
        },
      ),
    );
    expect(await debts(), isEmpty);
  });

  test('add rejects a debt beyond the maximum count', () async {
    for (var i = 0; i < kMaxDebts; i++) {
      expect(await actions().add(testDebt(id: '')), isA<DebtSaved>());
    }
    final outcome = await actions().add(testDebt(id: ''));
    expect(
      outcome,
      const DebtSaveOutcome.rejected(
        listErrors: {DebtListValidationError.tooMany},
      ),
    );
    expect(await debts(), hasLength(kMaxDebts));
  });

  test('update validates and stores changes', () async {
    final saved = (await actions().add(testDebt(id: '')) as DebtSaved).debt;
    final renamed = saved.copyWith(name: 'Renamed');
    expect(await actions().update(renamed), DebtSaveOutcome.saved(renamed));
    expect(await debts(), [renamed]);

    final invalid = saved.copyWith(aprBps: -1);
    expect(await actions().update(invalid), isA<DebtRejected>());
    expect(await debts(), [renamed]);
  });

  test('delete and reorder pass through to the repository', () async {
    final a =
        (await actions().add(testDebt(id: '', name: 'A')) as DebtSaved).debt;
    final b =
        (await actions().add(testDebt(id: '', name: 'B')) as DebtSaved).debt;
    await actions().reorder([b.id, a.id]);
    expect((await debts()).map((d) => d.name), ['B', 'A']);
    await actions().delete(b.id);
    expect((await debts()).map((d) => d.name), ['A']);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/debts/debts_provider_test.dart test/features/debts/debt_actions_test.dart`
Expected: FAIL to load, because `debts_providers.dart` doesn't exist.

- [ ] **Step 3: Implement**

`lib/features/debts/presentation/debts_providers.dart`:
```dart
import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'debts_providers.freezed.dart';
part 'debts_providers.g.dart';

/// The user's debts, in their order, in the current currency. Rebuilds when
/// settings change so amounts are always labelled with the current currency.
@Riverpod(keepAlive: true)
Stream<List<Debt>> debts(Ref ref) async* {
  final settings = await ref.watch(settingsControllerProvider.future);
  yield* ref.watch(debtRepositoryProvider).watchAll(settings.currencyCode);
}

@freezed
sealed class DebtSaveOutcome with _$DebtSaveOutcome {
  const factory DebtSaveOutcome.saved(Debt debt) = DebtSaved;

  const factory DebtSaveOutcome.rejected({
    @Default(<DebtValidationError>{}) Set<DebtValidationError> errors,
    @Default(<DebtListValidationError>{})
    Set<DebtListValidationError> listErrors,
  }) = DebtRejected;
}

/// Validated changes to the debt list. Screens call these; nothing invalid
/// reaches the database.
@Riverpod(keepAlive: true)
class DebtActions extends _$DebtActions {
  static const _uuid = Uuid();

  @override
  void build() {}

  /// Adds [draft] with a new id (the draft's id is ignored).
  Future<DebtSaveOutcome> add(Debt draft) async {
    final debt = draft.copyWith(id: _uuid.v4());
    final existing = await _stored();
    final outcome = _validate(debt, [...existing, debt]);
    if (outcome is DebtSaved) await ref.read(debtRepositoryProvider).add(debt);
    return outcome;
  }

  Future<DebtSaveOutcome> update(Debt debt) async {
    final existing = await _stored();
    final list = [
      for (final d in existing)
        if (d.id == debt.id) debt else d,
    ];
    final outcome = _validate(debt, list);
    if (outcome is DebtSaved) {
      await ref.read(debtRepositoryProvider).update(debt);
    }
    return outcome;
  }

  Future<void> delete(String id) => ref.read(debtRepositoryProvider).delete(id);

  Future<void> reorder(List<String> idsInOrder) =>
      ref.read(debtRepositoryProvider).reorder(idsInOrder);

  // Read from the database, not debtsProvider: the stream may not have
  // caught up with a write made a moment ago.
  Future<List<Debt>> _stored() async {
    final settings = await ref.read(settingsControllerProvider.future);
    return await ref
        .read(debtRepositoryProvider)
        .loadAll(settings.currencyCode);
  }

  DebtSaveOutcome _validate(Debt debt, List<Debt> resultingList) {
    final errors = validateDebt(debt);
    final listErrors = validateDebtList(resultingList);
    return errors.isEmpty && listErrors.isEmpty
        ? DebtSaveOutcome.saved(debt)
        : DebtSaveOutcome.rejected(errors: errors, listErrors: listErrors);
  }
}
```
The actions read `debtRepositoryProvider.loadAll` rather than `debtsProvider`: the stream's latest value may not include a write made a moment earlier, and a paused provider never emits.

- [ ] **Step 4: Generate code and run the tests**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+43: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/debts test/features/debts
git commit -m "feat(debts): debts stream and validated add/update/delete/reorder"
```

---

### Task 7: Ranked payoff plans, calculated off the UI thread

**Files:**
- Create: `lib/features/strategies/domain/rank_results.dart`
- Create: `lib/features/strategies/presentation/plans_providers.dart`
- Test: `test/features/strategies/rank_results_test.dart`
- Test: `test/features/strategies/plans_providers_test.dart`

**Interfaces:**
- Consumes: `debtsProvider`, `settingsControllerProvider`, `debtActionsProvider`, `calculateAll`.
- Produces:
  - `List<PayoffResult> rankResults(List<PayoffResult>)`. Feasible results come first, cheapest `totalPaid` first; ties go to fewer months, then `StrategyId` order. Infeasible results come next, then NeverClears. The input list is not modified.
  - `plansProvider`, which provides `AsyncValue<List<PayoffResult>>`, ranked and computed with `compute`
  - `planProvider(StrategyId)`, which provides `AsyncValue<PayoffResult>`

- [ ] **Step 1: Write the failing tests**

`test/features/strategies/rank_results_test.dart`:
```dart
import 'package:debt_destroyer/features/strategies/domain/rank_results.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  const gbp0 = Money.zero('GBP');

  PayoffResult feasible(StrategyId id, {required int paid, int months = 1}) =>
      PayoffResult.feasible(
        strategyId: id,
        plan: PayoffPlan(
          debts: const [],
          months: [
            for (var m = 1; m <= months; m++)
              MonthRow(
                month: m,
                interest: const [],
                payments: const [],
                closingBalances: const [],
              ),
          ],
          totalPaid: Money(paid, 'GBP'),
          totalInterest: gbp0,
          totalFees: gbp0,
        ),
      );

  test('puts feasible plans first, cheapest first', () {
    final ranked = rankResults([
      feasible(StrategyId.avalanche, paid: 500),
      const PayoffResult.neverClears(strategyId: StrategyId.lowestAprFirst),
      feasible(StrategyId.consolidation, paid: 300),
      const PayoffResult.infeasible(
        strategyId: StrategyId.boosted,
        shortfall: Money(1, 'GBP'),
        month: 1,
      ),
      feasible(StrategyId.balanceTransfer, paid: 400),
    ]);
    expect(ranked.map((r) => r.strategyId), [
      StrategyId.consolidation,
      StrategyId.balanceTransfer,
      StrategyId.avalanche,
      StrategyId.boosted,
      StrategyId.lowestAprFirst,
    ]);
  });

  test('breaks cost ties by fewer months, then strategy order', () {
    final ranked = rankResults([
      feasible(StrategyId.boosted, paid: 100, months: 3),
      feasible(StrategyId.lowestAprFirst, paid: 100, months: 2),
      feasible(StrategyId.avalanche, paid: 100, months: 3),
    ]);
    expect(ranked.map((r) => r.strategyId), [
      StrategyId.lowestAprFirst,
      StrategyId.avalanche,
      StrategyId.boosted,
    ]);
  });

  test('does not modify its input', () {
    final input = [
      feasible(StrategyId.avalanche, paid: 2),
      feasible(StrategyId.boosted, paid: 1),
    ];
    rankResults(input);
    expect(input.first.strategyId, StrategyId.avalanche);
  });
}
```

`test/features/strategies/plans_providers_test.dart`:
```dart
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/test_container.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    // Providers with no listener are paused; keep plans (and so debts) live.
    container = createTestContainer()..listen(plansProvider, (_, _) {});
  });

  /// Waits for the plans to reflect the latest debts and settings.
  Future<List<PayoffResult>> settledPlans() async {
    await container.pump();
    await container.read(debtsProvider.future);
    return await container.read(plansProvider.future);
  }

  test('with no debts every strategy is an empty feasible plan', () async {
    final plans = await settledPlans();
    expect(plans, hasLength(StrategyId.values.length));
    for (final result in plans) {
      expect((result as Feasible).plan.monthsToClear, 0);
    }
  });

  test('recalculates when a debt is added, cheapest first', () async {
    await container.read(debtActionsProvider.notifier).add(testDebt(id: ''));
    final plans = await settledPlans();
    final costs = [for (final r in plans) (r as Feasible).plan.totalPaid.minor];
    expect(costs.first, greaterThan(100000));
    expect(costs, [...costs]..sort());
  });

  test('recalculates when the budget changes', () async {
    await container.read(debtActionsProvider.notifier).add(testDebt(id: ''));
    final before = await settledPlans();
    await container
        .read(settingsControllerProvider.notifier)
        .setMonthlyBudget(1000);
    final after = await settledPlans();
    PayoffResult avalanche(List<PayoffResult> r) =>
        r.firstWhere((p) => p.strategyId == StrategyId.avalanche);
    expect(avalanche(before), isA<Feasible>());
    // 10.00 no longer covers the 25.00 minimum.
    expect(avalanche(after), isA<Infeasible>());
  });

  test('plan looks up one strategy by id', () async {
    container.listen(planProvider(StrategyId.consolidation), (_, _) {});
    final result = await container.read(
      planProvider(StrategyId.consolidation).future,
    );
    expect(result.strategyId, StrategyId.consolidation);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/strategies`
Expected: FAIL to load, because `rank_results.dart` and `plans_providers.dart` don't exist.

- [ ] **Step 3: Implement the ranking**

`lib/features/strategies/domain/rank_results.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';

/// Orders results for display: feasible plans cheapest first (ties: fewer
/// months, then strategy order), then infeasible, then never-clearing ones.
List<PayoffResult> rankResults(List<PayoffResult> results) {
  int group(PayoffResult r) => switch (r) {
    Feasible() => 0,
    Infeasible() => 1,
    NeverClears() => 2,
  };
  int compare(PayoffResult a, PayoffResult b) {
    final byGroup = group(a).compareTo(group(b));
    if (byGroup != 0) return byGroup;
    if (a is Feasible && b is Feasible) {
      final byCost = a.plan.totalPaid.compareTo(b.plan.totalPaid);
      if (byCost != 0) return byCost;
      final byMonths = a.plan.monthsToClear.compareTo(b.plan.monthsToClear);
      if (byMonths != 0) return byMonths;
    }
    return a.strategyId.index.compareTo(b.strategyId.index);
  }

  return [...results]..sort(compare);
}
```

- [ ] **Step 4: Implement the providers**

`lib/features/strategies/presentation/plans_providers.dart`:
```dart
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/domain/rank_results.dart';
import 'package:flutter/foundation.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'plans_providers.g.dart';

/// Every strategy's result for the current debts and settings, ranked by
/// [rankResults]. Recalculated off the UI thread whenever either changes.
@riverpod
Future<List<PayoffResult>> plans(Ref ref) async {
  final debts = await ref.watch(debtsProvider.future);
  final settings = await ref.watch(settingsControllerProvider.future);
  final results = await compute(_calculateAll, (
    debts,
    settings.monthlyBudget,
    settings.strategyParameters,
  ));
  return rankResults(results);
}

/// One strategy's result, looked up by id.
@riverpod
Future<PayoffResult> plan(Ref ref, StrategyId strategyId) async {
  final all = await ref.watch(plansProvider.future);
  return all.firstWhere((r) => r.strategyId == strategyId);
}

List<PayoffResult> _calculateAll(
  (List<Debt>, Money, StrategyParameters) input,
) => calculateAll(
  debts: input.$1,
  monthlyBudget: input.$2,
  parameters: input.$3,
);
```

- [ ] **Step 5: Generate code and run the tests**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+50: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/strategies test/features/strategies
git commit -m "feat(strategies): rank payoff plans computed in a background isolate"
```

---

### Task 8: App shell, router and bootstrap

Each screen here is a titled placeholder, which Plan 3 replaces. The routes, the onboarding redirect and the startup sequence are final.

**Files:**
- Create: `lib/app/theme.dart`, `lib/app/router.dart`, `lib/app/app.dart`
- Create: `lib/core/placeholder_screen.dart`
- Create: `lib/features/onboarding/presentation/onboarding_screen.dart`
- Create: `lib/features/debts/presentation/debts_screen.dart`
- Create: `lib/features/strategies/presentation/strategies_screen.dart`
- Create: `lib/features/analysis/presentation/plan_detail_screen.dart`
- Create: `lib/features/settings/presentation/settings_screen.dart`
- Modify: `lib/main.dart` (full replacement)
- Test: `test/app/router_test.dart`

**Interfaces:**
- Consumes: `settingsControllerProvider`, `SettingsKeys`, `testOverrides`.
- Produces:
  - `abstract final class Routes`, with `debts = '/'`, `onboarding = '/onboarding'`, `strategies = '/strategies'`, `settings = '/settings'` and `static String plan(StrategyId id)`, which returns `/strategies/<id.name>`
  - `routerProvider` (`GoRouter`, keepAlive)
  - `DebtDestroyerApp` (a `ConsumerWidget`)
  - `buildTheme(Brightness)` and `kBrandBlue`
  - `PlaceholderScreen({required String title, List<Widget>? actions})`
  - the screen widgets `OnboardingScreen`, `DebtsScreen`, `StrategiesScreen`, `PlanDetailScreen({required StrategyId strategyId})` and `SettingsScreen`

- [ ] **Step 1: Write the failing test**

`test/app/router_test.dart`:
```dart
import 'package:debt_destroyer/app/app.dart';
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../helpers/test_container.dart';

void main() {
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    bool onboardingComplete = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(
          prefs: {SettingsKeys.onboardingComplete: onboardingComplete},
        ),
        child: const DebtDestroyerApp(),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  Future<void> go(WidgetTester tester, ProviderContainer c, String loc) async {
    c.read(routerProvider).go(loc);
    await tester.pumpAndSettle();
  }

  testWidgets('a new user is sent to onboarding', (tester) async {
    final container = await pumpApp(tester);
    expect(find.text('Welcome'), findsWidgets);

    await go(tester, container, Routes.strategies);
    expect(find.text('Welcome'), findsWidgets);
  });

  testWidgets('finishing onboarding opens the debts screen', (tester) async {
    final container = await pumpApp(tester);
    await container
        .read(settingsControllerProvider.notifier)
        .completeOnboarding();
    await tester.pumpAndSettle();
    expect(find.text('Debts'), findsWidgets);
  });

  testWidgets('a returning user starts on debts and can navigate', (
    tester,
  ) async {
    final container = await pumpApp(tester, onboardingComplete: true);
    expect(find.text('Debts'), findsWidgets);

    await go(tester, container, Routes.onboarding);
    expect(find.text('Debts'), findsWidgets);

    await go(tester, container, Routes.strategies);
    expect(find.text('Strategies'), findsWidgets);

    await go(tester, container, Routes.plan(StrategyId.balanceTransfer));
    expect(find.text('Plan: balanceTransfer'), findsWidgets);

    await go(tester, container, Routes.settings);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('an unknown strategy id falls back to the strategies list', (
    tester,
  ) async {
    final container = await pumpApp(tester, onboardingComplete: true);
    await go(tester, container, '${Routes.strategies}/nonsense');
    expect(find.text('Strategies'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/app/router_test.dart`
Expected: FAIL to load, because `package:debt_destroyer/app/app.dart` and `router.dart` don't exist.

- [ ] **Step 3: Theme and placeholder screens**

`lib/app/theme.dart`:
```dart
import 'package:flutter/material.dart';

/// The blue of the app icon (legacy/resources/artwork.png).
const Color kBrandBlue = Color(0xFF1F78D1);

ThemeData buildTheme(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: kBrandBlue,
    brightness: brightness,
  ),
);
```

`lib/core/placeholder_screen.dart`:
```dart
import 'package:flutter/material.dart';

/// Temporary screen body used until Plan 3 builds the real screen.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, this.actions, super.key});

  final String title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: Center(child: Text(title)),
  );
}
```

`lib/features/onboarding/presentation/onboarding_screen.dart`:
```dart
import 'package:debt_destroyer/core/placeholder_screen.dart';
import 'package:flutter/material.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PlaceholderScreen(title: 'Welcome');
}
```

`lib/features/debts/presentation/debts_screen.dart`:
```dart
import 'package:debt_destroyer/core/placeholder_screen.dart';
import 'package:flutter/material.dart';

class DebtsScreen extends StatelessWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(title: 'Debts');
}
```

`lib/features/strategies/presentation/strategies_screen.dart`:
```dart
import 'package:debt_destroyer/core/placeholder_screen.dart';
import 'package:flutter/material.dart';

class StrategiesScreen extends StatelessWidget {
  const StrategiesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PlaceholderScreen(title: 'Strategies');
}
```

`lib/features/analysis/presentation/plan_detail_screen.dart`:
```dart
import 'package:debt_destroyer/core/placeholder_screen.dart';
import 'package:flutter/material.dart';
import 'package:payoff_engine/payoff_engine.dart';

class PlanDetailScreen extends StatelessWidget {
  const PlanDetailScreen({required this.strategyId, super.key});

  final StrategyId strategyId;

  @override
  Widget build(BuildContext context) =>
      PlaceholderScreen(title: 'Plan: ${strategyId.name}');
}
```

`lib/features/settings/presentation/settings_screen.dart`:
```dart
import 'package:debt_destroyer/core/placeholder_screen.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PlaceholderScreen(title: 'Settings');
}
```

- [ ] **Step 4: Router**

`lib/app/router.dart`:
```dart
import 'package:debt_destroyer/features/analysis/presentation/plan_detail_screen.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_screen.dart';
import 'package:debt_destroyer/features/onboarding/presentation/onboarding_screen.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_screen.dart';
import 'package:debt_destroyer/features/strategies/presentation/strategies_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'router.g.dart';

abstract final class Routes {
  static const debts = '/';
  static const onboarding = '/onboarding';
  static const strategies = '/strategies';
  static const settings = '/settings';

  static String plan(StrategyId id) => '$strategies/${id.name}';
}

/// App navigation. Until onboarding is complete every location redirects to
/// the onboarding screen; afterwards onboarding redirects home.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final onboardingComplete = ValueNotifier<bool?>(null);
  ref
    ..listen(
      settingsControllerProvider.select((s) => s.value?.onboardingComplete),
      (_, next) => onboardingComplete.value = next,
      fireImmediately: true,
    )
    ..onDispose(onboardingComplete.dispose);

  final router = GoRouter(
    refreshListenable: onboardingComplete,
    redirect: (context, state) {
      final complete = onboardingComplete.value;
      if (complete == null) return null; // settings still loading
      final atOnboarding = state.matchedLocation == Routes.onboarding;
      if (!complete && !atOnboarding) return Routes.onboarding;
      if (complete && atOnboarding) return Routes.debts;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.debts,
        builder: (context, state) => const DebtsScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.strategies,
        builder: (context, state) => const StrategiesScreen(),
        routes: [
          GoRoute(
            path: ':strategyId',
            redirect: (context, state) =>
                _strategyId(state) == null ? Routes.strategies : null,
            builder: (context, state) =>
                PlanDetailScreen(strategyId: _strategyId(state)!),
          ),
        ],
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}

StrategyId? _strategyId(GoRouterState state) =>
    StrategyId.values.asNameMap()[state.pathParameters['strategyId']];
```

- [ ] **Step 5: App widget and bootstrap**

`lib/app/app.dart`:
```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DebtDestroyerApp extends ConsumerWidget {
  const DebtDestroyerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Debt Destroyer',
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    routerConfig: ref.watch(routerProvider),
  );
}
```

Replace `lib/main.dart` with:
```dart
import 'package:debt_destroyer/app/app.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  // Load settings before the first frame so the router knows whether to
  // show onboarding.
  await container.read(settingsControllerProvider.future);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const DebtDestroyerApp(),
    ),
  );
}
```

- [ ] **Step 6: Generate code and run the tests**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`
Expected: `No issues found!`, format exits with 0, and `+54: All tests passed!`.

- [ ] **Step 7: Build both platforms once**

Run: `flutter build apk --debug && flutter build ios --simulator --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`, then `✓ Built build/ios/iphonesimulator/Runner.app`. Together these take about 3 minutes, and they prove the native SQLite and plugin setup compiles.

- [ ] **Step 8: Commit**

```bash
git add lib test
git commit -m "feat(app): router with onboarding redirect, theme and bootstrap"
```

---

### Task 9: CI and developer docs

**Files:**
- Create: `.github/workflows/app.yml`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add the workflow**

`.github/workflows/app.yml`:
```yaml
name: app

on:
  pull_request:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: dart format --output=none --set-exit-if-changed lib test
      - run: ./tool/codegen.sh
      - run: dart analyze --fatal-infos
      - run: flutter test
```
The format check runs before code generation, so generated files aren't checked. The Linux runner compiles SQLite through the `sqlite3` package's build hooks. This can't be checked locally: if the first CI run fails at `flutter test` with a SQLite load error, add `sudo apt-get install -y libsqlite3-dev` as a step before `flutter test`.

- [ ] **Step 2: Reproduce the CI steps locally from a clean state**

```bash
git clean -xdf -n -e legacy -e .superpowers   # preview: only .dart_tool/, build/, generated *.g.dart/*.freezed.dart
git clean -xdf -e legacy -e .superpowers
dart format --output=none --set-exit-if-changed lib test && ./tool/codegen.sh && dart analyze --fatal-infos && flutter test
```
Expected: the preview lists only build artifacts and generated files, then `+54: All tests passed!`. The `-e` excludes protect the ignored licensed assets under `legacy/`.

- [ ] **Step 3: Document the app in CLAUDE.md**

In `CLAUDE.md`, replace the line starting `Once the Flutter app exists (Plan 2), add its commands here:` with:
```markdown
App (run from the repo root):
- `./tool/codegen.sh` generates code for `payoff_engine` and then the app. Run it after a fresh checkout and after changing any freezed model, Riverpod provider or Drift table. Generated `*.g.dart`/`*.freezed.dart` files are not committed.
- `flutter test` runs all app tests. `flutter test test/path/to_test.dart --plain-name "name"` runs one test.
- `dart analyze --fatal-infos` and `dart format lib test`. CI (`.github/workflows/app.yml`) enforces both.
- `flutter run` runs the app on a connected device or simulator.
- To change the Drift schema: bump `schemaVersion` in `lib/features/debts/data/app_database.dart` and write the migration. Then run `dart run drift_dev make-migrations` and commit `drift_schemas/` and the generated `test/drift/` tests.

Gotchas:
- Riverpod 3 pauses providers that have no listener, so a `StreamProvider` read without a listener never emits. In tests, call `container.listen(provider, (_, _) {})` before reading `.future`. To check that a write took effect, read the repository (`loadAll`), not the stream's latest value.
- `select`/`selectAsync` come from `flutter_riverpod`, not `riverpod_annotation`. `Override` is in `package:flutter_riverpod/misc.dart`.
- Every amount is in minor units of the one app-wide currency (`AppSettings.currencyCode`). Change currency only through `SettingsController.setCurrency`, which rescales stored amounts when the number of decimal digits changes.
```
In the migration checklist, tick `Plan 2`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/app.yml CLAUDE.md
git commit -m "ci: analyze and test the Flutter app on PRs"
```
