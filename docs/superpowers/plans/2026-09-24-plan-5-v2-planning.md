# Debt Destroyer v2: Better Planning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the strategy comparison more useful and more honest:
- snowball, your own order, and a minimum-payments-only baseline
- per-debt promotional rates, more kinds of debt, fixed-payment loans
- a realistic balance transfer and consolidation
- a "pay £X more" slider and saved what-if scenarios

**Architecture:** `payoff_engine` is split into three pure stages:
- **restructure** turns the user's debts into the debts a strategy would really pay: identity, transfer or consolidation.
- **allocation order** decides who gets the extra money each month.
- **simulate** is one month loop driven only by debt properties.

The app gains:
- schema 2 in Drift: promo columns and a `scenarios` table
- a shared strategy-parameter form
- scenario providers, and a Strategies screen with a baseline line, a slider and a scenario picker

**Tech Stack:** Dart 3 / Flutter 3.47.2, freezed, Riverpod 3 with codegen, Drift 2.35 (`make-migrations`), go_router, intl/ARB.

**Spec:** `docs/superpowers/specs/2026-09-24-v2-planning-design.md`. Read it first. Where it and this plan disagree, the spec wins; stop and ask.

## Global Constraints

- Money is integer minor units (`Money`). Rates are integer basis points. Interest is `divideHalfEven(balance × apr, 120000)` once a month. Never use `double` for money except for display.
- `payoff_engine` has no Flutter imports. `calculate` is pure and never mutates its input.
- `DebtType` values are stored by name. Never rename an existing value (`creditCard`, `loan`, `personal`).
- Limits: `kMaxDebts = 50`, `kMaxAmountMinor = 100000000000`, `kMaxPromoMonths = 120`, `kMaxMonths = 1200`, consolidation term 6–120 months, arrangement fee 0–20% (2000 bps). Transfer card minimum payment: 3% (300 bps), with no floor.
- TDD is mandatory: failing test → minimal code → green → refactor. Every task ends with all of these green:
  - `dart analyze --fatal-infos`
  - `dart format --output=none --set-exit-if-changed lib test` (both in the app and in `packages/payoff_engine`)
  - `flutter test`
  - `(cd packages/payoff_engine && dart test)`
- After changing any freezed model, Riverpod provider or Drift table, run `./tool/codegen.sh` from the repo root. Generated `*.g.dart` and `*.freezed.dart` files are not committed.
- UI text goes in `lib/l10n/app_en.arb` and is read through `context.l10n`. Money and percentages use `lib/core/money_format.dart` with `formatLocaleProvider`.
- Widget tests use `pumpApp` (in-memory repositories, synchronous plan calculator). Never use Drift streams or `compute` in widget tests. After `tester.ensureVisible`, call `pumpAndSettle` before tapping.
- Riverpod 3 pauses providers that have no listener. In container tests, `container.listen(provider, (_, _) {})` before reading `.future`.
- Banners stay on Debts and Strategies only. The new Scenarios screens get no ads.
- Commit messages end with the two attribution lines given in the session instructions (`Co-Authored-By: …` and `Claude-Session: …`).

## Review Focus

These inputs are implied by the spec but no feature test would naturally hit them. Each has a test in the task named.

1. **Changing currency while the slider is non-zero.** The extra is in the old currency's minor units, so it must reset to 0, not become 100× larger in JPY. *(Task 10)*
2. **Lowering the budget in Settings below the slider's extra.** The extra must be capped at the budget, not carried over. *(Task 10)*
3. **Deleting the scenario that is currently selected.** Strategies falls back to Current, and the deleted id never reaches the calculator. *(Task 12)*
4. **A strategy that costs more than paying only the minimums** (for example a transfer fee on cheap debts). No "Saves -£…" line may appear. *(Task 9)*
5. **A promo that ends while the app is installed.** A debt saved with 1 month of promo left must read back with no promo the next month, not with 0 or −1 months (which the engine would reject). *(Task 7)*

## File map

Engine (`packages/payoff_engine/lib/src/`):
- `debt.dart`: `DebtType` (8 kinds), `Promo`, `Debt.promo`, `aprInMonth`
- `debt_kind.dart` (new): `isTransferable`, `isConsolidatable`, `defaultAllowsOverpayment`
- `debt_ordering.dart`: `compareHighestAprInMonth`, `compareSmallestBalanceFirst`
- `allocation_order.dart` (new): `AllocationOrder`, `allocationOrder(strategy, debts)`
- `restructure.dart` (new): `RestructureOutcome`, `Restructured`, `NotRestructurable`, `restructure`
- `fixed_loan_payment.dart` (new): `fixedLoanPayment`
- `simulate.dart` (new): the month loop
- `calculator.dart`: validation, empty-list plan, orchestration, `calculateAll`, `calculateBaseline`
- `strategy.dart`, `payoff_result.dart`, `validation.dart`, `minimum_payment.dart`: extended as described in each task

App (`lib/`):
- `core/labels.dart`: kinds, strategies, `NotApplicable` reasons
- `features/debts/domain/promo_dates.dart` (new): year-month ↔ months-left
- `features/debts/data/app_database.dart`: schema 2, `ScenarioRows`, migration
- `features/debts/data/drift_debt_repository.dart`: promo mapping; `convertAmounts` also rescales scenarios
- `features/debts/presentation/debt_form_screen.dart`: kind dropdown, loan payment, minimums only, promo
- `features/settings/presentation/parameter_fields.dart` (new): shared strategy-parameter fields
- `features/settings/…`: new keys, currency rescale of the credit limit, the screen uses the shared fields
- `features/strategies/domain/savings.dart`, `extra_payment.dart` (new)
- `features/strategies/presentation/plans_providers.dart`: `PlanSet`, baseline, `ExtraPayment`, active scenario
- `features/strategies/presentation/strategies_screen.dart`: baseline line, savings, slider, picker, save-as
- `features/scenarios/{domain,data,presentation}/` (new): model, repository, providers, Scenarios screen, editor, name dialog
- `features/analysis/…`: scenario name, "What changes", export notes

---

### Task 1: Debt kinds and promotional rates

**Files:**
- Modify: `packages/payoff_engine/lib/src/debt.dart`
- Create: `packages/payoff_engine/lib/src/debt_kind.dart`
- Modify: `packages/payoff_engine/lib/src/validation.dart`, `packages/payoff_engine/lib/src/calculator.dart` (only `_aprFor`), `packages/payoff_engine/lib/payoff_engine.dart`
- Test: `packages/payoff_engine/test/debt_kind_test.dart` (new), `packages/payoff_engine/test/promo_test.dart` (new), `packages/payoff_engine/test/helpers.dart`
- Modify (app): `lib/core/labels.dart`, `lib/l10n/app_en.arb`, `lib/features/debts/presentation/debts_screen.dart` (tile icon), `lib/features/debts/presentation/debt_form_screen.dart` (type dropdown, default, error cases)
- Test (app): `test/helpers/debts.dart`, `test/features/debts/debt_form_test.dart`

**Interfaces:**
- Produces:
  - `enum DebtType { creditCard, storeCard, loan, overdraft, studentLoan, mortgage, personal, other }`
  - `Promo({required int aprBps, required int months})`
  - `Debt.promo: Promo?`
  - `int aprInMonth(Debt debt, int month)`
  - `bool isTransferable(DebtType)`, `bool isConsolidatable(DebtType)`, `bool defaultAllowsOverpayment(DebtType)`
  - `DebtValidationError.promoAprOutOfRange`, `DebtValidationError.promoMonthsOutOfRange`

- [ ] **Step 1: Write the failing engine tests**

In `packages/payoff_engine/test/helpers.dart`, add a `promo` parameter to `debt()`:

```dart
Debt debt({
  required String id,
  required int balance,
  String? name,
  DebtType type = DebtType.creditCard,
  int aprBps = 0,
  int minPaymentPercentBps = 0,
  int minPaymentFloor = 0,
  bool allowsOverpayment = true,
  Promo? promo,
}) => Debt(
  id: id,
  name: name ?? id,
  type: type,
  balance: gbp(balance),
  aprBps: aprBps,
  minPaymentPercentBps: minPaymentPercentBps,
  minPaymentFloor: gbp(minPaymentFloor),
  allowsOverpayment: allowsOverpayment,
  promo: promo,
);
```

Create `packages/payoff_engine/test/debt_kind_test.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

void main() {
  test('only card balances can move to a transfer card', () {
    expect(
      {for (final t in DebtType.values) if (isTransferable(t)) t},
      {DebtType.creditCard, DebtType.storeCard},
    );
  });

  test('cards, store cards, loans and overdrafts can be consolidated', () {
    expect(
      {for (final t in DebtType.values) if (isConsolidatable(t)) t},
      {
        DebtType.creditCard,
        DebtType.storeCard,
        DebtType.loan,
        DebtType.overdraft,
      },
    );
  });

  test('student loans and mortgages default to minimums only', () {
    expect(
      {for (final t in DebtType.values) if (!defaultAllowsOverpayment(t)) t},
      {DebtType.studentLoan, DebtType.mortgage},
    );
  });

  test('v1 kinds keep their stored names', () {
    expect(DebtType.creditCard.name, 'creditCard');
    expect(DebtType.loan.name, 'loan');
    expect(DebtType.personal.name, 'personal');
  });
}
```

Create `packages/payoff_engine/test/promo_test.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('aprInMonth', () {
    final card = debt(
      id: 'a',
      balance: 100,
      aprBps: 1990,
      promo: const Promo(aprBps: 0, months: 2),
    );

    test('charges the promo rate for its months, then the normal rate', () {
      expect(aprInMonth(card, 1), 0);
      expect(aprInMonth(card, 2), 0);
      expect(aprInMonth(card, 3), 1990);
    });

    test('a debt without a promo always charges its APR', () {
      expect(aprInMonth(debt(id: 'b', balance: 100, aprBps: 500), 1), 500);
    });
  });

  group('validateDebt with a promo', () {
    Set<DebtValidationError> errors(Promo promo) => validateDebt(
      debt(id: 'a', balance: 100, aprBps: 1990, promo: promo),
    );

    test('accepts a promo of 1 to kMaxPromoMonths months at 0-100%', () {
      expect(errors(const Promo(aprBps: 0, months: 1)), isEmpty);
      expect(
        errors(const Promo(aprBps: 10000, months: kMaxPromoMonths)),
        isEmpty,
      );
    });

    test('rejects a rate outside 0-100%', () {
      expect(errors(const Promo(aprBps: 10001, months: 3)), {
        DebtValidationError.promoAprOutOfRange,
      });
      expect(errors(const Promo(aprBps: -1, months: 3)), {
        DebtValidationError.promoAprOutOfRange,
      });
    });

    test('rejects an ended or over-long promo', () {
      expect(errors(const Promo(aprBps: 0, months: 0)), {
        DebtValidationError.promoMonthsOutOfRange,
      });
      expect(errors(const Promo(aprBps: 0, months: kMaxPromoMonths + 1)), {
        DebtValidationError.promoMonthsOutOfRange,
      });
    });
  });

  test('the calculator charges the promo rate, then the normal APR', () {
    // 1,200.00 at 12% with 0% for two months, paying 100.00 a month.
    final plan = planOf(
      calculate(
        debts: [
          debt(
            id: 'a',
            balance: 120000,
            aprBps: 1200,
            promo: const Promo(aprBps: 0, months: 2),
          ),
        ],
        monthlyBudget: gbp(10000),
        strategy: const Strategy.avalanche(),
      ),
    );
    // Months 1-2 are free; month 3 charges 1% of 1,000.00; month 4 1% of 910.00.
    expect([for (final r in plan.months.take(4)) r.interest.single], [
      gbp(0),
      gbp(0),
      gbp(1000),
      gbp(910),
    ]);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd packages/payoff_engine && dart test test/debt_kind_test.dart test/promo_test.dart`
Expected: compilation errors: `Promo`, `promo`, `aprInMonth`, `isTransferable` and `DebtType.storeCard` are not defined.

- [ ] **Step 3: Implement the engine changes**

Replace `packages/payoff_engine/lib/src/debt.dart` with:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/src/money.dart';

part 'debt.freezed.dart';

/// Stored by name in the app's database: renaming a value breaks existing
/// rows unless a migration renames them too. Declaration order is the order
/// the debt form lists them in.
enum DebtType {
  creditCard,
  storeCard,
  loan,
  overdraft,
  studentLoan,
  mortgage,
  personal,
  other,
}

/// A lower rate for the first [months] months of a plan.
@freezed
abstract class Promo with _$Promo {
  const factory Promo({
    /// Rate during the promotion, in basis points (usually 0).
    required int aprBps,

    /// Months the promotion still applies, counting a plan's first month as
    /// month 1.
    required int months,
  }) = _Promo;
}

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

    /// A promotional rate charged instead of [aprBps] while it lasts.
    Promo? promo,
  }) = _Debt;
}

/// The rate charged on [debt] in [month] (1-based): the promotional rate
/// while it lasts, then [Debt.aprBps].
int aprInMonth(Debt debt, int month) => switch (debt.promo) {
  Promo(:final aprBps, :final months) when month <= months => aprBps,
  _ => debt.aprBps,
};
```

Create `packages/payoff_engine/lib/src/debt_kind.dart`:

```dart
import 'package:payoff_engine/src/debt.dart';

/// Whether a balance of this kind can move to a balance-transfer card.
bool isTransferable(DebtType type) => switch (type) {
  DebtType.creditCard || DebtType.storeCard => true,
  DebtType.loan ||
  DebtType.overdraft ||
  DebtType.studentLoan ||
  DebtType.mortgage ||
  DebtType.personal ||
  DebtType.other => false,
};

/// Whether a consolidation loan can replace a debt of this kind.
bool isConsolidatable(DebtType type) => switch (type) {
  DebtType.creditCard ||
  DebtType.storeCard ||
  DebtType.loan ||
  DebtType.overdraft => true,
  DebtType.studentLoan ||
  DebtType.mortgage ||
  DebtType.personal ||
  DebtType.other => false,
};

/// Whether a new debt of this kind should take extra payments. Student loans
/// are income-contingent and written off; mortgages are usually the cheapest
/// debt. Overpaying either rarely helps.
bool defaultAllowsOverpayment(DebtType type) => switch (type) {
  DebtType.studentLoan || DebtType.mortgage => false,
  DebtType.creditCard ||
  DebtType.storeCard ||
  DebtType.loan ||
  DebtType.overdraft ||
  DebtType.personal ||
  DebtType.other => true,
};
```

Export it from `packages/payoff_engine/lib/payoff_engine.dart` (keep the list alphabetical):

```dart
export 'src/debt_kind.dart';
```

In `packages/payoff_engine/lib/src/validation.dart`, append two values to `DebtValidationError`:

```dart
  floorCurrencyMismatch,
  promoAprOutOfRange,
  promoMonthsOutOfRange,
}
```

and add these two entries at the end of the set in `validateDebt`:

```dart
  if (debt.promo case final promo? when !_isRate(promo.aprBps))
    DebtValidationError.promoAprOutOfRange,
  if (debt.promo case final promo?
      when promo.months < 1 || promo.months > kMaxPromoMonths)
    DebtValidationError.promoMonthsOutOfRange,
```

In `packages/payoff_engine/lib/src/calculator.dart`, change the fallback branch of `_aprFor` so ordinary debts respect their promo:

```dart
int _aprFor(Strategy strategy, Debt debt, int month) => switch (strategy) {
  BalanceTransfer(:final promoMonths, :final revertAprBps) =>
    month <= promoMonths ? 0 : revertAprBps,
  _ => aprInMonth(debt, month),
};
```

- [ ] **Step 4: Generate code and run the engine tests**

Run: `cd packages/payoff_engine && dart run build_runner build -d && dart test`
Expected: `All tests passed!` (the 68 v1 tests plus the new ones).

- [ ] **Step 5: Write the failing app test**

In `test/helpers/debts.dart`, add `Promo? promo` to `testDebt` and pass it through (`promo: promo,`).

In `test/features/debts/debt_form_test.dart`:
- Add this helper at the top of `main`.
- Replace the test `'choosing Loan for a new debt turns off overpaying'` with the two tests below.

```dart
  Future<void> chooseType(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }
```

```dart
  testWidgets('offers every kind of debt', (tester) async {
    await pumpApp(tester, location: Routes.newDebt);
    await tester.tap(find.byKey(const ValueKey('type')));
    await tester.pumpAndSettle();
    for (final label in [
      'Credit card',
      'Store card or buy now, pay later',
      'Loan',
      'Overdraft',
      'Student loan',
      'Mortgage',
      'Friends & family',
      'Other',
    ]) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('choosing Student loan for a new debt turns off overpaying', (
    tester,
  ) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await chooseType(tester, 'Student loan');
    await fill(tester);
    await save(tester);
    expect(app.repository.stored.single.type, DebtType.studentLoan);
    expect(app.repository.stored.single.allowsOverpayment, isFalse);
  });
```

- [ ] **Step 6: Run the app tests to verify they fail**

Run: `./tool/codegen.sh && flutter test test/features/debts/debt_form_test.dart`
Expected: compilation errors. `labels.dart` and `debts_screen.dart` have non-exhaustive `switch`es over `DebtType`, and `debt_form_screen.dart` has one over `DebtValidationError`.

- [ ] **Step 7: Implement the app changes**

Add to `lib/l10n/app_en.arb` (after `debtTypePersonal`):

```json
  "debtTypeStoreCard": "Store card or buy now, pay later",
  "debtTypeOverdraft": "Overdraft",
  "debtTypeStudentLoan": "Student loan",
  "debtTypeMortgage": "Mortgage",
  "debtTypeOther": "Other",
  "fieldType": "Type",
```

Replace `debtTypeLabel` in `lib/core/labels.dart`:

```dart
String debtTypeLabel(AppLocalizations l10n, DebtType type) => switch (type) {
  DebtType.creditCard => l10n.debtTypeCreditCard,
  DebtType.storeCard => l10n.debtTypeStoreCard,
  DebtType.loan => l10n.debtTypeLoan,
  DebtType.overdraft => l10n.debtTypeOverdraft,
  DebtType.studentLoan => l10n.debtTypeStudentLoan,
  DebtType.mortgage => l10n.debtTypeMortgage,
  DebtType.personal => l10n.debtTypePersonal,
  DebtType.other => l10n.debtTypeOther,
};
```

In `DebtTile` (`lib/features/debts/presentation/debts_screen.dart`), replace the icon switch:

```dart
      leading: Icon(switch (debt.type) {
        DebtType.creditCard => Icons.credit_card,
        DebtType.storeCard => Icons.shopping_bag_outlined,
        DebtType.loan => Icons.account_balance_outlined,
        DebtType.overdraft => Icons.account_balance_wallet_outlined,
        DebtType.studentLoan => Icons.school_outlined,
        DebtType.mortgage => Icons.home_outlined,
        DebtType.personal => Icons.people_outline,
        DebtType.other => Icons.receipt_long_outlined,
      }, semanticLabel: debtTypeLabel(l10n, debt.type)),
```

In `lib/features/debts/presentation/debt_form_screen.dart`:
- In `initState`, set `_allowsOverpayment = d?.allowsOverpayment ?? defaultAllowsOverpayment(_type);` after `_type` is assigned.
- Replace the `SegmentedButton<DebtType>` padding block. Eight kinds don't fit in a segmented button.

```dart
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<DebtType>(
              key: const ValueKey('type'),
              initialValue: _type,
              decoration: InputDecoration(
                labelText: l10n.fieldType,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final t in DebtType.values)
                  DropdownMenuItem(
                    value: t,
                    child: Text(debtTypeLabel(l10n, t)),
                  ),
              ],
              onChanged: (t) => setState(() {
                _type = t!;
                // Suggest the usual choice for new debts only, never
                // overriding a saved one.
                if (widget.existing == null) {
                  _allowsOverpayment = defaultAllowsOverpayment(_type);
                }
              }),
            ),
          ),
```

In `_showErrors`, add the new cases before `floorCurrencyMismatch`. Task 8 gives them a field:

```dart
        case DebtValidationError.promoAprOutOfRange:
        case DebtValidationError.promoMonthsOutOfRange:
          break; // the form has no promo fields until Task 8
