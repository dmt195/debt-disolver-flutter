# Plan 3: Screens, Localisation and Export — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Plan 2's placeholder screens with the real app: onboarding, the debt list and form, strategy comparison, plan detail (summary, chart, schedule), settings, and CSV/XLSX export through the share sheet. All text is localised, all money is formatted and parsed exactly, and every screen is covered by widget tests.

**Architecture:** Screens are Riverpod `ConsumerWidget`s that read Plan 2's providers and call its validated actions.
- **Shared helpers** (`lib/core/`): exact money and percent formatting and parsing, the translation extension, the format-locale and clock providers, label functions, and `runGuarded`. `runGuarded` turns a failed write into a snackbar.
- **Schedule:** a pure `ScheduleTable` feeds both the schedule tab and the CSV/XLSX export. Export writes to a temporary file and hands it to the share sheet through a `FileSharer` seam.
- **Tests:** widget tests run the whole app through `pumpApp`, with an in-memory debt repository and a synchronous plan calculator. Drift streams and background isolates don't run under the widget test clock.

**Tech Stack:** Plan 2's stack, plus Flutter `gen-l10n` (English ARB), fl_chart 1.2, share_plus 13, path_provider 2.1 and excel 4.

**Spec:** `docs/superpowers/specs/2026-09-24-flutter-rebuild-design.md` (§6 screens, §8 error handling, §9 localisation). This plan also covers the minors deferred from Plan 2's review: the debts stream re-subscribing on every settings change, `main()` having no error path, the timing-based stream test, and the stored-enum-name warning. Read the spec alongside this plan.

**This is Plan 3 of 4.** Plan 4 covers ads, consent, crash reporting, build flavours and release prep.

## Global Constraints

- Everything from Plans 1 and 2 still holds: TDD, money in integer minor units, `./tool/codegen.sh` after changing annotated code, generated files not committed, `dart analyze --fatal-infos` clean, and `dart format` making no changes.
- **UI strings:** every user-visible string comes from `lib/l10n/app_en.arb`, read through `context.l10n`. The generated `lib/l10n/app_localizations*.dart` files are git-ignored and produced by `./tool/codegen.sh`, which runs `flutter gen-l10n`.
- **Number formatting** uses `formatLocaleProvider` (the device locale), not the UI language. Tests pin it to `en_GB` and pin the clock to 24 Sep 2026.
- **Money** is never parsed through `double`. `parseAmountMinor`/`parsePercentBps` work on digits, and `double` is used only to display amounts.
- **Widget tests** use `pumpApp`. They never use the Drift repository or `compute`. Call `pumpAndSettle` after `ensureVisible` and before tapping.
- **Errors after Save:** an error found after Save is shown with `forceErrorText` and cleared when its field is edited, never at the start of Save.
- **Screen class names and routes stay as Plan 2 defined them.** This plan adds only `Routes.newDebt` (`/debts/new`) and `Routes.editDebt(id)` (`/debts/<id>`).
- **Plan-time verification:** the finished plan was verified end to end. That covers analyze, 125 app and 68 engine tests, debug APK and iOS simulator builds, and a replay of every task's red/green steps with the cumulative counts stated below.

## Review Focus

1. **Typing amounts the way people do:** `1,234.56`, `1234`, ` 300 `, and in a comma-decimal locale `1.234,56`. These should be read exactly. Anything ambiguous, such as `1.234` for GBP, a minus sign or text, should be refused with an example of the expected format. Covered in Task 2 (`parseAmountMinor` tests) and Task 5 ("rejects text that is not an amount").
2. **Saving again without fixing a rejected value:** the message should stay and nothing should be saved. Before this plan's fix, the message vanished and nothing happened. Covered in Tasks 5 and 8 ("saving again without a fix keeps the message").
3. **Deleting a debt when storage fails:** the user should be told. The list may show the debt as gone until the next reload, but a snackbar must say the change wasn't saved. Covered in Task 5 ("a failed delete tells the user").
4. **A budget below the minimum payments:** a banner should say by how much, with a way to the budget setting. On the strategies screen, each infeasible plan should explain itself rather than show numbers. Covered in Task 5 ("warns when the budget is below…") and Tasks 6 and 7 ("explains a budget that cannot cover…", "an infeasible plan is explained, not drawn").
5. **Export with odd debt names** (commas, quotes, accents): the CSV should stay valid and the XLSX readable. Covered in Task 7 ("CSV quotes awkward headers…", "CSV is valid UTF-8…").

---

### Task 1: Minimum-payment helper in the engine

**Files:**
- Create: `packages/payoff_engine/lib/src/minimum_payment.dart`
- Modify: `packages/payoff_engine/lib/payoff_engine.dart` (export it), `packages/payoff_engine/lib/src/debt.dart` (doc comment on `DebtType`)
- Test: `packages/payoff_engine/test/minimum_payment_test.dart`

**Interfaces:**
- Produces: `Money minimumPayment(Debt debt)` and `Money totalMinimumPayments(List<Debt> debts, {required String currency})`. These follow the calculator's rule, applied to the current balance.

- [ ] **Step 1: Write the failing test**

`packages/payoff_engine/test/minimum_payment_test.dart`:
```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('minimumPayment', () {
    test('is the percentage when it exceeds the floor', () {
      final d = debt(
        id: 'a',
        balance: 200000,
        minPaymentPercentBps: 300,
        minPaymentFloor: 2500,
      );
      expect(minimumPayment(d), gbp(6000));
    });

    test('is the floor when it exceeds the percentage', () {
      final d = debt(
        id: 'a',
        balance: 50000,
        minPaymentPercentBps: 300,
        minPaymentFloor: 2500,
      );
      expect(minimumPayment(d), gbp(2500));
    });

    test('never exceeds the balance', () {
      final d = debt(id: 'a', balance: 1000, minPaymentFloor: 2500);
      expect(minimumPayment(d), gbp(1000));
    });

    test('rounds the percentage half to even', () {
      // 3% of 12.50 = 0.375 → 0.38 (pence 37.5 rounds to 38, the even one).
      final d = debt(id: 'a', balance: 1250, minPaymentPercentBps: 300);
      expect(minimumPayment(d), gbp(38));
    });
  });

  test('totalMinimumPayments sums every debt', () {
    final debts = [
      debt(id: 'a', balance: 50000, minPaymentFloor: 2500),
      debt(id: 'b', balance: 200000, minPaymentPercentBps: 300),
    ];
    expect(totalMinimumPayments(debts, currency: 'GBP'), gbp(8500));
    expect(totalMinimumPayments(const [], currency: 'GBP'), gbp(0));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/payoff_engine && dart test test/minimum_payment_test.dart`
Expected: FAIL to load, because `minimumPayment` isn't defined.

- [ ] **Step 3: Implement**

`packages/payoff_engine/lib/src/minimum_payment.dart`:
```dart
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/rounding.dart';

/// The payment [debt] requires this month at its current balance: the larger
/// of its floor and its percentage, but never more than the balance. The
/// calculator applies the same rule after adding each month's interest.
Money minimumPayment(Debt debt) {
  final balance = debt.balance.minor;
  if (balance <= 0) return Money.zero(debt.balance.currency);
  final byPercent = divideHalfEven(balance * debt.minPaymentPercentBps, 10000);
  final floor = debt.minPaymentFloor.minor;
  final minimum = byPercent > floor ? byPercent : floor;
  return Money(minimum < balance ? minimum : balance, debt.balance.currency);
}

/// The sum of [minimumPayment] over [debts], in [currency].
Money totalMinimumPayments(List<Debt> debts, {required String currency}) =>
    debts.fold(Money.zero(currency), (sum, d) => sum + minimumPayment(d));
```

Replace `packages/payoff_engine/lib/payoff_engine.dart` with:
```dart
/// Pure-Dart debt payoff calculator for Debt Destroyer.
library;

export 'src/calculator.dart';
export 'src/debt.dart';
export 'src/debt_ordering.dart';
export 'src/minimum_payment.dart';
export 'src/money.dart';
export 'src/payoff_result.dart';
export 'src/rounding.dart';
export 'src/strategy.dart';
export 'src/validation.dart';
```

Replace `packages/payoff_engine/lib/src/debt.dart` with this version, which adds only the `DebtType` doc comment:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/src/money.dart';

part 'debt.freezed.dart';

/// Stored by name in the app's database: renaming a value breaks existing
/// rows unless a migration renames them too.
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

- [ ] **Step 4: Run the engine suite**

Run: `cd packages/payoff_engine && dart run build_runner build -d && dart analyze --fatal-infos && dart test`
Expected: `No issues found!`, then `+68: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add packages/payoff_engine
git commit -m "feat(engine): minimum payment helpers for the debts screen"
```

---

### Task 2: Exact money and percent formatting and parsing

**Files:**
- Create: `lib/core/money_format.dart`
- Test: `test/core/money_format_test.dart`

**Interfaces:**
- Consumes: `currencyDecimalDigits` (Plan 2).
- Produces:
  - `String formatMoney(Money money, String locale)`
  - `String formatAmountInput(Money money, String locale)`
  - `int? parseAmountMinor(String text, {required String currencyCode, required String locale})`
  - `String formatPercent(int bps, String locale)`
  - `String formatPercentInput(int bps, String locale)`
  - `int? parsePercentBps(String text, String locale)`
  - `int? parseWholeNumber(String text)`

- [ ] **Step 1: Write the failing test**

`test/core/money_format_test.dart`:
```dart
import 'package:debt_destroyer/core/money_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  group('formatMoney', () {
    test('uses the locale and the currency symbol', () {
      expect(formatMoney(const Money(123456, 'GBP'), 'en_GB'), '£1,234.56');
      expect(formatMoney(const Money(123456, 'USD'), 'en_US'), r'$1,234.56');
      expect(formatMoney(const Money(1235, 'JPY'), 'en_GB'), '¥1,235');
      expect(
        formatMoney(const Money(123456, 'EUR'), 'de_DE'),
        contains('1.234,56'),
      );
    });

    test('shows whole amounts without dropping pence', () {
      expect(formatMoney(const Money(30000, 'GBP'), 'en_GB'), '£300.00');
      expect(formatMoney(const Money(5, 'GBP'), 'en_GB'), '£0.05');
    });
  });

  group('formatAmountInput', () {
    test('writes a plain number in the locale, no symbol or grouping', () {
      expect(formatAmountInput(const Money(123456, 'GBP'), 'en_GB'), '1234.56');
      expect(formatAmountInput(const Money(123456, 'EUR'), 'de_DE'), '1234,56');
      expect(formatAmountInput(const Money(1235, 'JPY'), 'en_GB'), '1235');
      expect(formatAmountInput(const Money(30000, 'GBP'), 'en_GB'), '300');
    });
  });

  group('parseAmountMinor', () {
    int? gb(String s) =>
        parseAmountMinor(s, currencyCode: 'GBP', locale: 'en_GB');

    test('parses whole and decimal amounts exactly', () {
      expect(gb('1234.56'), 123456);
      expect(gb('1,234.56'), 123456);
      expect(gb(' 300 '), 30000);
      expect(gb('0.5'), 50);
      expect(gb('.75'), 75);
    });

    test('rejects more decimals than the currency has', () {
      expect(gb('1.234'), isNull);
      expect(
        parseAmountMinor('10.5', currencyCode: 'JPY', locale: 'en_GB'),
        isNull,
      );
    });

    test('rejects text, signs, empty input and several decimal points', () {
      for (final bad in ['', ' ', 'abc', '-5', '+5', '1.2.3', '£5', '1e3']) {
        expect(gb(bad), isNull, reason: bad);
      }
    });

    test('follows the locale decimal separator', () {
      expect(
        parseAmountMinor('1.234,56', currencyCode: 'EUR', locale: 'de_DE'),
        123456,
      );
      expect(
        parseAmountMinor('1 234,56', currencyCode: 'EUR', locale: 'fr_FR'),
        123456,
      );
      expect(
        parseAmountMinor('1234 56', currencyCode: 'EUR', locale: 'fr_FR'),
        123456 * 100,
      );
    });

    test('rejects absurdly long numbers instead of overflowing', () {
      expect(gb('9' * 30), isNull);
    });
  });

  group('percent', () {
    test('formats basis points with up to two decimals', () {
      expect(formatPercent(1990, 'en_GB'), '19.9%');
      expect(formatPercent(400, 'en_GB'), '4%');
      expect(formatPercent(1234, 'en_GB'), '12.34%');
      expect(formatPercent(1990, 'de_DE'), '19,9\u00a0%');
    });

    test('formats input without the percent sign', () {
      expect(formatPercentInput(1990, 'en_GB'), '19.9');
      expect(formatPercentInput(0, 'en_GB'), '0');
    });

    test('parses percentages to basis points exactly', () {
      expect(parsePercentBps('19.9', 'en_GB'), 1990);
      expect(parsePercentBps('4', 'en_GB'), 400);
      expect(parsePercentBps('12.34', 'en_GB'), 1234);
      expect(parsePercentBps('19,9', 'de_DE'), 1990);
      expect(parsePercentBps('12.345', 'en_GB'), isNull);
      expect(parsePercentBps('x', 'en_GB'), isNull);
    });
  });

  test('parseWholeNumber accepts digits only', () {
    expect(parseWholeNumber('12'), 12);
    expect(parseWholeNumber(' 0 '), 0);
    expect(parseWholeNumber('1.5'), isNull);
    expect(parseWholeNumber('-1'), isNull);
    expect(parseWholeNumber(''), isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/money_format_test.dart`
Expected: FAIL to load, because `money_format.dart` doesn't exist.

- [ ] **Step 3: Implement**

`lib/core/money_format.dart`:
```dart
import 'package:debt_destroyer/core/currency.dart';
import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// [money] for display, e.g. `£1,234.56` in `en_GB`.
String formatMoney(Money money, String locale) {
  final format = NumberFormat.simpleCurrency(
    locale: locale,
    name: money.currency,
  );
  return format.format(_toMajor(money.minor, format.decimalDigits ?? 2));
}

/// [money] as a plain number for an input field: the locale's decimal
/// separator, no symbol or grouping, and no trailing zero decimals.
String formatAmountInput(Money money, String locale) => _plainNumber(
  money.minor,
  digits: currencyDecimalDigits(money.currency),
  locale: locale,
);

/// Parses what a user typed as an amount of [currencyCode], in minor units.
/// Accepts the locale's grouping and decimal separators. Returns null for
/// anything else, including more decimals than the currency has.
int? parseAmountMinor(
  String text, {
  required String currencyCode,
  required String locale,
}) => _parseScaled(
  text,
  maxFractionDigits: currencyDecimalDigits(currencyCode),
  locale: locale,
);

/// [bps] as a percentage for display, e.g. 1990 → `19.9%`.
String formatPercent(int bps, String locale) => (NumberFormat.percentPattern(
  locale,
)..maximumFractionDigits = 2).format(bps / 10000);

/// [bps] as a plain number for an input field, e.g. 1990 → `19.9`.
String formatPercentInput(int bps, String locale) =>
    _plainNumber(bps, digits: 2, locale: locale);

/// Parses a percentage with up to two decimals into basis points.
int? parsePercentBps(String text, String locale) =>
    _parseScaled(text, maxFractionDigits: 2, locale: locale);

/// Parses a non-negative whole number.
int? parseWholeNumber(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.length > 9) return null;
  if (!RegExp(r'^\d+$').hasMatch(trimmed)) return null;
  return int.parse(trimmed);
}

double _toMajor(int minor, int digits) {
  var divisor = 1;
  for (var i = 0; i < digits; i++) {
    divisor *= 10;
  }
  return minor / divisor;
}

String _plainNumber(int scaled, {required int digits, required String locale}) {
  final format = NumberFormat.decimalPattern(locale)
    ..minimumFractionDigits = 0
    ..maximumFractionDigits = digits
    ..turnOffGrouping();
  return format.format(_toMajor(scaled, digits));
}

/// Characters accepted as digit grouping, whatever the locale uses.
const _groupingChars = {',', '.', ' ', ' ', ' ', "'"};

int? _parseScaled(
  String text, {
  required int maxFractionDigits,
  required String locale,
}) {
  final symbols = NumberFormat.decimalPattern(locale).symbols;
  final decimalSep = symbols.DECIMAL_SEP;
  final grouping = {..._groupingChars, symbols.GROUP_SEP}..remove(decimalSep);

  final trimmed = text.trim();
  final buffer = StringBuffer();
  for (final char in trimmed.split('')) {
    if (grouping.contains(char)) continue;
    buffer.write(char);
  }
  final parts = buffer.toString().split(decimalSep);
  if (parts.length > 2) return null;
  final whole = parts[0];
  final fraction = parts.length == 2 ? parts[1] : '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  final digitsOnly = RegExp(r'^\d*$');
  if (!digitsOnly.hasMatch(whole) || !digitsOnly.hasMatch(fraction)) {
    return null;
  }
  if (fraction.length > maxFractionDigits) return null;
  // Long enough to be nonsense; also keeps the result inside 64 bits.
  if (whole.length + maxFractionDigits > 15) return null;
  final padded = fraction.padRight(maxFractionDigits, '0');
  return int.parse('${whole.isEmpty ? '0' : whole}$padded');
}
```

- [ ] **Step 4: Run the tests**

Run: `dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+77: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add lib/core/money_format.dart test/core/money_format_test.dart
git commit -m "feat(core): exact money and percentage formatting and parsing"
```

---

### Task 3: Localisation, shared UI helpers and new dependencies

**Files:**
- Modify: `pubspec.yaml` (new dependencies; `flutter: generate: true`)
- Create: `l10n.yaml`, `lib/l10n/app_en.arb`
- Modify: `tool/codegen.sh` (runs `flutter gen-l10n`) and `.gitignore` (ignores the generated localisation files)
- Create: `lib/core/l10n.dart`, `lib/core/labels.dart`, `lib/core/guarded.dart`
- Modify: `lib/app/app.dart` (localisation delegates)
- Modify: `test/helpers/test_container.dart` (pins the format locale and clock)
- Test: `test/core/labels_test.dart`

**Interfaces:**
- Produces:
  - `extension L10nContext on BuildContext { AppLocalizations get l10n; }`. `lib/core/l10n.dart` also re-exports `AppLocalizations`.
  - `formatLocaleProvider` (`String`) and `clockProvider` (`DateTime Function()`). Both are keepAlive, and tests override them.
  - The label functions `debtTypeLabel(l10n, DebtType)`, `strategyName(l10n, StrategyId)`, `strategyDescription(l10n, StrategyId, StrategyParameters, String locale)`, `planDebtName(l10n, PlanDebt)` and `formatDuration(l10n, int months)`.
  - `Future<T?> runGuarded<T>(BuildContext context, Future<T> Function() action)`. On error it logs, shows `l10n.errorSaving` in a snackbar, and returns null.

- [ ] **Step 1: Dependencies and generation config**

Replace `pubspec.yaml` with:
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
  excel: ^4.0.6
  fl_chart: ^1.2.0
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  flutter_riverpod: ^3.4.3
  freezed_annotation: ^3.1.0
  go_router: ^18.0.1
  intl: ^0.20.3
  path_provider: ^2.1.6
  payoff_engine:
    path: packages/payoff_engine
  riverpod_annotation: ^4.0.7
  share_plus: ^13.3.0
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
  generate: true
  uses-material-design: true
```

`l10n.yaml`:
```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
```

Replace `tool/codegen.sh` with:
```bash
#!/usr/bin/env bash
# Generates all build_runner code: the payoff_engine package first (the app
# imports its generated freezed classes), then the app.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd packages/payoff_engine && dart pub get && dart run build_runner build -d)
flutter pub get
flutter gen-l10n
dart run build_runner build -d
```

Replace `.gitignore` with this version, which adds `lib/l10n/app_localizations*.dart` under "Generated code":
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
lib/l10n/app_localizations*.dart
```

- [ ] **Step 2: The English strings**

`lib/l10n/app_en.arb`:
```json
{
  "@@locale": "en",
  "appTitle": "Debt Destroyer",
  "save": "Save",
  "cancel": "Cancel",
  "delete": "Delete",
  "retry": "Try again",
  "errorGeneric": "Something went wrong. Please try again.",
  "errorSaving": "Couldn't save your changes. Please try again.",

  "onboardingTitle": "Welcome to Debt Destroyer",
  "onboardingIntro1": "Debt Destroyer compares ways of paying off your debts, so you can choose the fastest and cheapest.",
  "onboardingIntro2": "Pay the minimum on every debt, then put everything else towards the one with the highest interest rate.",
  "onboardingIntro3": "When a debt is cleared, its payment rolls on to the next one: the quickest route to being debt-free.",
  "onboardingBudgetQuestion": "How much can you pay towards your debts each month?",
  "onboardingStart": "Get started",

  "debtsTitle": "Your debts",
  "debtsEmpty": "No debts yet. Add your first one to get started.",
  "addDebt": "Add debt",
  "compareStrategies": "Compare strategies",
  "totalDebt": "Total debt",
  "minimumPayments": "Minimum payments",
  "monthlyBudget": "Monthly budget",
  "budgetShortfall": "Your budget is {shortfall} short of this month's minimum payments.",
  "@budgetShortfall": {"placeholders": {"shortfall": {"type": "String"}}},
  "changeBudget": "Change budget",
  "deleteDebtTitle": "Delete {name}?",
  "@deleteDebtTitle": {"placeholders": {"name": {"type": "String"}}},
  "deleteDebtBody": "This can't be undone.",
  "debtApr": "{apr} APR",
  "@debtApr": {"placeholders": {"apr": {"type": "String"}}},
  "debtMinimum": "Minimum {amount}",
  "@debtMinimum": {"placeholders": {"amount": {"type": "String"}}},
  "settingsTooltip": "Settings",

  "debtTypeCreditCard": "Credit card",
  "debtTypeLoan": "Loan",
  "debtTypePersonal": "Friends & family",

  "newDebtTitle": "Add debt",
  "editDebtTitle": "Edit debt",
  "fieldName": "Name",
  "fieldBalance": "Balance",
  "fieldApr": "Interest rate (APR %)",
  "fieldMinPercent": "Minimum payment (% of balance)",
  "fieldMinFloor": "Minimum payment (at least)",
  "fieldAllowsOverpayment": "Can pay more than the minimum",
  "fieldAllowsOverpaymentHint": "Turn off for loans with fixed repayments",

  "errorInvalidAmount": "Enter an amount, e.g. {example}",
  "@errorInvalidAmount": {"placeholders": {"example": {"type": "String"}}},
  "errorInvalidPercent": "Enter a percentage, e.g. {example}",
  "@errorInvalidPercent": {"placeholders": {"example": {"type": "String"}}},
  "errorWholeNumber": "Enter a whole number",
  "errorNameEmpty": "Enter a name",
  "errorBalanceNotPositive": "Enter a balance above zero",
  "errorTooLarge": "That's more than the maximum allowed",
  "errorRateRange": "Enter a rate between 0 and 100",
  "errorPercentRange": "Enter a percentage between 0 and 100",
  "errorFloorNegative": "Can't be negative",
  "errorTooManyDebts": "You can track up to {max} debts",
  "@errorTooManyDebts": {"placeholders": {"max": {"type": "int"}}},
  "errorBudgetNotPositive": "Enter a budget above zero",
  "errorPromoMonthsRange": "Enter between 0 and {max} months",
  "@errorPromoMonthsRange": {"placeholders": {"max": {"type": "int"}}},

  "strategiesTitle": "Strategies",
  "strategiesEmpty": "Add a debt to compare strategies.",
  "strategyAvalanche": "Highest interest first",
  "strategyAvalancheDescription": "Minimums on everything, the rest to the highest-rate debt.",
  "strategyLowestAprFirst": "Lowest interest first",
  "strategyLowestAprFirstDescription": "Minimums on everything, the rest to the lowest-rate debt.",
  "strategyBoosted": "Pay 10% more",
  "strategyBoostedDescription": "Highest interest first, with a monthly budget 10% higher.",
  "strategyConsolidation": "Consolidation loan",
  "strategyConsolidationDescription": "One loan at {apr} replaces all your debts.",
  "@strategyConsolidationDescription": {"placeholders": {"apr": {"type": "String"}}},
  "strategyBalanceTransfer": "0% balance transfer",
  "strategyBalanceTransferDescription": "Move everything to a 0% card for {months} months ({fee} fee, then {apr}).",
  "@strategyBalanceTransferDescription": {"placeholders": {"months": {"type": "int"}, "fee": {"type": "String"}, "apr": {"type": "String"}}},
  "cheapest": "Cheapest",
  "debtFreeIn": "Debt-free in {duration}",
  "@debtFreeIn": {"placeholders": {"duration": {"type": "String"}}},
  "alreadyDebtFree": "Nothing left to pay.",
  "totalInterest": "Total interest",
  "totalPaid": "Total paid",
  "fees": "Fees",
  "infeasible": "Your budget is {shortfall} short of the minimum payments in month {month}.",
  "@infeasible": {"placeholders": {"shortfall": {"type": "String"}, "month": {"type": "int"}}},
  "neverClears": "Never pays off at this budget.",
  "plansError": "Couldn't calculate your plans. Check your debts and budget, then try again.",
  "months": "{count, plural, =1{1 month} other{{count} months}}",
  "@months": {"placeholders": {"count": {"type": "int"}}},
  "years": "{count, plural, =1{1 year} other{{count} years}}",
  "@years": {"placeholders": {"count": {"type": "int"}}},
  "yearsAndMonths": "{years} {months}",
  "@yearsAndMonths": {"placeholders": {"years": {"type": "String"}, "months": {"type": "String"}}},

  "tabSummary": "Summary",
  "tabChart": "Chart",
  "tabSchedule": "Schedule",
  "debtFreeBy": "Debt-free by {date}",
  "@debtFreeBy": {"placeholders": {"date": {"type": "String"}}},
  "payThisMonth": "Pay this month",
  "paymentPriority": "Payment priority",
  "paymentPriorityHint": "Extra money goes to the first debt that can take it.",
  "share": "Share",
  "exportCsv": "Spreadsheet (CSV)",
  "exportXlsx": "Excel workbook (XLSX)",
  "scheduleMonth": "Month",
  "scheduleTotal": "Total",
  "schedulePayment": "{name} payment",
  "@schedulePayment": {"placeholders": {"name": {"type": "String"}}},
  "scheduleBalance": "{name} balance",
  "@scheduleBalance": {"placeholders": {"name": {"type": "String"}}},
  "scheduleTotalPayment": "Total payment",
  "scheduleTotalBalance": "Total balance",
  "chartTitle": "Balance over time",
  "planUnavailable": "This plan isn't available for your current debts and budget.",
  "consolidationLoanName": "Consolidation loan",
  "balanceTransferCardName": "Balance transfer card",

  "settingsTitle": "Settings",
  "settingsCurrency": "Currency",
  "settingsBudget": "Monthly budget",
  "settingsConsolidation": "Consolidation loan",
  "settingsConsolidationApr": "Loan interest rate (APR %)",
  "settingsTransfer": "0% balance transfer",
  "settingsPromoMonths": "Interest-free months",
  "settingsTransferFee": "Transfer fee (% of balance)",
  "settingsRevertApr": "Interest rate afterwards (APR %)",
  "settingsSaved": "Saved"
}
```
Run: `./tool/codegen.sh`
Expected: it finishes with `Built with build_runner`, and `lib/l10n/app_localizations.dart` and `app_localizations_en.dart` now exist. `git status --short lib/l10n` shows only `app_en.arb`.

- [ ] **Step 3: Write the failing test**

`test/core/labels_test.dart`:
```dart
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('formats durations in years and months', () {
    expect(formatDuration(l10n, 1), '1 month');
    expect(formatDuration(l10n, 5), '5 months');
    expect(formatDuration(l10n, 12), '1 year');
    expect(formatDuration(l10n, 27), '2 years 3 months');
    expect(formatDuration(l10n, 13), '1 year 1 month');
  });

  test('names the synthetic debts and keeps user names', () {
    expect(
      planDebtName(
        l10n,
        const PlanDebt(
          id: kConsolidationDebtId,
          name: 'x',
          startingBalance: Money(1, 'GBP'),
        ),
      ),
      'Consolidation loan',
    );
    expect(
      planDebtName(
        l10n,
        const PlanDebt(id: 'a', name: 'Visa', startingBalance: Money(1, 'GBP')),
      ),
      'Visa',
    );
  });

  test('describes strategies with their parameters', () {
    const p = StrategyParameters();
    expect(
      strategyDescription(l10n, StrategyId.balanceTransfer, p, 'en_GB'),
      'Move everything to a 0% card for 12 months (4% fee, then 15%).',
    );
    expect(
      strategyDescription(l10n, StrategyId.consolidation, p, 'en_GB'),
      'One loan at 5% replaces all your debts.',
    );
  });

  test('every strategy and debt type has a label', () {
    for (final id in StrategyId.values) {
      expect(strategyName(l10n, id), isNotEmpty);
    }
    for (final type in DebtType.values) {
      expect(debtTypeLabel(l10n, type), isNotEmpty);
    }
  });
}
```
Run: `flutter test test/core/labels_test.dart`
Expected: FAIL to load, because `labels.dart` doesn't exist.

- [ ] **Step 4: Implement the helpers**