```

- [ ] **Step 8: Run all checks**

Run: `dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test && (cd packages/payoff_engine && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && dart test)`
Expected: `No issues found!` and `All tests passed!` everywhere.

- [ ] **Step 9: Commit**

```bash
git add packages/payoff_engine lib test
git commit -m "feat(engine): more kinds of debt and per-debt promotional rates"
```

---

### Task 2: Split the calculator into restructure and simulate (no behaviour change)

**Files:**
- Create: `packages/payoff_engine/lib/src/restructure.dart`, `packages/payoff_engine/lib/src/simulate.dart`
- Modify: `packages/payoff_engine/lib/src/calculator.dart`, `packages/payoff_engine/lib/src/minimum_payment.dart`, `packages/payoff_engine/lib/payoff_engine.dart`
- Test: `packages/payoff_engine/test/restructure_test.dart` (new), `packages/payoff_engine/test/simulate_test.dart` (new)

**Interfaces:**
- Consumes: `aprInMonth`, `Promo` (Task 1).
- Produces:
  - `class Restructured { List<Debt> debts; Money fees; }`
  - `Restructured restructure(List<Debt> debts, Strategy strategy, {required Money budget})`, which needs a non-empty `debts`
  - `PayoffResult simulate({required StrategyId strategyId, required List<Debt> debts, required Money budget, required Money fees})`
  - `int minimumPaymentMinor(Debt debt, int balanceMinor)`

This task is a pure refactor. Every existing engine test must pass **unchanged**.

- [ ] **Step 1: Write the failing tests**

Create `packages/payoff_engine/test/restructure_test.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final low = debt(id: 'low', balance: 1000, aprBps: 500);
  final high = debt(id: 'high', balance: 2000, aprBps: 2000);

  test('avalanche puts the highest APR first and adds no fees', () {
    final r = restructure([
      low,
      high,
    ], const Strategy.avalanche(), budget: gbp(500));
    expect(r.debts, [high, low]);
    expect(r.fees, gbp(0));
  });

  test('balance transfer is a card with a 0% promo, then the revert APR', () {
    final r = restructure(
      [low, high],
      const Strategy.balanceTransfer(
        feeBps: 400,
        promoMonths: 12,
        revertAprBps: 1500,
      ),
      budget: gbp(500),
    );
    final card = r.debts.single;
    expect(card.id, kBalanceTransferDebtId);
    expect(card.balance, gbp(3120)); // 3,000 + 4%
    expect(card.aprBps, 1500);
    expect(card.promo, const Promo(aprBps: 0, months: 12));
    expect(r.fees, gbp(120));
  });

  test('a transfer with no promo months has no promo', () {
    final r = restructure(
      [low],
      const Strategy.balanceTransfer(
        feeBps: 0,
        promoMonths: 0,
        revertAprBps: 1500,
      ),
      budget: gbp(500),
    );
    expect(r.debts.single.promo, isNull);
  });

  test('does not modify its input', () {
    final input = [low, high];
    restructure(input, const Strategy.avalanche(), budget: gbp(500));
    expect(input, [low, high]);
  });
}
```

Create `packages/payoff_engine/test/simulate_test.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('spends extra money in list order', () {
    final plan = planOf(
      simulate(
        strategyId: StrategyId.avalanche,
        debts: [
          debt(id: 'first', balance: 50000, aprBps: 500),
          debt(id: 'second', balance: 50000, aprBps: 2000),
        ],
        budget: gbp(10000),
        fees: gbp(0),
      ),
    );
    expect(plan.months.first.payments, [gbp(10000), gbp(0)]);
  });

  test('reports the fees it is given', () {
    final plan = planOf(
      simulate(
        strategyId: StrategyId.balanceTransfer,
        debts: [debt(id: 'a', balance: 1040)],
        budget: gbp(1040),
        fees: gbp(40),
      ),
    );
    expect(plan.totalFees, gbp(40));
    expect(plan.totalPaid, gbp(1040));
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd packages/payoff_engine && dart test test/restructure_test.dart test/simulate_test.dart`
Expected: compilation errors: `restructure` and `simulate` are not defined.

- [ ] **Step 3: Implement**

In `packages/payoff_engine/lib/src/minimum_payment.dart`, extract the rule so the loop can reuse it:

```dart
/// The payment [debt] requires this month at its current balance: the larger
/// of its floor and its percentage, but never more than the balance. The
/// calculator applies the same rule after adding each month's interest.
Money minimumPayment(Debt debt) => Money(
  minimumPaymentMinor(debt, debt.balance.minor),
  debt.balance.currency,
);

/// [minimumPayment] for [debt] at a balance of [balanceMinor].
int minimumPaymentMinor(Debt debt, int balanceMinor) {
  if (balanceMinor <= 0) return 0;
  final byPercent = divideHalfEven(
    balanceMinor * debt.minPaymentPercentBps,
    10000,
  );
  final floor = debt.minPaymentFloor.minor;
  final minimum = byPercent > floor ? byPercent : floor;
  return minimum < balanceMinor ? minimum : balanceMinor;
}
```

Create `packages/payoff_engine/lib/src/restructure.dart`:

```dart
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/debt_ordering.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/rounding.dart';
import 'package:payoff_engine/src/strategy.dart';

const String kConsolidationDebtId = 'consolidation';
const String kBalanceTransferDebtId = 'balance-transfer';

/// The debts a strategy would actually be paying.
final class Restructured {
  const Restructured({required this.debts, required this.fees});

  /// In the order extra money is allocated.
  final List<Debt> debts;

  /// One-off fees added to [debts]' balances, e.g. a transfer fee.
  final Money fees;
}

/// Turns the user's [debts] (not empty) into the debts [strategy] pays.
/// Pure: [debts] is not modified.
Restructured restructure(
  List<Debt> debts,
  Strategy strategy, {
  required Money budget,
}) {
  final currency = debts.first.balance.currency;
  final zero = Money.zero(currency);
  final total = debts.fold(zero, (sum, d) => sum + d.balance);
  return switch (strategy) {
    Avalanche() || Boosted() => Restructured(
      debts: [...debts]..sort(compareHighestAprFirst),
      fees: zero,
    ),
    LowestAprFirst() => Restructured(
      debts: [...debts]..sort(compareLowestAprFirst),
      fees: zero,
    ),
    Consolidation(:final aprBps) => Restructured(
      debts: [
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
      fees: zero,
    ),
    BalanceTransfer(:final feeBps, :final promoMonths, :final revertAprBps) =>
      () {
        final fee = Money(divideHalfEven(total.minor * feeBps, 10000), currency);
        return Restructured(
          debts: [
            Debt(
              id: kBalanceTransferDebtId,
              name: 'Balance transfer card',
              type: DebtType.creditCard,
              balance: total + fee,
              aprBps: revertAprBps,
              minPaymentPercentBps: 0,
              minPaymentFloor: budget,
              allowsOverpayment: false,
              promo: promoMonths > 0
                  ? Promo(aprBps: 0, months: promoMonths)
                  : null,
            ),
          ],
          fees: fee,
        );
      }(),
  };
}
```

Create `packages/payoff_engine/lib/src/simulate.dart`:

```dart
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/minimum_payment.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/rounding.dart';
import 'package:payoff_engine/src/strategy.dart';

/// A balance above this (in minor units) means the debt is growing without
/// bound; it also keeps `balance * aprBps` well inside 64-bit integers.
const int kBalanceCeilingMinor = 10000000000000;

/// Pays off [debts] (not empty) month by month with [budget]. Each month:
/// add interest at each debt's rate for that month, pay every minimum, then
/// spend what is left on overpayable debts in list order. [fees] are
/// reported as the plan's fees; they are already in the balances.
PayoffResult simulate({
  required StrategyId strategyId,
  required List<Debt> debts,
  required Money budget,
  required Money fees,
}) {
  final currency = budget.currency;
  final n = debts.length;
  final balances = [for (final d in debts) d.balance.minor];
  final rows = <MonthRow>[];
  var month = 0;
  while (balances.any((b) => b > 0)) {
    if (month == kMaxMonths) {
      return PayoffResult.neverClears(strategyId: strategyId);
    }
    month++;

    final interest = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      if (balances[i] <= 0) continue;
      interest[i] = divideHalfEven(
        balances[i] * aprInMonth(debts[i], month),
        120000,
      );
      balances[i] += interest[i];
      if (balances[i] > kBalanceCeilingMinor) {
        return PayoffResult.neverClears(strategyId: strategyId);
      }
    }

    final payments = [
      for (var i = 0; i < n; i++) minimumPaymentMinor(debts[i], balances[i]),
    ];
    final minimumsTotal = payments.fold(0, (a, b) => a + b);
    if (minimumsTotal > budget.minor) {
      return PayoffResult.infeasible(
        strategyId: strategyId,
        shortfall: Money(minimumsTotal - budget.minor, currency),
        month: month,
      );
    }

    var remaining = budget.minor - minimumsTotal;
    for (var i = 0; i < n; i++) {
      balances[i] -= payments[i];
      if (remaining > 0 && debts[i].allowsOverpayment && balances[i] > 0) {
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

  final zero = Money.zero(currency);
  Money sum(List<Money> Function(MonthRow) column) =>
      rows.fold(zero, (total, row) => column(row).fold(total, (t, m) => t + m));

  return PayoffResult.feasible(
    strategyId: strategyId,
    plan: PayoffPlan(
      debts: [
        for (final d in debts)
          PlanDebt(id: d.id, name: d.name, startingBalance: d.balance),
      ],
      months: rows,
      totalPaid: sum((r) => r.payments),
      totalInterest: sum((r) => r.interest),
      totalFees: fees,
    ),
  );
}
```

Replace the body of `packages/payoff_engine/lib/src/calculator.dart`. Keep the imports it still needs. The constants `kConsolidationDebtId`, `kBalanceTransferDebtId` and `kBalanceCeilingMinor` move to `restructure.dart` and `simulate.dart`.

```dart
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/restructure.dart';
import 'package:payoff_engine/src/rounding.dart';
import 'package:payoff_engine/src/simulate.dart';
import 'package:payoff_engine/src/strategy.dart';
import 'package:payoff_engine/src/validation.dart';

/// Simulates paying off [debts] with [monthlyBudget] using [strategy].
/// Pure: [debts] is not modified.
///
/// Throws [ArgumentError] if any debt fails [validateDebt], the list fails
/// [validateDebtList], or [monthlyBudget] is negative.
PayoffResult calculate({
  required List<Debt> debts,
  required Money monthlyBudget,
  required Strategy strategy,
}) {
  if (monthlyBudget.isNegative) {
    throw ArgumentError.value(monthlyBudget, 'monthlyBudget', 'is negative');
  }
  if (validateDebtList(debts).isNotEmpty ||
      debts.any((d) => validateDebt(d).isNotEmpty)) {
    throw ArgumentError.value(debts, 'debts', 'contains invalid debts');
  }
  final currency = monthlyBudget.currency;
  if (debts.any((d) => d.balance.currency != currency)) {
    throw ArgumentError.value(debts, 'debts', 'not in the budget currency');
  }
  final zero = Money.zero(currency);
  if (debts.isEmpty) {
    return PayoffResult.feasible(
      strategyId: strategy.id,
      plan: PayoffPlan(
        debts: const [],
        months: const [],
        totalPaid: zero,
        totalInterest: zero,
        totalFees: zero,
      ),
    );
  }

  final budget = switch (strategy) {
    Boosted(:final budgetPercent) => Money(
      divideHalfEven(monthlyBudget.minor * budgetPercent, 100),
      currency,
    ),
    _ => monthlyBudget,
  };
  final restructured = restructure(debts, strategy, budget: budget);
  return simulate(
    strategyId: strategy.id,
    debts: restructured.debts,
    budget: budget,
    fees: restructured.fees,
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
```

Export the new files from `packages/payoff_engine/lib/payoff_engine.dart`:

```dart
export 'src/restructure.dart';
export 'src/simulate.dart';
```

- [ ] **Step 4: Run every engine test**

Run: `cd packages/payoff_engine && dart test`
Expected: `All tests passed!`, with every v1 test unchanged. If a legacy figure moves by even a penny, the refactor changed behaviour. Fix it; don't edit the test.

- [ ] **Step 5: Run the app suite (it imports `kBalanceTransferDebtId` via the package export)**

Run: `dart analyze --fatal-infos && flutter test`
Expected: `No issues found!`, `All tests passed!`.

- [ ] **Step 6: Commit**

```bash
git add packages/payoff_engine
git commit -m "refactor(engine): split the calculator into restructure and simulate"
```

---

### Task 3: Strategy lineup, monthly re-ranking and payoff order

**Files:**
- Modify: `packages/payoff_engine/lib/src/strategy.dart`, `debt_ordering.dart`, `restructure.dart`, `simulate.dart`, `calculator.dart`, `packages/payoff_engine/lib/payoff_engine.dart`
- Create: `packages/payoff_engine/lib/src/allocation_order.dart`
- Test: `packages/payoff_engine/test/allocation_order_test.dart` (new), `debt_ordering_test.dart`, `strategy_test.dart`, `simulate_test.dart`, `calculator_test.dart`, `calculator_synthetic_test.dart`, `legacy_scenarios_test.dart`, `invariants_test.dart`
- Modify (app): `lib/core/labels.dart`, `lib/l10n/app_en.arb`, `lib/features/analysis/presentation/plan_summary_tab.dart`
- Test (app): `test/features/strategies/strategies_screen_test.dart`, `test/features/strategies/rank_results_test.dart`, `test/features/strategies/plans_providers_test.dart`, `test/features/analysis/plan_detail_test.dart`

**Interfaces:**
- Consumes: `aprInMonth` (Task 1); `restructure` and `simulate` (Task 2).
- Produces:
  - `enum StrategyId { avalanche, snowball, customOrder, consolidation, balanceTransfer, minimumsOnly }`
  - `Strategy.snowball()`, `Strategy.customOrder()`, `Strategy.minimumsOnly()` (classes `Snowball`, `CustomOrder`, `MinimumsOnly`)
  - `standardStrategies(p)` gives `[avalanche, snowball, customOrder, consolidation, balanceTransfer]`
  - `typedef AllocationOrder = List<int> Function(int month)` and `AllocationOrder allocationOrder(Strategy strategy, List<Debt> debts)`
  - `int compareHighestAprInMonth(Debt a, Debt b, int month)`, `int compareSmallestBalanceFirst(Debt a, Debt b)`
  - `simulate(…, required AllocationOrder order, bool allowExtra = true)`
  - `PayoffPlan.debts` is in **clearing order**
  - `PayoffResult calculateBaseline({required List<Debt> debts, required Money monthlyBudget})`

- [ ] **Step 1: Write the failing engine tests**

Replace `packages/payoff_engine/test/debt_ordering_test.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // Legacy bug: `(int) (a - b) * 100` made APRs < 1% apart compare equal.
  final low = debt(id: 'a', name: 'Alpha', balance: 100, aprBps: 1800);
  final high = debt(id: 'b', name: 'Beta', balance: 100, aprBps: 1850);

  test('highest-first separates APRs less than 1% apart', () {
    expect(
      [low, high]..sort((a, b) => compareHighestAprInMonth(a, b, 1)),
      [high, low],
    );
  });

  test('highest-first uses the rate charged in that month', () {
    final promo = debt(
      id: 'p',
      balance: 100,
      aprBps: 3000,
      promo: const Promo(aprBps: 0, months: 2),
    );
    int Function(Debt, Debt) inMonth(int m) =>
        (a, b) => compareHighestAprInMonth(a, b, m);
    expect([promo, low]..sort(inMonth(2)), [low, promo]);
    expect([promo, low]..sort(inMonth(3)), [promo, low]);
  });

  test('smallest balance first', () {
    final big = debt(id: 'big', balance: 500);
    final small = debt(id: 'small', balance: 300);
    expect([big, small]..sort(compareSmallestBalanceFirst), [small, big]);
  });

  test('ties break by name, then id', () {
    final b = debt(id: '2', name: 'Bravo', balance: 100, aprBps: 1000);
    final a1 = debt(id: '1', name: 'Alpha', balance: 100, aprBps: 1000);
    final a0 = debt(id: '0', name: 'Alpha', balance: 100, aprBps: 1000);
    expect(
      [b, a1, a0]..sort((x, y) => compareHighestAprInMonth(x, y, 1)),
      [a0, a1, b],
    );
    expect([b, a1, a0]..sort(compareSmallestBalanceFirst), [a0, a1, b]);
  });
}
```

Create `packages/payoff_engine/test/allocation_order_test.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final promo = debt(
    id: 'promo',
    balance: 100000,
    aprBps: 3000,
    promo: const Promo(aprBps: 0, months: 2),
  );
  final plain = debt(id: 'plain', balance: 30000, aprBps: 1000);

  test('avalanche re-ranks when a promo ends', () {
    final order = allocationOrder(const Strategy.avalanche(), [promo, plain]);
    expect(order(1), [1, 0]);
    expect(order(2), [1, 0]);
    expect(order(3), [0, 1]);
  });

  test('snowball ranks by starting balance and never re-ranks', () {
    final order = allocationOrder(const Strategy.snowball(), [promo, plain]);
    expect(order(1), [1, 0]);
    expect(order(30), [1, 0]);
  });

  test('custom order keeps the list order', () {
    final order = allocationOrder(const Strategy.customOrder(), [
      plain,
      promo,
    ]);
    expect(order(1), [0, 1]);
    expect(order(3), [0, 1]);
  });
}
```

Replace `packages/payoff_engine/test/strategy_test.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

void main() {
  test('each strategy reports its id', () {
    expect(const Strategy.avalanche().id, StrategyId.avalanche);
    expect(const Strategy.snowball().id, StrategyId.snowball);
    expect(const Strategy.customOrder().id, StrategyId.customOrder);
    expect(const Strategy.minimumsOnly().id, StrategyId.minimumsOnly);
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

  test('standardStrategies lists the five ranked strategies in order', () {
    final ids = standardStrategies(const StrategyParameters()).map((s) => s.id);
    expect(ids, [
      StrategyId.avalanche,
      StrategyId.snowball,
      StrategyId.customOrder,
      StrategyId.consolidation,
      StrategyId.balanceTransfer,
    ]);
  });
}
```

In `packages/payoff_engine/test/simulate_test.dart`:
- Add `order: (_) => [0, 1],` to the first test's `simulate` call.
- Add `order: (_) => [0],` to the second.
- Append:

```dart
  test('lists debts in the order they are cleared', () {
    // The loan's fixed 100.00 clears it in month 2; the card takes longer.
    final plan = planOf(
      simulate(
        strategyId: StrategyId.avalanche,
        debts: [
          debt(id: 'high', balance: 100000, aprBps: 2000),
          debt(
            id: 'loan',
            balance: 20000,
            minPaymentFloor: 10000,
            allowsOverpayment: false,
          ),
        ],
        budget: gbp(30000),
        fees: gbp(0),
        order: (_) => [0, 1],
      ),
    );
    expect(plan.payoffOrder, ['loan', 'high']);
    // Columns follow the same order: the loan's minimum, then the rest.
    expect(plan.months.first.payments, [gbp(10000), gbp(20000)]);
    expect(plan.monthsToClear, 5);
    expect(plan.totalPaid, gbp(124723));
  });

  test('with allowExtra false, pays only the minimums', () {
    final plan = planOf(
      simulate(
        strategyId: StrategyId.minimumsOnly,
        debts: [debt(id: 'a', balance: 100000, minPaymentFloor: 10000)],
        budget: gbp(50000),
        fees: gbp(0),
        order: (_) => [0],
        allowExtra: false,
      ),
    );
    expect(plan.monthsToClear, 10);
    expect(plan.months.every((r) => r.payments.single == gbp(10000)), isTrue);
  });
```

In `packages/payoff_engine/test/calculator_test.dart`:
- In `'does not modify the input list or its order'`, change `const Strategy.lowestAprFirst()` to `const Strategy.snowball()`.
- Replace the whole `group('calculate — strategies', …)` with:

```dart
  group('calculate — strategies', () {
    int col(PayoffPlan p, String id) => p.debts.indexWhere((d) => d.id == id);

    test('avalanche gives a 0% promo debt only its minimum until it ends', () {
      final plan = planOf(
        run([
          debt(
            id: 'a',
            balance: 100000,
            aprBps: 3000,
            promo: const Promo(aprBps: 0, months: 2),
          ),
          debt(id: 'b', balance: 100000, aprBps: 1000),
        ], 10000),
      );
      final a = col(plan, 'a');
      expect([for (final r in plan.months.take(3)) r.payments[a]], [
        gbp(0),
        gbp(0),
        gbp(10000),
      ]);
      expect(plan.months[2].interest[a], gbp(2500)); // 30% / 12 of 1,000.00
    });

    test('snowball pays the smallest starting balance first', () {
      final plan = planOf(
        run(
          [
            debt(id: 'a', balance: 50000, aprBps: 2000),
            debt(id: 'b', balance: 30000, aprBps: 500),
          ],
          10000,
          const Strategy.snowball(),
        ),
      );
      expect(plan.months.first.payments[col(plan, 'b')], gbp(10000));
      expect(plan.payoffOrder, ['b', 'a']);
      expect(plan.monthsToClear, 9);
      expect(plan.totalPaid, gbp(85737));
    });

    test('custom order follows the list', () {
      final plan = planOf(
        run(
          [
            debt(id: 'a', balance: 50000, aprBps: 500),
            debt(id: 'b', balance: 30000, aprBps: 2000),
          ],
          10000,
          const Strategy.customOrder(),
        ),
      );
      expect(plan.months.first.payments[col(plan, 'a')], gbp(10000));
      expect(plan.payoffOrder, ['a', 'b']);
      expect(plan.totalPaid, gbp(84467));
    });
  });

  group('calculateBaseline', () {
    test('pays only the minimums', () {
      final result = calculateBaseline(
        debts: [debt(id: 'a', balance: 100000, minPaymentFloor: 10000)],
        monthlyBudget: gbp(50000),
      );
      expect(result.strategyId, StrategyId.minimumsOnly);
      expect(planOf(result).monthsToClear, 10);
    });

    test('never clears when the minimum only covers the interest', () {
      // 2% of the balance a month against 24% APR (2% a month).
      final result = calculateBaseline(
        debts: [
          debt(
            id: 'a',
            balance: 100000,
            aprBps: 2400,
            minPaymentPercentBps: 200,
          ),
        ],
        monthlyBudget: gbp(50000),
      );
      expect(
        result,
        const PayoffResult.neverClears(strategyId: StrategyId.minimumsOnly),
      );
    });
  });
```

In `packages/payoff_engine/test/restructure_test.dart`, direct strategies no longer sort (ordering moves to `allocationOrder`). Replace the first test:

```dart
  test('direct strategies keep the list as given and add no fees', () {
    for (final s in const [
      Strategy.avalanche(),
      Strategy.snowball(),
      Strategy.customOrder(),
      Strategy.minimumsOnly(),
    ]) {
      final r = restructure([low, high], s, budget: gbp(500));
      expect(r.debts, [low, high], reason: '$s');
      expect(r.fees, gbp(0), reason: '$s');
    }
  });
```

In `packages/payoff_engine/test/calculator_synthetic_test.dart`, replace the last test:

```dart
  test('calculateAll returns one result per standard strategy, in order', () {
    final results = calculateAll(
      debts: [debt(id: 'a', balance: 100000)],
      monthlyBudget: gbp(25000),
      parameters: const StrategyParameters(),
    );
    expect(
      results.map((r) => r.strategyId),
      standardStrategies(const StrategyParameters()).map((s) => s.id),
    );
  });
```

In `packages/payoff_engine/test/legacy_scenarios_test.dart`:
- Delete every `expectPlan(p[StrategyId.lowestAprFirst]!, …)` and `expectPlan(p[StrategyId.boosted]!, …)` call, with their comments.
- Add at the end of S3:

```dart
    expectPlan(
      p[StrategyId.snowball]!,
      months: 22,
      paid: 705007,
      interest: 55007,
      order: ['c2', 'c1', 'l1'],
    );
    expectPlan(
      p[StrategyId.customOrder]!,
      months: 22,
      paid: 696187,
      interest: 46187,
      order: ['c1', 'c2', 'l1'],
    );
```

Replace `packages/payoff_engine/test/invariants_test.dart`:

```dart
// Randomised checks of properties every plan must satisfy.
import 'dart:math';

import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const cases = 300;

  List<Debt> randomDebts(Random r) => [
    for (var i = 0; i < 1 + r.nextInt(5); i++)
      debt(
        id: 'd$i',
        type: DebtType.values[r.nextInt(DebtType.values.length)],
        balance: 1 + r.nextInt(1000000),
        aprBps: r.nextInt(3001),
        minPaymentPercentBps: r.nextInt(501),
        minPaymentFloor: r.nextInt(5001),
        allowsOverpayment: r.nextInt(4) != 0,
        promo: r.nextInt(3) == 0
            ? Promo(aprBps: r.nextInt(501), months: 1 + r.nextInt(24))
            : null,
      ),
  ];

  StrategyParameters randomParameters(Random r) => StrategyParameters(
    consolidationAprBps: r.nextInt(2001),
    transferFeeBps: r.nextInt(501),
    promoMonths: r.nextInt(25),
    revertAprBps: r.nextInt(3001),
  );

  Money sum(Iterable<Money> xs) => xs.fold(gbp(0), (a, b) => a + b);

  test('every result satisfies the plan invariants', () {
    final r = Random(42);
    var feasible = 0;
    for (var c = 0; c < cases; c++) {
      final debts = randomDebts(r);
      final budget = gbp(1 + r.nextInt(200000));
      final strategies = [
        ...standardStrategies(randomParameters(r)),
        const Strategy.minimumsOnly(),
      ];
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
              plan.payoffOrder.toSet(),
              hasLength(plan.debts.length),
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
              expect(sum(row.payments) <= budget, isTrue, reason: label);
            }
            expect(
              plan.months.last.closingBalances.every((b) => b.isZero),
              isTrue,
              reason: label,
            );
        }
      }
    }
    // Guard against a generator that never exercises the feasible path.
    expect(feasible, greaterThan(cases));
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd packages/payoff_engine && dart test`
Expected: compilation errors: `Strategy.snowball`, `allocationOrder`, `compareHighestAprInMonth` and `calculateBaseline` are not defined.

- [ ] **Step 3: Implement**

Replace `packages/payoff_engine/lib/src/strategy.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'strategy.freezed.dart';

enum StrategyId {
  avalanche,
  snowball,
  customOrder,
  consolidation,
  balanceTransfer,
  minimumsOnly,
}

@freezed
sealed class Strategy with _$Strategy {
  /// Extra money to the debt with the highest rate that month.
  const factory Strategy.avalanche() = Avalanche;

  /// Extra money to the smallest starting balance first.
  const factory Strategy.snowball() = Snowball;

  /// Extra money to the debts in the order they are listed.
  const factory Strategy.customOrder() = CustomOrder;

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

  /// Only the minimum on every debt: the baseline the others are compared
  /// with.
  const factory Strategy.minimumsOnly() = MinimumsOnly;

  const Strategy._();

  StrategyId get id => switch (this) {
    Avalanche() => StrategyId.avalanche,
    Snowball() => StrategyId.snowball,
    CustomOrder() => StrategyId.customOrder,
    Consolidation() => StrategyId.consolidation,
    BalanceTransfer() => StrategyId.balanceTransfer,
    MinimumsOnly() => StrategyId.minimumsOnly,
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

/// The five strategies the app ranks, in display order. The baseline
/// ([Strategy.minimumsOnly]) is run separately by `calculateBaseline`.
List<Strategy> standardStrategies(StrategyParameters p) => [
  const Strategy.avalanche(),
  const Strategy.snowball(),
  const Strategy.customOrder(),
  Strategy.consolidation(aprBps: p.consolidationAprBps),
  Strategy.balanceTransfer(
    feeBps: p.transferFeeBps,
    promoMonths: p.promoMonths,
    revertAprBps: p.revertAprBps,
  ),
];
```

Replace `packages/payoff_engine/lib/src/debt_ordering.dart`:

```dart
import 'package:payoff_engine/src/debt.dart';

/// Highest rate charged in [month] first (a promotional rate counts while it
/// lasts); ties broken by name, then id.
int compareHighestAprInMonth(Debt a, Debt b, int month) {
  final byApr = aprInMonth(b, month).compareTo(aprInMonth(a, month));
  return byApr != 0 ? byApr : _byNameThenId(a, b);
}

/// Smallest balance first; ties broken by name, then id.
int compareSmallestBalanceFirst(Debt a, Debt b) {
  final byBalance = a.balance.compareTo(b.balance);
  return byBalance != 0 ? byBalance : _byNameThenId(a, b);
}

int _byNameThenId(Debt a, Debt b) {
  final byName = a.name.compareTo(b.name);
  return byName != 0 ? byName : a.id.compareTo(b.id);
}
```

Create `packages/payoff_engine/lib/src/allocation_order.dart`:

```dart
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/debt_ordering.dart';
import 'package:payoff_engine/src/strategy.dart';

/// For a month (1-based), the order in which debts receive money above
/// their minimums, as indexes into the simulated list.
typedef AllocationOrder = List<int> Function(int month);

/// The order [strategy] pays [debts] in. Avalanche-style strategies re-rank
/// every month by the rate charged that month, so a debt on a 0% promo gets
/// only its minimum until the promo ends.
AllocationOrder allocationOrder(Strategy strategy, List<Debt> debts) {
  final indexes = [for (var i = 0; i < debts.length; i++) i];
  List<int> sortedBy(int Function(Debt a, Debt b) compare) =>
      [...indexes]..sort((i, j) => compare(debts[i], debts[j]));
  AllocationOrder fixed(List<int> order) {
    final frozen = List<int>.unmodifiable(order);
    return (_) => frozen;
  }

  return switch (strategy) {
    Snowball() => fixed(sortedBy(compareSmallestBalanceFirst)),
    CustomOrder() => fixed(indexes),
    Avalanche() || Consolidation() || BalanceTransfer() || MinimumsOnly() =>
      (month) => sortedBy((a, b) => compareHighestAprInMonth(a, b, month)),
  };
}
```

In `packages/payoff_engine/lib/src/restructure.dart`, replace the first two switch arms (direct strategies are no longer sorted here; `allocationOrder` does that). Then remove the now-unused `debt_ordering.dart` import.

```dart
    Avalanche() || Snowball() || CustomOrder() || MinimumsOnly() =>
      Restructured(debts: [...debts], fees: zero),
```

In `packages/payoff_engine/lib/src/simulate.dart`:
- Import `package:payoff_engine/src/allocation_order.dart`.
- Add the parameters `required AllocationOrder order,` and `bool allowExtra = true,`.
- Update the doc comment: "…then spend what is left on overpayable debts in [order] (unless [allowExtra] is false). The plan lists debts in the order they are cleared."
- Replace everything from `var remaining = budget.minor - minimumsTotal;` to the end of the function:

```dart
    for (var i = 0; i < n; i++) {
      balances[i] -= payments[i];
    }
    final priority = order(month);
    if (allowExtra) {
      var remaining = budget.minor - minimumsTotal;
      for (final i in priority) {
        if (remaining == 0) break;
        if (!debts[i].allowsOverpayment || balances[i] == 0) continue;
        final extra = remaining < balances[i] ? remaining : balances[i];
        payments[i] += extra;
        balances[i] -= extra;
        remaining -= extra;
      }
    }
    for (final (position, i) in priority.indexed) {
      if (balances[i] == 0 && clearedAt[i] == null) {
        clearedAt[i] = (month, position);
      }
    }
    rows.add((interest: interest, payments: payments, closing: [...balances]));
  }

  // Columns in clearing order; debts cleared in the same month keep that
  // month's allocation order.
  final columns = [for (var i = 0; i < n; i++) i]
    ..sort((a, b) {
      final (monthA, positionA) = clearedAt[a]!;
      final (monthB, positionB) = clearedAt[b]!;
      final byMonth = monthA.compareTo(monthB);
      return byMonth != 0 ? byMonth : positionA.compareTo(positionB);
    });
  List<Money> pick(List<int> values) => [
    for (final i in columns) Money(values[i], currency),
  ];
  int total(List<int> Function(_Month) column) =>
      rows.fold(0, (sum, row) => column(row).fold(sum, (s, v) => s + v));

  return PayoffResult.feasible(
    strategyId: strategyId,
    plan: PayoffPlan(
      debts: [
        for (final i in columns)
          PlanDebt(
            id: debts[i].id,
            name: debts[i].name,
            startingBalance: debts[i].balance,
          ),
      ],
      months: [
        for (final (k, row) in rows.indexed)
          MonthRow(
            month: k + 1,
            interest: pick(row.interest),
            payments: pick(row.payments),
            closingBalances: pick(row.closing),
          ),
      ],
      totalPaid: Money(total((r) => r.payments), currency),
      totalInterest: Money(total((r) => r.interest), currency),
      totalFees: fees,
    ),
  );
}

typedef _Month = ({List<int> interest, List<int> payments, List<int> closing});
```

Also in `simulate`:
- Declare the rows as raw integers: replace `final rows = <MonthRow>[];` with `final rows = <_Month>[];`.
- Add `final clearedAt = List<(int, int)?>.filled(n, null);` after `balances`.

In `packages/payoff_engine/lib/src/calculator.dart`:
- Import `allocation_order.dart`.
- Delete the `Boosted` budget switch; use `monthlyBudget` directly.
- Replace the tail of `calculate` and add `calculateBaseline`:

```dart
  final restructured = restructure(debts, strategy, budget: monthlyBudget);
  return simulate(
    strategyId: strategy.id,
    debts: restructured.debts,
    budget: monthlyBudget,
    fees: restructured.fees,
    order: allocationOrder(strategy, restructured.debts),
    allowExtra: strategy is! MinimumsOnly,
  );
}
```

```dart
/// Paying only the minimums: the baseline [calculateAll]'s plans are
/// compared with.
PayoffResult calculateBaseline({
  required List<Debt> debts,
  required Money monthlyBudget,
}) => calculate(
  debts: debts,
  monthlyBudget: monthlyBudget,
  strategy: const Strategy.minimumsOnly(),
);
```

Also:
- Remove `import 'package:payoff_engine/src/rounding.dart';` from `calculator.dart` if it's now unused.
- Export `src/allocation_order.dart` from `payoff_engine.dart`.

- [ ] **Step 4: Generate code and run the engine tests**

Run: `cd packages/payoff_engine && dart run build_runner build -d && dart test`
Expected: `All tests passed!`. The S1–S4 avalanche and consolidation figures are unchanged. With no promos, a monthly re-rank gives the same order every month.

- [ ] **Step 5: Update the app tests for the new lineup**

In `test/features/strategies/strategies_screen_test.dart`, replace the name list in `'ranks every strategy and marks the cheapest'`:

```dart
    for (final name in [
      'Highest interest first',
      'Smallest balance first',
      'Your order',
      'Consolidation loan',
      '0% balance transfer',
    ]) {
```

In `test/features/strategies/rank_results_test.dart`, swap the removed ids:
- `StrategyId.lowestAprFirst` becomes `StrategyId.snowball`.
- `StrategyId.boosted` becomes `StrategyId.customOrder`.

In the tie-break test the expected order becomes `[StrategyId.snowball, StrategyId.avalanche, StrategyId.customOrder]`. Avalanche's index (0) is below customOrder's (2), and snowball has fewer months.

In `test/features/strategies/plans_providers_test.dart`, change `hasLength(StrategyId.values.length)` to `hasLength(5)`.

In `test/features/analysis/plan_detail_test.dart`, change `find.text('Payment priority')` to `find.text('Payoff order')`.

- [ ] **Step 6: Run the app tests to verify they fail**

Run: `./tool/codegen.sh && flutter test`
Expected: compilation errors in `lib/core/labels.dart` (`StrategyId.lowestAprFirst` doesn't exist).

- [ ] **Step 7: Implement the app changes**

In `lib/l10n/app_en.arb`:
- Delete `strategyLowestAprFirst`, `strategyLowestAprFirstDescription`, `strategyBoosted` and `strategyBoostedDescription`.
- Rename `paymentPriority` and `paymentPriorityHint` to the keys below.
- Add:

```json
  "strategySnowball": "Smallest balance first",
  "strategySnowballDescription": "Minimums on everything, the rest to the smallest debt, for quick wins.",
  "strategyCustomOrder": "Your order",
  "strategyCustomOrderDescription": "Minimums on everything, the rest in the order of your debts list.",
  "strategyMinimumsOnly": "Minimums only",
  "strategyMinimumsOnlyDescription": "Only the minimum payment on every debt.",
  "payoffOrder": "Payoff order",
  "payoffOrderHint": "The order your debts will be cleared in.",
```

In `lib/core/labels.dart`, replace the two strategy switches' removed arms:

```dart
String strategyName(AppLocalizations l10n, StrategyId id) => switch (id) {
  StrategyId.avalanche => l10n.strategyAvalanche,
  StrategyId.snowball => l10n.strategySnowball,
  StrategyId.customOrder => l10n.strategyCustomOrder,
  StrategyId.consolidation => l10n.strategyConsolidation,
  StrategyId.balanceTransfer => l10n.strategyBalanceTransfer,
  StrategyId.minimumsOnly => l10n.strategyMinimumsOnly,
};
```

and in `strategyDescription`:

```dart
  StrategyId.avalanche => l10n.strategyAvalancheDescription,
  StrategyId.snowball => l10n.strategySnowballDescription,
  StrategyId.customOrder => l10n.strategyCustomOrderDescription,
  StrategyId.minimumsOnly => l10n.strategyMinimumsOnlyDescription,
```

In `lib/features/analysis/presentation/plan_summary_tab.dart`, change `_Section(l10n.paymentPriority, hint: l10n.paymentPriorityHint)` to `_Section(l10n.payoffOrder, hint: l10n.payoffOrderHint)`.

- [ ] **Step 8: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test && (cd packages/payoff_engine && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && dart test)`
Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add packages/payoff_engine lib test
git commit -m "feat(engine): snowball, custom order and minimums-only baseline; re-rank monthly"
```

---

### Task 4: Realistic balance transfer

**Files:**
- Modify: `packages/payoff_engine/lib/src/strategy.dart`, `payoff_result.dart`, `restructure.dart`, `simulate.dart`, `calculator.dart`
- Test: `packages/payoff_engine/test/transfer_test.dart` (new), `restructure_test.dart`, `calculator_synthetic_test.dart`, `legacy_scenarios_test.dart`, `invariants_test.dart`
- Modify (app): `lib/core/labels.dart`, `lib/l10n/app_en.arb`, `lib/features/strategies/domain/rank_results.dart`, `lib/features/strategies/presentation/strategies_screen.dart`
- Test (app): `test/core/labels_test.dart`, `test/features/strategies/rank_results_test.dart`, `test/features/strategies/strategies_screen_test.dart`

**Interfaces:**
- Consumes: `isTransferable`, `aprInMonth` (Task 1); `compareHighestAprInMonth`, `allocationOrder`, the clearing-order `simulate` (Task 3).
- Produces:
  - `Strategy.balanceTransfer({required int feeBps, required int promoMonths, required int revertAprBps, Money? creditLimit})`
  - `StrategyParameters.transferCreditLimit: Money?` (default null)
  - `enum NotApplicableReason { noTransferableBalances, nothingToConsolidate }`
  - `PayoffResult.notApplicable({required StrategyId strategyId, required NotApplicableReason reason})`, class `NotApplicable`
  - `MovedBalance({required String debtId, required String name, required Money amount})`
  - `PlanChange.transfer({required List<MovedBalance> moved, required Money fee, required Money creditLimit, required bool limitAssumed, required int promoMonths})`, class `TransferChange`
  - `PayoffPlan.change: PlanChange?`
  - `sealed class RestructureOutcome`, with the subclasses `Restructured({debts, fees, change})` and `NotRestructurable(reason)`
  - `const int kTransferCardMinimumBps = 300`
  - `simulate(…, PlanChange? change)`
  - App: `String notApplicableReason(AppLocalizations, NotApplicableReason)`

- [ ] **Step 1: Write the failing engine tests**

Create `packages/payoff_engine/test/transfer_test.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final visa = debt(
    id: 'a',
    name: 'Visa',
    balance: 100000,
    aprBps: 2000,
    minPaymentPercentBps: 300,
    minPaymentFloor: 2500,
  );
  final store = debt(
    id: 'b',
    name: 'Store',
    type: DebtType.storeCard,
    balance: 50000,
    aprBps: 2500,
    minPaymentPercentBps: 300,
    minPaymentFloor: 2500,
  );
  final carLoan = debt(
    id: 'l',
    name: 'Car loan',
    type: DebtType.loan,
    balance: 200000,
    aprBps: 700,
    minPaymentFloor: 15000,
  );
  final debts = [visa, store, carLoan];

  Strategy transfer({Money? limit, int promoMonths = 12}) =>
      Strategy.balanceTransfer(
        feeBps: 300,
        promoMonths: promoMonths,
        revertAprBps: 1900,
        creditLimit: limit,
      );

  Restructured restructured(Strategy s, [List<Debt>? input]) =>
      restructure(input ?? debts, s, budget: gbp(60000)) as Restructured;

  test('with no limit, every card balance moves, highest APR first', () {
    final r = restructured(transfer());
    final card = r.debts.first;
    expect(card.id, kBalanceTransferDebtId);
    // 1,500.00 moved, plus 3% fees of 15.00 (store) and 30.00 (Visa).
    expect(card.balance, gbp(154500));
    expect(r.debts.skip(1), [carLoan]);
    expect(r.fees, gbp(4500));
    expect(
      r.change,
      PlanChange.transfer(
        moved: [
          MovedBalance(debtId: 'b', name: 'Store', amount: gbp(50000)),
          MovedBalance(debtId: 'a', name: 'Visa', amount: gbp(100000)),
        ],
        fee: gbp(4500),
        creditLimit: gbp(154500),
        limitAssumed: true,
        promoMonths: 12,
      ),
    );
  });

  test('the card is 0% for the promo, then the revert APR, 3% minimum', () {
    final card = restructured(transfer()).debts.first;
    expect(card.promo, const Promo(aprBps: 0, months: 12));
    expect(card.aprBps, 1900);
    expect(card.minPaymentPercentBps, kTransferCardMinimumBps);
    expect(card.minPaymentFloor, gbp(0));
    expect(card.allowsOverpayment, isTrue);
  });

  test('a limit moves part of a balance; the fee counts against it', () {
    final r = restructured(transfer(limit: gbp(100000)));
    // Store: 500.00 + 15.00 fee leaves 485.00 of room. Visa: 470.87 plus a
    // 14.13 fee fills it exactly; 470.88 would need 485.01.
    expect(r.debts.first.balance, gbp(100000));
    expect(r.fees, gbp(2913));
    expect(r.debts.skip(1).map((d) => (d.id, d.balance)), [
      ('a', gbp(52913)),
      ('l', gbp(200000)),
    ]);
    final change = r.change! as TransferChange;
    expect(change.limitAssumed, isFalse);
    expect(change.creditLimit, gbp(100000));
  });

  test('skips a balance already on a 0% promo', () {
    final onPromo = visa.copyWith(promo: const Promo(aprBps: 0, months: 6));
    final r = restructured(transfer(), [onPromo, store]);
    expect((r.change! as TransferChange).moved.map((m) => m.debtId), ['b']);
    expect(r.debts.skip(1), [onPromo]);
  });

  test('no promo months means no promo on the card', () {
    expect(restructured(transfer(promoMonths: 0)).debts.first.promo, isNull);
  });

  test('is not applicable when no balance can move', () {
    expect(
      calculate(
        debts: [carLoan],
        monthlyBudget: gbp(60000),
        strategy: transfer(),
      ),
      const PayoffResult.notApplicable(
        strategyId: StrategyId.balanceTransfer,
        reason: NotApplicableReason.noTransferableBalances,
      ),
    );
  });

  test('pays the other debts first while the card is at 0%', () {
    final plan = planOf(
      calculate(debts: debts, monthlyBudget: gbp(60000), strategy: transfer()),
    );
    expect(plan.monthsToClear, 6);
    expect(plan.totalPaid, gbp(357260));
    expect(plan.totalInterest, gbp(2760));
    expect(plan.totalFees, gbp(4500));
    expect(plan.payoffOrder, ['l', kBalanceTransferDebtId]);
    expect(plan.change, isA<TransferChange>());
  });

  test('a partial transfer leaves the rest on the original card', () {
    final plan = planOf(
      calculate(
        debts: debts,
        monthlyBudget: gbp(60000),
        strategy: transfer(limit: gbp(100000)),
      ),
    );
    expect(plan.monthsToClear, 6);
    expect(plan.totalPaid, gbp(357744));
    expect(plan.totalInterest, gbp(4831));
    expect(plan.totalFees, gbp(2913));
    expect(plan.payoffOrder, ['a', 'l', kBalanceTransferDebtId]);
  });

  test('rejects a credit limit in another currency', () {
    expect(
      () => calculate(
        debts: debts,
        monthlyBudget: gbp(60000),
        strategy: transfer(limit: const Money(100000, 'USD')),
      ),
      throwsArgumentError,
    );
  });
}
```

In `packages/payoff_engine/test/restructure_test.dart`, `restructure` now returns a `RestructureOutcome`. Add this helper and use it in place of each direct `restructure(…)` call whose result is read:

```dart
  Restructured paid(List<Debt> debts, Strategy strategy) =>
      restructure(debts, strategy, budget: gbp(500)) as Restructured;
```

In `packages/payoff_engine/test/calculator_synthetic_test.dart`, the transfer test's debt must charge interest to be transferable. Change it to `debt(id: 'a', balance: 1000000, aprBps: 1990, minPaymentFloor: 2500)`. Every expectation there still holds: the card is 10,400.00 at 0% for 15 months, with a 400.00 fee.

In `packages/payoff_engine/test/legacy_scenarios_test.dart`:
- Make `runAll` return `Map<StrategyId, PayoffResult>`:

```dart
  Map<StrategyId, PayoffResult> runAll(List<Debt> debts, int budget) => {
    for (final r in calculateAll(
      debts: debts,
      monthlyBudget: gbp(budget),
      parameters: params,
    ))
      r.strategyId: r,
  };
```

- Make `expectPlan` take `PayoffResult result`, with `final plan = planOf(result);` as its first line.
- Replace the S1 transfer expectation:

```dart
    // Legacy moved the interest-free card anyway (5 months, 1040.00). v2
    // only moves balances that charge interest, so there is nothing to move.
    expect(
      p[StrategyId.balanceTransfer],
      const PayoffResult.notApplicable(
        strategyId: StrategyId.balanceTransfer,
        reason: NotApplicableReason.noTransferableBalances,
      ),
    );
```

- Replace the S3 transfer expectation and its comment:

```dart
    // Legacy moved everything, loan included: 16 months, 6760.00. v2 moves
    // only the two cards (3,500.00 + 140.00 fee); the fixed-payment car loan
    // stays and sets the pace.
    expectPlan(
      p[StrategyId.balanceTransfer]!,
      months: 22,
      paid: 682395,
      interest: 18395,
      fees: 14000,
      order: [kBalanceTransferDebtId, 'l1'],
    );
```

S2 and S4 transfer figures are unchanged: every debt there is a card that charges interest, and the card takes the whole budget.

In `packages/payoff_engine/test/invariants_test.dart`:
- Add `transferCreditLimit: r.nextBool() ? null : gbp(1 + r.nextInt(2000000)),` to `randomParameters`.
- Add a `case NotApplicable(): break;` arm to the switch.
- Add at the end of the `Feasible` arm:

```dart
            if (plan.change case TransferChange(
              :final moved,
              :final fee,
              :final creditLimit,
            )) {
              expect(
                sum(moved.map((m) => m.amount)) + fee <= creditLimit,
                isTrue,
                reason: label,
              );
            }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd packages/payoff_engine && dart test`
Expected: compilation errors: `creditLimit`, `PlanChange`, `NotApplicableReason` and `Restructured` (as a subtype) are not defined.

- [ ] **Step 3: Implement the engine changes**

In `packages/payoff_engine/lib/src/strategy.dart`, replace the balance-transfer factory and extend the parameters:

```dart
  /// Move card balances that charge interest to a card at 0% for
  /// [promoMonths] months, then [revertAprBps], adding a [feeBps] fee. At
  /// most [creditLimit] (fees included) moves; with no limit, everything
  /// eligible fits.
  const factory Strategy.balanceTransfer({
    required int feeBps,
    required int promoMonths,
    required int revertAprBps,
    Money? creditLimit,
  }) = BalanceTransfer;
```

```dart
@freezed
abstract class StrategyParameters with _$StrategyParameters {
  const factory StrategyParameters({
    @Default(500) int consolidationAprBps,
    @Default(400) int transferFeeBps,
    @Default(12) int promoMonths,
    @Default(1500) int revertAprBps,

    /// The transfer card's limit, in the budget currency; null assumes
    /// every eligible balance fits.
    Money? transferCreditLimit,
  }) = _StrategyParameters;
}
```

Also:
- Add `import 'package:payoff_engine/src/money.dart';` to `strategy.dart`.
- Pass `creditLimit: p.transferCreditLimit,` in `standardStrategies`.

In `packages/payoff_engine/lib/src/payoff_result.dart`, add the new variant to `PayoffResult`:

```dart
  /// [strategyId] can't be used with these debts, for [reason].
  const factory PayoffResult.notApplicable({
    required StrategyId strategyId,
    required NotApplicableReason reason,
  }) = NotApplicable;
```

Add `PlanChange? change,` as the last field of `PayoffPlan`, with the doc comment `/// What the strategy moved or replaced, if anything.` Then add:

```dart
enum NotApplicableReason { noTransferableBalances, nothingToConsolidate }

/// A balance moved to a transfer card or replaced by a consolidation loan.
@freezed
abstract class MovedBalance with _$MovedBalance {
  const factory MovedBalance({
    required String debtId,
    required String name,
    required Money amount,
  }) = _MovedBalance;
}

/// What a strategy changed about the user's debts.
@freezed
sealed class PlanChange with _$PlanChange {
  /// [moved] went to a card at 0% for [promoMonths] months. [creditLimit]
  /// was assumed (just enough for everything) when [limitAssumed].
  const factory PlanChange.transfer({
    required List<MovedBalance> moved,
    required Money fee,
    required Money creditLimit,
    required bool limitAssumed,
    required int promoMonths,
  }) = TransferChange;
}
```

Replace `packages/payoff_engine/lib/src/restructure.dart`:

```dart
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/debt_kind.dart';
import 'package:payoff_engine/src/debt_ordering.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/rounding.dart';
import 'package:payoff_engine/src/strategy.dart';

const String kConsolidationDebtId = 'consolidation';
const String kBalanceTransferDebtId = 'balance-transfer';

/// Minimum payment on the balance-transfer card: 3% of the balance.
const int kTransferCardMinimumBps = 300;

sealed class RestructureOutcome {
  const RestructureOutcome();
}

/// The debts a strategy would actually be paying.
final class Restructured extends RestructureOutcome {
  const Restructured({required this.debts, required this.fees, this.change});

  final List<Debt> debts;

  /// One-off fees added to [debts]' balances, e.g. a transfer fee.
  final Money fees;

  /// What the strategy moved or replaced, for display.
  final PlanChange? change;
}

/// The strategy can't be used with these debts.
final class NotRestructurable extends RestructureOutcome {
  const NotRestructurable(this.reason);

  final NotApplicableReason reason;
}

/// Turns the user's [debts] (not empty) into the debts [strategy] pays.
/// Pure: [debts] is not modified.
RestructureOutcome restructure(
  List<Debt> debts,
  Strategy strategy, {
  required Money budget,
}) {
  final currency = debts.first.balance.currency;
  final zero = Money.zero(currency);
  return switch (strategy) {
    Avalanche() || Snowball() || CustomOrder() || MinimumsOnly() =>
      Restructured(debts: [...debts], fees: zero),
    Consolidation(:final aprBps) => Restructured(
      debts: [
        Debt(
          id: kConsolidationDebtId,
          name: 'Consolidation loan',
          type: DebtType.loan,
          balance: debts.fold(zero, (sum, d) => sum + d.balance),
          aprBps: aprBps,
          minPaymentPercentBps: 0,
          minPaymentFloor: budget,
          allowsOverpayment: false,
        ),
      ],
      fees: zero,
    ),
    BalanceTransfer() => _transfer(debts, strategy),
  };
}

RestructureOutcome _transfer(List<Debt> debts, BalanceTransfer t) {
  final currency = debts.first.balance.currency;
  int fee(int amount) => divideHalfEven(amount * t.feeBps, 10000);

  final candidates = [
    for (final d in debts)
      if (isTransferable(d.type) && aprInMonth(d, 1) > 0) d,
  ]..sort((a, b) => compareHighestAprInMonth(a, b, 1));
  // With no limit, assume just enough for every candidate and its own fee.
  final limit =
      t.creditLimit?.minor ??
      candidates.fold(0, (sum, d) => sum + d.balance.minor + fee(d.balance.minor));

  var room = limit;
  var fees = 0;
  final moved = <String, int>{};
  for (final d in candidates) {
    final amount = _largestFitting(room, d.balance.minor, fee);
    if (amount == 0) continue;
    moved[d.id] = amount;
    fees += fee(amount);
    room -= amount + fee(amount);
  }
  if (moved.isEmpty) {
    return const NotRestructurable(NotApplicableReason.noTransferableBalances);
  }

  final card = Debt(
    id: kBalanceTransferDebtId,
    name: 'Balance transfer card',
    type: DebtType.creditCard,
    balance: Money(moved.values.fold(0, (a, b) => a + b) + fees, currency),
    aprBps: t.revertAprBps,
    minPaymentPercentBps: kTransferCardMinimumBps,
    minPaymentFloor: Money.zero(currency),
    allowsOverpayment: true,
    promo: t.promoMonths > 0 ? Promo(aprBps: 0, months: t.promoMonths) : null,
  );
  return Restructured(
    debts: [
      card,
      for (final d in debts)
        if (d.balance.minor - (moved[d.id] ?? 0) case final left when left > 0)
          d.copyWith(balance: Money(left, currency)),
    ],
    fees: Money(fees, currency),
    change: PlanChange.transfer(
      moved: [
        for (final d in candidates)
          if (moved[d.id] case final amount?)
            MovedBalance(
              debtId: d.id,
              name: d.name,
              amount: Money(amount, currency),
            ),
      ],
      fee: Money(fees, currency),
      creditLimit: Money(limit, currency),
      limitAssumed: t.creditLimit == null,
      promoMonths: t.promoMonths,
    ),
  );
}

/// The largest amount up to [max] that fits in [room] together with its fee.
/// The amount plus its fee rises with the amount, so a binary search finds it.
int _largestFitting(int room, int max, int Function(int) fee) {
  var low = 0;
  var high = max;
  while (low < high) {
    final mid = low + (high - low + 1) ~/ 2;
    if (mid + fee(mid) <= room) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low;
}
```

In `packages/payoff_engine/lib/src/simulate.dart`, add a `PlanChange? change,` parameter and pass `change: change,` into the `PayoffPlan`.

In `packages/payoff_engine/lib/src/calculator.dart`, add after the currency check:

```dart
  if (strategy case BalanceTransfer(creditLimit: final limit?)
      when limit.currency != currency) {
    throw ArgumentError.value(limit, 'creditLimit', 'not in the budget currency');
  }
```

and replace the restructure-and-simulate tail:

```dart
  return switch (restructure(debts, strategy, budget: monthlyBudget)) {
    NotRestructurable(:final reason) => PayoffResult.notApplicable(
      strategyId: strategy.id,
      reason: reason,
    ),
    Restructured(debts: final paid, :final fees, :final change) => simulate(
      strategyId: strategy.id,
      debts: paid,
      budget: monthlyBudget,
      fees: fees,
      change: change,
      order: allocationOrder(strategy, paid),
      allowExtra: strategy is! MinimumsOnly,
    ),
  };
```

- [ ] **Step 4: Generate code and run the engine tests**

Run: `cd packages/payoff_engine && dart run build_runner build -d && dart test`
Expected: `All tests passed!`

- [ ] **Step 5: Write the failing app tests**

In `test/core/labels_test.dart`, change the expected transfer description to `'Move card balances to a 0% card for 12 months (4% fee, then 15%).'`, and append:

```dart
  test('explains why a strategy does not apply', () {
    expect(
      notApplicableReason(l10n, NotApplicableReason.noTransferableBalances),
      'Not available: there are no card balances with interest to move.',
    );
    expect(
      notApplicableReason(l10n, NotApplicableReason.nothingToConsolidate),
      'Not available: none of your debts can be consolidated.',
    );
  });
```

In `test/features/strategies/rank_results_test.dart`, append:

```dart
  test('puts strategies that do not apply last', () {
    final ranked = rankResults([
      const PayoffResult.notApplicable(
        strategyId: StrategyId.balanceTransfer,
        reason: NotApplicableReason.noTransferableBalances,
      ),
      const PayoffResult.neverClears(strategyId: StrategyId.snowball),
      feasible(StrategyId.avalanche, paid: 1),
    ]);
    expect(ranked.map((r) => r.strategyId), [
      StrategyId.avalanche,
      StrategyId.snowball,
      StrategyId.balanceTransfer,
    ]);
  });
```

In `test/features/strategies/strategies_screen_test.dart`, append:

```dart
  testWidgets('says why a strategy does not apply', (tester) async {
    await pumpApp(
      tester,
      debts: [simple], // 0% card: nothing worth transferring
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    const reason =
        'Not available: there are no card balances with interest to move.';
    await tester.scrollUntilVisible(find.text(reason), 100);
    expect(find.text(reason), findsOneWidget);
  });
```

- [ ] **Step 6: Run them to verify they fail**

Run: `./tool/codegen.sh && flutter test test/core/labels_test.dart test/features/strategies`
Expected: compilation errors. The switches over `PayoffResult` in `rank_results.dart` and `strategies_screen.dart` are not exhaustive, and `notApplicableReason` is undefined.

- [ ] **Step 7: Implement the app changes**

In `lib/l10n/app_en.arb`, change `strategyBalanceTransferDescription` and add the reasons:

```json
  "strategyBalanceTransferDescription": "Move card balances to a 0% card for {months} months ({fee} fee, then {apr}).",
  "notApplicableNoTransfer": "Not available: there are no card balances with interest to move.",
  "notApplicableNoConsolidation": "Not available: none of your debts can be consolidated.",
```

Add to `lib/core/labels.dart`:

```dart
/// Why a strategy can't be used with the current debts.
String notApplicableReason(
  AppLocalizations l10n,
  NotApplicableReason reason,
) => switch (reason) {
  NotApplicableReason.noTransferableBalances => l10n.notApplicableNoTransfer,
  NotApplicableReason.nothingToConsolidate => l10n.notApplicableNoConsolidation,
};
```

In `lib/features/strategies/domain/rank_results.dart`, update the doc comment ("…then infeasible, never-clearing, and finally not-applicable ones") and add `NotApplicable() => 3,` to `group`.

In `_StrategyCard.build` (`strategies_screen.dart`), add an arm to the `details` switch:

```dart
      NotApplicable(:final reason) => Text(
        notApplicableReason(l10n, reason),
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
```

- [ ] **Step 8: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test && (cd packages/payoff_engine && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && dart test)`
Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add packages/payoff_engine lib test
git commit -m "feat(engine): balance transfer moves only card balances, within a credit limit"
```

---

### Task 5: Realistic consolidation

**Files:**
- Create: `packages/payoff_engine/lib/src/fixed_loan_payment.dart`
- Modify: `packages/payoff_engine/lib/src/strategy.dart`, `payoff_result.dart`, `restructure.dart`, `calculator.dart`, `packages/payoff_engine/lib/payoff_engine.dart`
- Test: `packages/payoff_engine/test/consolidation_test.dart` (new), `restructure_test.dart`, `transfer_test.dart`, `calculator_guard_test.dart`, `invariants_test.dart`
- Modify (app): `lib/core/labels.dart`, `lib/l10n/app_en.arb`
- Test (app): `test/core/labels_test.dart`

**Interfaces:**
- Consumes: `isConsolidatable` (Task 1); `RestructureOutcome`, `PlanChange`, `MovedBalance`, `NotApplicableReason` (Task 4).
- Produces:
  - `Strategy.consolidation({required int aprBps, int termMonths = 60, int feeBps = 0})`
  - `StrategyParameters.consolidationTermMonths` (60) and `consolidationFeeBps` (0)
  - `int fixedLoanPayment({required int balanceMinor, required int aprBps, required int termMonths})`
  - `PlanChange.consolidation({required List<MovedBalance> replaced, required Money fee, required Money monthlyPayment, required int termMonths, required int aprBps})`, class `ConsolidationChange`
  - `RestructureOutcome restructure(List<Debt> debts, Strategy strategy)`: the `budget` parameter is removed

- [ ] **Step 1: Write the failing engine tests**

Create `packages/payoff_engine/test/consolidation_test.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('fixedLoanPayment', () {
    test('at 0% it is the balance over the term, rounded up', () {
      expect(
        fixedLoanPayment(balanceMinor: 100000, aprBps: 0, termMonths: 12),
        8334,
      );
    });

    test('uses the engine\'s own monthly interest and rounding', () {
      expect(
        fixedLoanPayment(balanceMinor: 120000, aprBps: 1200, termMonths: 12),
        10662,
      );
      expect(
        fixedLoanPayment(balanceMinor: 500000, aprBps: 600, termMonths: 60),
        9667,
      );
    });

    test('is the smallest payment that clears within the term', () {
      PayoffPlan loanPaying(int payment) => planOf(
        calculate(
          debts: [
            debt(
              id: 'loan',
              type: DebtType.loan,
              balance: 120000,
              aprBps: 1200,
              minPaymentFloor: payment,
              allowsOverpayment: false,
            ),
          ],
          monthlyBudget: gbp(payment),
          strategy: const Strategy.avalanche(),
        ),
      );
      expect(loanPaying(10662).monthsToClear, 12);
      expect(loanPaying(10661).monthsToClear, 13);
    });
  });

  group('consolidation', () {
    final visa = debt(
      id: 'a',
      name: 'Visa',
      balance: 100000,
      aprBps: 2000,
      minPaymentPercentBps: 300,
      minPaymentFloor: 2500,
    );
    final mum = debt(
      id: 'f',
      name: 'Mum',
      type: DebtType.personal,
      balance: 50000,
      minPaymentFloor: 5000,
    );
    const strategy = Strategy.consolidation(
      aprBps: 600,
      termMonths: 24,
      feeBps: 200,
    );

    test('replaces eligible debts with a fixed-payment loan', () {
      final r = restructure([visa, mum], strategy) as Restructured;
      final loan = r.debts.first;
      expect(loan.id, kConsolidationDebtId);
      expect(loan.balance, gbp(102000)); // 1,000.00 + 2% fee
      expect(loan.minPaymentPercentBps, 0);
      expect(loan.minPaymentFloor, gbp(4521));
      expect(loan.allowsOverpayment, isTrue);
      expect(r.debts.skip(1), [mum]);
      expect(r.fees, gbp(2000));
      expect(
        r.change,
        PlanChange.consolidation(
          replaced: [
            MovedBalance(debtId: 'a', name: 'Visa', amount: gbp(100000)),
          ],
          fee: gbp(2000),
          monthlyPayment: gbp(4521),
          termMonths: 24,
          aprBps: 600,
        ),
      );
    });

    test('overpays the loan with what the budget has left', () {
      final plan = planOf(
        calculate(
          debts: [visa, mum],
          monthlyBudget: gbp(30000),
          strategy: strategy,
        ),
      );
      expect(plan.monthsToClear, 6);
      expect(plan.totalPaid, gbp(153320));
      expect(plan.totalInterest, gbp(1320));
      expect(plan.totalFees, gbp(2000));
      expect(plan.payoffOrder, [kConsolidationDebtId, 'f']);
    });

    test('is not applicable when nothing can be consolidated', () {
      expect(
        calculate(
          debts: [
            debt(id: 's', type: DebtType.studentLoan, balance: 100000),
          ],
          monthlyBudget: gbp(10000),
          strategy: strategy,
        ),
        const PayoffResult.notApplicable(
          strategyId: StrategyId.consolidation,
          reason: NotApplicableReason.nothingToConsolidate,
        ),
      );
    });

    test('rejects a term below one month', () {
      expect(
        () => calculate(
          debts: [visa],
          monthlyBudget: gbp(10000),
          strategy: const Strategy.consolidation(aprBps: 600, termMonths: 0),
        ),
        throwsArgumentError,
      );
    });
  });
}
```

In `restructure_test.dart` and `transfer_test.dart`, delete every `budget: gbp(…)` argument passed to `restructure`.

In `packages/payoff_engine/test/calculator_guard_test.dart`, replace the last test. The loan's fixed payment (about 8.4% of 5 × 10¹² a month) now exceeds the budget:

```dart
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
    // The 60-month payment alone is far above the budget.
    expect(result, isA<Infeasible>());
  });
```

In `packages/payoff_engine/test/invariants_test.dart`:
- Add `consolidationTermMonths: 6 + r.nextInt(115), consolidationFeeBps: r.nextInt(2001),` to `randomParameters`.
- Add at the end of the `Feasible` arm:

```dart
            if (plan.change case ConsolidationChange(:final termMonths)) {
              final loan = plan.debts.indexWhere(
                (d) => d.id == kConsolidationDebtId,
              );
              final end = termMonths < plan.monthsToClear
                  ? termMonths
                  : plan.monthsToClear;
              expect(
                plan.months[end - 1].closingBalances[loan].isZero,
                isTrue,
                reason: '$label: loan outlives its term',
              );
            }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd packages/payoff_engine && dart test`
Expected: compilation errors: `fixedLoanPayment`, `termMonths`, `PlanChange.consolidation` are undefined, and `restructure`'s `budget` parameter is still required.

- [ ] **Step 3: Implement the engine changes**

Create `packages/payoff_engine/lib/src/fixed_loan_payment.dart`:

```dart
import 'package:payoff_engine/src/rounding.dart';

/// The smallest whole monthly payment that clears [balanceMinor] at
/// [aprBps] within [termMonths] months, using the calculator's own monthly
/// interest and rounding (so the loan really does clear on time). Integer
/// arithmetic throughout: a binary search, not an annuity formula.
int fixedLoanPayment({
  required int balanceMinor,
  required int aprBps,
  required int termMonths,
}) {
  bool clears(int payment) {
    var balance = balanceMinor;
    for (var m = 0; m < termMonths; m++) {
      balance += divideHalfEven(balance * aprBps, 120000);
      balance -= payment < balance ? payment : balance;
      if (balance == 0) return true;
    }
    return false;
  }

  // Never less than an interest-free share; never more than clearing the
  // loan in its first month.
  var low = (balanceMinor + termMonths - 1) ~/ termMonths;
  var high = balanceMinor + divideHalfEven(balanceMinor * aprBps, 120000);
  while (low < high) {
    final mid = low + (high - low) ~/ 2;
    if (clears(mid)) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low;
}
```

Export it from `payoff_engine.dart`.

In `strategy.dart`, replace the consolidation factory and extend the parameters:

```dart
  /// Replace every consolidatable debt with one loan at [aprBps], repaid over
  /// [termMonths] months, plus a [feeBps] arrangement fee. What the budget
  /// has left over the loan payment goes to the loan and the other debts.
  const factory Strategy.consolidation({
    required int aprBps,
    @Default(60) int termMonths,
    @Default(0) int feeBps,
  }) = Consolidation;
```

```dart
    @Default(500) int consolidationAprBps,
    @Default(60) int consolidationTermMonths,
    @Default(0) int consolidationFeeBps,
```

and in `standardStrategies`:

```dart
  Strategy.consolidation(
    aprBps: p.consolidationAprBps,
    termMonths: p.consolidationTermMonths,
    feeBps: p.consolidationFeeBps,
  ),
```

In `payoff_result.dart`, add the second `PlanChange` variant:

```dart
  /// [replaced] were paid off by a loan of their total plus [fee], repaid at
  /// [monthlyPayment] for [termMonths] months at [aprBps].
  const factory PlanChange.consolidation({
    required List<MovedBalance> replaced,
    required Money fee,
    required Money monthlyPayment,
    required int termMonths,
    required int aprBps,
  }) = ConsolidationChange;
```

In `restructure.dart`:
- Remove the `budget` parameter.
- Import `fixed_loan_payment.dart`.
- Replace the consolidation arm with `Consolidation() => _consolidate(debts, strategy),`.
- Add:

```dart
RestructureOutcome _consolidate(List<Debt> debts, Consolidation c) {
  final currency = debts.first.balance.currency;
  final replaced = [
    for (final d in debts)
      if (isConsolidatable(d.type)) d,
  ];
  if (replaced.isEmpty) {
    return const NotRestructurable(NotApplicableReason.nothingToConsolidate);
  }
  final principal = replaced.fold(0, (sum, d) => sum + d.balance.minor);
  final fee = divideHalfEven(principal * c.feeBps, 10000);
  final payment = fixedLoanPayment(
    balanceMinor: principal + fee,
    aprBps: c.aprBps,
    termMonths: c.termMonths,
  );
  final loan = Debt(
    id: kConsolidationDebtId,
    name: 'Consolidation loan',
    type: DebtType.loan,
    balance: Money(principal + fee, currency),
    aprBps: c.aprBps,
    minPaymentPercentBps: 0,
    minPaymentFloor: Money(payment, currency),
    allowsOverpayment: true,
  );
  return Restructured(
    debts: [
      loan,
      for (final d in debts)
        if (!isConsolidatable(d.type)) d,
    ],
    fees: Money(fee, currency),
    change: PlanChange.consolidation(
      replaced: [
        for (final d in replaced)
          MovedBalance(debtId: d.id, name: d.name, amount: d.balance),
      ],
      fee: Money(fee, currency),
      monthlyPayment: Money(payment, currency),
      termMonths: c.termMonths,
      aprBps: c.aprBps,
    ),
  );
}
```

In `calculator.dart`:
- Drop the `budget:` argument from the `restructure` call.
- Add after the credit-limit check:

```dart
  if (strategy case Consolidation(:final termMonths) when termMonths < 1) {
    throw ArgumentError.value(termMonths, 'termMonths', 'must be at least 1');
  }
```

- [ ] **Step 4: Generate code and run the engine tests**

Run: `cd packages/payoff_engine && dart run build_runner build -d && dart test`
Expected: `All tests passed!`. The S1–S4 consolidation figures are unchanged: every debt there is consolidatable, and the budget covers far more than the 60-month payment, so the loan still takes the whole budget.

- [ ] **Step 5: Write the failing app test**

In `test/core/labels_test.dart`, change the consolidation expectation to:

```dart
    expect(
      strategyDescription(l10n, StrategyId.consolidation, p, 'en_GB'),
      'A 60-month loan at 5% replaces your cards, loans and overdrafts.',
    );
```

- [ ] **Step 6: Run it to verify it fails**

Run: `./tool/codegen.sh && flutter test test/core/labels_test.dart`
Expected: FAIL. The description is still `One loan at 5% replaces all your debts.`

- [ ] **Step 7: Implement**

In `lib/l10n/app_en.arb`, replace `strategyConsolidationDescription` and its metadata:

```json
  "strategyConsolidationDescription": "A {months}-month loan at {apr} replaces your cards, loans and overdrafts.",
  "@strategyConsolidationDescription": {"placeholders": {"months": {"type": "int"}, "apr": {"type": "String"}}},
```

In `lib/core/labels.dart`:

```dart
  StrategyId.consolidation => l10n.strategyConsolidationDescription(
    p.consolidationTermMonths,
    formatPercent(p.consolidationAprBps, locale),
  ),
```

- [ ] **Step 8: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test && (cd packages/payoff_engine && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && dart test)`
Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add packages/payoff_engine lib test
git commit -m "feat(engine): consolidation loan with a term, arrangement fee and fixed payment"
```

---

### Task 6: Settings for the new strategy parameters

**Files:**
- Modify: `packages/payoff_engine/lib/src/validation.dart`
- Test: `packages/payoff_engine/test/debt_list_validation_test.dart`
- Create (app): `lib/features/settings/presentation/parameter_fields.dart`
- Modify (app): `lib/features/settings/data/prefs_settings_repository.dart`, `lib/features/settings/presentation/settings_controller.dart`, `lib/features/settings/presentation/settings_screen.dart`, `lib/features/strategies/presentation/strategies_screen.dart`, `lib/l10n/app_en.arb`
- Test (app): `test/features/settings/prefs_settings_repository_test.dart`, `test/features/settings/settings_controller_test.dart`, `test/features/settings/settings_screen_test.dart`, `test/features/strategies/strategies_screen_test.dart`

**Interfaces:**
- Consumes: `StrategyParameters.transferCreditLimit` (Task 4); `consolidationTermMonths` and `consolidationFeeBps` (Task 5); `TransferChange` (Task 4).
- Produces:
  - Engine: `kMinConsolidationTermMonths = 6`, `kMaxConsolidationTermMonths = 120`, `kMaxConsolidationFeeBps = 2000`
  - Engine: `StrategyParametersValidationError.{consolidationTermOutOfRange, consolidationFeeOutOfRange, creditLimitNotPositive, creditLimitTooLarge}`
  - `SettingsKeys.{consolidationTermMonths, consolidationFeeBps, transferCreditLimitMinor}`
  - `enum ParameterField { consolidationApr, consolidationTerm, consolidationFee, promoMonths, transferFee, revertApr, creditLimit }`
  - `class ParameterControllers` with a `(StrategyParameters, {required String locale})` constructor, `operator [](ParameterField)`, `StrategyParameters parse({required String locale, required String currencyCode})` and `dispose()`
  - `class ParameterFields extends StatelessWidget` with `({required ParameterControllers controllers, required Map<ParameterField, String> errors, required ValueChanged<ParameterField> onEdited, required String currencyCode})`
  - `Map<ParameterField, String> parameterErrorMessages(AppLocalizations l10n, Set<StrategyParametersValidationError> errors, String locale)`

- [ ] **Step 1: Write the failing engine test**

Append to the `validateStrategyParameters` group in `packages/payoff_engine/test/debt_list_validation_test.dart`:

```dart
    test('checks the consolidation term and fee', () {
      expect(
        validateStrategyParameters(
          const StrategyParameters(
            consolidationTermMonths: kMinConsolidationTermMonths,
            consolidationFeeBps: kMaxConsolidationFeeBps,
          ),
        ),
        isEmpty,
      );
      expect(
        validateStrategyParameters(
          const StrategyParameters(
            consolidationTermMonths: kMaxConsolidationTermMonths + 1,
            consolidationFeeBps: kMaxConsolidationFeeBps + 1,
          ),
        ),
        {
          StrategyParametersValidationError.consolidationTermOutOfRange,
          StrategyParametersValidationError.consolidationFeeOutOfRange,
        },
      );
      expect(
        validateStrategyParameters(
          const StrategyParameters(consolidationTermMonths: 5),
        ),
        {StrategyParametersValidationError.consolidationTermOutOfRange},
      );
    });

    test('an optional credit limit must be positive and not too large', () {
      StrategyParameters limit(int minor) =>
          StrategyParameters(transferCreditLimit: Money(minor, 'GBP'));
      expect(validateStrategyParameters(limit(1)), isEmpty);
      expect(validateStrategyParameters(limit(0)), {
        StrategyParametersValidationError.creditLimitNotPositive,
      });
      expect(validateStrategyParameters(limit(kMaxAmountMinor + 1)), {
        StrategyParametersValidationError.creditLimitTooLarge,
      });
    });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/payoff_engine && dart test test/debt_list_validation_test.dart`
Expected: compilation errors: `kMinConsolidationTermMonths` and the new error values are undefined.

- [ ] **Step 3: Implement the engine validation**

In `packages/payoff_engine/lib/src/validation.dart`, add the constants after `kMaxPromoMonths`:

```dart
/// Accepted consolidation loan terms, in months.
const int kMinConsolidationTermMonths = 6;
const int kMaxConsolidationTermMonths = 120;

/// Highest accepted arrangement fee: 20%.
const int kMaxConsolidationFeeBps = 2000;
```

Replace the error enum:

```dart
enum StrategyParametersValidationError {
  consolidationAprOutOfRange,
  consolidationTermOutOfRange,
  consolidationFeeOutOfRange,
  transferFeeOutOfRange,
  promoMonthsOutOfRange,
  revertAprOutOfRange,
  creditLimitNotPositive,
  creditLimitTooLarge,
}
```

and add these entries to the set in `validateStrategyParameters`:

```dart
  if (p.consolidationTermMonths < kMinConsolidationTermMonths ||
      p.consolidationTermMonths > kMaxConsolidationTermMonths)
    StrategyParametersValidationError.consolidationTermOutOfRange,
  if (p.consolidationFeeBps < 0 ||
      p.consolidationFeeBps > kMaxConsolidationFeeBps)
    StrategyParametersValidationError.consolidationFeeOutOfRange,
  if (p.transferCreditLimit case final limit? when !limit.isPositive)
    StrategyParametersValidationError.creditLimitNotPositive,
  if (p.transferCreditLimit case final limit?
      when limit.minor > kMaxAmountMinor)
    StrategyParametersValidationError.creditLimitTooLarge,
```

Run: `cd packages/payoff_engine && dart test`
Expected: `All tests passed!`

- [ ] **Step 4: Write the failing app tests**

In `test/features/settings/prefs_settings_repository_test.dart`, extend `'saves and loads every field'` so the parameters include the new fields:

```dart
      strategyParameters: StrategyParameters(
        consolidationAprBps: 399,
        consolidationTermMonths: 36,
        consolidationFeeBps: 150,
        transferFeeBps: 250,
        promoMonths: 18,
        revertAprBps: 2290,
        transferCreditLimit: Money(500000, 'USD'),
      ),
```

and add to the `falls back to defaults` group:

```dart
    test('settings saved before v2 load with the new defaults', () async {
      final s = await repositoryWith(
        storedSettings({SettingsKeys.consolidationAprBps: 700}),
      ).load();
      expect(s.strategyParameters.consolidationAprBps, 700);
      expect(s.strategyParameters.consolidationTermMonths, 60);
      expect(s.strategyParameters.consolidationFeeBps, 0);
      expect(s.strategyParameters.transferCreditLimit, isNull);
    });
```

In `test/features/settings/settings_controller_test.dart`, add to the `setCurrency` group:

```dart
    test('rescales the credit limit with the budget', () async {
      await controller().setStrategyParameters(
        const StrategyParameters(transferCreditLimit: Money(12345, 'GBP')),
      );
      await controller().setCurrency('JPY');
      expect(
        (await settings()).strategyParameters.transferCreditLimit,
        const Money(123, 'JPY'),
      );
    });
```

In `test/features/settings/settings_screen_test.dart`, add a helper at the top of `main`. The list builds lazily, so fields low on the screen may not exist until scrolled to:

```dart
  Future<void> enter(WidgetTester tester, String label, String text) async {
    await tester.scrollUntilVisible(field(label), 100);
    await tester.enterText(field(label), text);
  }
```

Then append:

```dart
  testWidgets('saves the loan term, fee and a credit limit', (tester) async {
    final app = await pumpApp(tester, location: Routes.settings);
    await enter(tester, 'Loan term (months)', '36');
    await enter(tester, 'Arrangement fee (% of loan)', '1.5');
    await enter(tester, 'Credit limit (optional)', '5,000');
    await save(tester);
    final p = app.container
        .read(settingsControllerProvider)
        .value!
        .strategyParameters;
    expect(p.consolidationTermMonths, 36);
    expect(p.consolidationFeeBps, 150);
    expect(p.transferCreditLimit, const Money(500000, 'GBP'));
  });

  testWidgets('an empty credit limit means none is set', (tester) async {
    final app = await pumpApp(
      tester,
      location: Routes.settings,
      settings: {SettingsKeys.transferCreditLimitMinor: 500000},
    );
    await tester.scrollUntilVisible(find.text('5000'), 100);
    expect(find.text('5000'), findsOneWidget);
    await enter(tester, 'Credit limit (optional)', '');
    await save(tester);
    expect(
      app.container
          .read(settingsControllerProvider)
          .value!
          .strategyParameters
          .transferCreditLimit,
      isNull,
    );
  });

  testWidgets('shows why a term or limit was rejected', (tester) async {
    await pumpApp(tester, location: Routes.settings);
    await enter(tester, 'Loan term (months)', '3');
    await enter(tester, 'Credit limit (optional)', '0');
    await save(tester);
    await tester.scrollUntilVisible(
      find.text('Enter between 6 and 120 months'),
      -100,
    );
    expect(find.text('Enter between 6 and 120 months'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Enter a limit above zero, or leave it empty'),
      100,
    );
    expect(
      find.text('Enter a limit above zero, or leave it empty'),
      findsOneWidget,
    );
  });
```

Add `import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';` to that file.

In `test/features/strategies/strategies_screen_test.dart`, append:

```dart
  testWidgets('says when the transfer assumes a credit limit', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a')], // 1,000.00 at 19.9%
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.strategies,
    );
    // 1,000.00 plus the 4% fee.
    const note = 'Assumes a £1,040.00 credit limit.';
    await tester.scrollUntilVisible(find.text(note), 100);
    expect(find.text(note), findsOneWidget);
    await tester.tap(find.text('Set yours'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.settings);
  });
```

- [ ] **Step 5: Run them to verify they fail**

Run: `./tool/codegen.sh && flutter test test/features/settings test/features/strategies`
Expected: compilation errors. `SettingsKeys.transferCreditLimitMinor` is undefined, and the switch in `settings_screen.dart` over `StrategyParametersValidationError` is no longer exhaustive.

- [ ] **Step 6: Implement persistence and the currency rescale**

In `lib/features/settings/data/prefs_settings_repository.dart`:
- Add the keys:

```dart
  static const consolidationTermMonths = 'consolidationTermMonths';
  static const consolidationFeeBps = 'consolidationFeeBps';
  static const transferCreditLimitMinor = 'transferCreditLimitMinor';
```

- In `load`, build the parameters as:

```dart
    const d = StrategyParameters();
    final limitMinor = field<int>(SettingsKeys.transferCreditLimitMinor);
    final parameters = StrategyParameters(
      consolidationAprBps:
          field<int>(SettingsKeys.consolidationAprBps) ?? d.consolidationAprBps,
      consolidationTermMonths:
          field<int>(SettingsKeys.consolidationTermMonths) ??
          d.consolidationTermMonths,
      consolidationFeeBps:
          field<int>(SettingsKeys.consolidationFeeBps) ?? d.consolidationFeeBps,
      transferFeeBps:
          field<int>(SettingsKeys.transferFeeBps) ?? d.transferFeeBps,
      promoMonths: field<int>(SettingsKeys.promoMonths) ?? d.promoMonths,
      revertAprBps: field<int>(SettingsKeys.revertAprBps) ?? d.revertAprBps,
      transferCreditLimit: limitMinor == null
          ? null
          : Money(limitMinor, currencyCode),
    );
```

- In `save`, add:

```dart
        SettingsKeys.consolidationTermMonths: p.consolidationTermMonths,
        SettingsKeys.consolidationFeeBps: p.consolidationFeeBps,
        SettingsKeys.transferCreditLimitMinor: p.transferCreditLimit?.minor,
```

In `SettingsController.setCurrency` (`settings_controller.dart`), rescale the limit along with the budget:

```dart
      final fromDigits = currencyDecimalDigits(current.currencyCode);
      final toDigits = currencyDecimalDigits(currencyCode);
      int rescale(int minor) => rescaleMinor(
        minor,
        fromDigits: fromDigits,
        toDigits: toDigits,
      ).clamp(1, kMaxAmountMinor);
      final limit = current.strategyParameters.transferCreditLimit;
      await _save(
        current.copyWith(
          currencyCode: currencyCode,
          // Keep rescaled amounts valid: never zero, never over the limit.
          monthlyBudget: Money(rescale(current.monthlyBudget.minor), currencyCode),
          strategyParameters: current.strategyParameters.copyWith(
            transferCreditLimit: limit == null
                ? null
                : Money(rescale(limit.minor), currencyCode),
          ),
        ),
      );
```

This replaces the existing `budgetMinor` computation and `_save` call in that method.

- [ ] **Step 7: Implement the shared parameter fields and the Settings screen**

Add to `lib/l10n/app_en.arb`:

```json
  "settingsConsolidationTerm": "Loan term (months)",
  "settingsConsolidationFee": "Arrangement fee (% of loan)",
  "settingsCreditLimit": "Credit limit (optional)",
  "settingsCreditLimitHint": "Leave empty to assume every card balance fits",
  "errorConsolidationTermRange": "Enter between {min} and {max} months",
  "@errorConsolidationTermRange": {"placeholders": {"min": {"type": "int"}, "max": {"type": "int"}}},
  "errorConsolidationFeeRange": "Enter a fee between 0 and {max}",
  "@errorConsolidationFeeRange": {"placeholders": {"max": {"type": "String"}}},
  "errorCreditLimitNotPositive": "Enter a limit above zero, or leave it empty",
  "transferLimitAssumed": "Assumes a {limit} credit limit.",
  "@transferLimitAssumed": {"placeholders": {"limit": {"type": "String"}}},
  "setCreditLimit": "Set yours",
```

Create `lib/features/settings/presentation/parameter_fields.dart`:

```dart
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payoff_engine/payoff_engine.dart';

enum ParameterField {
  consolidationApr,
  consolidationTerm,
  consolidationFee,
  promoMonths,
  transferFee,
  revertApr,
  creditLimit,
}

/// Text controllers for every strategy parameter. Settings and the scenario
/// editor both show these fields.
class ParameterControllers {
  ParameterControllers(StrategyParameters p, {required String locale})
    : _controllers = {
        ParameterField.consolidationApr: TextEditingController(
          text: formatPercentInput(p.consolidationAprBps, locale),
        ),
        ParameterField.consolidationTerm: TextEditingController(
          text: '${p.consolidationTermMonths}',
        ),
        ParameterField.consolidationFee: TextEditingController(
          text: formatPercentInput(p.consolidationFeeBps, locale),
        ),
        ParameterField.promoMonths: TextEditingController(
          text: '${p.promoMonths}',
        ),
        ParameterField.transferFee: TextEditingController(
          text: formatPercentInput(p.transferFeeBps, locale),
        ),
        ParameterField.revertApr: TextEditingController(
          text: formatPercentInput(p.revertAprBps, locale),
        ),
        ParameterField.creditLimit: TextEditingController(
          text: switch (p.transferCreditLimit) {
            final limit? => formatAmountInput(limit, locale),
            null => '',
          },
        ),
      };

  final Map<ParameterField, TextEditingController> _controllers;

  TextEditingController operator [](ParameterField field) =>
      _controllers[field]!;

  /// The typed values. Call only after every field's validator passed.
  StrategyParameters parse({
    required String locale,
    required String currencyCode,
  }) {
    String text(ParameterField f) => _controllers[f]!.text;
    final limit = text(ParameterField.creditLimit).trim();
    return StrategyParameters(
      consolidationAprBps: parsePercentBps(
        text(ParameterField.consolidationApr),
        locale,
      )!,
      consolidationTermMonths: parseWholeNumber(
        text(ParameterField.consolidationTerm),
      )!,
      consolidationFeeBps: parsePercentBps(
        text(ParameterField.consolidationFee),
        locale,
      )!,
      promoMonths: parseWholeNumber(text(ParameterField.promoMonths))!,
      transferFeeBps: parsePercentBps(
        text(ParameterField.transferFee),
        locale,
      )!,
      revertAprBps: parsePercentBps(text(ParameterField.revertApr), locale)!,
      transferCreditLimit: limit.isEmpty
          ? null
          : Money(
              parseAmountMinor(
                limit,
                currencyCode: currencyCode,
                locale: locale,
              )!,
              currencyCode,
            ),
    );
  }

  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
  }
}

/// The strategy parameter fields under their headings. [errors] are shown
/// as forced errors; [onEdited] lets the caller clear a field's error when
/// it changes (never at the start of a save).
class ParameterFields extends ConsumerWidget {
  const ParameterFields({
    required this.controllers,
    required this.errors,
    required this.onEdited,
    required this.currencyCode,
    super.key,
  });

  final ParameterControllers controllers;
  final Map<ParameterField, String> errors;
  final ValueChanged<ParameterField> onEdited;
  final String currencyCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final percentError = l10n.errorInvalidPercent(
      formatPercentInput(1990, locale),
    );
    String? percent(String v) =>
        parsePercentBps(v, locale) == null ? percentError : null;
    String? whole(String v) =>
        parseWholeNumber(v) == null ? l10n.errorWholeNumber : null;
    String? optionalAmount(String v) =>
        v.trim().isEmpty ||
            parseAmountMinor(v, currencyCode: currencyCode, locale: locale) !=
                null
        ? null
        : l10n.errorInvalidAmount(
            formatAmountInput(Money(500000, currencyCode), locale),
          );

    Widget field(
      ParameterField f,
      String label,
      String? Function(String) validate, {
      String? helper,
      TextInputType keyboard = const TextInputType.numberWithOptions(
        decimal: true,
      ),
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey(f),
        controller: controllers[f],
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
        validator: (v) => validate(v ?? ''),
        forceErrorText: errors[f],
        onChanged: (_) => onEdited(f),
      ),
    );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(l10n.settingsConsolidation),
        field(
          ParameterField.consolidationApr,
          l10n.settingsConsolidationApr,
          percent,
        ),
        field(
          ParameterField.consolidationTerm,
          l10n.settingsConsolidationTerm,
          whole,
          keyboard: TextInputType.number,
        ),
        field(
          ParameterField.consolidationFee,
          l10n.settingsConsolidationFee,
          percent,
        ),
        heading(l10n.settingsTransfer),
        field(
          ParameterField.promoMonths,
          l10n.settingsPromoMonths,
          whole,
          keyboard: TextInputType.number,
        ),
        field(
          ParameterField.transferFee,
          l10n.settingsTransferFee,
          percent,
        ),
        field(ParameterField.revertApr, l10n.settingsRevertApr, percent),
        field(
          ParameterField.creditLimit,
          l10n.settingsCreditLimit,
          optionalAmount,
          helper: l10n.settingsCreditLimitHint,
        ),
      ],
    );
  }
}

/// Messages for rejected parameters, keyed by the field that shows each.
Map<ParameterField, String> parameterErrorMessages(
  AppLocalizations l10n,
  Set<StrategyParametersValidationError> errors,
  String locale,
) {
  final messages = <ParameterField, String>{};
  for (final e in errors) {
    final (field, message) = switch (e) {
      StrategyParametersValidationError.consolidationAprOutOfRange => (
        ParameterField.consolidationApr,
        l10n.errorRateRange,
      ),
      StrategyParametersValidationError.consolidationTermOutOfRange => (
        ParameterField.consolidationTerm,
        l10n.errorConsolidationTermRange(
          kMinConsolidationTermMonths,
          kMaxConsolidationTermMonths,
        ),
      ),
      StrategyParametersValidationError.consolidationFeeOutOfRange => (
        ParameterField.consolidationFee,
        l10n.errorConsolidationFeeRange(
          formatPercent(kMaxConsolidationFeeBps, locale),
        ),
      ),
      StrategyParametersValidationError.transferFeeOutOfRange => (
        ParameterField.transferFee,
        l10n.errorRateRange,
      ),
      StrategyParametersValidationError.promoMonthsOutOfRange => (
        ParameterField.promoMonths,
        l10n.errorPromoMonthsRange(kMaxPromoMonths),
      ),
      StrategyParametersValidationError.revertAprOutOfRange => (
        ParameterField.revertApr,
        l10n.errorRateRange,
      ),
      StrategyParametersValidationError.creditLimitNotPositive => (
        ParameterField.creditLimit,
        l10n.errorCreditLimitNotPositive,
      ),
      StrategyParametersValidationError.creditLimitTooLarge => (
        ParameterField.creditLimit,
        l10n.errorTooLarge,
      ),
    };
    messages[field] = message;
  }
  return messages;
}
```

Replace `_SettingsForm` and `_SettingsFormState` in `lib/features/settings/presentation/settings_screen.dart`, and delete the file's `_Field` enum:

```dart
class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings, super.key});

  final AppSettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _budget;
  late final ParameterControllers _parameters;
  String? _budgetError;
  Map<ParameterField, String> _parameterErrors = const {};

  @override
  void initState() {
    super.initState();
    final locale = ref.read(formatLocaleProvider);
    _budget = TextEditingController(
      text: formatAmountInput(widget.settings.monthlyBudget, locale),
    );
    _parameters = ParameterControllers(
      widget.settings.strategyParameters,
      locale: locale,
    );
  }

  @override
  void dispose() {
    _budget.dispose();
    _parameters.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final code = widget.settings.currencyCode;
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
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              key: const ValueKey('budget'),
              controller: _budget,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.settingsBudget,
                border: const OutlineInputBorder(),
              ),
              validator: (v) =>
                  parseAmountMinor(
                        v ?? '',
                        currencyCode: code,
                        locale: locale,
                      ) ==
                      null
                  ? l10n.errorInvalidAmount(
                      formatAmountInput(Money(30000, code), locale),
                    )
                  : null,
              forceErrorText: _budgetError,
              onChanged: (_) {
                if (_budgetError != null) setState(() => _budgetError = null);
              },
            ),
          ),
          ParameterFields(
            controllers: _parameters,
            errors: _parameterErrors,
            currencyCode: code,
            onEdited: (f) {
              if (_parameterErrors.containsKey(f)) {
                setState(() => _parameterErrors = {..._parameterErrors}..remove(f));
              }
            },
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: Text(l10n.save)),
          if (ref.watch(privacyOptionsRequiredProvider).value ?? false)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(l10n.privacyChoices),
              subtitle: Text(l10n.privacyChoicesHint),
              onTap: () => runGuarded(
                context,
                () => ref.read(adsServiceProvider).showPrivacyOptions(),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    // A field rejected last time keeps its message until it is edited.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final locale = ref.read(formatLocaleProvider);
    final code = widget.settings.currencyCode;
    final budgetMinor = parseAmountMinor(
      _budget.text,
      currencyCode: code,
      locale: locale,
    )!;
    final parameters = _parameters.parse(locale: locale, currencyCode: code);
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
    setState(() {
      _budgetError = budgetErrors.contains(BudgetValidationError.notPositive)
          ? l10n.errorBudgetNotPositive
          : budgetErrors.contains(BudgetValidationError.tooLarge)
          ? l10n.errorTooLarge
          : null;
      _parameterErrors = parameterErrorMessages(l10n, parameterErrors, locale);
    });
    if (budgetErrors.isEmpty && parameterErrors.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSaved)));
    }
  }
}
```

Add `import 'package:debt_destroyer/features/settings/presentation/parameter_fields.dart';` to the screen.

The existing tests find fields by label (`'Monthly budget'`, `'Interest-free months'` and so on), and those labels are unchanged.

- [ ] **Step 8: Show the assumed limit on the transfer card**

In `_FeasibleDetails.build` (`strategies_screen.dart`), add this as the last child of the `Column`:

```dart
        if (plan.change case TransferChange(
          limitAssumed: true,
          :final creditLimit,
        ))
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.transferLimitAssumed(formatMoney(creditLimit, locale)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () => context.push(Routes.settings),
                child: Text(l10n.setCreditLimit),
              ),
            ],
          ),
```

- [ ] **Step 9: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test && (cd packages/payoff_engine && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && dart test)`
Expected: all green.

- [ ] **Step 10: Commit**

```bash
git add packages/payoff_engine lib test
git commit -m "feat(settings): loan term, arrangement fee and transfer credit limit"
```

---

### Task 7: Schema 2: promo columns, scenarios table, promo dates

**Files:**
- Create: `lib/features/debts/domain/promo_dates.dart`
- Modify: `lib/features/debts/data/app_database.dart`, `lib/features/debts/data/drift_debt_repository.dart`, `lib/app/dependencies.dart`
- Generated and committed: `drift_schemas/app_database/drift_schema_v2.json`, `lib/features/debts/data/app_database.steps.dart`, `test/drift/app_database/generated/*`
- Test: `test/features/debts/promo_dates_test.dart` (new), `test/features/debts/drift_debt_repository_test.dart`, `test/drift/app_database/migration_test.dart` (generated, then edited)

**Interfaces:**
- Consumes: `Promo`, `Debt.promo` (Task 1).
- Produces:
  - `int yearMonthOf(DateTime date)`
  - `int promoMonthsLeft(int endYearMonth, DateTime now)`
  - `int promoEndYearMonth(int months, DateTime now)`
  - Drift: the `debts` table gains `promoAprBps` and `promoEndsYearMonth` (nullable ints)
  - The `ScenarioRows` table (SQL name `scenarios`, data class `ScenarioRow`), with columns `id`, `name`, `monthlyBudgetMinor`, `consolidationAprBps`, `consolidationTermMonths`, `consolidationFeeBps`, `transferFeeBps`, `promoMonths`, `revertAprBps`, `transferCreditLimitMinor` (nullable) and `createdAt`
  - `schemaVersion == 2`
  - `DriftDebtRepository(db, now: …)` uses `now` for promo months

- [ ] **Step 1: Write the failing tests**

Create `test/features/debts/promo_dates_test.dart`:

```dart
import 'package:debt_destroyer/features/debts/domain/promo_dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sep2026 = DateTime(2026, 9, 24);

  test('a calendar month as yyyymm', () {
    expect(yearMonthOf(sep2026), 202609);
  });

  test('months left counts this month and the last one', () {
    expect(promoMonthsLeft(202609, sep2026), 1);
    expect(promoMonthsLeft(202703, sep2026), 7);
    expect(promoMonthsLeft(202608, sep2026), 0); // ended last month
  });

  test('the end month for a number of months left', () {
    expect(promoEndYearMonth(1, sep2026), 202609);
    expect(promoEndYearMonth(4, sep2026), 202612);
    expect(promoEndYearMonth(5, sep2026), 202701);
    expect(promoEndYearMonth(7, sep2026), 202703);
  });

  test('the two conversions round-trip', () {
    for (var months = 1; months <= 120; months++) {
      expect(
        promoMonthsLeft(promoEndYearMonth(months, sep2026), sep2026),
        months,
      );
    }
  });
}
```

Append to `test/features/debts/drift_debt_repository_test.dart`, inside `main`:

```dart
  group('promotional rates', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 9, 24);
      repo = DriftDebtRepository(db, now: () => now);
    });

    test('stores the end month and reads back the months left', () async {
      await repo.add(
        testDebt(id: 'a', promo: const Promo(aprBps: 0, months: 7)),
      );
      final row = await db.select(db.debtRows).getSingle();
      expect(row.promoAprBps, 0);
      expect(row.promoEndsYearMonth, 202703);
      expect(
        (await repo.loadAll('GBP')).single.promo,
        const Promo(aprBps: 0, months: 7),
      );

      now = DateTime(2027, 1, 5);
      expect(
        (await repo.loadAll('GBP')).single.promo,
        const Promo(aprBps: 0, months: 3),
      );
    });

    test('a promo that has ended reads back as none', () async {
      await repo.add(
        testDebt(id: 'a', promo: const Promo(aprBps: 0, months: 1)),
      );
      now = DateTime(2026, 10, 1);
      final debt = (await repo.loadAll('GBP')).single;
      expect(debt.promo, isNull);
      // Never 0 or negative months, which the engine would reject.
      expect(validateDebt(debt), isEmpty);
    });

    test('saving a debt without a promo clears it', () async {
      final withPromo = testDebt(
        id: 'a',
        promo: const Promo(aprBps: 0, months: 7),
      );
      await repo.add(withPromo);
      await repo.update(withPromo.copyWith(promo: null));
      final row = await db.select(db.debtRows).getSingle();
      expect(row.promoAprBps, isNull);
      expect(row.promoEndsYearMonth, isNull);
    });
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/debts/promo_dates_test.dart test/features/debts/drift_debt_repository_test.dart`
Expected: compilation errors: `promo_dates.dart` doesn't exist, and `promoAprBps` is not a column.

- [ ] **Step 3: Implement the promo dates**

Create `lib/features/debts/domain/promo_dates.dart`:

```dart
/// Promotions are stored by their last calendar month (`yyyymm`) and handed
/// to the engine as "months left, counting this one", so a stored promo
/// shortens by itself as time passes.
library;

/// [date]'s calendar month as `yyyymm`, e.g. September 2026 → 202609.
int yearMonthOf(DateTime date) => date.year * 100 + date.month;

/// Months from [now]'s month to [endYearMonth], counting both: a promo that
/// ends this month has 1 month left. Zero or less means it has ended.
int promoMonthsLeft(int endYearMonth, DateTime now) =>
    _index(endYearMonth) - _index(yearMonthOf(now)) + 1;

/// The last month of a promo with [months] left, counting from [now].
int promoEndYearMonth(int months, DateTime now) {
  final index = _index(yearMonthOf(now)) + months - 1;
  return (index ~/ 12) * 100 + index % 12 + 1;
}

/// Months since year 0, so months can be subtracted.
int _index(int yearMonth) => (yearMonth ~/ 100) * 12 + yearMonth % 100 - 1;
```

- [ ] **Step 4: Add the columns and the scenarios table**

In `lib/features/debts/data/app_database.dart`, add to `DebtRows` after `allowsOverpayment`:

```dart
  /// Promotional rate, if any; null when there is none.
  IntColumn get promoAprBps => integer().nullable()();

  /// Last month of the promotion as `yyyymm` (see promo_dates.dart).
  IntColumn get promoEndsYearMonth => integer().nullable()();
```

Add the table:

```dart
/// Saved what-if scenarios: a budget and strategy settings applied to the
/// one real debt list. Money is in minor units of the app-wide currency.
@DataClassName('ScenarioRow')
class ScenarioRows extends Table {
  @override
  String get tableName => 'scenarios';

  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get monthlyBudgetMinor => integer()();
  IntColumn get consolidationAprBps => integer()();
  IntColumn get consolidationTermMonths => integer()();
  IntColumn get consolidationFeeBps => integer()();
  IntColumn get transferFeeBps => integer()();
  IntColumn get promoMonths => integer()();
  IntColumn get revertAprBps => integer()();
  IntColumn get transferCreditLimitMinor => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

Change the annotation to `@DriftDatabase(tables: [DebtRows, AppMeta, ScenarioRows])` and `schemaVersion` to `2`.

- [ ] **Step 5: Generate the schema and migration scaffolding**

Run:
```bash
./tool/codegen.sh
dart run drift_dev make-migrations
```
Expected:
- `drift_schemas/app_database/drift_schema_v2.json`
- `lib/features/debts/data/app_database.steps.dart`
- `test/drift/app_database/generated/{schema.dart,schema_v1.dart,schema_v2.dart}`
- `test/drift/app_database/migration_test.dart`

- [ ] **Step 6: Write the migration**

The generated `app_database.steps.dart` declares `Schema2` with one field per table, named after the SQL table name (`debts`, `scenarios`), and column getters with their Dart names. If its names differ, use the generated ones.

In `app_database.dart`:
- Add `import 'package:debt_destroyer/features/debts/data/app_database.steps.dart';`.
- Add to `AppDatabase`:

```dart
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.addColumn(schema.debts, schema.debts.promoAprBps);
        await m.addColumn(schema.debts, schema.debts.promoEndsYearMonth);
        await m.createTable(schema.scenarios);
      },
    ),
  );
```

Replace the generated `test/drift/app_database/migration_test.dart` with the version below. Its schema-validation loop is what `make-migrations` generates; the data test is filled in. If a generated class or column name differs, use what `generated/schema_v1.dart` declares, and keep the assertions.

```dart
// ignore_for_file: unused_local_variable, unused_import
import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  test('v1 debts survive the upgrade with no promo', () async {
    final created = DateTime(2026, 9, 1);
    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.debts,
          v1.DebtsCompanion.insert(
            id: 'a',
            name: 'Visa',
            type: 'creditCard',
            balanceMinor: 123456,
            aprBps: 1990,
            minPaymentPercentBps: 300,
            minPaymentFloorMinor: 2500,
            allowsOverpayment: true,
            sortIndex: 0,
            createdAt: created,
            updatedAt: created,
          ),
        );
      },
      validateItems: (newDb) async {
        final row = await newDb.select(newDb.debts).getSingle();
        expect(row.name, 'Visa');
        expect(row.balanceMinor, 123456);
        expect(row.promoAprBps, isNull);
        expect(row.promoEndsYearMonth, isNull);
        expect(await newDb.select(newDb.scenarios).get(), isEmpty);
      },
    );
  });
}
```

- [ ] **Step 7: Map promos in the repository**

In `lib/features/debts/data/drift_debt_repository.dart`, import `promo_dates.dart`. Then extend `_toDebt` (add after `allowsOverpayment`):

```dart
    promo: switch ((row.promoAprBps, row.promoEndsYearMonth)) {
      (final int apr, final int end)
          when promoMonthsLeft(end, _now()) >= 1 =>
        Promo(aprBps: apr, months: promoMonthsLeft(end, _now())),
      _ => null, // none, or it has ended
    },
```

and `_toCompanion`:

```dart
    promoAprBps: Value(debt.promo?.aprBps),
    promoEndsYearMonth: Value(switch (debt.promo) {
      final promo? => promoEndYearMonth(promo.months, _now()),
      null => null,
    }),
```

In `lib/app/dependencies.dart`, give the repository the app clock so tests control promo dates. Import `package:debt_destroyer/core/l10n.dart`, then:

```dart
@Riverpod(keepAlive: true)
DebtRepository debtRepository(Ref ref) => DriftDebtRepository(
  ref.watch(appDatabaseProvider),
  now: ref.watch(clockProvider),
);
```

- [ ] **Step 8: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`
Expected: all green, including `test/drift/app_database/migration_test.dart`.

- [ ] **Step 9: Commit**

```bash
git add lib test drift_schemas
git commit -m "feat(data): schema 2 with promotional rates and a scenarios table"
```

---

### Task 8: Debt form: loan payment, minimums only, promotional rate

**Files:**
- Modify: `lib/features/debts/presentation/debt_form_screen.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/debts/debt_form_test.dart`

**Interfaces:**
- Consumes: `defaultAllowsOverpayment`, `Promo`, `kMaxPromoMonths` (Task 1); `promoEndYearMonth`, `promoMonthsLeft` (Task 7); `clockProvider` (`lib/core/l10n.dart`).
- Produces: widget keys `ValueKey('minimumsOnly')`, `ValueKey('promo')` and `ValueKey('promoUntil')`; field labels "Monthly payment", "Promotional rate (APR %)" and "Until the end of".

- [ ] **Step 1: Write the failing tests**

In `test/features/debts/debt_form_test.dart`:
- In `'adds a debt with exactly the amounts typed'`, add `expect(saved.promo, isNull);`.
- Append:

```dart
  testWidgets('a loan asks for one monthly payment', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await chooseType(tester, 'Loan');
    expect(field('Minimum payment (% of balance)'), findsNothing);
    await tester.enterText(field('Name'), 'Car');
    await tester.enterText(field('Balance'), '3000');
    await tester.enterText(field('Interest rate (APR %)'), '6.5');
    await tester.enterText(field('Monthly payment'), '150');
    await save(tester);
    final saved = app.repository.stored.single;
    expect(saved.minPaymentPercentBps, 0);
    expect(saved.minPaymentFloor.minor, 15000);
    expect(saved.allowsOverpayment, isTrue);
  });

  testWidgets('a loan saved with a percentage keeps both minimum fields', (
    tester,
  ) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a', type: DebtType.loan)],
      location: Routes.editDebt('a'),
    );
    expect(field('Minimum payment (% of balance)'), findsOneWidget);
    expect(field('Minimum payment (at least)'), findsOneWidget);
  });

  testWidgets('explains minimums only for a student loan', (tester) async {
    await pumpApp(tester, location: Routes.newDebt);
    await chooseType(tester, 'Student loan');
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('minimumsOnly')),
    );
    expect(toggle.value, isTrue);
    expect(find.textContaining('written off'), findsOneWidget);
  });

  Future<void> turnOnPromo(WidgetTester tester, String rate) async {
    await tester.ensureVisible(find.byKey(const ValueKey('promo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('promo')));
    await tester.pumpAndSettle();
    await tester.enterText(field('Promotional rate (APR %)'), rate);
  }

  testWidgets('saves a promotional rate until a chosen month', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester);
    await turnOnPromo(tester, '0');
    await tester.ensureVisible(find.byKey(const ValueKey('promoUntil')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('promoUntil')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('March 2027').last);
    await tester.pumpAndSettle();
    await save(tester);
    // The test clock is 24 Sep 2026: September to March is 7 months.
    expect(
      app.repository.stored.single.promo,
      const Promo(aprBps: 0, months: 7),
    );
  });

  testWidgets('shows an existing promo\'s end month', (tester) async {
    await pumpApp(
      tester,
      debts: [
        testDebt(id: 'a', promo: const Promo(aprBps: 0, months: 7)),
      ],
      location: Routes.editDebt('a'),
    );
    expect(find.text('March 2027'), findsOneWidget);
  });

  testWidgets('rejects a promotional rate over 100%', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester);
    await turnOnPromo(tester, '150');
    await save(tester);
    expect(find.text('Enter a rate between 0 and 100'), findsOneWidget);
    expect(app.repository.stored, isEmpty);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/debts/debt_form_test.dart`
Expected: the new tests FAIL. The finders for `'Monthly payment'` and `ValueKey('minimumsOnly')` find nothing.

- [ ] **Step 3: Implement**

Replace in `lib/l10n/app_en.arb`: remove `fieldAllowsOverpayment` and `fieldAllowsOverpaymentHint`, and add:

```json
  "fieldMonthlyPayment": "Monthly payment",
  "fieldMinimumsOnly": "Minimums only",
  "fieldMinimumsOnlyHint": "Never put extra money towards this debt",
  "fieldMinimumsOnlyNote": "Usually best for this kind of debt: student loans are written off after a set time, and mortgages are usually the cheapest debt you have.",
  "fieldPromo": "Promotional rate",
  "fieldPromoHint": "A lower rate for a limited time, such as a 0% deal",
  "fieldPromoApr": "Promotional rate (APR %)",
  "fieldPromoUntil": "Until the end of",
```

In `lib/features/debts/presentation/debt_form_screen.dart`, add these imports: `package:debt_destroyer/features/debts/domain/promo_dates.dart` and `package:intl/intl.dart`. Then:

1. Change the field enum to `enum _Field { name, balance, apr, minPercent, minFloor, promoApr }`.
2. Add state and a getter to `_DebtFormState`:

```dart
  late bool _hasPromo;
  late int _promoUntil;

  /// Loans are entered as one fixed monthly payment, unless an existing
  /// loan was saved with a percentage minimum.
  bool get _fixedPayment =>
      _type == DebtType.loan &&
      (widget.existing?.minPaymentPercentBps ?? 0) == 0;
```

3. In `initState`, add the promo controller to the map, and initialise the promo after `_allowsOverpayment`:

```dart
      _Field.promoApr: TextEditingController(
        text: percent(d?.promo?.aprBps ?? 0),
      ),
```

```dart
    _hasPromo = d?.promo != null;
    _promoUntil = promoEndYearMonth(
      d?.promo?.months ?? 12,
      ref.read(clockProvider)(),
    );
```

4. In `build`, compute the offered months after `example`:

```dart
    final now = ref.watch(clockProvider)();
    final promoEnds = [
      for (var m = 1; m <= kMaxPromoMonths; m++) promoEndYearMonth(m, now),
    ];
```

5. Replace the two minimum fields and the `SwitchListTile` with:

```dart
          if (_fixedPayment)
            field(
              _Field.minFloor,
              l10n.fieldMonthlyPayment,
              keyboard: numberKeyboard,
              validator: (v) => amount(v, required: true),
            )
          else ...[
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
          ],
          SwitchListTile(
            key: const ValueKey('minimumsOnly'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.fieldMinimumsOnly),
            subtitle: Text(
              defaultAllowsOverpayment(_type)
                  ? l10n.fieldMinimumsOnlyHint
                  : l10n.fieldMinimumsOnlyNote,
            ),
            value: !_allowsOverpayment,
            onChanged: (v) => setState(() => _allowsOverpayment = !v),
          ),
          SwitchListTile(
            key: const ValueKey('promo'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.fieldPromo),
            subtitle: Text(l10n.fieldPromoHint),
            value: _hasPromo,
            onChanged: (v) => setState(() => _hasPromo = v),
          ),
          if (_hasPromo) ...[
            field(
              _Field.promoApr,
              l10n.fieldPromoApr,
              keyboard: numberKeyboard,
              validator: (v) => percent(v, required: true),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<int>(
                key: const ValueKey('promoUntil'),
                initialValue: _promoUntil,
                decoration: InputDecoration(
                  labelText: l10n.fieldPromoUntil,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final end in promoEnds)
                    DropdownMenuItem(
                      value: end,
                      child: Text(
                        DateFormat.yMMMM(
                          locale,
                        ).format(DateTime(end ~/ 100, end % 100)),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _promoUntil = v!),
              ),
            ),
          ],
```

6. In `_save`, build the debt with the new fields:

```dart
    final now = ref.read(clockProvider)();
    final debt = Debt(
      id: widget.existing?.id ?? '',
      name: _controllers[_Field.name]!.text.trim(),
      type: _type,
      balance: Money(amount(_Field.balance), code),
      aprBps: percent(_Field.apr),
      minPaymentPercentBps: _fixedPayment ? 0 : percent(_Field.minPercent),
      minPaymentFloor: Money(amount(_Field.minFloor), code),
      allowsOverpayment: _allowsOverpayment,
      promo: _hasPromo
          ? Promo(
              aprBps: percent(_Field.promoApr),
              months: promoMonthsLeft(_promoUntil, now),
            )
          : null,
    );
```

7. In `_showErrors`, replace the two promo cases from Task 1:

```dart
        case DebtValidationError.promoAprOutOfRange:
          byField[_Field.promoApr] = l10n.errorRateRange;
        case DebtValidationError.promoMonthsOutOfRange:
          break; // the month list only offers 1 to kMaxPromoMonths months
```

- [ ] **Step 4: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "feat(debts): loan payment, minimums only and promotional rate in the debt form"
```

---

### Task 9: The minimums-only baseline and savings on Strategies

**Files:**
- Create: `lib/features/strategies/domain/savings.dart`
- Modify: `lib/features/strategies/presentation/plans_providers.dart`, `lib/features/strategies/presentation/strategies_screen.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/strategies/savings_test.dart` (new), `test/features/strategies/plans_providers_test.dart`, `test/features/strategies/strategies_screen_test.dart`, `test/helpers/pump_app.dart`

**Interfaces:**
- Consumes: `calculateBaseline`, `StrategyId.minimumsOnly` (Task 3).
- Produces:
  - `typedef PlanSet = ({List<PayoffResult> ranked, PayoffResult baseline})`
  - `PlanSet calculatePlanSet(List<Debt> debts, Money monthlyBudget, StrategyParameters parameters)`
  - `typedef PlanCalculator = Future<PlanSet> Function(List<Debt>, Money, StrategyParameters)`
  - `plansProvider` gives `Future<PlanSet>`, with `ranked` sorted by `rankResults`
  - `planProvider(StrategyId.minimumsOnly)` returns the baseline
  - `typedef Savings = ({Money money, int months})` and `Savings? savingsAgainst(PayoffPlan plan, PayoffResult baseline)`
  - Widget key `ValueKey('baseline')`

- [ ] **Step 1: Write the failing tests**

Create `test/features/strategies/savings_test.dart`:

```dart
import 'package:debt_destroyer/features/strategies/domain/savings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  const gbp0 = Money.zero('GBP');

  PayoffPlan plan({required int paid, required int months}) => PayoffPlan(
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
  );

  PayoffResult baseline({required int paid, required int months}) =>
      PayoffResult.feasible(
        strategyId: StrategyId.minimumsOnly,
        plan: plan(paid: paid, months: months),
      );

  test('money and months saved against the baseline', () {
    expect(
      savingsAgainst(
        plan(paid: 1000, months: 4),
        baseline(paid: 1500, months: 60),
      ),
      (money: const Money(500, 'GBP'), months: 56),
    );
  });

  test('nothing when the plan costs the same or more', () {
    expect(
      savingsAgainst(
        plan(paid: 1500, months: 4),
        baseline(paid: 1500, months: 60),
      ),
      isNull,
    );
    expect(
      savingsAgainst(
        plan(paid: 1600, months: 4),
        baseline(paid: 1500, months: 60),
      ),
      isNull,
    );
  });

  test('never negative months', () {
    expect(
      savingsAgainst(
        plan(paid: 1000, months: 70),
        baseline(paid: 1500, months: 60),
      )?.months,
      0,
    );
  });

  test('nothing when the baseline does not clear', () {
    expect(
      savingsAgainst(
        plan(paid: 1000, months: 4),
        const PayoffResult.neverClears(strategyId: StrategyId.minimumsOnly),
      ),
      isNull,
    );
  });
}
```

In `test/features/strategies/plans_providers_test.dart`:
- Make `settledPlans()` return `Future<PlanSet>`.
- Read `.ranked` wherever a list was used: `plans.ranked`, `avalanche(before.ranked)`, and so on.
- Append:

```dart
  test('includes the minimums-only baseline', () async {
    await container
        .read(debtActionsProvider.notifier)
        .add(testDebt(id: ''));
    final plans = await settledPlans();
    expect(plans.baseline.strategyId, StrategyId.minimumsOnly);
    expect((plans.baseline as Feasible).plan.monthsToClear, 62);
  });

  test('plan finds the baseline by id', () async {
    container.listen(planProvider(StrategyId.minimumsOnly), (_, _) {});
    final result = await container.read(
      planProvider(StrategyId.minimumsOnly).future,
    );
    expect(result.strategyId, StrategyId.minimumsOnly);
  });
```

In `test/helpers/pump_app.dart`, change the calculator override:

```dart
        planCalculatorProvider.overrideWithValue(
          (debts, budget, parameters) async =>
              calculatePlanSet(debts, budget, parameters),
        ),
```

In `test/features/strategies/strategies_screen_test.dart`, append:

```dart
  testWidgets('compares each plan with paying only the minimums', (
    tester,
  ) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')], // 1,000.00 at 19.9%, min 3% or 25.00
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.strategies,
    );
    expect(
      find.text('Minimums only: 5 years 2 months · £587.88 interest'),
      findsOneWidget,
    );
    // Highest interest first: 1,037.82 over 4 months against 1,587.88 over 62.
    await tester.scrollUntilVisible(
      find.text('Saves £550.06 · 4 years 10 months sooner than minimums only'),
      100,
    );
    expect(
      find.text('Saves £550.06 · 4 years 10 months sooner than minimums only'),
      findsWidgets,
    );
  });

  testWidgets('shows no savings for a plan that costs more', (tester) async {
    await pumpApp(
      tester,
      // 0%, and the minimum is the whole budget: nothing can beat it.
      debts: [
        testDebt(
          id: 'a',
          aprBps: 0,
          minPaymentPercentBps: 0,
          minPaymentFloor: 25000,
        ),
      ],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    expect(find.text('Minimums only: 4 months · £0.00 interest'), findsOneWidget);
    expect(find.textContaining('Saves'), findsNothing);
    expect(find.textContaining('-£'), findsNothing);
  });

  testWidgets('says when minimums alone never clear the debts', (
    tester,
  ) async {
    await pumpApp(
      tester,
      debts: [simple], // no minimum payment at all
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    expect(
      find.text('Paying only the minimums would never clear these debts.'),
      findsOneWidget,
    );
    expect(
      find.text('Clears your debts; minimums alone never would'),
      findsWidgets,
    );
  });

  testWidgets('opens the baseline plan', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.strategies,
    );
    await tester.tap(find.byKey(const ValueKey('baseline')));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.plan(StrategyId.minimumsOnly));
    expect(find.text('Debt-free in 5 years 2 months'), findsOneWidget);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `./tool/codegen.sh && flutter test test/features/strategies`
Expected: compilation errors: `savings.dart`, `PlanSet` and `calculatePlanSet` are undefined.

- [ ] **Step 3: Implement**

Create `lib/features/strategies/domain/savings.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';

/// What a plan saves compared with paying only the minimums.
typedef Savings = ({Money money, int months});

/// [plan]'s savings against [baseline], or null when the baseline doesn't
/// clear the debts or [plan] costs no less. Months never go below zero.
Savings? savingsAgainst(PayoffPlan plan, PayoffResult baseline) {
  if (baseline is! Feasible) return null;
  final money = baseline.plan.totalPaid - plan.totalPaid;
  if (!money.isPositive) return null;
  final months = baseline.plan.monthsToClear - plan.monthsToClear;
  return (money: money, months: months > 0 ? months : 0);
}
```

In `lib/features/strategies/presentation/plans_providers.dart`, replace the calculator typedef, the providers and the isolate entry point:

```dart
/// The ranked strategies and the minimums-only baseline they are compared
/// with.
typedef PlanSet = ({List<PayoffResult> ranked, PayoffResult baseline});

/// Runs every standard strategy and the baseline. The app computes in a
/// background isolate; widget tests substitute a synchronous version
/// because isolates don't run under the test clock.
typedef PlanCalculator =
    Future<PlanSet> Function(
      List<Debt> debts,
      Money monthlyBudget,
      StrategyParameters parameters,
    );

/// Every standard strategy plus the baseline. Pure, so it can run in an
/// isolate.
PlanSet calculatePlanSet(
  List<Debt> debts,
  Money monthlyBudget,
  StrategyParameters parameters,
) => (
  ranked: calculateAll(
    debts: debts,
    monthlyBudget: monthlyBudget,
    parameters: parameters,
  ),
  baseline: calculateBaseline(debts: debts, monthlyBudget: monthlyBudget),
);

@Riverpod(keepAlive: true)
PlanCalculator planCalculator(Ref ref) =>
    (debts, budget, parameters) =>
        compute(_calculatePlanSet, (debts, budget, parameters));

/// Every strategy's result for the current debts and settings, ranked by
/// [rankResults], and the baseline. Recalculated whenever either changes.
@riverpod
Future<PlanSet> plans(Ref ref) async {
  final debts = await ref.watch(debtsProvider.future);
  final settings = await ref.watch(settingsControllerProvider.future);
  final set = await ref.watch(planCalculatorProvider)(
    debts,
    settings.monthlyBudget,
    settings.strategyParameters,
  );
  return (ranked: rankResults(set.ranked), baseline: set.baseline);
}

/// One strategy's result, looked up by id (the baseline included).
@riverpod
Future<PayoffResult> plan(Ref ref, StrategyId strategyId) async {
  final set = await ref.watch(plansProvider.future);
  if (strategyId == StrategyId.minimumsOnly) return set.baseline;
  return set.ranked.firstWhere((r) => r.strategyId == strategyId);
}

PlanSet _calculatePlanSet((List<Debt>, Money, StrategyParameters) input) =>
    calculatePlanSet(input.$1, input.$2, input.$3);
```

Add to `lib/l10n/app_en.arb`:

```json
  "baselineSummary": "Minimums only: {duration} · {interest} interest",
  "@baselineSummary": {"placeholders": {"duration": {"type": "String"}, "interest": {"type": "String"}}},
  "baselineNeverClears": "Paying only the minimums would never clear these debts.",
  "savesVersusMinimums": "Saves {amount} · {duration} sooner than minimums only",
  "@savesVersusMinimums": {"placeholders": {"amount": {"type": "String"}, "duration": {"type": "String"}}},
  "savesMoneyVersusMinimums": "Saves {amount} compared with minimums only",
  "@savesMoneyVersusMinimums": {"placeholders": {"amount": {"type": "String"}}},
  "clearsUnlikeMinimums": "Clears your debts; minimums alone never would",
```

In `lib/features/strategies/presentation/strategies_screen.dart`, import `savings.dart`, then:

1. Replace the `AsyncData` arm of the body switch:

```dart
        (AsyncData(:final value), final StrategyParameters parameters) =>
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _BaselineLine(value.baseline),
              for (final (i, result) in value.ranked.indexed)
                _StrategyCard(
                  result: result,
                  baseline: value.baseline,
                  parameters: parameters,
                  cheapest: i == 0 && result is Feasible,
                ),
            ],
          ),
```

2. Add the baseline line widget:

```dart
/// The minimums-only reference every strategy is measured against.
class _BaselineLine extends ConsumerWidget {
  const _BaselineLine(this.baseline);

  final PayoffResult baseline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final text = switch (baseline) {
      Feasible(:final plan) when plan.monthsToClear > 0 => l10n.baselineSummary(
        formatDuration(l10n, plan.monthsToClear),
        formatMoney(plan.totalInterest, locale),
      ),
      NeverClears() => l10n.baselineNeverClears,
      _ => null, // infeasible: every card already says so
    };
    if (text == null) return const SizedBox.shrink();
    final opens = baseline is Feasible;
    return ListTile(
      key: const ValueKey('baseline'),
      leading: const Icon(Icons.hourglass_bottom),
      title: Text(text),
      trailing: opens ? const Icon(Icons.chevron_right) : null,
      onTap: opens
          ? () => context.push(Routes.plan(StrategyId.minimumsOnly))
          : null,
    );
  }
}
```

3. Give `_StrategyCard` a `required this.baseline` field (`final PayoffResult baseline;`), and pass it on: `Feasible(:final plan) => _FeasibleDetails(plan: plan, baseline: baseline, locale: locale),`.

4. Give `_FeasibleDetails` a `required this.baseline` field (`final PayoffResult baseline;`). Add this child after the total-paid `Text`, before the transfer-limit row from Task 6:

```dart
        if (_savingsText(l10n) case final text?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
```

Then add the method:

```dart
  String? _savingsText(AppLocalizations l10n) {
    if (baseline is NeverClears) return l10n.clearsUnlikeMinimums;
    final savings = savingsAgainst(plan, baseline);
    if (savings == null) return null;
    final amount = formatMoney(savings.money, locale);
    return savings.months > 0
        ? l10n.savesVersusMinimums(
            amount,
            formatDuration(l10n, savings.months),
          )
        : l10n.savesMoneyVersusMinimums(amount);
  }
```

- [ ] **Step 4: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "feat(strategies): minimums-only baseline and what each plan saves"
```

---

### Task 10: "Pay £X more a month" slider

**Files:**
- Create: `lib/features/strategies/domain/extra_payment.dart`
- Modify: `lib/features/strategies/presentation/plans_providers.dart`, `lib/features/strategies/presentation/strategies_screen.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/strategies/extra_payment_test.dart` (new), `test/features/strategies/plans_providers_test.dart`, `test/features/strategies/strategies_screen_test.dart`

**Interfaces:**
- Consumes: `PlanSet`, `plansProvider` (Task 9); `currencyDecimalDigits`, `rescaleMinor` (`lib/core/currency.dart`).
- Produces:
  - `int extraPaymentStepMinor(Money budget)`
  - `extraPaymentProvider`, a keep-alive `Notifier<int>` in minor units with `set(int minor)`. It resets to 0 when the currency changes.
  - `plansProvider` uses `budget + min(extra, budget)`
  - Widget key `ValueKey('payMore')`

- [ ] **Step 1: Write the failing tests**

Create `test/features/strategies/extra_payment_test.dart`:

```dart
import 'package:debt_destroyer/features/strategies/domain/extra_payment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  test('about 60 round steps across the budget', () {
    expect(extraPaymentStepMinor(const Money(30000, 'GBP')), 500); // £5
    expect(extraPaymentStepMinor(const Money(100000, 'GBP')), 2000); // £20
    expect(extraPaymentStepMinor(const Money(1234500, 'GBP')), 50000); // £500
  });

  test('never below one major unit', () {
    expect(extraPaymentStepMinor(const Money(5000, 'GBP')), 100); // £1
  });

  test('works in currencies without decimals', () {
    expect(extraPaymentStepMinor(const Money(30000, 'JPY')), 500); // ¥500
  });
}
```

Append to `test/features/strategies/plans_providers_test.dart`. All three tests are needed: the Review Focus has items 1 and 2.

```dart
  group('extra payment', () {
    // 3,000.00 at 0% with no minimum; the default budget is 300.00.
    Debt interestFree() => testDebt(
      id: '',
      balance: 300000,
      aprBps: 0,
      minPaymentPercentBps: 0,
      minPaymentFloor: 0,
    );
    int avalancheMonths(PlanSet plans) =>
        (plans.ranked.firstWhere((r) => r.strategyId == StrategyId.avalanche)
                as Feasible)
            .plan
            .monthsToClear;

    test('is added to the budget', () async {
      await container.read(debtActionsProvider.notifier).add(interestFree());
      container.read(extraPaymentProvider.notifier).set(20000);
      expect(avalancheMonths(await settledPlans()), 6); // 500.00 a month
    });

    test('is capped at the budget', () async {
      await container.read(debtActionsProvider.notifier).add(interestFree());
      container.read(extraPaymentProvider.notifier).set(1000000);
      expect(avalancheMonths(await settledPlans()), 5); // 600.00, not 10,300
    });

    test('resets when the currency changes', () async {
      container.read(extraPaymentProvider.notifier).set(5000);
      await container
          .read(settingsControllerProvider.notifier)
          .setCurrency('JPY');
      expect(container.read(extraPaymentProvider), 0);
    });
  });
```

Append to `test/features/strategies/strategies_screen_test.dart`:

```dart
  testWidgets('the slider pays more each month', (tester) async {
    await pumpApp(
      tester,
      debts: [simple], // 1,000.00 at 0%
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    expect(find.text('Pay £0.00 more a month'), findsOneWidget);
    // £5 steps up to £250; the middle of the track is £125.
    await tester.tap(find.byKey(const ValueKey('payMore')));
    await tester.pumpAndSettle();
    expect(find.text('Pay £125.00 more a month'), findsOneWidget);
    expect(find.text('£375.00 a month in total'), findsOneWidget);
    expect(find.text('Debt-free in 3 months'), findsWidgets);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `./tool/codegen.sh && flutter test test/features/strategies`
Expected: compilation errors: `extra_payment.dart` and `extraPaymentProvider` are undefined.

- [ ] **Step 3: Implement**

Create `lib/features/strategies/domain/extra_payment.dart`:

```dart
import 'package:debt_destroyer/core/currency.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// A round slider step (1, 2 or 5 × 10ⁿ major units, never less than one)
/// that splits [budget] into about 60 steps, in minor units.
int extraPaymentStepMinor(Money budget) {
  final unit = rescaleMinor(
    1,
    fromDigits: 0,
    toDigits: currencyDecimalDigits(budget.currency),
  );
  final target = budget.minor ~/ unit ~/ 60;
  for (var magnitude = 1; ; magnitude *= 10) {
    for (final multiple in const [1, 2, 5]) {
      if (multiple * magnitude >= target) return multiple * magnitude * unit;
    }
  }
}
```

In `plans_providers.dart`, add the provider:

```dart
/// Extra paid each month on top of the budget, in minor units: the
/// Strategies screen's "pay more" slider. Kept for the session only, and
/// reset when the currency changes (its minor units would mean something
/// else).
@Riverpod(keepAlive: true)
class ExtraPayment extends _$ExtraPayment {
  @override
  int build() {
    ref.watch(
      settingsControllerProvider.select((s) => s.value?.currencyCode),
    );
    return 0;
  }

  void set(int minor) => state = minor < 0 ? 0 : minor;
}
```

and in `plans`, use it:

```dart
  final budget = settings.monthlyBudget;
  // Never more than the budget again, even if the budget has since shrunk.
  final extra = ref.watch(extraPaymentProvider).clamp(0, budget.minor);
  final set = await ref.watch(planCalculatorProvider)(
    debts,
    budget + Money(extra, budget.currency),
    settings.strategyParameters,
  );
```

Add to `lib/l10n/app_en.arb`:

```json
  "payMore": "Pay {amount} more a month",
  "@payMore": {"placeholders": {"amount": {"type": "String"}}},
  "payMoreTotal": "{total} a month in total",
  "@payMoreTotal": {"placeholders": {"total": {"type": "String"}}},
```

In `strategies_screen.dart`:
- Import `dart:async` and `extra_payment.dart`.
- Read the whole settings: replace the `parameters` lookup with `final settings = ref.watch(settingsControllerProvider).value;`.
- Match `(AsyncData(:final value), final AppSettings settings)` and use `settings.strategyParameters` for the cards. Import `app_settings.dart`.
- Put `_PayMoreSlider(budget: settings.monthlyBudget)` first in the `ListView` children.
- Add:

```dart
/// "Pay £X more a month": changes the budget every plan uses, recalculating
/// shortly after the thumb stops moving.
class _PayMoreSlider extends ConsumerStatefulWidget {
  const _PayMoreSlider({required this.budget});

  final Money budget;

  @override
  ConsumerState<_PayMoreSlider> createState() => _PayMoreSliderState();
}

class _PayMoreSliderState extends ConsumerState<_PayMoreSlider> {
  double? _dragging;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _commit(double value) =>
      ref.read(extraPaymentProvider.notifier).set(value.round());

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final step = extraPaymentStepMinor(widget.budget);
    final divisions = widget.budget.minor ~/ step;
    if (divisions < 1) return const SizedBox.shrink();
    final max = divisions * step;
    final committed = ref.watch(extraPaymentProvider).clamp(0, max);
    final value = _dragging ?? committed.toDouble();
    final extra = Money(value.round(), widget.budget.currency);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.payMore(formatMoney(extra, locale)),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            key: const ValueKey('payMore'),
            value: value,
            max: max.toDouble(),
            divisions: divisions,
            label: formatMoney(extra, locale),
            onChanged: (v) {
              setState(() => _dragging = v);
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 250),
                () => _commit(v),
              );
            },
            onChangeEnd: (v) {
              _debounce?.cancel();
              _commit(v);
              setState(() => _dragging = null);
            },
          ),
          Text(
            l10n.payMoreTotal(formatMoney(widget.budget + extra, locale)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "feat(strategies): pay-more slider"
```

---

### Task 11: Scenario model, repositories and actions

**Files:**
- Create: `lib/features/scenarios/domain/scenario.dart`, `lib/features/scenarios/domain/scenario_repository.dart`, `lib/features/scenarios/data/drift_scenario_repository.dart`, `lib/features/scenarios/presentation/scenarios_providers.dart`
- Modify: `lib/features/debts/data/drift_debt_repository.dart` (`convertAmounts`), `lib/features/debts/domain/debt_repository.dart` (doc), `lib/app/dependencies.dart`
- Create (test): `test/helpers/in_memory_scenario_repository.dart`, `test/features/scenarios/scenario_test.dart`, `test/features/scenarios/drift_scenario_repository_test.dart`, `test/features/scenarios/scenario_actions_test.dart`
- Modify (test): `test/helpers/pump_app.dart`, `test/features/debts/drift_debt_repository_test.dart`

**Interfaces:**
- Consumes: `ScenarioRows` / `ScenarioRow` (Task 7); the full `StrategyParameters` (Tasks 4–5); `validateStrategyParameters` (Task 6).
- Produces:
  - `Scenario({required String id, required String name, required Money monthlyBudget, required StrategyParameters parameters, required DateTime createdAt})`
  - `enum ScenarioNameError { empty, duplicate }` and `Set<ScenarioNameError> validateScenarioName(String name, Iterable<Scenario> others)`
  - `ScenarioRepository` with `watchAll(currencyCode)`, `loadAll(currencyCode)`, `save(scenario)` (insert or replace) and `delete(id)`
  - `scenarioRepositoryProvider`
  - `scenariosProvider` (`Stream<List<Scenario>>`, keep-alive)
  - `ScenarioSaveOutcome`, with the variants `ScenarioSaved(scenario)` and `ScenarioRejected({nameErrors, budgetErrors, parameterErrors})`
  - `scenarioActionsProvider.notifier`, with `create({name, monthlyBudget, parameters})`, `update(scenario)` and `delete(id)`
  - `pumpApp(…, scenarios: [...])` and `AppHarness.scenarios` (an `InMemoryScenarioRepository`)

- [ ] **Step 1: Write the failing tests**

Create `test/features/scenarios/scenario_test.dart`:

```dart
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  Scenario named(String name) => Scenario(
    id: name,
    name: name,
    monthlyBudget: const Money(30000, 'GBP'),
    parameters: const StrategyParameters(),
    createdAt: DateTime(2026, 9, 24),
  );

  test('a name must not be empty', () {
    expect(validateScenarioName('  ', const []), {ScenarioNameError.empty});
  });

  test('names are unique, ignoring case and spaces', () {
    expect(validateScenarioName(' bonus ', [named('Bonus')]), {
      ScenarioNameError.duplicate,
    });
    expect(validateScenarioName('Pay rise', [named('Bonus')]), isEmpty);
  });
}
```

Create `test/features/scenarios/drift_scenario_repository_test.dart`:

```dart
import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/scenarios/data/drift_scenario_repository.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  late AppDatabase db;
  late DriftScenarioRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftScenarioRepository(db);
  });
  tearDown(() => db.close());

  final bonus = Scenario(
    id: 's1',
    name: 'Bonus',
    monthlyBudget: const Money(45050, 'GBP'),
    parameters: const StrategyParameters(
      consolidationAprBps: 399,
      consolidationTermMonths: 36,
      consolidationFeeBps: 150,
      transferFeeBps: 250,
      promoMonths: 18,
      revertAprBps: 2290,
      transferCreditLimit: Money(500000, 'GBP'),
    ),
    createdAt: DateTime(2026, 9, 24, 10),
  );

  test('stores every field', () async {
    await repo.save(bonus);
    expect(await repo.loadAll('GBP'), [bonus]);
  });

  test('saving the same id replaces it', () async {
    await repo.save(bonus);
    await repo.save(bonus.copyWith(name: 'Pay rise'));
    expect((await repo.loadAll('GBP')).single.name, 'Pay rise');
  });

  test('lists oldest first and labels amounts with the currency', () async {
    final later = bonus.copyWith(
      id: 's2',
      name: 'Later',
      createdAt: DateTime(2026, 9, 25),
    );
    await repo.save(later);
    await repo.save(bonus);
    final all = await repo.loadAll('USD');
    expect(all.map((s) => s.id), ['s1', 's2']);
    expect(all.first.monthlyBudget, const Money(45050, 'USD'));
    expect(
      all.first.parameters.transferCreditLimit,
      const Money(500000, 'USD'),
    );
  });

  test('deletes', () async {
    await repo.save(bonus);
    await repo.delete('s1');
    expect(await repo.loadAll('GBP'), isEmpty);
  });

  test('watchAll emits after each change', () async {
    final lengths = <int>[];
    final sub = repo.watchAll('GBP').listen((s) => lengths.add(s.length));
    await pumpEventQueue();
    await repo.save(bonus);
    await pumpEventQueue();
    await sub.cancel();
    expect(lengths, [0, 1]);
  });
}
```

Append to `test/features/debts/drift_debt_repository_test.dart`. It needs imports of `drift_scenario_repository.dart` and `scenario.dart`.

```dart
  test('converting amounts rescales saved scenarios too', () async {
    await repo.convertAmounts(toCurrencyCode: 'GBP');
    final scenarios = DriftScenarioRepository(db);
    await scenarios.save(
      Scenario(
        id: 's',
        name: 'Bonus',
        monthlyBudget: const Money(45050, 'GBP'),
        parameters: const StrategyParameters(
          transferCreditLimit: Money(12345, 'GBP'),
        ),
        createdAt: DateTime(2026, 9, 24),
      ),
    );
    await repo.convertAmounts(toCurrencyCode: 'JPY');
    final s = (await scenarios.loadAll('JPY')).single;
    expect(s.monthlyBudget, const Money(450, 'JPY')); // 450.50 → 450 (half-even)
    expect(s.parameters.transferCreditLimit, const Money(123, 'JPY'));
  });
```

Create `test/features/scenarios/scenario_actions_test.dart`:

```dart
import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/test_container.dart';

void main() {
  late ProviderContainer container;
  ScenarioActions actions() => container.read(scenarioActionsProvider.notifier);
  Future<List<Scenario>> stored() =>
      container.read(scenarioRepositoryProvider).loadAll('GBP');

  setUp(() => container = createTestContainer());

  Future<ScenarioSaveOutcome> create(String name, {int budget = 45000}) =>
      actions().create(
        name: name,
        monthlyBudget: Money(budget, 'GBP'),
        parameters: const StrategyParameters(),
      );

  test('creates a scenario with a new id, trimmed name and the clock', () async {
    final saved = ((await create(' Bonus ')) as ScenarioSaved).scenario;
    expect(saved.id, isNotEmpty);
    expect(saved.name, 'Bonus');
    expect(saved.createdAt, DateTime(2026, 9, 24));
    expect(await stored(), [saved]);
  });

  test('rejects an empty or duplicate name', () async {
    await create('Bonus');
    expect(
      await create(''),
      const ScenarioSaveOutcome.rejected(
        nameErrors: {ScenarioNameError.empty},
      ),
    );
    expect(
      await create('BONUS'),
      const ScenarioSaveOutcome.rejected(
        nameErrors: {ScenarioNameError.duplicate},
      ),
    );
    expect(await stored(), hasLength(1));
  });

  test('rejects an invalid budget', () async {
    expect(
      await create('Zero', budget: 0),
      const ScenarioSaveOutcome.rejected(
        budgetErrors: {BudgetValidationError.notPositive},
      ),
    );
  });

  test('an update may keep its own name', () async {
    final saved = ((await create('Bonus')) as ScenarioSaved).scenario;
    final outcome = await actions().update(
      saved.copyWith(monthlyBudget: const Money(50000, 'GBP')),
    );
    expect(outcome, isA<ScenarioSaved>());
    expect((await stored()).single.monthlyBudget, const Money(50000, 'GBP'));
  });

  test('delete removes it', () async {
    final saved = ((await create('Bonus')) as ScenarioSaved).scenario;
    await actions().delete(saved.id);
    expect(await stored(), isEmpty);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/scenarios test/features/debts/drift_debt_repository_test.dart`
Expected: compilation errors: the `scenarios` feature doesn't exist.

- [ ] **Step 3: Implement the domain and data layers**

Create `lib/features/scenarios/domain/scenario.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/payoff_engine.dart';

part 'scenario.freezed.dart';

/// Saved what-if settings (a budget and strategy parameters) applied to the
/// one real debt list. It never holds debts of its own.
@freezed
abstract class Scenario with _$Scenario {
  const factory Scenario({
    required String id,
    required String name,
    required Money monthlyBudget,
    required StrategyParameters parameters,
    required DateTime createdAt,
  }) = _Scenario;
}

enum ScenarioNameError { empty, duplicate }

/// Problems with [name] given the [others] already saved (leave out the
/// scenario being renamed). Names compare ignoring case and outer spaces.
Set<ScenarioNameError> validateScenarioName(
  String name,
  Iterable<Scenario> others,
) {
  final key = name.trim().toLowerCase();
  return {
    if (key.isEmpty) ScenarioNameError.empty,
    if (key.isNotEmpty &&
        others.any((s) => s.name.trim().toLowerCase() == key))
      ScenarioNameError.duplicate,
  };
}
```

Create `lib/features/scenarios/domain/scenario_repository.dart`:

```dart
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';

abstract interface class ScenarioRepository {
  /// Saved scenarios, oldest first, re-emitted after every change. Amounts
  /// are labelled with [currencyCode].
  Stream<List<Scenario>> watchAll(String currencyCode);

  /// The saved scenarios, read once.
  Future<List<Scenario>> loadAll(String currencyCode);

  /// Inserts [scenario], or replaces the stored one with the same id.
  Future<void> save(Scenario scenario);

  /// Removes the scenario with [id], if it exists.
  Future<void> delete(String id);
}
```

Create `lib/features/scenarios/data/drift_scenario_repository.dart`:

```dart
import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario_repository.dart';
import 'package:drift/drift.dart';
import 'package:payoff_engine/payoff_engine.dart';

class DriftScenarioRepository implements ScenarioRepository {
  DriftScenarioRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Scenario>> watchAll(String currencyCode) => _ordered().watch().map(
    (rows) => [for (final row in rows) _toScenario(row, currencyCode)],
  );

  @override
  Future<List<Scenario>> loadAll(String currencyCode) async => [
    for (final row in await _ordered().get()) _toScenario(row, currencyCode),
  ];

  SimpleSelectStatement<$ScenarioRowsTable, ScenarioRow> _ordered() =>
      _db.select(_db.scenarioRows)..orderBy([
        (t) => OrderingTerm(expression: t.createdAt),
        (t) => OrderingTerm(expression: t.id),
      ]);

  @override
  Future<void> save(Scenario scenario) =>
      _db.into(_db.scenarioRows).insertOnConflictUpdate(_toCompanion(scenario));

  @override
  Future<void> delete(String id) =>
      (_db.delete(_db.scenarioRows)..where((t) => t.id.equals(id))).go();

  Scenario _toScenario(ScenarioRow row, String currencyCode) => Scenario(
    id: row.id,
    name: row.name,
    monthlyBudget: Money(row.monthlyBudgetMinor, currencyCode),
    parameters: StrategyParameters(
      consolidationAprBps: row.consolidationAprBps,
      consolidationTermMonths: row.consolidationTermMonths,
      consolidationFeeBps: row.consolidationFeeBps,
      transferFeeBps: row.transferFeeBps,
      promoMonths: row.promoMonths,
      revertAprBps: row.revertAprBps,
      transferCreditLimit: switch (row.transferCreditLimitMinor) {
        final limit? => Money(limit, currencyCode),
        null => null,
      },
    ),
    createdAt: row.createdAt,
  );

  ScenarioRowsCompanion _toCompanion(Scenario s) {
    final p = s.parameters;
    return ScenarioRowsCompanion(
      id: Value(s.id),
      name: Value(s.name),
      monthlyBudgetMinor: Value(s.monthlyBudget.minor),
      consolidationAprBps: Value(p.consolidationAprBps),
      consolidationTermMonths: Value(p.consolidationTermMonths),
      consolidationFeeBps: Value(p.consolidationFeeBps),
      transferFeeBps: Value(p.transferFeeBps),
      promoMonths: Value(p.promoMonths),
      revertAprBps: Value(p.revertAprBps),
      transferCreditLimitMinor: Value(p.transferCreditLimit?.minor),
      createdAt: Value(s.createdAt),
    );
  }
}
```

In `DriftDebtRepository.convertAmounts`, rescale scenarios in the same transaction. Add after the debts loop, inside `if (fromDigits != toDigits)`:

```dart
            // Scenarios hold amounts in the same app-wide currency.
            final scenarios = await _db.select(_db.scenarioRows).get();
            for (final row in scenarios) {
              await (_db.update(
                _db.scenarioRows,
              )..where((t) => t.id.equals(row.id))).write(
                ScenarioRowsCompanion(
                  monthlyBudgetMinor: Value(
                    rescale(row.monthlyBudgetMinor, min: 1),
                  ),
                  transferCreditLimitMinor: Value(
                    switch (row.transferCreditLimitMinor) {
                      final limit? => rescale(limit, min: 1),
                      null => null,
                    },
                  ),
                ),
              );
            }
```

In `DebtRepository.convertAmounts`'s doc comment (`debt_repository.dart`), change "every balance and floor is rescaled" to "every balance and floor, and every saved scenario's budget and credit limit, is rescaled".

In `lib/app/dependencies.dart`, import the scenario repository and add:

```dart
@Riverpod(keepAlive: true)
ScenarioRepository scenarioRepository(Ref ref) =>
    DriftScenarioRepository(ref.watch(appDatabaseProvider));
```

- [ ] **Step 4: Implement the providers and actions**

Create `lib/features/scenarios/presentation/scenarios_providers.dart`:

```dart
import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'scenarios_providers.freezed.dart';
part 'scenarios_providers.g.dart';

/// Saved scenarios, oldest first, labelled with the current currency. Stays
/// loading until settings have loaded.
@Riverpod(keepAlive: true)
Stream<List<Scenario>> scenarios(Ref ref) {
  final (currencyCode, error) = ref.watch(
    settingsControllerProvider.select((s) => (s.value?.currencyCode, s.error)),
  );
  if (error != null) return Stream.error(error);
  if (currencyCode == null) return const Stream.empty();
  return ref.watch(scenarioRepositoryProvider).watchAll(currencyCode);
}

@freezed
sealed class ScenarioSaveOutcome with _$ScenarioSaveOutcome {
  const factory ScenarioSaveOutcome.saved(Scenario scenario) = ScenarioSaved;

  const factory ScenarioSaveOutcome.rejected({
    @Default(<ScenarioNameError>{}) Set<ScenarioNameError> nameErrors,
    @Default(<BudgetValidationError>{}) Set<BudgetValidationError> budgetErrors,
    @Default(<StrategyParametersValidationError>{})
    Set<StrategyParametersValidationError> parameterErrors,
  }) = ScenarioRejected;
}

/// Validated changes to the saved scenarios.
@Riverpod(keepAlive: true)
class ScenarioActions extends _$ScenarioActions {
  static const _uuid = Uuid();

  /// The change in progress; each new one waits for it, so a name check and
  /// its write can't interleave with another.
  Future<void> _pending = Future<void>.value();

  @override
  void build() {}

  /// Saves a new scenario.
  Future<ScenarioSaveOutcome> create({
    required String name,
    required Money monthlyBudget,
    required StrategyParameters parameters,
  }) => _serialised(
    () => _save(
      Scenario(
        id: _uuid.v4(),
        name: name.trim(),
        monthlyBudget: monthlyBudget,
        parameters: parameters,
        createdAt: ref.read(clockProvider)(),
      ),
    ),
  );

  /// Replaces the saved scenario with [scenario]'s id.
  Future<ScenarioSaveOutcome> update(Scenario scenario) => _serialised(
    () => _save(scenario.copyWith(name: scenario.name.trim())),
  );

  Future<void> delete(String id) => _serialised(
    () => ref.read(scenarioRepositoryProvider).delete(id),
  );

  Future<ScenarioSaveOutcome> _save(Scenario scenario) async {
    final settings = await ref.read(settingsControllerProvider.future);
    final repository = ref.read(scenarioRepositoryProvider);
    final others = (await repository.loadAll(
      settings.currencyCode,
    )).where((s) => s.id != scenario.id);
    final nameErrors = validateScenarioName(scenario.name, others);
    final budgetErrors = validateBudget(scenario.monthlyBudget);
    final parameterErrors = validateStrategyParameters(scenario.parameters);
    if (nameErrors.isNotEmpty ||
        budgetErrors.isNotEmpty ||
        parameterErrors.isNotEmpty) {
      return ScenarioSaveOutcome.rejected(
        nameErrors: nameErrors,
        budgetErrors: budgetErrors,
        parameterErrors: parameterErrors,
      );
    }
    await repository.save(scenario);
    return ScenarioSaveOutcome.saved(scenario);
  }

  Future<T> _serialised<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
```

- [ ] **Step 5: Give widget tests an in-memory scenario repository**

Create `test/helpers/in_memory_scenario_repository.dart`:

```dart
import 'dart:async';

import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario_repository.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Widget tests can't use Drift streams. Unlike the Drift repository, a
/// currency switch does not rescale these scenarios.
class InMemoryScenarioRepository implements ScenarioRepository {
  InMemoryScenarioRepository([List<Scenario> initial = const []])
    : _scenarios = [...initial];

  final List<Scenario> _scenarios;
  final _changes = StreamController<void>.broadcast();

  List<Scenario> get stored => List.unmodifiable(_scenarios);

  List<Scenario> _labelled(String currency) => [
    for (final s in _scenarios)
      s.copyWith(
        monthlyBudget: Money(s.monthlyBudget.minor, currency),
        parameters: s.parameters.copyWith(
          transferCreditLimit: switch (s.parameters.transferCreditLimit) {
            final limit? => Money(limit.minor, currency),
            null => null,
          },
        ),
      ),
  ];

  @override
  Stream<List<Scenario>> watchAll(String currencyCode) async* {
    yield _labelled(currencyCode);
    await for (final _ in _changes.stream) {
      yield _labelled(currencyCode);
    }
  }

  @override
  Future<List<Scenario>> loadAll(String currencyCode) async =>
      _labelled(currencyCode);

  @override
  Future<void> save(Scenario scenario) async {
    final i = _scenarios.indexWhere((s) => s.id == scenario.id);
    if (i < 0) {
      _scenarios.add(scenario);
    } else {
      _scenarios[i] = scenario;
    }
    _changes.add(null);
  }

  @override
  Future<void> delete(String id) async {
    _scenarios.removeWhere((s) => s.id == id);
    _changes.add(null);
  }
}
```

In `test/helpers/pump_app.dart`:
- Add a `List<Scenario> scenarios = const []` parameter.
- Create `final scenarioRepository = InMemoryScenarioRepository(scenarios);`.
- Add the override `scenarioRepositoryProvider.overrideWithValue(scenarioRepository),`.
- Give `AppHarness` a third field:

```dart
class AppHarness {
  AppHarness(this.container, this.repository, this.scenarios);

  final ProviderContainer container;
  final InMemoryDebtRepository repository;
  final InMemoryScenarioRepository scenarios;

  GoRouterNavigator get router => GoRouterNavigator(container);
}
```

Return `AppHarness(container, repository, scenarioRepository)`.

- [ ] **Step 6: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add lib test
git commit -m "feat(scenarios): saved what-if scenarios with validation, rescaled with the currency"
```

---

### Task 12: Choosing and saving scenarios on Strategies

**Files:**
- Create: `lib/features/scenarios/presentation/scenario_name_dialog.dart`
- Modify: `lib/features/scenarios/presentation/scenarios_providers.dart`, `lib/features/strategies/presentation/plans_providers.dart`, `lib/features/strategies/presentation/strategies_screen.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/strategies/plans_providers_test.dart`, `test/features/strategies/strategies_screen_test.dart`

**Interfaces:**
- Consumes: `scenariosProvider`, `scenarioActionsProvider`, `ScenarioSaveOutcome` (Task 11); `extraPaymentProvider` (Task 10).
- Produces:
  - `selectedScenarioIdProvider`, a keep-alive `Notifier<String?>` with `select(String? id)`, where null means Current
  - `typedef ActiveScenario = ({String? id, String? name, Money monthlyBudget, StrategyParameters parameters})`
  - `activeScenarioProvider` (`Future<ActiveScenario>`)
  - `plansProvider` uses the active scenario
  - `extraPaymentProvider` also resets when the selection changes
  - `ScenarioActions.delete` resets the selection if it was the deleted one
  - `Future<bool> showScenarioNameDialog(BuildContext, {required String title, required Future<String?> Function(String name) submit, String initialName = ''})`
  - `String? scenarioOutcomeMessage(AppLocalizations, ScenarioSaveOutcome)`
  - Widget keys `ValueKey('scenario')` (picker) and `ValueKey('scenarioName')` (dialog field)

- [ ] **Step 1: Write the failing tests**

In `test/features/strategies/plans_providers_test.dart`, move `interestFree()` and `avalancheMonths()` from the `extra payment` group up to the top of `main`, so the new group can use them. Then append:

```dart
  group('scenarios', () {
    Future<Scenario> saveBonus() async =>
        ((await container
                        .read(scenarioActionsProvider.notifier)
                        .create(
                          name: 'Bonus',
                          monthlyBudget: const Money(60000, 'GBP'),
                          parameters: const StrategyParameters(),
                        ))
                    as ScenarioSaved)
            .scenario;

    test('plans use the selected scenario\'s budget', () async {
      await container.read(debtActionsProvider.notifier).add(interestFree());
      final bonus = await saveBonus();
      container.read(selectedScenarioIdProvider.notifier).select(bonus.id);
      expect(avalancheMonths(await settledPlans()), 5); // 600.00 a month
    });

    test('choosing a scenario resets the extra payment', () async {
      final bonus = await saveBonus();
      container.read(extraPaymentProvider.notifier).set(5000);
      container.read(selectedScenarioIdProvider.notifier).select(bonus.id);
      expect(container.read(extraPaymentProvider), 0);
    });

    test('deleting the selected scenario falls back to Current', () async {
      await container.read(debtActionsProvider.notifier).add(interestFree());
      final bonus = await saveBonus();
      container.read(selectedScenarioIdProvider.notifier).select(bonus.id);
      await container.read(scenarioActionsProvider.notifier).delete(bonus.id);
      expect(container.read(selectedScenarioIdProvider), isNull);
      expect(avalancheMonths(await settledPlans()), 10); // 300.00 a month
    });
  });
```

In `test/features/strategies/strategies_screen_test.dart`, add imports for `scenario.dart`, then append:

```dart
  final bonus = Scenario(
    id: 's1',
    name: 'Bonus',
    monthlyBudget: const Money(50000, 'GBP'),
    parameters: const StrategyParameters(),
    createdAt: DateTime(2026, 9, 1),
  );

  testWidgets('shows plans for a chosen scenario', (tester) async {
    await pumpApp(
      tester,
      debts: [simple],
      scenarios: [bonus],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    expect(find.text('Debt-free in 4 months'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('scenario')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bonus').last);
    await tester.pumpAndSettle();
    expect(find.text('Debt-free in 2 months'), findsWidgets);
  });

  testWidgets('saves the slider as a scenario and switches to it', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      debts: [simple],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    await tester.tap(find.byKey(const ValueKey('payMore'))); // +£125
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as scenario'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('scenarioName')), 'Bonus');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = app.scenarios.stored.single;
    expect(saved.name, 'Bonus');
    expect(saved.monthlyBudget, const Money(37500, 'GBP'));
    expect(find.text('Scenario saved'), findsOneWidget);
    // Now on the saved scenario: its budget includes the extra.
    expect(find.text('Pay £0.00 more a month'), findsOneWidget);
    expect(find.text('Debt-free in 3 months'), findsWidgets);
  });

  testWidgets('a duplicate name is explained in the dialog', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [simple],
      scenarios: [bonus],
      settings: {SettingsKeys.monthlyBudgetMinor: 25000},
      location: Routes.strategies,
    );
    await tester.tap(find.text('Save as scenario'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('scenarioName')), 'bonus');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('You already have a scenario with that name'),
      findsOneWidget,
    );
    expect(app.scenarios.stored, hasLength(1));
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `./tool/codegen.sh && flutter test test/features/strategies`
Expected: compilation errors: `selectedScenarioIdProvider` and the `scenarios:` parameter's widgets are missing.

- [ ] **Step 3: Implement selection and the active scenario**

Append to `scenarios_providers.dart`:

```dart
/// The saved scenario shown on Strategies, or null for Current. Kept for the
/// session only.
@Riverpod(keepAlive: true)
class SelectedScenarioId extends _$SelectedScenarioId {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

/// The budget and strategy settings Strategies uses: the selected saved
/// scenario's, or Current's (from Settings). [id] and [name] are null for
/// Current.
typedef ActiveScenario = ({
  String? id,
  String? name,
  Money monthlyBudget,
  StrategyParameters parameters,
});

/// Falls back to Current if the selected scenario no longer exists.
@riverpod
Future<ActiveScenario> activeScenario(Ref ref) async {
  final settings = await ref.watch(settingsControllerProvider.future);
  final id = ref.watch(selectedScenarioIdProvider);
  if (id != null) {
    final saved = await ref.watch(scenariosProvider.future);
    if (saved.where((s) => s.id == id).firstOrNull case final s?) {
      return (
        id: s.id,
        name: s.name,
        monthlyBudget: s.monthlyBudget,
        parameters: s.parameters,
      );
    }
  }
  return (
    id: null,
    name: null,
    monthlyBudget: settings.monthlyBudget,
    parameters: settings.strategyParameters,
  );
}
```

In `ScenarioActions.delete`, clear a selection that points at the deleted scenario:

```dart
  Future<void> delete(String id) => _serialised(() async {
    await ref.read(scenarioRepositoryProvider).delete(id);
    if (ref.read(selectedScenarioIdProvider) == id) {
      ref.read(selectedScenarioIdProvider.notifier).select(null);
    }
  });
```

In `plans_providers.dart`, import `scenarios_providers.dart`. Then:
- In `ExtraPayment.build`, add `ref.watch(selectedScenarioIdProvider);` so a new selection resets the extra.
- Replace the settings lookup in `plans`:

```dart
@riverpod
Future<PlanSet> plans(Ref ref) async {
  final debts = await ref.watch(debtsProvider.future);
  final active = await ref.watch(activeScenarioProvider.future);
  final budget = active.monthlyBudget;
  // Never more than the budget again, even if the budget has since shrunk.
  final extra = ref.watch(extraPaymentProvider).clamp(0, budget.minor);
  final set = await ref.watch(planCalculatorProvider)(
    debts,
    budget + Money(extra, budget.currency),
    active.parameters,
  );
  return (ranked: rankResults(set.ranked), baseline: set.baseline);
}
```

Update the provider's doc comment: "…for the current debts and the active scenario…".

- [ ] **Step 4: Implement the name dialog**

Add to `lib/l10n/app_en.arb`:

```json
  "scenarioCurrent": "Current",
  "saveAsScenario": "Save as scenario",
  "scenarioNameLabel": "Name",
  "scenarioSaved": "Scenario saved",
  "errorScenarioNameEmpty": "Enter a name",
  "errorScenarioNameDuplicate": "You already have a scenario with that name",
  "errorScenarioInvalid": "This scenario's budget or settings aren't valid",
```

Create `lib/features/scenarios/presentation/scenario_name_dialog.dart`:

```dart
import 'package:debt_destroyer/core/crash_reporter.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks for a scenario name. [submit] tries to save it and returns an error
/// message, or null once saved; the dialog then closes and returns true.
Future<bool> showScenarioNameDialog(
  BuildContext context, {
  required String title,
  required Future<String?> Function(String name) submit,
  String initialName = '',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ScenarioNameDialog(
        title: title,
        submit: submit,
        initialName: initialName,
      ),
    ) ??
    false;

/// The message for a rejected scenario, or null when it was saved.
String? scenarioOutcomeMessage(
  AppLocalizations l10n,
  ScenarioSaveOutcome outcome,
) => switch (outcome) {
  ScenarioSaved() => null,
  ScenarioRejected(:final nameErrors)
      when nameErrors.contains(ScenarioNameError.empty) =>
    l10n.errorScenarioNameEmpty,
  ScenarioRejected(:final nameErrors)
      when nameErrors.contains(ScenarioNameError.duplicate) =>
    l10n.errorScenarioNameDuplicate,
  ScenarioRejected() => l10n.errorScenarioInvalid,
};

class _ScenarioNameDialog extends ConsumerStatefulWidget {
  const _ScenarioNameDialog({
    required this.title,
    required this.submit,
    required this.initialName,
  });

  final String title;
  final Future<String?> Function(String name) submit;
  final String initialName;

  @override
  ConsumerState<_ScenarioNameDialog> createState() =>
      _ScenarioNameDialogState();
}

class _ScenarioNameDialogState extends ConsumerState<_ScenarioNameDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    String? error;
    try {
      error = await widget.submit(_name.text);
    } on Object catch (e, stackTrace) {
      ref
          .read(crashReporterProvider)
          .recordError(e, stackTrace, reason: 'Saving a scenario failed');
      if (!mounted) return;
      error = context.l10n.errorSaving;
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('scenarioName'),
        controller: _name,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l10n.scenarioNameLabel,
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Add the picker and "Save as scenario" to Strategies**

In `strategies_screen.dart`, import `scenarios_providers.dart`, `scenario_name_dialog.dart` and `scenario.dart`. Then:

1. In `StrategiesScreen.build`, watch `final active = ref.watch(activeScenarioProvider);` instead of the settings. Switch on `(plans, active)`, matching `(AsyncData(:final value), AsyncData(value: final ActiveScenario scenario))`. Also invalidate `activeScenarioProvider` in the error arm's retry. The list becomes:

```dart
            children: [
              const _ScenarioPicker(),
              _PayMoreSlider(budget: scenario.monthlyBudget),
              _SaveAsScenarioButton(active: scenario),
              _BaselineLine(value.baseline),
              for (final (i, result) in value.ranked.indexed)
                _StrategyCard(
                  result: result,
                  baseline: value.baseline,
                  parameters: scenario.parameters,
                  cheapest: i == 0 && result is Feasible,
                ),
            ],
```

2. Add the widgets:

```dart
/// Current, then each saved scenario. Hidden until something is saved.
class _ScenarioPicker extends ConsumerWidget {
  const _ScenarioPicker();

  /// Stands for Current in the menu: a null item value would read as "no
  /// selection". Scenario ids are UUIDs, so it can't clash.
  static const _current = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final saved = ref.watch(scenariosProvider).value ?? const <Scenario>[];
    if (saved.isEmpty) return const SizedBox.shrink();
    final selected = ref.watch(selectedScenarioIdProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: DropdownButton<String>(
        key: const ValueKey('scenario'),
        isExpanded: true,
        // A selection that was just deleted shows as Current.
        value: saved.any((s) => s.id == selected) ? selected : _current,
        items: [
          DropdownMenuItem(
            value: _current,
            child: Text(l10n.scenarioCurrent),
          ),
          for (final s in saved)
            DropdownMenuItem(value: s.id, child: Text(s.name)),
        ],
        onChanged: (id) => ref
            .read(selectedScenarioIdProvider.notifier)
            .select(id == null || id == _current ? null : id),
      ),
    );
  }
}

/// Saves the scenario being viewed (plus any extra from the slider) under a
/// new name, then switches to it.
class _SaveAsScenarioButton extends ConsumerWidget {
  const _SaveAsScenarioButton({required this.active});

  final ActiveScenario active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final extra = ref
        .watch(extraPaymentProvider)
        .clamp(0, active.monthlyBudget.minor);
    // A saved scenario with nothing added would only be a copy of itself.
    if (active.id != null && extra == 0) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.bookmark_add_outlined),
        label: Text(l10n.saveAsScenario),
        onPressed: () => _save(context, ref, extra),
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref, int extra) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final budget =
        active.monthlyBudget + Money(extra, active.monthlyBudget.currency);
    Scenario? created;
    final saved = await showScenarioNameDialog(
      context,
      title: l10n.saveAsScenario,
      submit: (name) async {
        final outcome = await ref
            .read(scenarioActionsProvider.notifier)
            .create(
              name: name,
              monthlyBudget: budget,
              parameters: active.parameters,
            );
        if (outcome case ScenarioSaved(:final scenario)) created = scenario;
        return scenarioOutcomeMessage(l10n, outcome);
      },
    );
    if (!saved || created == null) return;
    ref.read(selectedScenarioIdProvider.notifier).select(created!.id);
    messenger.showSnackBar(SnackBar(content: Text(l10n.scenarioSaved)));
  }
}
```

- [ ] **Step 6: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add lib test
git commit -m "feat(strategies): choose a scenario and save the slider as one"
```

---

### Task 13: Scenarios screen: list, edit, delete, compare

**Files:**
- Create: `lib/features/scenarios/presentation/scenarios_screen.dart`, `lib/features/scenarios/presentation/scenario_form_screen.dart`, `lib/features/scenarios/presentation/scenario_comparison.dart`
- Modify: `lib/app/router.dart`, `lib/features/strategies/presentation/strategies_screen.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/scenarios/scenarios_screen_test.dart` (new), `test/features/strategies/strategies_screen_test.dart`

**Interfaces:**
- Consumes: `ParameterControllers`, `ParameterFields`, `parameterErrorMessages` (Task 6); `scenariosProvider`, `scenarioActionsProvider` (Task 11); `activeScenarioProvider` (Task 12); `planCalculatorProvider`, `rankResults` (Task 9).
- Produces:
  - `Routes.scenarios = '/scenarios'` and `Routes.editScenario(String id)`
  - `ScenariosScreen`, `ScenarioFormScreen(scenarioId:)`
  - `typedef ScenarioComparison = ({String? id, String? name, Feasible? best})` and `scenarioComparisonProvider`

- [ ] **Step 1: Write the failing tests**

Create `test/features/scenarios/scenarios_screen_test.dart`:

```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/settings/data/prefs_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../../helpers/debts.dart';
import '../../helpers/pump_app.dart';

void main() {
  final bonus = Scenario(
    id: 's1',
    name: 'Bonus',
    monthlyBudget: const Money(50000, 'GBP'),
    parameters: const StrategyParameters(),
    createdAt: DateTime(2026, 9, 1),
  );

  testWidgets('lists saved scenarios', (tester) async {
    await pumpApp(tester, scenarios: [bonus], location: Routes.scenarios);
    expect(find.text('Bonus'), findsOneWidget);
    expect(find.text('£500.00 a month'), findsOneWidget);
  });

  testWidgets('with none saved, explains how to make one', (tester) async {
    await pumpApp(tester, location: Routes.scenarios);
    expect(find.textContaining('No saved scenarios yet'), findsOneWidget);
  });

  testWidgets('edits a scenario\'s name and budget', (tester) async {
    final app = await pumpApp(
      tester,
      scenarios: [bonus],
      location: Routes.scenarios,
    );
    await tester.tap(find.text('Bonus'));
    await tester.pumpAndSettle();
    expect(find.text('Edit scenario'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Pay rise',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Monthly budget'),
      '650',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final saved = app.scenarios.stored.single;
    expect(saved.name, 'Pay rise');
    expect(saved.monthlyBudget, const Money(65000, 'GBP'));
    expect(app.router.location, Routes.scenarios);
  });

  testWidgets('an empty name is refused in the editor', (tester) async {
    final app = await pumpApp(
      tester,
      scenarios: [bonus],
      location: Routes.editScenario('s1'),
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), ' ');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);
    expect(app.scenarios.stored.single.name, 'Bonus');
  });

  testWidgets('deletes a scenario after asking', (tester) async {
    final app = await pumpApp(
      tester,
      scenarios: [bonus],
      location: Routes.scenarios,
    );
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Bonus?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(app.scenarios.stored, isEmpty);
  });

  testWidgets('compares the best plan in each scenario', (tester) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a')], // 1,000.00 at 19.9%, min 3% or 25.00
      scenarios: [bonus],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.scenarios,
    );
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    // The 5% consolidation loan is cheapest in both.
    expect(
      find.text('Consolidation loan: debt-free in 4 months, £9.25 interest'),
      findsOneWidget,
    );
    expect(
      find.text('Consolidation loan: debt-free in 3 months, £6.30 interest'),
      findsOneWidget,
    );
    final cheapest = find.ancestor(
      of: find.text('Cheapest'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: cheapest, matching: find.text('Bonus')),
      findsOneWidget,
    );
  });
}
```

In `test/features/strategies/strategies_screen_test.dart`, append:

```dart
  testWidgets('opens the scenarios screen', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [simple],
      location: Routes.strategies,
    );
    await tester.tap(find.byTooltip('Scenarios'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.scenarios);
  });

  testWidgets('the limit link edits the scenario being viewed', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      debts: [testDebt(id: 'a')],
      scenarios: [bonus],
      location: Routes.strategies,
    );
    await tester.tap(find.byKey(const ValueKey('scenario')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bonus').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Set yours'), 100);
    await tester.tap(find.text('Set yours'));
    await tester.pumpAndSettle();
    expect(app.router.location, Routes.editScenario('s1'));
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `./tool/codegen.sh && flutter test test/features/scenarios test/features/strategies`
Expected: compilation errors: `Routes.scenarios` and `Routes.editScenario` are undefined.

- [ ] **Step 3: Implement**

Add to `lib/l10n/app_en.arb`:

```json
  "scenariosTitle": "Scenarios",
  "scenariosTabSaved": "Saved",
  "scenariosTabCompare": "Compare",
  "scenariosEmpty": "No saved scenarios yet. Move the slider on the Strategies screen, then save it as a scenario.",
  "scenarioBudget": "{budget} a month",
  "@scenarioBudget": {"placeholders": {"budget": {"type": "String"}}},
  "deleteScenarioTitle": "Delete {name}?",
  "@deleteScenarioTitle": {"placeholders": {"name": {"type": "String"}}},
  "editScenarioTitle": "Edit scenario",
  "compareBest": "{strategy}: debt-free in {duration}, {interest} interest",
  "@compareBest": {"placeholders": {"strategy": {"type": "String"}, "duration": {"type": "String"}, "interest": {"type": "String"}}},
  "compareNoPlan": "No plan clears these debts",
```

Create `lib/features/scenarios/presentation/scenario_comparison.dart`:

```dart
import 'package:debt_destroyer/features/debts/presentation/debts_providers.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:debt_destroyer/features/strategies/domain/rank_results.dart';
import 'package:debt_destroyer/features/strategies/presentation/plans_providers.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'scenario_comparison.g.dart';

/// One row of the Compare tab: a scenario (null [id] and [name] for
/// Current) and its cheapest plan, or null if no plan clears the debts.
typedef ScenarioComparison = ({String? id, String? name, Feasible? best});

/// Current, then every saved scenario, each with its cheapest plan.
@riverpod
Future<List<ScenarioComparison>> scenarioComparison(Ref ref) async {
  final debts = await ref.watch(debtsProvider.future);
  final settings = await ref.watch(settingsControllerProvider.future);
  final saved = await ref.watch(scenariosProvider.future);
  final calculate = ref.watch(planCalculatorProvider);

  Future<Feasible?> best(Money budget, StrategyParameters parameters) async {
    final set = await calculate(debts, budget, parameters);
    final first = rankResults(set.ranked).first;
    return first is Feasible ? first : null;
  }

  return [
    (
      id: null,
      name: null,
      best: await best(settings.monthlyBudget, settings.strategyParameters),
    ),
    for (final s in saved)
      (id: s.id, name: s.name, best: await best(s.monthlyBudget, s.parameters)),
  ];
}
```

Create `lib/features/scenarios/presentation/scenarios_screen.dart`:

```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/labels.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenario_comparison.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Saved scenarios, and a side-by-side comparison. No ads here.
class ScenariosScreen extends StatelessWidget {
  const ScenariosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.scenariosTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.scenariosTabSaved),
              Tab(text: l10n.scenariosTabCompare),
            ],
          ),
        ),
        body: const TabBarView(children: [_SavedTab(), _CompareTab()]),
      ),
    );
  }
}

class _SavedTab extends ConsumerWidget {
  const _SavedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    return switch (ref.watch(scenariosProvider)) {
      AsyncData(:final value) when value.isEmpty => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.scenariosEmpty, textAlign: TextAlign.center),
        ),
      ),
      AsyncData(:final value) => ListView(
        children: [
          for (final s in value)
            ListTile(
              key: ValueKey(s.id),
              title: Text(s.name),
              subtitle: Text(
                l10n.scenarioBudget(formatMoney(s.monthlyBudget, locale)),
              ),
              onTap: () => context.push(Routes.editScenario(s.id)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l10n.delete,
                onPressed: () => _confirmDelete(context, ref, s),
              ),
            ),
        ],
      ),
      AsyncError() => ErrorRetryView(
        onRetry: () => ref.invalidate(scenariosProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Scenario scenario,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteScenarioTitle(scenario.name)),
        content: Text(l10n.deleteDebtBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runGuarded(
      context,
      () => ref.read(scenarioActionsProvider.notifier).delete(scenario.id),
    );
  }
}

class _CompareTab extends ConsumerWidget {
  const _CompareTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(scenarioComparisonProvider)) {
        AsyncData(:final value) => _CompareList(value),
        AsyncError() => ErrorRetryView(
          onRetry: () => ref.invalidate(scenarioComparisonProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
}

class _CompareList extends ConsumerWidget {
  const _CompareList(this.rows);

  final List<ScenarioComparison> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final theme = Theme.of(context);
    Money? cheapest;
    for (final row in rows) {
      final paid = row.best?.plan.totalPaid;
      if (paid != null && (cheapest == null || paid < cheapest)) {
        cheapest = paid;
      }
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final row in rows)
          _row(
            context,
            l10n,
            locale,
            row,
            theme,
            isCheapest: cheapest != null && row.best?.plan.totalPaid == cheapest,
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    String locale,
    ScenarioComparison row,
    ThemeData theme, {
    required bool isCheapest,
  }) => Card(
    key: ValueKey('compare-${row.id ?? 'current'}'),
    color: isCheapest ? theme.colorScheme.primaryContainer : null,
    child: ListTile(
      title: Text(row.name ?? l10n.scenarioCurrent),
      subtitle: Text(switch (row.best) {
        final best? when best.plan.monthsToClear == 0 => l10n.alreadyDebtFree,
        final best? => l10n.compareBest(
          strategyName(l10n, best.strategyId),
          formatDuration(l10n, best.plan.monthsToClear),
          formatMoney(best.plan.totalInterest, locale),
        ),
        null => l10n.compareNoPlan,
      }),
      trailing: isCheapest ? Chip(label: Text(l10n.cheapest)) : null,
    ),
  );
}
```

Create `lib/features/scenarios/presentation/scenario_form_screen.dart`:

```dart
import 'package:debt_destroyer/core/error_view.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:debt_destroyer/features/scenarios/domain/scenario.dart';
import 'package:debt_destroyer/features/scenarios/presentation/scenarios_providers.dart';
import 'package:debt_destroyer/features/settings/presentation/parameter_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Edits a saved scenario: its name, budget and strategy settings.
class ScenarioFormScreen extends ConsumerWidget {
  const ScenarioFormScreen({required this.scenarioId, super.key});

  final String scenarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final title = Text(l10n.editScenarioTitle);
    final body = switch (ref.watch(scenariosProvider)) {
      AsyncData(:final value) => switch (value
          .where((s) => s.id == scenarioId)
          .firstOrNull) {
        final scenario? => _ScenarioForm(
          // Amounts are rescaled when the currency changes.
          key: ValueKey('${scenario.id}-${scenario.monthlyBudget.currency}'),
          scenario: scenario,
        ),
        null => Center(child: Text(l10n.errorGeneric)),
      },
      AsyncError() => ErrorRetryView(
        onRetry: () => ref.invalidate(scenariosProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
    return Scaffold(appBar: AppBar(title: title), body: body);
  }
}

class _ScenarioForm extends ConsumerStatefulWidget {
  const _ScenarioForm({required this.scenario, super.key});

  final Scenario scenario;

  @override
  ConsumerState<_ScenarioForm> createState() => _ScenarioFormState();
}

class _ScenarioFormState extends ConsumerState<_ScenarioForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _budget;
  late final ParameterControllers _parameters;
  String? _nameError;
  String? _budgetError;
  Map<ParameterField, String> _parameterErrors = const {};

  @override
  void initState() {
    super.initState();
    final locale = ref.read(formatLocaleProvider);
    _name = TextEditingController(text: widget.scenario.name);
    _budget = TextEditingController(
      text: formatAmountInput(widget.scenario.monthlyBudget, locale),
    );
    _parameters = ParameterControllers(
      widget.scenario.parameters,
      locale: locale,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    _parameters.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = ref.watch(formatLocaleProvider);
    final code = widget.scenario.monthlyBudget.currency;
    InputDecoration decoration(String label) =>
        InputDecoration(labelText: label, border: const OutlineInputBorder());
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              controller: _name,
              decoration: decoration(l10n.scenarioNameLabel),
              forceErrorText: _nameError,
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              controller: _budget,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: decoration(l10n.settingsBudget),
              validator: (v) =>
                  parseAmountMinor(
                        v ?? '',
                        currencyCode: code,
                        locale: locale,
                      ) ==
                      null
                  ? l10n.errorInvalidAmount(
                      formatAmountInput(Money(30000, code), locale),
                    )
                  : null,
              forceErrorText: _budgetError,
              onChanged: (_) {
                if (_budgetError != null) setState(() => _budgetError = null);
              },
            ),
          ),
          ParameterFields(
            controllers: _parameters,
            errors: _parameterErrors,
            currencyCode: code,
            onEdited: (f) {
              if (_parameterErrors.containsKey(f)) {
                setState(() => _parameterErrors = {..._parameterErrors}..remove(f));
              }
            },
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
    final code = widget.scenario.monthlyBudget.currency;
    final updated = widget.scenario.copyWith(
      name: _name.text,
      monthlyBudget: Money(
        parseAmountMinor(_budget.text, currencyCode: code, locale: locale)!,
        code,
      ),
      parameters: _parameters.parse(locale: locale, currencyCode: code),
    );
    final outcome = await runGuarded(
      context,
      () => ref.read(scenarioActionsProvider.notifier).update(updated),
    );
    if (!mounted) return;
    switch (outcome) {
      case ScenarioSaved():
        context.pop();
      case ScenarioRejected(
        :final nameErrors,
        :final budgetErrors,
        :final parameterErrors,
      ):
        setState(() {
          _nameError = nameErrors.contains(ScenarioNameError.empty)
              ? l10n.errorScenarioNameEmpty
              : nameErrors.contains(ScenarioNameError.duplicate)
              ? l10n.errorScenarioNameDuplicate
              : null;
          _budgetError =
              budgetErrors.contains(BudgetValidationError.notPositive)
              ? l10n.errorBudgetNotPositive
              : budgetErrors.contains(BudgetValidationError.tooLarge)
              ? l10n.errorTooLarge
              : null;
          _parameterErrors = parameterErrorMessages(
            l10n,
            parameterErrors,
            locale,
          );
        });
      case null:
        break; // runGuarded already told the user
    }
  }
}
```

In `lib/app/router.dart`:
- Add `static const scenarios = '/scenarios';` and `static String editScenario(String id) => '$scenarios/$id';` to `Routes`.
- Import the two screens.
- Add the routes:

```dart
      GoRoute(
        path: Routes.scenarios,
        builder: (context, state) => const ScenariosScreen(),
        routes: [
          GoRoute(
            path: ':scenarioId',
            builder: (context, state) => ScenarioFormScreen(
              scenarioId: state.pathParameters['scenarioId']!,
            ),
          ),
        ],
      ),
```

In `strategies_screen.dart`:
- Add an `actions:` list to the `AppBar`:

```dart
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: l10n.scenariosTitle,
            onPressed: () => context.push(Routes.scenarios),
          ),
        ],
```

- Make `_FeasibleDetails` a `ConsumerWidget` (`build(BuildContext context, WidgetRef ref)`).
- Point the "Set yours" link at the scenario being viewed:

```dart
              TextButton(
                onPressed: () {
                  final id = ref.read(activeScenarioProvider).value?.id;
                  context.push(
                    id == null ? Routes.settings : Routes.editScenario(id),
                  );
                },
                child: Text(l10n.setCreditLimit),
              ),
```

- [ ] **Step 4: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "feat(scenarios): scenarios screen with editing, deleting and comparison"
```

---

### Task 14: Plan detail: scenario name, "What changes", export notes

**Files:**
- Create: `lib/features/analysis/presentation/plan_change_lines.dart`
- Modify: `lib/features/analysis/domain/schedule_table.dart`, `lib/features/analysis/data/schedule_export.dart`, `lib/features/analysis/presentation/plan_detail_screen.dart`, `lib/features/analysis/presentation/plan_summary_tab.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/analysis/schedule_test.dart`, `test/features/analysis/plan_detail_test.dart`

**Interfaces:**
- Consumes: `PlanChange`, `TransferChange`, `ConsolidationChange` (Tasks 4–5); `activeScenarioProvider` (Task 12).
- Produces:
  - `ScheduleTable.notes: List<String>` (default `const []`)
  - `buildScheduleTable(…, List<String> notes = const [])`
  - `scheduleTableFor(l10n, plan, {List<String> notes = const []})`
  - `List<String> planChangeLines(AppLocalizations l10n, PlanChange change, String locale)`

- [ ] **Step 1: Write the failing tests**

Append to `test/features/analysis/schedule_test.dart`:

```dart
  ScheduleTable withNotes() => buildScheduleTable(
    plan,
    debtNames: ['Visa', 'Loan, "car"'],
    labels: labels,
    notes: ['Scenario: Current', 'Transfer fee: £1,000.00'],
  );

  test('CSV puts notes above the schedule, then a blank line', () {
    final lines = scheduleToCsv(withNotes()).substring(1).split('\r\n');
    expect(lines.take(4), [
      'Scenario: Current',
      '"Transfer fee: £1,000.00"',
      '',
      'Month,Visa payment,Visa balance,"Loan, ""car"" payment",'
          '"Loan, ""car"" balance",Total payment,Total balance',
    ]);
  });

  test('XLSX puts notes above the schedule, then a blank row', () {
    final rows = Excel.decodeBytes(
      scheduleToXlsx(withNotes()),
    ).tables['Schedule']!.rows;
    expect(rows[0][0]!.value, TextCellValue('Scenario: Current'));
    expect(rows[3][0]!.value, TextCellValue('Month'));
  });
```

In `test/features/analysis/plan_detail_test.dart`, append:

```dart
  testWidgets('explains what a balance transfer changes', (tester) async {
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a', name: 'Visa')], // 1,000.00 at 19.9%
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plan(StrategyId.balanceTransfer),
    );
    await tester.scrollUntilVisible(find.text('What changes'), 100);
    for (final line in [
      'Visa: £1,000.00 moved to the transfer card',
      'Transfer fee: £40.00',
      'Credit limit: £1,040.00 (assumed)',
      '0% for 12 months',
    ]) {
      await tester.scrollUntilVisible(find.text(line), 100);
      expect(find.text(line), findsOneWidget);
    }
  });

  testWidgets('exports name the scenario and what changes', (tester) async {
    final exporter = _RecordingExporter();
    await pumpApp(
      tester,
      debts: [testDebt(id: 'a', name: 'Visa')],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plan(StrategyId.balanceTransfer),
      overrides: [planExporterProvider.overrideWithValue(exporter)],
    );
    await tester.tap(find.byTooltip('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spreadsheet (CSV)'));
    await tester.pumpAndSettle();
    final (table, _, _) = exporter.calls.single;
    expect(table.notes.first, 'Scenario: Current');
    expect(table.notes, contains('Transfer fee: £40.00'));
  });

  testWidgets('names a saved scenario under the title', (tester) async {
    final app = await pumpApp(
      tester,
      debts: [visa],
      scenarios: [
        Scenario(
          id: 's1',
          name: 'Bonus',
          monthlyBudget: const Money(50000, 'GBP'),
          parameters: const StrategyParameters(),
          createdAt: DateTime(2026, 9, 1),
        ),
      ],
      location: Routes.plan(StrategyId.avalanche),
    );
    app.container.read(selectedScenarioIdProvider.notifier).select('s1');
    await tester.pumpAndSettle();
    expect(find.text('Scenario: Bonus'), findsOneWidget);
  });
```

Add imports for `scenario.dart` and `scenarios_providers.dart`.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/analysis`
Expected: compilation errors: `notes` is not a parameter of `buildScheduleTable`, and `ScheduleTable.notes` is undefined.

- [ ] **Step 3: Implement**

In `lib/features/analysis/domain/schedule_table.dart`:
- Add `this.notes = const []` to the `ScheduleTable` constructor, with the field:

```dart
  /// Lines shown above the table in exports: the scenario and what the
  /// strategy changed.
  final List<String> notes;
```

- Add a `List<String> notes = const []` parameter to `buildScheduleTable`, and pass `notes: notes` to the `ScheduleTable`.

In `lib/features/analysis/data/schedule_export.dart`, write the notes first. In `scheduleToCsv`:

```dart
  final lines = [
    for (final note in table.notes) _csvField(note),
    if (table.notes.isNotEmpty) '',
    table.headers.map(_csvField).join(','),
```

and in `scheduleToXlsx`, before the headers row:

```dart
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet()!;
  excel.rename(defaultSheet, sheetName);
  for (final note in table.notes) {
    excel.appendRow(sheetName, [TextCellValue(note)]);
  }
  if (table.notes.isNotEmpty) {
    excel.appendRow(sheetName, [TextCellValue('')]);
  }
  excel.appendRow(sheetName, [for (final h in table.headers) TextCellValue(h)]);
```

Add to `lib/l10n/app_en.arb`:

```json
  "planScenario": "Scenario: {name}",
  "@planScenario": {"placeholders": {"name": {"type": "String"}}},
  "whatChanges": "What changes",
  "changeMovedToCard": "{name}: {amount} moved to the transfer card",
  "@changeMovedToCard": {"placeholders": {"name": {"type": "String"}, "amount": {"type": "String"}}},
  "changeTransferFee": "Transfer fee: {amount}",
  "@changeTransferFee": {"placeholders": {"amount": {"type": "String"}}},
  "changeCreditLimit": "Credit limit: {amount}",
  "@changeCreditLimit": {"placeholders": {"amount": {"type": "String"}}},
  "changeCreditLimitAssumed": "Credit limit: {amount} (assumed)",
  "@changeCreditLimitAssumed": {"placeholders": {"amount": {"type": "String"}}},
  "changePromoMonths": "{months, plural, =1{0% for 1 month} other{0% for {months} months}}",
  "@changePromoMonths": {"placeholders": {"months": {"type": "int"}}},
  "changeReplacedByLoan": "{name}: {amount} paid off by the loan",
  "@changeReplacedByLoan": {"placeholders": {"name": {"type": "String"}, "amount": {"type": "String"}}},
  "changeLoanPayment": "Loan: {payment} a month for {months} months at {apr}",
  "@changeLoanPayment": {"placeholders": {"payment": {"type": "String"}, "months": {"type": "int"}, "apr": {"type": "String"}}},
  "changeArrangementFee": "Arrangement fee: {amount}",
  "@changeArrangementFee": {"placeholders": {"amount": {"type": "String"}}},
```

Create `lib/features/analysis/presentation/plan_change_lines.dart`:

```dart
import 'package:debt_destroyer/core/l10n.dart';
import 'package:debt_destroyer/core/money_format.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// What a strategy moved or replaced, as lines of text for the Summary tab
/// and for exports.
List<String> planChangeLines(
  AppLocalizations l10n,
  PlanChange change,
  String locale,
) {
  String money(Money m) => formatMoney(m, locale);
  return switch (change) {
    TransferChange(
      :final moved,
      :final fee,
      :final creditLimit,
      :final limitAssumed,
      :final promoMonths,
    ) =>
      [
        for (final m in moved) l10n.changeMovedToCard(m.name, money(m.amount)),
        l10n.changeTransferFee(money(fee)),
        if (limitAssumed)
          l10n.changeCreditLimitAssumed(money(creditLimit))
        else
          l10n.changeCreditLimit(money(creditLimit)),
        l10n.changePromoMonths(promoMonths),
      ],
    ConsolidationChange(
      :final replaced,
      :final fee,
      :final monthlyPayment,
      :final termMonths,
      :final aprBps,
    ) =>
      [
        for (final r in replaced)
          l10n.changeReplacedByLoan(r.name, money(r.amount)),
        l10n.changeLoanPayment(
          money(monthlyPayment),
          termMonths,
          formatPercent(aprBps, locale),
        ),
        if (fee.isPositive) l10n.changeArrangementFee(money(fee)),
      ],
  };
}
```

In `plan_summary_tab.dart`, import `plan_change_lines.dart`. After the first `Card` in the `ListView`, add:

```dart
        if (plan.change case final change?) ...[
          _Section(l10n.whatChanges),
          Card(
            child: Column(
              children: [
                for (final line in planChangeLines(l10n, change, locale))
                  ListTile(dense: true, title: Text(line)),
              ],
            ),
          ),
        ],
```

In `plan_detail_screen.dart`:
- Import `scenarios_providers.dart` and `plan_change_lines.dart`. `formatLocaleProvider` comes from `core/l10n.dart`, which is already imported.
- In `_PlanTabs.build`:

```dart
    final locale = ref.watch(formatLocaleProvider);
    final scenarioName = ref.watch(activeScenarioProvider).value?.name;
    final table = scheduleTableFor(
      l10n,
      plan,
      notes: [
        l10n.planScenario(scenarioName ?? l10n.scenarioCurrent),
        if (plan.change case final change?)
          ...planChangeLines(l10n, change, locale),
      ],
    );
```

- Show a saved scenario's name under the title. Set the `AppBar`'s `title:` to:

```dart
          title: scenarioName == null
              ? title
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    Text(
                      l10n.planScenario(scenarioName),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
```

- Give `scheduleTableFor` a `{List<String> notes = const []}` parameter and pass it on to `buildScheduleTable`.

- [ ] **Step 4: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "feat(analysis): scenario name, what changes, and export notes"
```

---

### Task 15: End-to-end widget test and docs

**Files:**
- Create: `test/app/end_to_end_test.dart`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write the end-to-end test**

Create `test/app/end_to_end_test.dart`:

```dart
import 'package:debt_destroyer/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

import '../helpers/pump_app.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'add a promo debt, compare, pay more, save a scenario, open its plan',
    (tester) async {
      final app = await pumpApp(tester);

      await tapVisible(tester, find.text('Add debt'));
      await tester.enterText(field('Name'), 'Visa');
      await tester.enterText(field('Balance'), '2000');
      await tester.enterText(field('Interest rate (APR %)'), '22.9');
      await tester.enterText(field('Minimum payment (% of balance)'), '3');
      await tester.enterText(field('Minimum payment (at least)'), '25');
      await tapVisible(tester, find.byKey(const ValueKey('promo')));
      await tester.enterText(field('Promotional rate (APR %)'), '0');
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(
        app.repository.stored.single.promo,
        const Promo(aprBps: 0, months: 12),
      );

      await tapVisible(tester, find.text('Compare strategies'));
      expect(app.router.location, Routes.strategies);
      expect(find.textContaining('Minimums only: '), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('payMore')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Save as scenario'));
      await tester.enterText(
        find.byKey(const ValueKey('scenarioName')),
        'Stretch',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(app.scenarios.stored.single.name, 'Stretch');

      await tester.scrollUntilVisible(
        find.text('Highest interest first'),
        100,
      );
      await tapVisible(tester, find.text('Highest interest first'));
      expect(app.router.location, Routes.plan(StrategyId.avalanche));
      expect(find.text('Scenario: Stretch'), findsOneWidget);
    },
  );
}
```

- [ ] **Step 2: Run it**

Run: `flutter test test/app/end_to_end_test.dart`
Expected: PASS. If it fails, the failure is a real integration bug between tasks. Debug it (superpowers:systematic-debugging) rather than weakening the test.

- [ ] **Step 3: Update CLAUDE.md**

In `CLAUDE.md`:
1. Under "Migration status", add after Plan 4:

```markdown
- [x] Plan 5: v2 better planning — snowball, your order, minimums-only baseline, promos, realistic transfer and consolidation, pay-more slider, saved scenarios (`docs/superpowers/plans/2026-09-24-plan-5-v2-planning.md`, spec `docs/superpowers/specs/2026-09-24-v2-planning-design.md`)
```

2. In "Project goal", after the design spec bullet, add: `- **v2 spec:** docs/superpowers/specs/2026-09-24-v2-planning-design.md (builds on the v1 spec).`
3. Add to "Gotchas":

```markdown
- The engine runs in three stages: `restructure` (transfer/consolidation turn the user's debts into the debts actually paid), `allocationOrder` (avalanche-style strategies re-rank every month by the rate charged that month) and `simulate`. `PayoffPlan.debts` is in the order debts are *cleared*, not the priority order.
- Promotions are stored as their last calendar month (`promoEndsYearMonth`, `yyyymm`) and read as "months left" using the repository's clock; an ended promo reads back as none. Widget tests fix the clock at 24 Sep 2026.
- `plansProvider` gives a `PlanSet` (`ranked` plus the minimums-only `baseline`) for the *active scenario* (the selected saved scenario, or Current = Settings) plus the slider's `extraPaymentProvider`, which resets when the currency or the selection changes.
- `DriftDebtRepository.convertAmounts` also rescales saved scenarios (same database, same transaction). The in-memory test repositories don't rescale scenarios.
- Strategy-parameter fields (Settings and the scenario editor) come from `ParameterFields` in `lib/features/settings/presentation/parameter_fields.dart`; add new parameters there once.
```

4. In the Legacy "Solver" section, add at the end: `The Flutter app no longer offers lowest-APR-first or the 110% "boosted" plan (v2 spec §3.1).`

- [ ] **Step 4: Final verification**

Run from the repo root:
```bash
./tool/codegen.sh
dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test
flutter test
(cd packages/payoff_engine && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && dart test)
```
Expected: `No issues found!` twice, and `All tests passed!` for both suites.

- [ ] **Step 5: Commit**

```bash
git add test CLAUDE.md
git commit -m "test: v2 end-to-end flow; docs: v2 in CLAUDE.md"
```