`lib/core/l10n.dart`:
```dart
import 'dart:ui';

import 'package:debt_destroyer/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:debt_destroyer/l10n/app_localizations.dart';

part 'l10n.g.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Locale for number and date formatting: the device's, so separators match
/// what the user expects even though the UI text is English only.
@Riverpod(keepAlive: true)
String formatLocale(Ref ref) =>
    Intl.verifiedLocale(
      PlatformDispatcher.instance.locale.toString(),
      NumberFormat.localeExists,
      onFailure: (_) => 'en',
    ) ??
    'en';

/// The current time. Tests override it to get stable dates.
@Riverpod(keepAlive: true)
DateTime Function() clock(Ref ref) => DateTime.now;
```

`lib/core/labels.dart`:
```dart
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:payoff_engine/payoff_engine.dart';

String debtTypeLabel(AppLocalizations l10n, DebtType type) => switch (type) {
  DebtType.creditCard => l10n.debtTypeCreditCard,
  DebtType.loan => l10n.debtTypeLoan,
  DebtType.personal => l10n.debtTypePersonal,
};

String strategyName(AppLocalizations l10n, StrategyId id) => switch (id) {
  StrategyId.avalanche => l10n.strategyAvalanche,
  StrategyId.lowestAprFirst => l10n.strategyLowestAprFirst,
  StrategyId.boosted => l10n.strategyBoosted,
  StrategyId.consolidation => l10n.strategyConsolidation,
  StrategyId.balanceTransfer => l10n.strategyBalanceTransfer,
};

String strategyDescription(
  AppLocalizations l10n,
  StrategyId id,
  StrategyParameters p,
  String locale,
) => switch (id) {
  StrategyId.avalanche => l10n.strategyAvalancheDescription,
  StrategyId.lowestAprFirst => l10n.strategyLowestAprFirstDescription,
  StrategyId.boosted => l10n.strategyBoostedDescription,
  StrategyId.consolidation => l10n.strategyConsolidationDescription(
    formatPercent(p.consolidationAprBps, locale),
  ),
  StrategyId.balanceTransfer => l10n.strategyBalanceTransferDescription(
    p.promoMonths,
    formatPercent(p.transferFeeBps, locale),
    formatPercent(p.revertAprBps, locale),
  ),
};

/// The name to show for a debt in a plan; the calculator's synthetic debts
/// get translated names.
String planDebtName(AppLocalizations l10n, PlanDebt debt) => switch (debt.id) {
  kConsolidationDebtId => l10n.consolidationLoanName,
  kBalanceTransferDebtId => l10n.balanceTransferCardName,
  _ => debt.name,
};

/// e.g. `2 years 3 months`, `1 year`, `5 months`.
String formatDuration(AppLocalizations l10n, int months) {
  final years = months ~/ 12;
  final rest = months % 12;
  if (years == 0) return l10n.months(rest);
  if (rest == 0) return l10n.years(years);
  return l10n.yearsAndMonths(l10n.years(years), l10n.months(rest));
}
```

`lib/core/guarded.dart`:
```dart
import 'dart:developer';

import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';

/// Runs [action]. If it throws, logs the error, tells the user their change
/// wasn't saved, and returns null.
Future<T?> runGuarded<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = context.l10n.errorSaving;
  try {
    return await action();
  } on Object catch (error, stackTrace) {
    log('Action failed', error: error, stackTrace: stackTrace);
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return null;
  }
}
```

Replace `lib/app/app.dart` with:
```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DebtDestroyerApp extends ConsumerWidget {
  const DebtDestroyerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    onGenerateTitle: (context) => context.l10n.appTitle,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    routerConfig: ref.watch(routerProvider),
  );
}
```

Replace `test/helpers/test_container.dart` with:
```dart
import 'dart:convert';

import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Test doubles for the app's platform dependencies: in-memory preferences
/// seeded with [prefs], an in-memory database, GBP as the device currency,
/// `en_GB` number formatting and a fixed clock (24 Sep 2026). Pass the
/// result to a [ProviderContainer] or [ProviderScope].
List<Override> testOverrides({Map<String, Object> prefs = const {}}) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(prefs);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return [
    appDatabaseProvider.overrideWithValue(db),
    defaultCurrencyCodeProvider.overrideWithValue('GBP'),
    formatLocaleProvider.overrideWithValue('en_GB'),
    clockProvider.overrideWithValue(() => DateTime(2026, 9, 24)),
  ];
}

/// A container with [testOverrides], disposed after the test. Failing
/// providers are not retried, so errors surface immediately.
ProviderContainer createTestContainer({Map<String, Object> prefs = const {}}) =>
    ProviderContainer.test(
      overrides: testOverrides(prefs: prefs),
      retry: (_, _) => null,
    );

/// Preferences holding a stored settings object with only [fields] set;
/// the rest fall back to defaults when loaded.
Map<String, Object> storedSettings(Map<String, Object?> fields) => {
  SettingsKeys.settings: jsonEncode(fields),
};
```

- [ ] **Step 5: Generate code and run the tests**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+81: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock l10n.yaml lib/l10n/app_en.arb tool/codegen.sh .gitignore lib/core lib/app/app.dart test/helpers/test_container.dart test/core/labels_test.dart
git commit -m "feat(app): English localisation and shared UI helpers"
```

---

### Task 4: Test seams, the widget-test harness and the Plan 2 minors

This task gives widget tests a whole app that runs under the test clock. It also fixes three minors deferred from Plan 2: the debts stream re-subscribing on every settings change, `main()` having no error path, and the timing-based stream test.

**Files:**
- Modify: `lib/features/strategies/presentation/plans_providers.dart` (adds the `planCalculatorProvider` seam)
- Modify: `lib/features/debts/presentation/debts_providers.dart` (`debtsProvider` selects the currency only)
- Modify: `lib/main.dart` (the app starts even if settings fail to load)
- Create: `test/helpers/in_memory_debt_repository.dart`, `test/helpers/pump_app.dart`
- Modify: `test/features/debts/debts_provider_test.dart` (adds a re-subscription test), `test/features/debts/drift_debt_repository_test.dart` (the stream test waits on emissions, not a timer), `test/app/router_test.dart` (asserts screen types, so later tasks don't break it)

**Interfaces:**
- Produces:
  - `typedef PlanCalculator = Future<List<PayoffResult>> Function(List<Debt> debts, Money monthlyBudget, StrategyParameters parameters)`, with `planCalculatorProvider`. The app uses `compute`, and tests use a synchronous version.
  - `debtsProvider` now rebuilds only when the currency (or a settings error) changes.
  - Test helpers:
    - `class InMemoryDebtRepository implements DebtRepository`, with `stored`, `watchCount` and `Exception? failWritesWith`
    - `Future<AppHarness> pumpApp(WidgetTester tester, {String location, List<Debt> debts, Map<String, Object?> settings, List<Override> overrides})`
    - `AppHarness`, with `container`, `repository` and `router.go(tester, location)`/`router.location`

- [ ] **Step 1: Write the failing tests and harness**

`test/helpers/in_memory_debt_repository.dart`:
```dart
import 'dart:async';

import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/debts/domain/debt_repository.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// A [DebtRepository] held in memory, for widget tests: the Drift one relies
/// on timers and I/O that don't run under the widget test clock. Amounts are
/// kept in minor units, relabelled with the requested currency like Drift.
class InMemoryDebtRepository implements DebtRepository {
  InMemoryDebtRepository([List<Debt> initial = const []])
    : _debts = [...initial];

  final List<Debt> _debts;
  final _changes = StreamController<void>.broadcast();
  String? _amountsCurrency;

  /// Set to make every write throw, to test error handling.
  Exception? failWritesWith;

  List<Debt> get stored => List.unmodifiable(_debts);

  List<Debt> _labelled(String currency) => [
    for (final d in _debts)
      d.copyWith(
        balance: Money(d.balance.minor, currency),
        minPaymentFloor: Money(d.minPaymentFloor.minor, currency),
      ),
  ];

  /// How many times [watchAll] has been called.
  int watchCount = 0;

  @override
  Stream<List<Debt>> watchAll(String currencyCode) async* {
    watchCount++;
    yield _labelled(currencyCode);
    await for (final _ in _changes.stream) {
      yield _labelled(currencyCode);
    }
  }

  @override
  Future<List<Debt>> loadAll(String currencyCode) async =>
      _labelled(currencyCode);

  Future<void> _write(void Function() change) async {
    if (failWritesWith case final error?) throw error;
    change();
    _changes.add(null);
  }

  @override
  Future<void> add(Debt debt) => _write(() => _debts.add(debt));

  @override
  Future<void> update(Debt debt) => _write(() {
    final i = _debts.indexWhere((d) => d.id == debt.id);
    if (i < 0) throw StateError('No debt with id ${debt.id}');
    _debts[i] = debt;
  });

  @override
  Future<void> delete(String id) =>
      _write(() => _debts.removeWhere((d) => d.id == id));

  @override
  Future<void> reorder(List<String> idsInOrder) => _write(() {
    final byId = {for (final d in _debts) d.id: d};
    _debts
      ..clear()
      ..addAll([for (final id in idsInOrder) byId[id]!]);
  });

  @override
  Future<String?> amountsCurrencyCode() async => _amountsCurrency;

  @override
  Future<void> convertAmounts({required String toCurrencyCode}) async {
    final from = _amountsCurrency;
    _amountsCurrency = toCurrencyCode;
    if (from == null || from == toCurrencyCode) return;
    int rescale(int minor, int min) => rescaleMinor(
      minor,
      fromDigits: currencyDecimalDigits(from),
      toDigits: currencyDecimalDigits(toCurrencyCode),
    ).clamp(min, kMaxAmountMinor);
    for (var i = 0; i < _debts.length; i++) {
      final d = _debts[i];
      _debts[i] = d.copyWith(
        balance: Money(rescale(d.balance.minor, 1), toCurrencyCode),
        minPaymentFloor: Money(
          rescale(d.minPaymentFloor.minor, 0),
          toCurrencyCode,
        ),
      );
    }
    _changes.add(null);
  }
}
```

`test/helpers/pump_app.dart`:
```dart
import 'package:debt_destroyer/app/app.dart';
import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import 'in_memory_debt_repository.dart';
import 'test_container.dart';

/// The whole app for a widget test, opened at [location], with in-memory
/// storage holding [debts] and settings seeded from [settings] (onboarding
/// complete unless overridden). Plans are calculated synchronously.
Future<AppHarness> pumpApp(
  WidgetTester tester, {
  String location = Routes.debts,
  List<Debt> debts = const [],
  Map<String, Object?> settings = const {},
  List<Override> overrides = const [],
}) async {
  final repository = InMemoryDebtRepository(debts);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...testOverrides(
          prefs: storedSettings({
            SettingsKeys.onboardingComplete: true,
            ...settings,
          }),
        ),
        debtRepositoryProvider.overrideWithValue(repository),
        planCalculatorProvider.overrideWithValue(
          (debts, budget, parameters) async => calculateAll(
            debts: debts,
            monthlyBudget: budget,
            parameters: parameters,
          ),
        ),
        ...overrides,
      ],
      child: const DebtDestroyerApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  if (location != Routes.debts) {
    container.read(routerProvider).go(location);
    await tester.pumpAndSettle();
  }
  return AppHarness(container, repository);
}

class AppHarness {
  AppHarness(this.container, this.repository);

  final ProviderContainer container;
  final InMemoryDebtRepository repository;

  GoRouterNavigator get router => GoRouterNavigator(container);
}

/// Small wrapper so tests can navigate without importing go_router.
class GoRouterNavigator {
  GoRouterNavigator(this._container);

  final ProviderContainer _container;

  Future<void> go(WidgetTester tester, String location) async {
    _container.read(routerProvider).go(location);
    await tester.pumpAndSettle();
  }

  /// The location on top of the stack, including screens opened with push.
  String get location => _container
      .read(routerProvider)
      .routerDelegate
      .currentConfiguration
      .last
      .matchedLocation;
}
```

Replace `test/features/debts/debts_provider_test.dart` with:
```dart
import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/in_memory_debt_repository.dart';
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

  test('only re-subscribes when the currency changes', () async {
    final repository = InMemoryDebtRepository([testDebt(id: 'a')]);
    final c = ProviderContainer.test(
      overrides: [
        ...testOverrides(),
        debtRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (_, _) => null,
    )..listen(debtsProvider, (_, _) {});
    await c.read(debtsProvider.future);
    final settings = c.read(settingsControllerProvider.notifier);
    final before = repository.watchCount;

    await settings.setMonthlyBudget(12345);
    await settings.completeOnboarding();
    await c.pump();
    await c.read(debtsProvider.future);
    expect(repository.watchCount, before);

    await settings.setCurrency('USD');
    await c.pump();
    await c.read(debtsProvider.future);
    expect(repository.watchCount, before + 1);
  });
}
```

Replace `test/features/debts/drift_debt_repository_test.dart` with:
```dart
import 'dart:async';
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
    final emitted = StreamController<void>.broadcast();
    addTearDown(emitted.close);
    final sub = repo.watchAll('GBP').listen((d) {
      lengths.add(d.length);
      emitted.add(null);
    });
    addTearDown(sub.cancel);

    // Wait for each emission before the next change, so none are merged.
    Future<void> after(Future<void> Function() change) async {
      final next = emitted.stream.first;
      await change();
      await next;
    }

    await emitted.stream.first;
    await after(() => repo.add(testDebt(id: 'a')));
    await after(() => repo.add(testDebt(id: 'b')));
    await after(() => repo.delete('a'));
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

  group('convertAmounts', () {
    test('the first call only records the currency', () async {
      await repo.add(testDebt(id: 'a', balance: 123456));
      expect(await repo.amountsCurrencyCode(), isNull);
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      expect(await repo.amountsCurrencyCode(), 'GBP');
      expect((await all()).single.balance, const Money(123456, 'GBP'));
    });

    test('rescales balances and floors between decimal-digit counts', () async {
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      await repo.add(testDebt(id: 'a', balance: 123456, minPaymentFloor: 2550));
      await repo.convertAmounts(toCurrencyCode: 'JPY');
      final debt = (await all('JPY')).single;
      expect(debt.balance, const Money(1235, 'JPY'));
      expect(debt.minPaymentFloor, const Money(26, 'JPY'));
      expect(await repo.amountsCurrencyCode(), 'JPY');
    });

    test('converting to the current currency again changes nothing', () async {
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      await repo.add(testDebt(id: 'a', balance: 123456));
      await repo.convertAmounts(toCurrencyCode: 'JPY');
      await repo.convertAmounts(toCurrencyCode: 'JPY');
      expect((await all('JPY')).single.balance, const Money(1235, 'JPY'));
    });

    test('concurrent conversions to the same currency rescale once', () async {
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      await repo.add(testDebt(id: 'a', balance: 123456));
      await Future.wait([
        repo.convertAmounts(toCurrencyCode: 'JPY'),
        repo.convertAmounts(toCurrencyCode: 'JPY'),
      ]);
      expect((await all('JPY')).single.balance, const Money(1235, 'JPY'));
    });

    test('keeps rescaled amounts within the valid range', () async {
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      await repo.add(testDebt(id: 'small', balance: 40, minPaymentFloor: 40));
      await repo.convertAmounts(toCurrencyCode: 'JPY');
      final small = (await all('JPY')).single;
      expect(small.balance, const Money(1, 'JPY'), reason: 'never 0');
      expect(small.minPaymentFloor, const Money(0, 'JPY'));

      await repo.delete('small');
      await repo.add(
        testDebt(
          id: 'big',
          balance: kMaxAmountMinor,
          minPaymentFloor: kMaxAmountMinor,
        ),
      );
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      final big = (await all()).single;
      expect(big.balance, const Money(kMaxAmountMinor, 'GBP'));
      expect(big.minPaymentFloor, const Money(kMaxAmountMinor, 'GBP'));
      for (final d in await all()) {
        expect(validateDebt(d), isEmpty);
      }
    });
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

Replace `test/app/router_test.dart` with:
```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_detail_screen.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_screen.dart';
import 'package:debt_destroyer/features/onboarding/presentation/onboarding_screen.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_screen.dart';
import 'package:debt_destroyer/features/strategies/presentation/strategies_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('a new user is sent to onboarding', (tester) async {
    final app = await pumpApp(
      tester,
      settings: {SettingsKeys.onboardingComplete: false},
    );
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await app.router.go(tester, Routes.strategies);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('finishing onboarding opens the debts screen', (tester) async {
    final app = await pumpApp(
      tester,
      settings: {SettingsKeys.onboardingComplete: false},
    );
    await app.container
        .read(settingsControllerProvider.notifier)
        .completeOnboarding();
    await tester.pumpAndSettle();
    expect(find.byType(DebtsScreen), findsOneWidget);
  });

  testWidgets('a returning user starts on debts and can navigate', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    expect(find.byType(DebtsScreen), findsOneWidget);

    await app.router.go(tester, Routes.onboarding);
    expect(find.byType(DebtsScreen), findsOneWidget);

    await app.router.go(tester, Routes.strategies);
    expect(find.byType(StrategiesScreen), findsOneWidget);

    await app.router.go(tester, Routes.plan(StrategyId.balanceTransfer));
    final detail = tester.widget<PlanDetailScreen>(
      find.byType(PlanDetailScreen),
    );
    expect(detail.strategyId, StrategyId.balanceTransfer);

    await app.router.go(tester, Routes.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('an unknown strategy id falls back to the strategies list', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await app.router.go(tester, '${Routes.strategies}/nonsense');
    expect(find.byType(StrategiesScreen), findsOneWidget);
    expect(app.router.location, Routes.strategies);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/debts/debts_provider_test.dart test/app/router_test.dart`
Expected: FAIL. `planCalculatorProvider` is undefined, so `pump_app.dart` doesn't compile.

- [ ] **Step 3: Implement the seams**

Replace `lib/features/strategies/presentation/plans_providers.dart` with:
```dart
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/domain/rank_results.dart';
import 'package:flutter/foundation.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'plans_providers.g.dart';

/// Runs every standard strategy. The app computes in a background isolate;
/// widget tests substitute a synchronous version because isolates don't run
/// under the test clock.
typedef PlanCalculator = Future<List<PayoffResult>> Function(
  List<Debt> debts,
  Money monthlyBudget,
  StrategyParameters parameters,
);

@Riverpod(keepAlive: true)
PlanCalculator planCalculator(Ref ref) =>
    (debts, budget, parameters) =>
        compute(_calculateAll, (debts, budget, parameters));

/// Every strategy's result for the current debts and settings, ranked by
/// [rankResults]. Recalculated whenever either changes.
@riverpod
Future<List<PayoffResult>> plans(Ref ref) async {
  final debts = await ref.watch(debtsProvider.future);
  final settings = await ref.watch(settingsControllerProvider.future);
  final results = await ref.watch(planCalculatorProvider)(
    debts,
    settings.monthlyBudget,
    settings.strategyParameters,
  );
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

Replace `lib/features/debts/presentation/debts_providers.dart` with:
```dart
import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'debts_providers.freezed.dart';
part 'debts_providers.g.dart';

/// The user's debts, in their order, labelled with the current currency.
/// Re-subscribes to the database only when the currency changes (not on
/// every settings change), and stays loading until settings have loaded.
@Riverpod(keepAlive: true)
Stream<List<Debt>> debts(Ref ref) {
  final (currencyCode, error) = ref.watch(
    settingsControllerProvider.select((s) => (s.value?.currencyCode, s.error)),
  );
  if (error != null) return Stream.error(error);
  if (currencyCode == null) return const Stream.empty();
  return ref.watch(debtRepositoryProvider).watchAll(currencyCode);
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

  /// The change in progress; each new one waits for it, so a check (such
  /// as the debt count) and its write can't interleave with another.
  Future<void> _pending = Future<void>.value();

  @override
  void build() {}

  /// Adds [draft] with a new id (the draft's id is ignored).
  Future<DebtSaveOutcome> add(Debt draft) => _serialised(() async {
    final debt = draft.copyWith(id: _uuid.v4());
    final existing = await _stored();
    final outcome = _validate(debt, [...existing, debt]);
    if (outcome is DebtSaved) await ref.read(debtRepositoryProvider).add(debt);
    return outcome;
  });

  Future<DebtSaveOutcome> update(Debt debt) => _serialised(() async {
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
  });

  Future<void> delete(String id) =>
      _serialised(() => ref.read(debtRepositoryProvider).delete(id));

  Future<void> reorder(List<String> idsInOrder) =>
      _serialised(() => ref.read(debtRepositoryProvider).reorder(idsInOrder));

  Future<T> _serialised<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

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

Replace `lib/main.dart` with:
```dart
import 'dart:developer';

import 'package:debt_destroyer/app/app.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  // Load settings before the first frame so the router knows whether to
  // show onboarding. If loading fails the app still starts; the screens show
  // the error and offer a retry.
  try {
    await container.read(settingsControllerProvider.future);
  } on Object catch (error, stackTrace) {
    log('Settings failed to load', error: error, stackTrace: stackTrace);
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const DebtDestroyerApp(),
    ),
  );
}
```

- [ ] **Step 4: Generate code and run the tests**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+82: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "test: whole-app widget harness; debts stream re-subscribes only on currency change"
```

---

### Task 5: Debts list and debt form

**Files:**
- Modify: `lib/app/router.dart` (adds the debt form routes)
- Modify: `lib/features/debts/presentation/debts_screen.dart` (the real screen)
- Create: `lib/features/debts/presentation/debt_form_screen.dart`
- Test: `test/features/debts/debts_screen_test.dart`, `test/features/debts/debt_form_test.dart`

**Interfaces:**
- Consumes: `debtsProvider`, `debtActionsProvider`, `settingsControllerProvider`, `totalMinimumPayments`, `minimumPayment`, the money-format and label helpers, `runGuarded`.
- Produces:
  - `Routes.newDebt = '/debts/new'` and `Routes.editDebt(String id)`, which returns `/debts/<id>`
  - `DebtFormScreen({String? debtId})`
  - `DebtTile({required Debt debt, required String locale})`

- [ ] **Step 1: Write the failing tests**

`test/features/debts/debts_screen_test.dart`:
```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  final card = testDebt(id: 'a', name: 'Visa', balance: 200000);
  final loan = testDebt(
    id: 'b',
    name: 'Car loan',
    balance: 300000,
    aprBps: 650,
    minPaymentPercentBps: 0,
    minPaymentFloor: 15000,
    allowsOverpayment: false,
  );

  testWidgets('lists debts with the totals', (tester) async {
    await pumpApp(tester, debts: [card, loan]);
    expect(find.text('Visa'), findsOneWidget);
    expect(find.text('Car loan'), findsOneWidget);
    expect(find.text('£2,000.00'), findsOneWidget);
    expect(find.text('£5,000.00'), findsOneWidget); // total debt
    expect(find.text('£210.00'), findsOneWidget); // 60.00 + 150.00 minimums
    expect(find.text('£300.00'), findsOneWidget); // budget
    expect(find.textContaining('19.9% APR'), findsOneWidget);
  });

  testWidgets('with no debts, explains and disables comparing', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('No debts yet'), findsOneWidget);
    final compare = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Compare strategies'),
    );
    expect(compare.onPressed, isNull);
  });

  testWidgets('warns when the budget is below the minimum payments', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      debts: [card, loan],
      settings: {SettingsKeys.monthlyBudgetMinor: 20000},
    );
    expect(
      find.text(
        "Your budget is £10.00 short of this month's minimum payments.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Change budget'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.settings);
  });

  testWidgets('compare opens the strategies', (tester) async {
    final app = await pumpApp(tester, debts: [card]);
    await tester.tap(find.text('Compare strategies'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.strategies);
  });

  testWidgets('tapping a debt opens it for editing', (tester) async {
    final app = await pumpApp(tester, debts: [card]);
    await tester.tap(find.text('Visa'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.editDebt('a'));
  });

  testWidgets('swiping asks before deleting', (tester) async {
    final app = await pumpApp(tester, debts: [card, loan]);

    await tester.drag(find.text('Visa'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete Visa?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(app.repository.stored, hasLength(2));

    await tester.drag(find.text('Visa'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(app.repository.stored.map((d) => d.id), ['b']);
    expect(find.text('Visa'), findsNothing);
  });

  testWidgets('a failed delete tells the user', (tester) async {
    final app = await pumpApp(tester, debts: [card]);
    app.repository.failWritesWith = Exception('disk full');
    await tester.drag(find.text('Visa'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't save your changes. Please try again."),
      findsOneWidget,
    );
  });
}
```

`test/features/debts/debt_form_test.dart`:
```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> fill(
    WidgetTester tester, {
    String name = 'Visa',
    String balance = '1,234.56',
    String apr = '19.9',
    String minPercent = '3',
    String minFloor = '25',
  }) async {
    await tester.enterText(field('Name'), name);
    await tester.enterText(field('Balance'), balance);
    await tester.enterText(field('Interest rate (APR %)'), apr);
    await tester.enterText(field('Minimum payment (% of balance)'), minPercent);
    await tester.enterText(field('Minimum payment (at least)'), minFloor);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('adds a debt with exactly the amounts typed', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester);
    await save(tester);

    final saved = app.repository.stored.single;
    expect(saved.name, 'Visa');
    expect(saved.type, DebtType.creditCard);
    expect(saved.balance.minor, 123456);
    expect(saved.aprBps, 1990);
    expect(saved.minPaymentPercentBps, 300);
    expect(saved.minPaymentFloor.minor, 2500);
    expect(saved.allowsOverpayment, isTrue);
    expect(app.router.location, Routes.debts);
  });

  testWidgets('optional minimums may be left empty', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester, minPercent: '', minFloor: '');
    await save(tester);
    final saved = app.repository.stored.single;
    expect(saved.minPaymentPercentBps, 0);
    expect(saved.minPaymentFloor.minor, 0);
  });

  testWidgets('rejects text that is not an amount', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester, balance: 'lots');
    await save(tester);
    expect(find.text('Enter an amount, e.g. 1234'), findsOneWidget);
    expect(app.repository.stored, isEmpty);
  });

  testWidgets('shows the rule each invalid value breaks', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester, name: '  ', balance: '0', apr: '150');
    await save(tester);
    expect(find.text('Enter a name'), findsOneWidget);
    expect(find.text('Enter a balance above zero'), findsOneWidget);
    expect(find.text('Enter a rate between 0 and 100'), findsOneWidget);
    expect(app.repository.stored, isEmpty);
  });

  testWidgets('saving again without a fix keeps the message', (tester) async {
    await pumpApp(tester, location: Routes.newDebt);
    await fill(tester, apr: '150');
    await save(tester);
    await save(tester);
    expect(find.text('Enter a rate between 0 and 100'), findsOneWidget);
  });

  testWidgets('a corrected debt saves on the next try', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester, apr: '150');
    await save(tester);
    expect(find.text('Enter a rate between 0 and 100'), findsOneWidget);

    await tester.enterText(field('Interest rate (APR %)'), '15');
    await save(tester);
    expect(app.repository.stored.single.aprBps, 1500);
  });

  testWidgets('choosing Loan for a new debt turns off overpaying', (
    tester,
  ) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await tester.tap(find.text('Loan'));
    await tester.pumpAndSettle();
    await fill(tester);
    await save(tester);
    expect(app.repository.stored.single.type, DebtType.loan);
    expect(app.repository.stored.single.allowsOverpayment, isFalse);
  });

  testWidgets('edits an existing debt in place', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a', name: 'Visa', balance: 123456)],
      location: Routes.editDebt('a'),
    );
    expect(find.text('1234.56'), findsOneWidget);
    expect(find.text('19.9'), findsOneWidget);
    await tester.enterText(field('Name'), 'Visa Gold');
    await save(tester);
    final saved = app.repository.stored.single;
    expect(saved.id, 'a');
    expect(saved.name, 'Visa Gold');
    expect(saved.balance.minor, 123456);
  });

  testWidgets('refuses a debt beyond the maximum count', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [for (var i = 0; i < kMaxDebts; i++) testDebt(id: 'd$i')],
      location: Routes.newDebt,
    );
    await fill(tester);
    await save(tester);
    expect(find.text('You can track up to 50 debts'), findsOneWidget);
    expect(app.repository.stored, hasLength(kMaxDebts));
  });

  testWidgets('editing a debt that no longer exists shows an error', (
    tester,
  ) async {
    await pumpApp(tester, location: Routes.editDebt('gone'));
    expect(find.text('Edit debt'), findsOneWidget);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/debts/debts_screen_test.dart test/features/debts/debt_form_test.dart`
Expected: FAIL. `Routes.newDebt`/`Routes.editDebt` are undefined, and the placeholder screen has none of the expected text.

- [ ] **Step 3: Implement**

Replace `lib/app/router.dart` with:
```dart
import 'package:debt_destroyer/features/analysis/presentation/plan_detail_screen.dart';
import 'package:debt_destroyer/features/debts/presentation/debt_form_screen.dart';
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
  static const newDebt = '/debts/new';
  static const onboarding = '/onboarding';
  static const strategies = '/strategies';
  static const settings = '/settings';

  static String plan(StrategyId id) => '$strategies/${id.name}';

  static String editDebt(String id) => '/debts/$id';
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
        routes: [
          GoRoute(
            path: 'debts/new',
            builder: (context, state) => const DebtFormScreen(),
          ),
          GoRoute(
            path: 'debts/:debtId',
            builder: (context, state) =>
                DebtFormScreen(debtId: state.pathParameters['debtId']),
          ),
        ],
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

Replace `lib/features/debts/presentation/debts_screen.dart` with:
```dart
import 'dart:async';

import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final debts = ref.watch(debtsProvider);
    final settings = ref.watch(settingsControllerProvider).value;
    final hasDebts = debts.value?.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.debtsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTooltip,
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newDebt),
        icon: const Icon(Icons.add),
        label: Text(l10n.addDebt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
      bottomNavigationBar: BottomAppBar(
        child: Row(
          children: [
            FilledButton(
              onPressed: hasDebts
                  ? () => context.push(Routes.strategies)
                  : null,
              child: Text(l10n.compareStrategies),
            ),
          ],
        ),
      ),
      body: switch ((debts, settings)) {
        (AsyncData(:final value), final AppSettings settings) => _DebtsBody(
          debts: value,
          settings: settings,
        ),
        (AsyncError(), _) => _ErrorView(
          onRetry: () => ref.invalidate(debtsProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(context.l10n.errorGeneric),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retry)),
      ],
    ),
  );
}

class _DebtsBody extends ConsumerStatefulWidget {
  const _DebtsBody({required this.debts, required this.settings});

  final List<Debt> debts;
  final AppSettings settings;

  @override
  ConsumerState<_DebtsBody> createState() => _DebtsBodyState();
}

class _DebtsBodyState extends ConsumerState<_DebtsBody> {
  /// Debts swiped away but not yet gone from the stream. A dismissed
  /// Dismissible must leave the tree immediately.
  final _removed = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final debts = [
      for (final d in widget.debts)
        if (!_removed.contains(d.id)) d,
    ];
    final currency = widget.settings.currencyCode;
    final minimums = totalMinimumPayments(debts, currency: currency);
    final budget = widget.settings.monthlyBudget;

    return Column(
      children: [
        _SummaryCard(
          total: debts.fold(Money.zero(currency), (sum, d) => sum + d.balance),
          minimums: minimums,
          budget: budget,
          locale: locale,
        ),
        if (minimums > budget)
          _ShortfallBanner(shortfall: minimums - budget, locale: locale),
        Expanded(
          child: debts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.debtsEmpty, textAlign: TextAlign.center),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: debts.length,
                  onReorderItem: (from, to) => _reorder(debts, from, to),
                  itemBuilder: (context, i) => _dismissible(debts[i], locale),
                ),
        ),
      ],
    );
  }

  Widget _dismissible(Debt debt, String locale) => Dismissible(
    key: ValueKey(debt.id),
    direction: DismissDirection.endToStart,
    background: ColoredBox(
      color: Theme.of(context).colorScheme.errorContainer,
      child: const Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Icon(Icons.delete_outline),
        ),
      ),
    ),
    confirmDismiss: (_) => _confirmDelete(debt),
    onDismissed: (_) {
      setState(() => _removed.add(debt.id));
      unawaited(
        runGuarded(
          context,
          () => ref.read(debtActionsProvider.notifier).delete(debt.id),
        ),
      );
    },
    child: DebtTile(debt: debt, locale: locale),
  );

  Future<bool> _confirmDelete(Debt debt) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteDebtTitle(debt.name)),
        content: Text(l10n.deleteDebtBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _reorder(List<Debt> debts, int from, int to) async {
    final ids = [for (final d in debts) d.id];
    final moved = ids.removeAt(from);
    ids.insert(to, moved); // onReorderItem already adjusted [to]
    await runGuarded(
      context,
      () => ref.read(debtActionsProvider.notifier).reorder(ids),
    );
  }
}

class DebtTile extends StatelessWidget {
  const DebtTile({required this.debt, required this.locale, super.key});

  final Debt debt;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      leading: Icon(switch (debt.type) {
        DebtType.creditCard => Icons.credit_card,
        DebtType.loan => Icons.account_balance_outlined,
        DebtType.personal => Icons.people_outline,
      }, semanticLabel: debtTypeLabel(l10n, debt.type)),
      title: Text(debt.name),
      subtitle: Text(
        '${l10n.debtApr(formatPercent(debt.aprBps, locale))} · '
        '${l10n.debtMinimum(formatMoney(minimumPayment(debt), locale))}',
      ),
      trailing: Text(
        formatMoney(debt.balance, locale),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: () => context.push(Routes.editDebt(debt.id)),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.minimums,
    required this.budget,
    required this.locale,
  });

  final Money total;
  final Money minimums;
  final Money budget;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget figure(String label, Money value) => Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(
            formatMoney(value, locale),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            figure(l10n.totalDebt, total),
            figure(l10n.minimumPayments, minimums),
            figure(l10n.monthlyBudget, budget),
          ],
        ),
      ),
    );
  }
}

class _ShortfallBanner extends StatelessWidget {
  const _ShortfallBanner({required this.shortfall, required this.locale});

  final Money shortfall;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: ListTile(
        leading: Icon(Icons.warning_amber, color: scheme.onErrorContainer),
        title: Text(
          l10n.budgetShortfall(formatMoney(shortfall, locale)),
          style: TextStyle(color: scheme.onErrorContainer),
        ),
        trailing: TextButton(
          onPressed: () => context.push(Routes.settings),
          child: Text(l10n.changeBudget),
        ),
      ),
    );
  }
}
```

`lib/features/debts/presentation/debt_form_screen.dart`:
```dart
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Adds a debt, or edits the one with [debtId].
class DebtFormScreen extends ConsumerWidget {
  const DebtFormScreen({this.debtId, super.key});

  final String? debtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final currency = ref.watch(
      settingsControllerProvider.select((s) => s.value?.currencyCode),
    );
    final debts = ref.watch(debtsProvider);
    final title = Text(debtId == null ? l10n.newDebtTitle : l10n.editDebtTitle);
    if (currency == null || !debts.hasValue) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final existing = debtId == null
        ? null
        : debts.requireValue.where((d) => d.id == debtId).firstOrNull;
    if (debtId != null && existing == null) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: Center(child: Text(l10n.errorGeneric)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: title),
      body: _DebtForm(
        key: ValueKey(debtId),
        existing: existing,
        currencyCode: currency,
      ),
    );
  }
}

enum _Field { name, balance, apr, minPercent, minFloor }

class _DebtForm extends ConsumerStatefulWidget {
  const _DebtForm({
    required this.existing,
    required this.currencyCode,
    super.key,
  });

  final Debt? existing;
  final String currencyCode;

  @override
  ConsumerState<_DebtForm> createState() => _DebtFormState();
}

class _DebtFormState extends ConsumerState<_DebtForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<_Field, TextEditingController> _controllers;
  late DebtType _type;
  late bool _allowsOverpayment;
  Map<_Field, String> _errors = const {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final locale = ref.read(formatLocaleProvider);
    final d = widget.existing;
    String money(Money m) => formatAmountInput(m, locale);
    String percent(int bps) => formatPercentInput(bps, locale);
    _controllers = {
      _Field.name: TextEditingController(text: d?.name ?? ''),
      _Field.balance: TextEditingController(
        text: d == null ? '' : money(d.balance),
      ),
      _Field.apr: TextEditingController(
        text: d == null ? '' : percent(d.aprBps),
      ),
      _Field.minPercent: TextEditingController(
        text: d == null ? '' : percent(d.minPaymentPercentBps),
      ),
      _Field.minFloor: TextEditingController(
        text: d == null ? '' : money(d.minPaymentFloor),
      ),
    };
    _type = d?.type ?? DebtType.creditCard;
    _allowsOverpayment = d?.allowsOverpayment ?? true;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final example = formatAmountInput(
      Money(123456 ~/ 100 * 100, widget.currencyCode),
      locale,
    );

    String? amount(String? text, {required bool required}) {
      final value = text ?? '';
      if (!required && value.trim().isEmpty) return null;
      return parseAmountMinor(
                value,
                currencyCode: widget.currencyCode,
                locale: locale,
              ) ==
              null
          ? l10n.errorInvalidAmount(example)
          : null;
    }

    String? percent(String? text, {required bool required}) {
      final value = text ?? '';
      if (!required && value.trim().isEmpty) return null;
      return parsePercentBps(value, locale) == null
          ? l10n.errorInvalidPercent(formatPercentInput(1990, locale))
          : null;
    }

    Widget field(
      _Field f,
      String label, {
      String? Function(String?)? validator,
      TextInputType? keyboard,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey(f),
        controller: _controllers[f],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: keyboard,
        validator: validator,
        forceErrorText: _errors[f],
        onChanged: (_) {
          if (_errors.containsKey(f)) {
            setState(() => _errors = {..._errors}..remove(f));
          }
        },
      ),
    );

    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          field(_Field.name, l10n.fieldName),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SegmentedButton<DebtType>(
              segments: [
                for (final t in DebtType.values)
                  ButtonSegment(value: t, label: Text(debtTypeLabel(l10n, t))),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.single;
                // Loans usually have fixed repayments; suggest that for new
                // debts only, never overriding a saved choice.
                if (widget.existing == null) {
                  _allowsOverpayment = _type != DebtType.loan;
                }
              }),
            ),
          ),
          field(
            _Field.balance,
            l10n.fieldBalance,
            keyboard: numberKeyboard,
            validator: (v) => amount(v, required: true),
          ),
          field(
            _Field.apr,
            l10n.fieldApr,
            keyboard: numberKeyboard,
            validator: (v) => percent(v, required: true),
          ),
          field(
            _Field.minPercent,
            l10n.fieldMinPercent,
            keyboard: numberKeyboard,
            validator: (v) => percent(v, required: false),
          ),
          field(
            _Field.minFloor,
            l10n.fieldMinFloor,
            keyboard: numberKeyboard,
            validator: (v) => amount(v, required: false),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.fieldAllowsOverpayment),
            subtitle: Text(l10n.fieldAllowsOverpaymentHint),
            value: _allowsOverpayment,
            onChanged: (v) => setState(() => _allowsOverpayment = v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    // A field rejected last time keeps its message until it is edited.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final locale = ref.read(formatLocaleProvider);
    final code = widget.currencyCode;
    int amount(_Field f) =>
        parseAmountMinor(
          _controllers[f]!.text,
          currencyCode: code,
          locale: locale,
        ) ??
        0;
    int percent(_Field f) =>
        parsePercentBps(_controllers[f]!.text, locale) ?? 0;

    final debt = Debt(
      id: widget.existing?.id ?? '',
      name: _controllers[_Field.name]!.text.trim(),
      type: _type,
      balance: Money(amount(_Field.balance), code),
      aprBps: percent(_Field.apr),
      minPaymentPercentBps: percent(_Field.minPercent),
      minPaymentFloor: Money(amount(_Field.minFloor), code),
      allowsOverpayment: _allowsOverpayment,
    );

    setState(() => _saving = true);
    final actions = ref.read(debtActionsProvider.notifier);
    final outcome = await runGuarded(
      context,
      () => widget.existing == null ? actions.add(debt) : actions.update(debt),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (outcome) {
      case DebtSaved():
        context.pop();
      case DebtRejected(:final errors, :final listErrors):
        _showErrors(errors, listErrors);
      case null:
        break; // runGuarded already told the user
    }
  }

  void _showErrors(
    Set<DebtValidationError> errors,
    Set<DebtListValidationError> listErrors,
  ) {
    final l10n = context.l10n;
    final byField = <_Field, String>{};
    for (final e in errors) {
      switch (e) {
        case DebtValidationError.nameEmpty:
          byField[_Field.name] = l10n.errorNameEmpty;
        case DebtValidationError.balanceNotPositive:
          byField[_Field.balance] = l10n.errorBalanceNotPositive;
        case DebtValidationError.balanceTooLarge:
          byField[_Field.balance] = l10n.errorTooLarge;
        case DebtValidationError.aprOutOfRange:
          byField[_Field.apr] = l10n.errorRateRange;
        case DebtValidationError.minPaymentPercentOutOfRange:
          byField[_Field.minPercent] = l10n.errorPercentRange;
        case DebtValidationError.minPaymentFloorNegative:
          byField[_Field.minFloor] = l10n.errorFloorNegative;
        case DebtValidationError.minPaymentFloorTooLarge:
          byField[_Field.minFloor] = l10n.errorTooLarge;
        case DebtValidationError.floorCurrencyMismatch:
          break; // not reachable from this form: one currency throughout
      }
    }
    setState(() => _errors = byField);
    if (listErrors.contains(DebtListValidationError.tooMany)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorTooManyDebts(kMaxDebts))),
      );
    }
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+99: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "feat(debts): debt list with totals, shortfall warning, reorder, delete and form"
```

---

### Task 6: Strategies screen

**Files:**
- Modify: `lib/features/strategies/presentation/strategies_screen.dart` (the real screen)
- Test: `test/features/strategies/strategies_screen_test.dart`

**Interfaces:**
- Consumes: `plansProvider`, `debtsProvider`, `settingsControllerProvider`, `strategyName`, `strategyDescription`, `formatDuration`, `formatMoney`.

- [ ] **Step 1: Write the failing test**

`test/features/strategies/strategies_screen_test.dart`:
```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  // 1,000.00 at 0% with no minimum, paid at 250.00 a month.
  final simple = testDebt(
    id: 'a',
    name: 'Visa',
    aprBps: 0,
    minPaymentPercentBps: 0,
    minPaymentFloor: 0,
  );

  testWidgets('ranks every strategy and marks the cheapest', (tester) async {
    await pumpApp(
      tester,
      debts: [simple],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    for (final name in [
      'Highest interest first',
      'Lowest interest first',
      'Pay 10% more',
      'Consolidation loan',
      '0% balance transfer',
    ]) {
      await tester.scrollUntilVisible(find.text(name), 100);
      expect(find.text(name), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('Cheapest'), -100);
    expect(find.text('Cheapest'), findsOneWidget);
    // Ties on cost and months fall back to strategy order.
    final cheapestCard = find.ancestor(
      of: find.text('Cheapest'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(
        of: cheapestCard,
        matching: find.text('Highest interest first'),
      ),
      findsOneWidget,
    );
    expect(find.text('Debt-free in 4 months'), findsWidgets);
    expect(find.text('Total paid: £1,000.00'), findsWidgets);
  });

  testWidgets('explains a budget that cannot cover the minimums', (
    tester,
  ) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      settings: {SettingsKeys.monthlyBudgetMinor: 1000},
      location: Routes.strategies,
    );
    expect(
      find.textContaining('short of the minimum payments in month 1'),
      findsWidgets,
    );
  });

  testWidgets('opens a feasible plan', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [simple],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    await tester.tap(find.text('Highest interest first'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.plan(StrategyId.avalanche));
  });

  testWidgets('with no debts, asks for one', (tester) async {
    await pumpApp(tester, location: Routes.strategies);
    expect(find.text('Add a debt to compare strategies.'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/strategies/strategies_screen_test.dart`
Expected: FAIL, because the placeholder shows no strategy cards.

- [ ] **Step 3: Implement**

Replace `lib/features/strategies/presentation/strategies_screen.dart` with:
```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';

class StrategiesScreen extends ConsumerWidget {
  const StrategiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final debts = ref.watch(debtsProvider).value;
    final plans = ref.watch(plansProvider);
    final parameters = ref
        .watch(settingsControllerProvider)
        .value
        ?.strategyParameters;

    final Widget body;
    if (debts != null && debts.isEmpty) {
      body = _Message(l10n.strategiesEmpty);
    } else {
      body = switch ((plans, parameters)) {
        (AsyncData(:final value), final StrategyParameters parameters) =>
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final (i, result) in value.indexed)
                _StrategyCard(
                  result: result,
                  parameters: parameters,
                  cheapest: i == 0 && result is Feasible,
                ),
            ],
          ),
        (AsyncError(), _) => _Message(
          l10n.plansError,
          onRetry: () => ref.invalidate(plansProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.strategiesTitle)),
      body: body,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ],
      ),
    ),
  );
}

class _StrategyCard extends ConsumerWidget {
  const _StrategyCard({
    required this.result,
    required this.parameters,
    required this.cheapest,
  });

  final PayoffResult result;
  final StrategyParameters parameters;
  final bool cheapest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final theme = Theme.of(context);
    final id = result.strategyId;

    final details = switch (result) {
      Feasible(:final plan) => _FeasibleDetails(plan: plan, locale: locale),
      Infeasible(:final shortfall, :final month) => Text(
        l10n.infeasible(formatMoney(shortfall, locale), month),
        style: TextStyle(color: theme.colorScheme.error),
      ),
      NeverClears() => Text(
        l10n.neverClears,
        style: TextStyle(color: theme.colorScheme.error),
      ),
    };

    return Card(
      key: ValueKey(id),
      color: cheapest ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: result is Feasible ? () => context.push(Routes.plan(id)) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strategyName(l10n, id),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (cheapest) Chip(label: Text(l10n.cheapest)),
                ],
              ),
              Text(
                strategyDescription(l10n, id, parameters, locale),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              details,
            ],
          ),
        ),
      ),
    );
  }
}

class _FeasibleDetails extends StatelessWidget {
  const _FeasibleDetails({required this.plan, required this.locale});

  final PayoffPlan plan;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (plan.monthsToClear == 0) return Text(l10n.alreadyDebtFree);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.debtFreeIn(formatDuration(l10n, plan.monthsToClear)),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(
          '${l10n.totalInterest}: ${formatMoney(plan.totalInterest, locale)}',
        ),
        if (plan.totalFees.isPositive)
          Text('${l10n.fees}: ${formatMoney(plan.totalFees, locale)}'),
        Text('${l10n.totalPaid}: ${formatMoney(plan.totalPaid, locale)}'),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+103: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/strategies test/features/strategies
git commit -m "feat(strategies): ranked strategy cards with cheapest and infeasible states"
```

---

### Task 7: Plan detail with summary, chart, schedule and export

**Files:**
- Create: `lib/features/analysis/domain/schedule_table.dart`
- Create: `lib/features/analysis/data/schedule_export.dart`, `lib/features/analysis/data/plan_exporter.dart`
- Create: `lib/features/analysis/presentation/plan_summary_tab.dart`, `plan_chart_tab.dart`, `plan_schedule_tab.dart`
- Modify: `lib/features/analysis/presentation/plan_detail_screen.dart` (the real screen)
- Test: `test/features/analysis/schedule_test.dart`, `test/features/analysis/plan_detail_test.dart`

**Interfaces:**
- Consumes: `planProvider`, `planDebtName`, `strategyName`, `formatMoney`, `formatDuration`, `clockProvider`, `runGuarded`, `currencyDecimalDigits`.
- Produces:
  - `ScheduleTable`, `ScheduleRow` and `ScheduleLabels`, with `buildScheduleTable(PayoffPlan, {required List<String> debtNames, required ScheduleLabels labels})`
  - `String scheduleToCsv(ScheduleTable)`, `List<int> scheduleToXlsx(ScheduleTable, {String sheetName})` and `String majorUnitsText(Money)`
  - `enum ExportFormat { csv, xlsx }`
  - `abstract interface class FileSharer`, implemented by `SharePlusFileSharer`
  - `class PlanExporter`, with `Future<File> export(ScheduleTable, ExportFormat, {required String baseName, String? subject})`
  - `fileSharerProvider` and `planExporterProvider`
  - `List<List<double>> stackedBalances(PayoffPlan)`
  - `ScheduleTable scheduleTableFor(AppLocalizations, PayoffPlan)`

- [ ] **Step 1: Write the failing tests**

`test/features/analysis/schedule_test.dart`:
```dart
import 'dart:convert';
import 'dart:io';

import 'package:debt_destroyer/features/analysis/data/plan_exporter.dart';
import 'package:debt_destroyer/features/analysis/data/schedule_export.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_chart_tab.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

Money gbp(int minor) => Money(minor, 'GBP');

/// Two debts, two months: payments and balances chosen to be easy to check.
final plan = PayoffPlan(
  debts: [
    PlanDebt(id: 'a', name: 'Visa', startingBalance: gbp(15000)),
    PlanDebt(id: 'b', name: 'Loan, "car"', startingBalance: gbp(5050)),
  ],
  months: [
    MonthRow(
      month: 1,
      interest: [gbp(0), gbp(0)],
      payments: [gbp(10000), gbp(2525)],
      closingBalances: [gbp(5000), gbp(2525)],
    ),
    MonthRow(
      month: 2,
      interest: [gbp(0), gbp(0)],
      payments: [gbp(5000), gbp(2525)],
      closingBalances: [gbp(0), gbp(0)],
    ),
  ],
  totalPaid: gbp(20050),
  totalInterest: gbp(0),
  totalFees: gbp(0),
);

const labels = ScheduleLabels(
  month: 'Month',
  payment: _payment,
  balance: _balance,
  totalPayment: 'Total payment',
  totalBalance: 'Total balance',
);
String _payment(String name) => '$name payment';
String _balance(String name) => '$name balance';

ScheduleTable table() => buildScheduleTable(
  plan,
  debtNames: ['Visa', 'Loan, "car"'],
  labels: labels,
);

void main() {
  test('lays out payments and balances per debt, then totals', () {
    final t = table();
    expect(t.headers, [
      'Month',
      'Visa payment',
      'Visa balance',
      'Loan, "car" payment',
      'Loan, "car" balance',
      'Total payment',
      'Total balance',
    ]);
    expect(t.rows.first.month, 1);
    expect(t.rows.first.amounts, [
      gbp(10000),
      gbp(5000),
      gbp(2525),
      gbp(2525),
      gbp(12525),
      gbp(7525),
    ]);
  });

  test('majorUnitsText writes exact decimals', () {
    expect(majorUnitsText(gbp(123456)), '1234.56');
    expect(majorUnitsText(gbp(5)), '0.05');
    expect(majorUnitsText(gbp(0)), '0.00');
    expect(majorUnitsText(gbp(-150)), '-1.50');
    expect(majorUnitsText(const Money(1235, 'JPY')), '1235');
  });

  test('CSV quotes awkward headers and uses plain numbers', () {
    expect(
      scheduleToCsv(table()),
      [
        [
          'Month',
          'Visa payment',
          'Visa balance',
          '"Loan, ""car"" payment"',
          '"Loan, ""car"" balance"',
          'Total payment',
          'Total balance',
        ].join(','),
        '1,100.00,50.00,25.25,25.25,125.25,75.25',
        '2,50.00,0.00,25.25,0.00,75.25,0.00',
        '',
      ].join('\r\n'),
    );
  });

  test('XLSX holds the same table with numeric cells', () {
    final workbook = Excel.decodeBytes(scheduleToXlsx(table()));
    final rows = workbook.tables['Schedule']!.rows;
    expect(rows, hasLength(3));
    expect(rows[0][1]!.value, TextCellValue('Visa payment'));
    // Whole numbers read back as integer cells; either way they're numbers.
    num numeric(CellValue? v) => switch (v) {
      IntCellValue(:final value) => value,
      DoubleCellValue(:final value) => value,
      _ => throw StateError('not a number: $v'),
    };
    expect(numeric(rows[1][0]!.value), 1);
    expect(numeric(rows[1][1]!.value), 100);
    expect(numeric(rows[2][5]!.value), 75.25);
  });

  test('stacked balances start from the starting balances', () {
    expect(stackedBalances(plan), [
      [150.0, 200.5],
      [50.0, 75.25],
      [0.0, 0.0],
    ]);
  });

  test(
    'PlanExporter writes the file and hands it to the share sheet',
    () async {
      final dir = await Directory.systemTemp.createTemp('export');
      addTearDown(() => dir.delete(recursive: true));
      final sharer = _RecordingSharer();
      final exporter = PlanExporter(sharer, () async => dir);

      final csv = await exporter.export(
        table(),
        ExportFormat.csv,
        baseName: 'plan',
      );
      expect(csv.path, '${dir.path}/plan.csv');
      expect(await csv.readAsString(), scheduleToCsv(table()));
      expect(sharer.shared.single, (csv.path, 'text/csv'));

      final xlsx = await exporter.export(
        table(),
        ExportFormat.xlsx,
        baseName: 'plan',
      );
      expect(xlsx.path.endsWith('.xlsx'), isTrue);
      expect(
        Excel.decodeBytes(await xlsx.readAsBytes()).tables,
        contains('Schedule'),
      );
    },
  );

  test('CSV is valid UTF-8 for non-ASCII names', () {
    final t = buildScheduleTable(
      plan,
      debtNames: ['Crédit', 'Ünicode'],
      labels: labels,
    );
    expect(
      utf8.decode(utf8.encode(scheduleToCsv(t))),
      contains('Crédit payment'),
    );
  });
}

class _RecordingSharer implements FileSharer {
  final shared = <(String, String)>[];

  @override
  Future<void> shareFile(
    File file, {
    required String mimeType,
    String? subject,
  }) async {
    shared.add((file.path, mimeType));
  }
}
```

`test/features/analysis/plan_detail_test.dart`:
```dart
import 'dart:io';

import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/analysis/data/plan_exporter.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

class _RecordingExporter extends PlanExporter {
  _RecordingExporter() : super(_NoSharer(), () async => Directory.systemTemp);

  final calls = <(ScheduleTable, ExportFormat, String)>[];
  Exception? failWith;

  @override
  Future<File> export(
    ScheduleTable table,
    ExportFormat format, {
    required String baseName,
    String? subject,
  }) async {
    if (failWith case final error?) throw error;
    calls.add((table, format, baseName));
    return File('unused');
  }
}

class _NoSharer implements FileSharer {
  @override
  Future<void> shareFile(
    File file, {
    required String mimeType,
    String? subject,
  }) async {}
}

void main() {
  final visa = testDebt(
    id: 'a',
    name: 'Visa',
    aprBps: 0,
    minPaymentPercentBps: 0,
    minPaymentFloor: 0,
  );

  Future<AppHarness> open(
    WidgetTester tester, {
    _RecordingExporter? exporter,
  }) => pumpApp(
    tester,
    debts: [visa],
    settings: {SettingsKeys.monthlyBudgetMinor: 25000},
    location: Routes.plan(StrategyId.avalanche),
    overrides: [
      if (exporter != null) planExporterProvider.overrideWithValue(exporter),
    ],
  );

  testWidgets('summarises when and how the debts are cleared', (tester) async {
    await open(tester);
    // The fixed test clock is 24 Sep 2026; four payments later is January.
    expect(find.text('Debt-free by January 2027'), findsOneWidget);
    expect(find.text('Debt-free in 4 months'), findsOneWidget);
    expect(find.text('£1,000.00'), findsOneWidget); // total paid
    expect(find.text('£0.00'), findsOneWidget); // total interest
    expect(find.text('£250.00'), findsOneWidget); // this month
    expect(find.text('Payment priority'), findsOneWidget);
  });

  testWidgets('charts the balance over time', (tester) async {
    await open(tester);
    await tester.tap(find.text('Chart'));
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Balance over time'), findsOneWidget);
  });

  testWidgets('shows the month-by-month schedule', (tester) async {
    await open(tester);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Visa payment'), findsOneWidget);
    expect(find.text('Total balance'), findsOneWidget);
    expect(find.text('£750.00'), findsNWidgets(2)); // month 1 balance + total
  });

  testWidgets('shares the schedule as CSV or XLSX', (tester) async {
    final exporter = _RecordingExporter();
    await open(tester, exporter: exporter);
    for (final (label, format) in [
      ('Spreadsheet (CSV)', ExportFormat.csv),
      ('Excel workbook (XLSX)', ExportFormat.xlsx),
    ]) {
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(exporter.calls.last.$2, format);
    }
    final (table, _, baseName) = exporter.calls.first;
    expect(baseName, 'debt-plan-avalanche');
    expect(table.rows, hasLength(4));
  });

  testWidgets('a failed export tells the user', (tester) async {
    final exporter = _RecordingExporter()..failWith = Exception('no space');
    await open(tester, exporter: exporter);
    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spreadsheet (CSV)'));
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't save your changes. Please try again."),
      findsOneWidget,
    );
  });

  testWidgets('an infeasible plan is explained, not drawn', (tester) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      settings: {SettingsKeys.monthlyBudgetMinor: 1000},
      location: Routes.plan(StrategyId.avalanche),
    );
    expect(
      find.text("This plan isn't available for your current debts and budget."),
      findsOneWidget,
    );
    expect(find.byType(TabBar), findsNothing);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/analysis`
Expected: FAIL to load, because `schedule_table.dart`, `schedule_export.dart` and `plan_exporter.dart` don't exist.

- [ ] **Step 3: The schedule and its export**

`lib/features/analysis/domain/schedule_table.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// A plan laid out as rows for the schedule tab and for export: for each
/// month, every debt's payment and closing balance, then the totals.
@immutable
class ScheduleTable {
  const ScheduleTable({required this.headers, required this.rows});

  /// `Month`, then per debt `<name> payment`, `<name> balance`, then
  /// `Total payment`, `Total balance`.
  final List<String> headers;
  final List<ScheduleRow> rows;
}

@immutable
class ScheduleRow {
  const ScheduleRow({required this.month, required this.amounts});

  final int month;

  /// In [ScheduleTable.headers] order after `Month`.
  final List<Money> amounts;
}

/// Column labels, supplied by the caller so they can be translated.
@immutable
class ScheduleLabels {
  const ScheduleLabels({
    required this.month,
    required this.payment,
    required this.balance,
    required this.totalPayment,
    required this.totalBalance,
  });

  final String month;
  final String Function(String debtName) payment;
  final String Function(String debtName) balance;
  final String totalPayment;
  final String totalBalance;
}

ScheduleTable buildScheduleTable(
  PayoffPlan plan, {
  required List<String> debtNames,
  required ScheduleLabels labels,
}) {
  assert(debtNames.length == plan.debts.length, 'one name per plan debt');
  final currency = plan.totalPaid.currency;
  Money sum(List<Money> values) =>
      values.fold(Money.zero(currency), (a, b) => a + b);
  return ScheduleTable(
    headers: [
      labels.month,
      for (final name in debtNames) ...[
        labels.payment(name),
        labels.balance(name),
      ],
      labels.totalPayment,
      labels.totalBalance,
    ],
    rows: [
      for (final row in plan.months)
        ScheduleRow(
          month: row.month,
          amounts: [
            for (var i = 0; i < plan.debts.length; i++) ...[
              row.payments[i],
              row.closingBalances[i],
            ],
            sum(row.payments),
            sum(row.closingBalances),
          ],
        ),
    ],
  );
}
```

`lib/features/analysis/data/schedule_export.dart`:
```dart
import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:excel/excel.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// [table] as CSV (RFC 4180, CRLF line ends). Amounts are plain numbers in
/// major units with a `.` decimal point, e.g. `1234.56`, so spreadsheets in
/// any locale read them as numbers.
String scheduleToCsv(ScheduleTable table) {
  final lines = [
    table.headers.map(_csvField).join(','),
    for (final row in table.rows)
      [
        '${row.month}',
        for (final amount in row.amounts) majorUnitsText(amount),
      ].join(','),
  ];
  return '${lines.join('\r\n')}\r\n';
}

/// [table] as an XLSX workbook with one sheet, amounts as numbers.
List<int> scheduleToXlsx(ScheduleTable table, {String sheetName = 'Schedule'}) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet()!;
  excel
    ..rename(defaultSheet, sheetName)
    ..appendRow(sheetName, [for (final h in table.headers) TextCellValue(h)]);
  for (final row in table.rows) {
    excel.appendRow(sheetName, [
      IntCellValue(row.month),
      for (final amount in row.amounts)
        DoubleCellValue(double.parse(majorUnitsText(amount))),
    ]);
  }
  return excel.save()!;
}

/// [money] in major units as exact decimal text, e.g. `1234.56`.
String majorUnitsText(Money money) {
  final digits = currencyDecimalDigits(money.currency);
  final text = money.minor.abs().toString().padLeft(digits + 1, '0');
  final sign = money.isNegative ? '-' : '';
  if (digits == 0) return '$sign$text';
  final split = text.length - digits;
  return '$sign${text.substring(0, split)}.${text.substring(split)}';
}

String _csvField(String value) {
  if (!value.contains(RegExp('[",\r\n]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}
```

`lib/features/analysis/data/plan_exporter.dart`:
```dart
import 'dart:convert';
import 'dart:io';

import 'package:debt_destroyer/features/analysis/data/schedule_export.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

part 'plan_exporter.g.dart';

enum ExportFormat {
  csv('csv', 'text/csv'),
  xlsx(
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );

  ExportFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}

/// Hands a file to the platform share sheet.
abstract interface class FileSharer {
  Future<void> shareFile(
    File file, {
    required String mimeType,
    String? subject,
  });
}

class SharePlusFileSharer implements FileSharer {
  @override
  Future<void> shareFile(
    File file, {
    required String mimeType,
    String? subject,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
      ),
    );
  }
}

/// Writes a schedule to a temporary file and shares it. The temporary
/// directory needs no storage permission.
class PlanExporter {
  PlanExporter(this._sharer, this._directory);

  final FileSharer _sharer;
  final Future<Directory> Function() _directory;

  /// Returns the file written (and shared).
  Future<File> export(
    ScheduleTable table,
    ExportFormat format, {
    required String baseName,
    String? subject,
  }) async {
    final dir = await _directory();
    final file = File('${dir.path}/$baseName.${format.extension}');
    final bytes = switch (format) {
      ExportFormat.csv => utf8.encode(scheduleToCsv(table)),
      ExportFormat.xlsx => scheduleToXlsx(table),
    };
    await file.writeAsBytes(bytes, flush: true);
    await _sharer.shareFile(file, mimeType: format.mimeType, subject: subject);
    return file;
  }
}

@Riverpod(keepAlive: true)
FileSharer fileSharer(Ref ref) => SharePlusFileSharer();

@Riverpod(keepAlive: true)
PlanExporter planExporter(Ref ref) =>
    PlanExporter(ref.watch(fileSharerProvider), getTemporaryDirectory);
```

- [ ] **Step 4: The tabs and the screen**

`lib/features/analysis/presentation/plan_summary_tab.dart`:
```dart
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

class PlanSummaryTab extends ConsumerWidget {
  const PlanSummaryTab({required this.plan, super.key});

  final PayoffPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);
    final debtFreeDate = DateTime(now.year, now.month + plan.monthsToClear);
    final firstMonth = plan.months.first;

    Widget row(String label, Money value) => ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(formatMoney(value, locale)),
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                title: Text(
                  l10n.debtFreeBy(
                    DateFormat.yMMMM(locale).format(debtFreeDate),
                  ),
                  style: theme.textTheme.titleLarge,
                ),
                subtitle: Text(
                  l10n.debtFreeIn(formatDuration(l10n, plan.monthsToClear)),
                ),
              ),
              row(l10n.totalPaid, plan.totalPaid),
              row(l10n.totalInterest, plan.totalInterest),
              if (plan.totalFees.isPositive) row(l10n.fees, plan.totalFees),
            ],
          ),
        ),
        _Section(l10n.payThisMonth),
        Card(
          child: Column(
            children: [
              for (final (i, debt) in plan.debts.indexed)
                if (firstMonth.payments[i].isPositive)
                  row(planDebtName(l10n, debt), firstMonth.payments[i]),
            ],
          ),
        ),
        _Section(l10n.paymentPriority, hint: l10n.paymentPriorityHint),
        Card(
          child: Column(
            children: [
              for (final (i, debt) in plan.debts.indexed)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 12, child: Text('${i + 1}')),
                  title: Text(planDebtName(l10n, debt)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (hint != null)
          Text(hint!, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
```

`lib/features/analysis/presentation/plan_chart_tab.dart`:
```dart
import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Balances over time, stacked by debt: the top line is the total owed.
class PlanChartTab extends ConsumerWidget {
  const PlanChartTab({required this.plan, super.key});

  final PayoffPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final scheme = Theme.of(context).colorScheme;
    final colors = chartColors(scheme);
    final stacks = stackedBalances(plan);
    final currency = plan.totalPaid.currency;
    final compact = NumberFormat.compactSimpleCurrency(
      locale: locale,
      name: currency,
    );

    // Draw the tallest stack first so each lower band paints over it.
    final bars = [
      for (var i = plan.debts.length - 1; i >= 0; i--)
        LineChartBarData(
          spots: [
            for (final (month, totals) in stacks.indexed)
              FlSpot(month.toDouble(), totals[i]),
          ],
          color: colors[i % colors.length],
          barWidth: 1.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: colors[i % colors.length].withValues(alpha: 0.35),
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              l10n.chartTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                lineBarsData: bars,
                lineTouchData: const LineTouchData(enabled: false),
                gridData: const FlGridData(drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          compact.format(value),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: Text(l10n.scheduleMonth),
                    sideTitles: const SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final (i, debt) in plan.debts.indexed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      color: colors[i % colors.length],
                    ),
                    const SizedBox(width: 4),
                    Text(planDebtName(l10n, debt)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A distinguishable colour per debt, taken from the theme.
List<Color> chartColors(ColorScheme scheme) => [
  scheme.primary,
  scheme.tertiary,
  scheme.secondary,
  scheme.error,
  scheme.primaryFixedDim,
  scheme.tertiaryFixedDim,
  scheme.secondaryFixedDim,
];

/// For month 0 (starting balances) through the last month, the cumulative
/// balance in major units: element `i` is the sum of debts `0..i`.
List<List<double>> stackedBalances(PayoffPlan plan) {
  final digits = currencyDecimalDigits(plan.totalPaid.currency);
  var scale = 1;
  for (var i = 0; i < digits; i++) {
    scale *= 10;
  }
  List<double> cumulative(List<Money> balances) {
    var running = 0;
    return [for (final b in balances) (running += b.minor) / scale];
  }

  return [
    cumulative([for (final d in plan.debts) d.startingBalance]),
    for (final row in plan.months) cumulative(row.closingBalances),
  ];
}
```

`lib/features/analysis/presentation/plan_schedule_tab.dart`:
```dart
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The month-by-month schedule. Rows are built lazily: a plan can run to
/// 1,200 months.
class PlanScheduleTab extends ConsumerWidget {
  const PlanScheduleTab({required this.table, super.key});

  final ScheduleTable table;

  static const double _monthWidth = 64;
  static const double _amountWidth = 132;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(formatLocaleProvider);
    final theme = Theme.of(context);
    final width = _monthWidth + _amountWidth * (table.headers.length - 1) + 16;

    Widget cell(String text, double w, {TextStyle? style, bool end = true}) =>
        SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Text(
              text,
              style: style,
              textAlign: end ? TextAlign.end : TextAlign.start,
            ),
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            Material(
              color: theme.colorScheme.surfaceContainerHigh,
              child: Row(
                children: [
                  for (final (i, h) in table.headers.indexed)
                    cell(
                      h,
                      i == 0 ? _monthWidth : _amountWidth,
                      style: theme.textTheme.labelMedium,
                      end: i != 0,
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: table.rows.length,
                itemBuilder: (context, r) {
                  final row = table.rows[r];
                  return Row(
                    children: [
                      cell('${row.month}', _monthWidth, end: false),
                      for (final amount in row.amounts)
                        cell(formatMoney(amount, locale), _amountWidth),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Replace `lib/features/analysis/presentation/plan_detail_screen.dart` with:
```dart
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/features/analysis/data/plan_exporter.dart';
import 'package:debt_destroyer/features/analysis/domain/schedule_table.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_chart_tab.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_schedule_tab.dart';
import 'package:debt_destroyer/features/analysis/presentation/plan_summary_tab.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';

class PlanDetailScreen extends ConsumerWidget {
  const PlanDetailScreen({required this.strategyId, super.key});

  final StrategyId strategyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final title = Text(strategyName(l10n, strategyId));
    final result = ref.watch(planProvider(strategyId));
    return switch (result) {
      AsyncData(value: Feasible(:final plan)) when plan.monthsToClear > 0 =>
        _PlanTabs(title: title, plan: plan, strategyId: strategyId),
      AsyncData() || AsyncError() => Scaffold(
        appBar: AppBar(title: title),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.planUnavailable, textAlign: TextAlign.center),
          ),
        ),
      ),
      _ => Scaffold(
        appBar: AppBar(title: title),
        body: const Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _PlanTabs extends ConsumerWidget {
  const _PlanTabs({
    required this.title,
    required this.plan,
    required this.strategyId,
  });

  final Widget title;
  final PayoffPlan plan;
  final StrategyId strategyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final table = scheduleTableFor(l10n, plan);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: title,
          actions: [
            PopupMenuButton<ExportFormat>(
              icon: const Icon(Icons.share_outlined),
              tooltip: l10n.share,
              onSelected: (format) => runGuarded(
                context,
                () => ref
                    .read(planExporterProvider)
                    .export(
                      table,
                      format,
                      baseName: 'debt-plan-${strategyId.name}',
                      subject: strategyName(l10n, strategyId),
                    ),
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: ExportFormat.csv,
                  child: Text(l10n.exportCsv),
                ),
                PopupMenuItem(
                  value: ExportFormat.xlsx,
                  child: Text(l10n.exportXlsx),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.tabSummary),
              Tab(text: l10n.tabChart),
              Tab(text: l10n.tabSchedule),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            PlanSummaryTab(plan: plan),
            PlanChartTab(plan: plan),
            PlanScheduleTab(table: table),
          ],
        ),
      ),
    );
  }
}

/// The plan's schedule with translated column names.
ScheduleTable scheduleTableFor(AppLocalizations l10n, PayoffPlan plan) =>
    buildScheduleTable(
      plan,
      debtNames: [for (final d in plan.debts) planDebtName(l10n, d)],
      labels: ScheduleLabels(
        month: l10n.scheduleMonth,
        payment: l10n.schedulePayment,
        balance: l10n.scheduleBalance,
        totalPayment: l10n.scheduleTotalPayment,
        totalBalance: l10n.scheduleTotalBalance,
      ),
    );
```

- [ ] **Step 5: Generate code and run the tests**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+116: All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/analysis test/features/analysis
git commit -m "feat(analysis): plan summary, stacked chart, schedule and CSV/XLSX sharing"
```

---

### Task 8: Settings screen

**Files:**
- Create: `lib/core/currencies.dart`, `lib/features/settings/presentation/currency_picker.dart`
- Modify: `lib/features/settings/presentation/settings_screen.dart` (the real screen)
- Test: `test/features/settings/settings_screen_test.dart`

**Interfaces:**
- Produces:
  - `const List<String> kCurrencyCodes`, with `currencyChoices(String current)` and `currencyLabel(String code, String locale)` (for example `GBP (£)`)
  - `CurrencyPicker({required String value, required ValueChanged<String> onChanged})`

- [ ] **Step 1: Write the failing test**

`test/features/settings/settings_screen_test.dart`:
```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the current settings', (tester) async {
    await pumpApp(tester, location: Routes.settings);
    expect(find.text('GBP (£)'), findsOneWidget);
    expect(find.text('300'), findsOneWidget); // budget
    expect(find.text('5'), findsOneWidget); // consolidation APR
    expect(find.text('12'), findsOneWidget); // promo months
  });

  testWidgets('saves a new budget and strategy settings', (tester) async {
    final app = await pumpApp(tester, location: Routes.settings);
    await tester.enterText(field('Monthly budget'), '450.50');
    await tester.enterText(field('Interest-free months'), '18');
    await tester.enterText(field('Transfer fee (% of balance)'), '2.5');
    await save(tester);

    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.monthlyBudget, const Money(45050, 'GBP'));
    expect(settings.strategyParameters.promoMonths, 18);
    expect(settings.strategyParameters.transferFeeBps, 250);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('shows why a value was rejected', (tester) async {
    final app = await pumpApp(tester, location: Routes.settings);
    await tester.enterText(field('Monthly budget'), '0');
    await tester.enterText(field('Interest-free months'), '200');
    await save(tester);
    expect(find.text('Enter a budget above zero'), findsOneWidget);
    expect(find.text('Enter between 0 and 120 months'), findsOneWidget);
    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.monthlyBudget, const Money(30000, 'GBP'));
    expect(settings.strategyParameters.promoMonths, 12);
  });

  testWidgets('saving again without a fix keeps the message', (tester) async {
    await pumpApp(tester, location: Routes.settings);
    await tester.enterText(field('Monthly budget'), '0');
    await save(tester);
    await save(tester);
    expect(find.text('Enter a budget above zero'), findsOneWidget);
  });

  testWidgets('a corrected value saves on the next try', (tester) async {
    final app = await pumpApp(tester, location: Routes.settings);
    await tester.enterText(field('Monthly budget'), '0');
    await save(tester);
    expect(find.text('Enter a budget above zero'), findsOneWidget);

    await tester.enterText(field('Monthly budget'), '450');
    await save(tester);
    expect(find.text('Enter a budget above zero'), findsNothing);
    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.monthlyBudget, const Money(45000, 'GBP'));
  });

  testWidgets('switching currency keeps amounts at face value', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a', balance: 123456)],
      location: Routes.settings,
    );
    await tester.tap(find.text('GBP (£)'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('JPY (¥)'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('JPY (¥)').last);
    await tester.pumpAndSettle();

    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.currencyCode, 'JPY');
    expect(settings.monthlyBudget, const Money(300, 'JPY'));
    expect(find.text('300'), findsOneWidget);
    expect(app.repository.stored.single.balance.minor, 1235);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/settings/settings_screen_test.dart`
Expected: FAIL, because the placeholder has no fields.

- [ ] **Step 3: Implement**

`lib/core/currencies.dart`:
```dart
import 'package:intl/intl.dart';

/// Currencies offered in the pickers; the current one is always added.
const List<String> kCurrencyCodes = [
  'GBP', 'EUR', 'USD', 'CAD', 'AUD', 'NZD', 'CHF', 'SEK', 'NOK', 'DKK', //
  'PLN', 'CZK', 'HUF', 'JPY', 'CNY', 'INR', 'SGD', 'HKD', 'ZAR', 'BRL', //
  'MXN',
];

/// [kCurrencyCodes] plus [current] if it isn't already listed.
List<String> currencyChoices(String current) => [
  if (!kCurrencyCodes.contains(current)) current,
  ...kCurrencyCodes,
];

/// e.g. `GBP (£)`.
String currencyLabel(String code, String locale) {
  final symbol = NumberFormat.simpleCurrency(
    locale: locale,
    name: code,
  ).currencySymbol;
  return symbol == code ? code : '$code ($symbol)';
}
```

`lib/features/settings/presentation/currency_picker.dart`:
```dart
import 'package:debt_destroyer/core/currencies.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CurrencyPicker extends ConsumerWidget {
  const CurrencyPicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(formatLocaleProvider);
    return DropdownButtonFormField<String>(
      key: const ValueKey('currency'),
      initialValue: value,
      decoration: InputDecoration(
        labelText: context.l10n.settingsCurrency,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final code in currencyChoices(value))
          DropdownMenuItem(
            value: code,
            child: Text(currencyLabel(code, locale)),
          ),
      ],
      onChanged: (code) {
        if (code != null) onChanged(code);
      },
    );
  }
}
```

Replace `lib/features/settings/presentation/settings_screen.dart` with:
```dart
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:debt_destroyer/features/settings/presentation/currency_picker.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          // Rebuild the fields when the currency changes: amounts are rescaled.
          : _SettingsForm(
              key: ValueKey(settings.currencyCode),
              settings: settings,
            ),
    );
  }
}

enum _Field { budget, consolidationApr, promoMonths, transferFee, revertApr }

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings, super.key});

  final AppSettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<_Field, TextEditingController> _controllers;
  Map<_Field, String> _errors = const {};

  @override
  void initState() {
    super.initState();
    final locale = ref.read(formatLocaleProvider);
    final s = widget.settings;
    final p = s.strategyParameters;
    String percent(int bps) => formatPercentInput(bps, locale);
    _controllers = {
      _Field.budget: TextEditingController(
        text: formatAmountInput(s.monthlyBudget, locale),
      ),
      _Field.consolidationApr: TextEditingController(
        text: percent(p.consolidationAprBps),
      ),
      _Field.promoMonths: TextEditingController(text: '${p.promoMonths}'),
      _Field.transferFee: TextEditingController(
        text: percent(p.transferFeeBps),
      ),
      _Field.revertApr: TextEditingController(text: percent(p.revertAprBps)),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final code = widget.settings.currencyCode;
    final percentError = l10n.errorInvalidPercent(
      formatPercentInput(1990, locale),
    );
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);

    Widget field(
      _Field f,
      String label,
      String? Function(String) validate, {
      TextInputType keyboard = numberKeyboard,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey(f),
        controller: _controllers[f],
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (v) => validate(v ?? ''),
        forceErrorText: _errors[f],
        onChanged: (_) {
          if (_errors.containsKey(f)) {
            setState(() => _errors = {..._errors}..remove(f));
          }
        },
      ),
    );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CurrencyPicker(
              value: code,
              onChanged: (next) => runGuarded(
                context,
                () => ref
                    .read(settingsControllerProvider.notifier)
                    .setCurrency(next),
              ),
            ),
          ),
          field(
            _Field.budget,
            l10n.settingsBudget,
            (v) =>
                parseAmountMinor(v, currencyCode: code, locale: locale) == null
                ? l10n.errorInvalidAmount(
                    formatAmountInput(Money(30000, code), locale),
                  )
                : null,
          ),
          heading(l10n.settingsConsolidation),
          field(
            _Field.consolidationApr,
            l10n.settingsConsolidationApr,
            (v) => parsePercentBps(v, locale) == null ? percentError : null,
          ),
          heading(l10n.settingsTransfer),
          field(
            _Field.promoMonths,
            l10n.settingsPromoMonths,
            (v) => parseWholeNumber(v) == null ? l10n.errorWholeNumber : null,
            keyboard: TextInputType.number,
          ),
          field(
            _Field.transferFee,
            l10n.settingsTransferFee,
            (v) => parsePercentBps(v, locale) == null ? percentError : null,
          ),
          field(
            _Field.revertApr,
            l10n.settingsRevertApr,
            (v) => parsePercentBps(v, locale) == null ? percentError : null,
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: Text(l10n.save)),
        ],
      ),
    );
  }

  Future<void> _save() async {
    // A field rejected last time keeps its message until it is edited.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final locale = ref.read(formatLocaleProvider);
    String text(_Field f) => _controllers[f]!.text;
    final budgetMinor = parseAmountMinor(
      text(_Field.budget),
      currencyCode: widget.settings.currencyCode,
      locale: locale,
    )!;
    final parameters = StrategyParameters(
      consolidationAprBps: parsePercentBps(
        text(_Field.consolidationApr),
        locale,
      )!,
      promoMonths: parseWholeNumber(text(_Field.promoMonths))!,
      transferFeeBps: parsePercentBps(text(_Field.transferFee), locale)!,
      revertAprBps: parsePercentBps(text(_Field.revertApr), locale)!,
    );
    final controller = ref.read(settingsControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final result = await runGuarded(context, () async {
      final budgetErrors = await controller.setMonthlyBudget(budgetMinor);
      final parameterErrors = await controller.setStrategyParameters(
        parameters,
      );
      return (budgetErrors, parameterErrors);
    });
    if (result == null || !mounted) return;
    final (budgetErrors, parameterErrors) = result;
    final errors = <_Field, String>{
      if (budgetErrors.contains(BudgetValidationError.notPositive))
        _Field.budget: l10n.errorBudgetNotPositive,
      if (budgetErrors.contains(BudgetValidationError.tooLarge))
        _Field.budget: l10n.errorTooLarge,
      for (final e in parameterErrors)
        switch (e) {
          StrategyParametersValidationError.consolidationAprOutOfRange =>
            _Field.consolidationApr,
          StrategyParametersValidationError.transferFeeOutOfRange =>
            _Field.transferFee,
          StrategyParametersValidationError.promoMonthsOutOfRange =>
            _Field.promoMonths,
          StrategyParametersValidationError.revertAprOutOfRange =>
            _Field.revertApr,
        }: switch (e) {
          StrategyParametersValidationError.promoMonthsOutOfRange =>
            l10n.errorPromoMonthsRange(kMaxPromoMonths),
          _ => l10n.errorRateRange,
        },
    };
    setState(() => _errors = errors);
    if (errors.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSaved)));
    }
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, then `+122: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add lib/core/currencies.dart lib/features/settings test/features/settings
git commit -m "feat(settings): currency, budget and strategy settings screen"
```

---

### Task 9: Onboarding screen

**Files:**
- Modify: `lib/features/onboarding/presentation/onboarding_screen.dart` (the real screen)
- Delete: `lib/core/placeholder_screen.dart`, which nothing uses any more
- Test: `test/features/onboarding/onboarding_screen_test.dart`

- [ ] **Step 1: Write the failing test**

`test/features/onboarding/onboarding_screen_test.dart`:
```dart
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/pump_app.dart';

void main() {
  Future<AppHarness> open(WidgetTester tester) =>
      pumpApp(tester, settings: {SettingsKeys.onboardingComplete: false});

  Future<void> start(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
  }

  testWidgets('explains the app and suggests the defaults', (tester) async {
    await open(tester);
    expect(find.text('Welcome to Debt Destroyer'), findsOneWidget);
    expect(find.textContaining('highest interest rate'), findsOneWidget);
    expect(find.text('GBP (£)'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
  });

  testWidgets('saves the chosen currency and budget, then opens debts', (
    tester,
  ) async {
    final app = await open(tester);
    await tester.tap(find.text('GBP (£)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EUR (€)').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '450');
    await start(tester);

    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.currencyCode, 'EUR');
    expect(settings.monthlyBudget, const Money(45000, 'EUR'));
    expect(settings.onboardingComplete, isTrue);
    expect(find.text('Your debts'), findsOneWidget);
  });

  testWidgets('does not continue with an invalid budget', (tester) async {
    final app = await open(tester);
    await tester.enterText(find.byType(TextFormField), '0');
    await start(tester);
    expect(find.text('Enter a budget above zero'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'abc');
    await start(tester);
    expect(find.text('Enter an amount, e.g. 300'), findsOneWidget);
    final settings = app.container.read(settingsControllerProvider).value!;
    expect(settings.onboardingComplete, isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/onboarding`
Expected: FAIL, because the placeholder shows only "Welcome".

- [ ] **Step 3: Implement**

Replace `lib/features/onboarding/presentation/onboarding_screen.dart` with:
```dart
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/settings/presentation/currency_picker.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// First launch: what the app does, then currency and monthly budget. The
/// router leaves this screen once onboarding is complete.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _budget = TextEditingController();
  String? _currency;
  bool _prefilled = false;
  bool _saving = false;

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final settings = ref.watch(settingsControllerProvider).value;
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final currency = _currency ??= settings.currencyCode;
    if (!_prefilled) {
      _prefilled = true;
      _budget.text = formatAmountInput(settings.monthlyBudget, locale);
    }
    final theme = Theme.of(context);

    Widget point(IconData icon, String text) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(text),
    );

    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(l10n.onboardingTitle, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              point(Icons.compare_arrows, l10n.onboardingIntro1),
              point(Icons.trending_down, l10n.onboardingIntro2),
              point(Icons.flag_outlined, l10n.onboardingIntro3),
              const SizedBox(height: 24),
              CurrencyPicker(
                value: currency,
                onChanged: (code) => setState(() => _currency = code),
              ),
              const SizedBox(height: 16),
              Text(l10n.onboardingBudgetQuestion),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('budget'),
                controller: _budget,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.monthlyBudget,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => _budgetProblem(v ?? '', currency, locale),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _start,
                child: Text(l10n.onboardingStart),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _budgetProblem(String text, String currency, String locale) {
    final l10n = context.l10n;
    final minor = parseAmountMinor(
      text,
      currencyCode: currency,
      locale: locale,
    );
    if (minor == null) {
      return l10n.errorInvalidAmount(
        formatAmountInput(Money(30000, currency), locale),
      );
    }
    final errors = validateBudget(Money(minor, currency));
    if (errors.contains(BudgetValidationError.tooLarge)) {
      return l10n.errorTooLarge;
    }
    if (errors.contains(BudgetValidationError.notPositive)) {
      return l10n.errorBudgetNotPositive;
    }
    return null;
  }

  Future<void> _start() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final locale = ref.read(formatLocaleProvider);
    final currency = _currency!;
    final minor = parseAmountMinor(
      _budget.text,
      currencyCode: currency,
      locale: locale,
    )!;
    setState(() => _saving = true);
    final controller = ref.read(settingsControllerProvider.notifier);
    await runGuarded(context, () async {
      await controller.setCurrency(currency);
      await controller.setMonthlyBudget(minor);
      await controller.completeOnboarding();
    });
    if (mounted) setState(() => _saving = false);
  }
}
```
Then run `git rm lib/core/placeholder_screen.dart`.

- [ ] **Step 4: Run the tests**

Run: `dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`
Expected: `No issues found!`, format exits with 0, and `+125: All tests passed!`.

- [ ] **Step 5: Commit**

```bash
git add -A lib test
git commit -m "feat(onboarding): welcome, currency and budget before first use"
```

---

### Task 10: Builds and developer docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Build both platforms**

Run: `flutter build apk --debug && flutter build ios --simulator --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk` and `✓ Built build/ios/iphonesimulator/Runner.app`. This proves the fl_chart, share_plus and path_provider plugins compile.

- [ ] **Step 2: Update CLAUDE.md**

Make these edits:
- Replace the line starting ``- `./tool/codegen.sh` generates code for `payoff_engine` and then the app.`` with:
  ```markdown
  - `./tool/codegen.sh` generates code for `payoff_engine`, the app's translations (`flutter gen-l10n`) and then the app. Run it after a fresh checkout and after changing any freezed model, Riverpod provider or Drift table. Generated `*.g.dart`/`*.freezed.dart` files are not committed.
  ```
- After the Gotchas line about `select`/`selectAsync`, add:
  ```markdown
  - UI text lives in `lib/l10n/app_en.arb`, read through `context.l10n`. Money and percentages are formatted and parsed with `lib/core/money_format.dart`, using `formatLocaleProvider` (the device locale). Parsing is exact integer arithmetic; never convert money through `double` except for display.
  - Widget tests use `pumpApp` (`test/helpers/pump_app.dart`): the whole app with an `InMemoryDebtRepository` and a synchronous `planCalculatorProvider`. Drift's streams and `compute` isolates don't run under the widget test clock, so never use the real ones in widget tests. After `tester.ensureVisible`, call `pumpAndSettle` before tapping.
  - Errors found after Save are shown with `forceErrorText`. Clear a field's forced error in its `onChanged`, never at the start of Save: a stale forced error makes `validate()` fail silently.
  ```
- Tick `Plan 3` in the migration checklist.

- [ ] **Step 3: Full verification and commit**

Run: `dart analyze --fatal-infos && flutter test && (cd packages/payoff_engine && dart test)`
Expected: `No issues found!`, `+125: All tests passed!` and `+68: All tests passed!`.
```bash
git add CLAUDE.md
git commit -m "docs: Plan 3 commands and widget-test gotchas"
```
