# Moving Balances Between Your Own Cards: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users record balance-transfer offers on their own cards, and add a "Move balances between your cards" pay-off strategy. It finds worthwhile moves and models each card as portions sharing one minimum, with payments allocated by the UK rule.

**Architecture:** In `payoff_engine`:
- `Debt` gains an optional `TransferOffer`.
- `simulate` learns about card *groups*: one minimum on the card total, allocated lowest rate first; extra goes highest current rate first within a card.
- `calculate` runs a greedy move search for the new `CardTransfers` strategy, over `_simulateBest` (the look-ahead avalanche).

In the app:
- Drift schema 3 stores the offer.
- The debt form edits it.
- Strategies, plan detail and exports show the moves.

**Tech Stack:** Dart 3 / Flutter 3.47.2, freezed, Riverpod 3 (codegen), Drift 2.35 (`make-migrations`), go_router, intl/ARB.

**Spec:** `docs/superpowers/specs/2026-09-25-card-transfers-design.md`. It builds on `2026-09-24-v2-planning-design.md`. Read both. Where the spec and this plan disagree, the spec wins; stop and ask.

## Global Constraints

- Money is integer minor units (`Money`). Rates are integer basis points. Interest is `divideHalfEven(balance × apr, 120000)` once a month. Fees are `divideHalfEven(amount × feeBps, 10000)`. Never use `double` for money except for display.
- `payoff_engine` has no Flutter imports. `calculate` is pure and never mutates its input.
- With no transfer offers recorded, every existing plan's figures must stay exactly the same. Every existing engine test passes unchanged, except the lineup and count tests this plan updates explicitly.
- Offer limits: fee 0–10000 bps. Promo aprBps 0–10000, months 1–`kMaxPromoMonths` (120). Available credit > 0 and ≤ `kMaxAmountMinor` (100000000000), in the debt's currency. Offers are allowed only where `isTransferable(type)`. At most 10 moves (`kMaxCardMoves`).
- The UK allocation rule: a card's minimum is worked out once on the card's total with the card's own rule, and allocated to portions lowest current APR first. Payments above the minimum go to that card's portions highest current APR first.
- Borrowing alternatives (consolidation, a new 0% card) stay apart and are never marked cheapest. `cardTransfers` is a way to pay off: `isBorrowingAlternative` is false.
- TDD is mandatory. Every task ends with all of these green:
  - `dart analyze --fatal-infos`
  - `dart format --output=none --set-exit-if-changed lib test` (in the app and in `packages/payoff_engine`)
  - `flutter test`
  - `(cd packages/payoff_engine && dart test)`
- After changing any freezed model, Riverpod provider, Drift table or ARB file, run `./tool/codegen.sh` from the repo root. Generated `*.g.dart` and `*.freezed.dart` files are not committed.
- UI text goes in `lib/l10n/app_en.arb`. Money and percentages use `lib/core/money_format.dart` with `formatLocaleProvider`.
- Widget tests use `pumpApp`. The test clock is 24 Sep 2026. The Settings and debt form lists are taller than the 800×600 test viewport, and each `TextFormField` contains its own Scrollable, so `scrollUntilVisible` needs an explicit `scrollable:` finder (see the `formList` helper in `test/features/debts/debt_form_test.dart`). Change only how widgets are found or scrolled, never what is asserted.
- Commit messages end with the two attribution lines given in the session instructions.

## Review Focus

These inputs are implied by the spec but no feature test would naturally hit them. Each has a test in the task named.

1. **No offers recorded:** every other strategy's figures are unchanged, and card transfers reports "no card has an offer". *(Task 3, invariants and regression)*
2. **A move that would make the minimums unaffordable** (for example onto a card with a steep percentage minimum) must never be chosen. *(Task 3)*
3. **A card that is both a possible source and has an offer** must never both give and receive money. *(Task 3)*
4. **Switching currency** rescales an offer's available credit along with everything else. *(Task 4)*
5. **Changing a card's kind to one that can't receive transfers** drops its offer when saved, rather than failing validation silently. *(Task 5)*

---

### Task 1: Transfer offers on debts

**Files:**
- Modify: `packages/payoff_engine/lib/src/debt.dart`, `packages/payoff_engine/lib/src/validation.dart`
- Test: `packages/payoff_engine/test/transfer_offer_test.dart` (new), `packages/payoff_engine/test/helpers.dart`
- Modify (app, so the exhaustive switch compiles): `lib/features/debts/presentation/debt_form_screen.dart` (`_showErrors`)

**Interfaces:**
- Produces:
  - `TransferOffer({required int feeBps, Promo? promo, required Money availableCredit})`
  - `Debt.transferOffer: TransferOffer?`
  - `DebtValidationError.{offerOnNonCard, offerFeeOutOfRange, offerPromoAprOutOfRange, offerPromoMonthsOutOfRange, offerCreditNotPositive, offerCreditTooLarge, offerCurrencyMismatch}`
  - test helper `debt(…, TransferOffer? transferOffer)`

- [ ] **Step 1: Write the failing tests**

In `packages/payoff_engine/test/helpers.dart`, add `TransferOffer? transferOffer,` to `debt()` and pass it through (`transferOffer: transferOffer,`).

Create `packages/payoff_engine/test/transfer_offer_test.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  TransferOffer offer({
    int feeBps = 300,
    Promo? promo = const Promo(aprBps: 0, months: 12),
    Money? credit,
  }) => TransferOffer(
    feeBps: feeBps,
    promo: promo,
    availableCredit: credit ?? gbp(200000),
  );

  Set<DebtValidationError> errors(
    TransferOffer o, {
    DebtType type = DebtType.creditCard,
  }) => validateDebt(
    debt(id: 'a', balance: 100, aprBps: 1990, type: type, transferOffer: o),
  );

  test('accepts a card offer with or without a promo', () {
    expect(errors(offer()), isEmpty);
    expect(errors(offer(promo: null)), isEmpty);
    expect(errors(offer(), type: DebtType.storeCard), isEmpty);
  });

  test('only cards can receive transfers', () {
    expect(errors(offer(), type: DebtType.loan), {
      DebtValidationError.offerOnNonCard,
    });
  });

  test('checks the fee and the promo', () {
    expect(errors(offer(feeBps: 10001)), {
      DebtValidationError.offerFeeOutOfRange,
    });
    expect(errors(offer(promo: const Promo(aprBps: 10001, months: 3))), {
      DebtValidationError.offerPromoAprOutOfRange,
    });
    expect(errors(offer(promo: const Promo(aprBps: 0, months: 0))), {
      DebtValidationError.offerPromoMonthsOutOfRange,
    });
    expect(
      errors(offer(promo: const Promo(aprBps: 0, months: kMaxPromoMonths + 1))),
      {DebtValidationError.offerPromoMonthsOutOfRange},
    );
  });

  test('checks the available credit', () {
    expect(errors(offer(credit: gbp(0))), {
      DebtValidationError.offerCreditNotPositive,
    });
    expect(errors(offer(credit: gbp(kMaxAmountMinor + 1))), {
      DebtValidationError.offerCreditTooLarge,
    });
    expect(errors(offer(credit: const Money(100, 'USD'))), {
      DebtValidationError.offerCurrencyMismatch,
    });
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd packages/payoff_engine && dart test test/transfer_offer_test.dart`
Expected: compilation errors: `TransferOffer` and `transferOffer` are undefined.

- [ ] **Step 3: Implement**

In `packages/payoff_engine/lib/src/debt.dart`, add after `Promo`:

```dart
/// A balance-transfer offer on one of the user's own cards: what moving a
/// balance onto it costs, and how much it can take.
@freezed
abstract class TransferOffer with _$TransferOffer {
  const factory TransferOffer({
    /// Fee as a share of the amount moved, in basis points.
    required int feeBps,

    /// Rate and length for moved money, counted from the move (a plan's
    /// month 1). Afterwards moved money pays the card's own APR.
    Promo? promo,

    /// Room left on the card; moves plus their fees must fit.
    required Money availableCredit,
  }) = _TransferOffer;
}
```

and add to `Debt`, after `promo`:

```dart
    /// A balance-transfer offer on this card, if the user has one.
    TransferOffer? transferOffer,
```

In `packages/payoff_engine/lib/src/validation.dart`:
- Import `package:payoff_engine/src/debt_kind.dart`.
- Append the seven values to `DebtValidationError`, in the order listed in the Interfaces.
- Add at the end of `validateDebt`'s set:

```dart
  if (debt.transferOffer != null && !isTransferable(debt.type))
    DebtValidationError.offerOnNonCard,
  if (debt.transferOffer case final o? when !_isRate(o.feeBps))
    DebtValidationError.offerFeeOutOfRange,
  if (debt.transferOffer?.promo case final p? when !_isRate(p.aprBps))
    DebtValidationError.offerPromoAprOutOfRange,
  if (debt.transferOffer?.promo case final p?
      when p.months < 1 || p.months > kMaxPromoMonths)
    DebtValidationError.offerPromoMonthsOutOfRange,
  if (debt.transferOffer case final o? when !o.availableCredit.isPositive)
    DebtValidationError.offerCreditNotPositive,
  if (debt.transferOffer case final o?
      when o.availableCredit.minor > kMaxAmountMinor)
    DebtValidationError.offerCreditTooLarge,
  if (debt.transferOffer case final o?
      when o.availableCredit.currency != debt.balance.currency)
    DebtValidationError.offerCurrencyMismatch,
```

In `lib/features/debts/presentation/debt_form_screen.dart` `_showErrors`, add the seven new cases before `floorCurrencyMismatch` as one `case …: break;` group, with the comment `// the form has no offer fields until Task 5`.

- [ ] **Step 4: Generate and run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test && (cd packages/payoff_engine && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && dart test)`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add packages/payoff_engine lib
git commit -m "feat(engine): balance-transfer offers on the user's cards"
```

---

### Task 2: Cards made of portions in `simulate`

**Files:**
- Modify: `packages/payoff_engine/lib/src/simulate.dart`, `packages/payoff_engine/lib/src/calculator.dart` (`_simulateBest` passes `groups` through)
- Test: `packages/payoff_engine/test/simulate_test.dart`

**Interfaces:**
- Consumes: `minimumPaymentMinor`, `aprInMonth`.
- Produces:
  - `simulate(…, List<List<int>>? groups)`. `groups` holds indexes into `debts`, each card's own debt first. When null, each debt is its own group, which is today's behaviour exactly.
  - `_simulateBest(…, List<List<int>>? groups)` (private, in calculator.dart)

- [ ] **Step 1: Write the failing tests**

Append to `packages/payoff_engine/test/simulate_test.dart`:

```dart
  group('cards made of portions', () {
    // One card: its own 100.00 at 12%, and 100.00 moved on at 0% for 12
    // months. The card's minimum is 10% of the card total, with no floor.
    final own = debt(
      id: 'card',
      balance: 10000,
      aprBps: 1200,
      minPaymentPercentBps: 1000,
    );
    final moved = debt(
      id: 'card#from-x',
      balance: 10000,
      aprBps: 1200,
      promo: const Promo(aprBps: 0, months: 12),
    );

    PayoffPlan run(int budget) => planOf(
      simulate(
        strategyId: StrategyId.cardTransfers,
        debts: [own, moved],
        budget: gbp(budget),
        fees: gbp(0),
        order: (_) => [0, 1],
        groups: [
          [0, 1],
        ],
      ),
    );

    int col(PayoffPlan p, String id) => p.debts.indexWhere((d) => d.id == id);

    test('one minimum on the card total, lowest rate first', () {
      // Month 1: own +1.00 interest; card total 201.00; 10% minimum is
      // 20.10, all to the 0% portion. The extra 10.00 goes to the 12% one.
      final plan = run(3010);
      final first = plan.months.first;
      expect(first.interest[col(plan, 'card')], gbp(100));
      expect(first.interest[col(plan, 'card#from-x')], gbp(0));
      expect(first.payments[col(plan, 'card#from-x')], gbp(2010));
      expect(first.payments[col(plan, 'card')], gbp(1000));
    });

    test('the 0% portion is cleared last', () {
      final plan = run(3010);
      expect(plan.payoffOrder, ['card', 'card#from-x']);
    });

    test('the minimums of all cards must fit the budget', () {
      expect(
        simulate(
          strategyId: StrategyId.cardTransfers,
          debts: [own, moved],
          budget: gbp(2000),
          fees: gbp(0),
          order: (_) => [0, 1],
          groups: [
            [0, 1],
          ],
        ),
        PayoffResult.infeasible(
          strategyId: StrategyId.cardTransfers,
          shortfall: gbp(10),
          month: 1,
        ),
      );
    });
  });
```

`StrategyId.cardTransfers` doesn't exist until Task 3. For this task only, use `StrategyId.avalanche` in these three tests. Task 3 switches them to `cardTransfers` when it adds the id.

- [ ] **Step 2: Run them to verify they fail**

Run: `cd packages/payoff_engine && dart test test/simulate_test.dart`
Expected: compilation error: no named parameter `groups`.

- [ ] **Step 3: Implement**

In `simulate.dart`, add the parameter `List<List<int>>? groups,`, and extend the doc comment:

```dart
/// [groups] lists the portions of each card as indexes into [debts], the
/// card's own debt first. A card's minimum is worked out once on its total
/// with its own debt's rule and paid to its portions lowest current rate
/// first; money above the minimum goes to its portions highest current rate
/// first (the UK rule). Cards are ranked for extra money by their
/// best-ranked portion in [order]. Without [groups] every debt is a card of
/// its own.
```

Replace the body from the `final payments = [` line to the end of the `for (final (position, i) in priority.indexed)` loop with:

```dart
    final payments = List.filled(n, 0);
    var minimumsTotal = 0;
    for (final members in cards) {
      final total = members.fold(0, (s, i) => s + balances[i]);
      if (total <= 0) continue;
      var due = minimumPaymentMinor(debts[members.first], total);
      minimumsTotal += due;
      for (final i in byRate(members, month, highestFirst: false)) {
        if (due == 0) break;
        final pay = due < balances[i] ? due : balances[i];
        payments[i] += pay;
        due -= pay;
      }
    }
    if (minimumsTotal > budget.minor) {
      return PayoffResult.infeasible(
        strategyId: strategyId,
        shortfall: Money(minimumsTotal - budget.minor, currency),
        month: month,
      );
    }

    for (var i = 0; i < n; i++) {
      balances[i] -= payments[i];
    }
    // Cards in the order their best-ranked portion appears; within a card,
    // highest current rate first.
    final seen = <int>{};
    final sequence = [
      for (final i in order(month))
        if (seen.add(cardOf[i]))
          ...byRate(cards[cardOf[i]], month, highestFirst: true),
    ];
    if (allowExtra) {
      var remaining = budget.minor - minimumsTotal;
      for (final i in sequence) {
        if (remaining == 0) break;
        final overpayable = debts[cards[cardOf[i]].first].allowsOverpayment;
        if (!overpayable || balances[i] == 0) continue;
        final extra = remaining < balances[i] ? remaining : balances[i];
        payments[i] += extra;
        balances[i] -= extra;
        remaining -= extra;
      }
    }
    for (final (position, i) in sequence.indexed) {
      if (balances[i] == 0 && clearedAt[i] == null) {
        clearedAt[i] = (month, position);
      }
    }
```

and before the `while` loop:

```dart
  final cards = groups ?? [for (var i = 0; i < n; i++) [i]];
  final cardOf = List.filled(n, 0);
  for (final (c, members) in cards.indexed) {
    for (final i in members) {
      cardOf[i] = c;
    }
  }
  // A card's portions by the rate charged in [month]; ties keep list order.
  List<int> byRate(
    List<int> members,
    int month, {
    required bool highestFirst,
  }) {
    final sorted = [...members];
    mergeSort<int>(
      sorted,
      compare: (a, b) {
        final byApr = aprInMonth(debts[a], month).compareTo(
          aprInMonth(debts[b], month),
        );
        return highestFirst ? -byApr : byApr;
      },
    );
    return sorted;
  }
```

`mergeSort` (a stable sort) comes from `package:collection/collection.dart`. Add `collection: ^1.19.0` to `packages/payoff_engine/pubspec.yaml` `dependencies` if it isn't already resolvable, then run `dart pub get`. Dart's `List.sort` isn't guaranteed stable, and the tie order matters for payoff order.

In `calculator.dart`, add a `List<List<int>>? groups` parameter to `_simulateBest` and pass `groups: groups` to `simulate`.

- [ ] **Step 4: Run all engine tests**

Run: `cd packages/payoff_engine && dart format lib test && dart analyze --fatal-infos && dart test`
Expected: `All tests passed!`. Every existing test is unchanged: with `groups` null, each card has one portion, so the minimum, allocation and clearing positions are exactly as before.

- [ ] **Step 5: Commit**

```bash
git add packages/payoff_engine
git commit -m "feat(engine): cards made of portions with one minimum and UK allocation"
```

---

### Task 3: The card-transfers strategy and move search

**Files:**
- Create: `packages/payoff_engine/lib/src/fee_fit.dart`, `packages/payoff_engine/lib/src/card_transfers.dart`
- Modify: `packages/payoff_engine/lib/src/strategy.dart`, `payoff_result.dart`, `restructure.dart`, `allocation_order.dart`, `calculator.dart`, `packages/payoff_engine/lib/payoff_engine.dart`
- Test: `packages/payoff_engine/test/card_transfers_test.dart` (new), `strategy_test.dart`, `simulate_test.dart`, `invariants_test.dart`
- Modify (app, exhaustive switches and text): `lib/core/labels.dart`, `lib/features/strategies/domain/strategy_groups.dart`, `lib/features/analysis/presentation/plan_change_lines.dart`, `lib/l10n/app_en.arb`
- Test (app): `test/core/labels_test.dart`, `test/features/strategies/plans_providers_test.dart`

**Interfaces:**
- Consumes: `TransferOffer` (Task 1); `simulate(…, groups:)` and `_simulateBest(…, groups:)` (Task 2); `isTransferable`, `aprInMonth`.
- Produces:
  - `StrategyId.cardTransfers` (enum order: avalanche, snowball, customOrder, cardTransfers, consolidation, balanceTransfer, minimumsOnly)
  - `Strategy.cardTransfers()` (class `CardTransfers`); `standardStrategies` gives `[avalanche, snowball, customOrder, cardTransfers, consolidation, balanceTransfer]`
  - `NotApplicableReason.{noCardOffers, noWorthwhileMoves}`
  - `CardMove({fromDebtId, fromName, toDebtId, toName, Money amount, Money fee, Promo? promo})`
  - `PlanChange.cardTransfers({required List<CardMove> moves, required Money fee})` (class `CardTransferChange`)
  - `int largestFittingAmount(int room, int max, int Function(int) fee)`
  - `const int kMaxCardMoves = 10`
  - `({List<Debt> debts, List<List<int>> groups}) applyCardMoves(List<Debt> debts, List<CardMove> moves)`
  - `List<CardMove> cardMoveCandidates(List<Debt> debts, List<CardMove> moves)`
  - App: `strategyName`, `strategyDescription` and `strategyBestFor` cover `cardTransfers` (nickname null); `notApplicableReason` covers both new reasons; `planChangeLines` covers `CardTransferChange`

- [ ] **Step 1: Write the failing engine tests**

Create `packages/payoff_engine/test/card_transfers_test.dart`:

```dart
import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const strategy = Strategy.cardTransfers();
  const zeroForAYear = Promo(aprBps: 0, months: 12);

  // Store card: 1,000.00 at 30%. Amex: 500.00 at 12% with an offer of
  // 0% for 12 months, 3% fee, 600.00 of room.
  final store = debt(
    id: 'store',
    name: 'Store',
    type: DebtType.storeCard,
    balance: 100000,
    aprBps: 3000,
    minPaymentPercentBps: 300,
    minPaymentFloor: 2500,
  );
  final amex = debt(
    id: 'amex',
    name: 'Amex',
    balance: 50000,
    aprBps: 1200,
    minPaymentPercentBps: 300,
    minPaymentFloor: 2500,
    transferOffer: TransferOffer(
      feeBps: 300,
      promo: zeroForAYear,
      availableCredit: gbp(60000),
    ),
  );

  PayoffResult run(List<Debt> debts, int budget) =>
      calculate(debts: debts, monthlyBudget: gbp(budget), strategy: strategy);

  test('moves the most that fits the room, fee included', () {
    // x + 3% of x <= 600.00 gives x = 582.52 with a 17.48 fee (600.00);
    // 582.53 would need 600.01.
    final plan = planOf(run([store, amex], 30000));
    final change = plan.change! as CardTransferChange;
    expect(change.moves, [
      CardMove(
        fromDebtId: 'store',
        fromName: 'Store',
        toDebtId: 'amex',
        toName: 'Amex',
        amount: gbp(58252),
        fee: gbp(1748),
        promo: zeroForAYear,
      ),
    ]);
    expect(plan.totalFees, gbp(1748));
    expect(
      plan.debts.map((d) => d.id),
      containsAll(['store', 'amex', 'amex#from-store']),
    );
    expect(
      plan.debts.firstWhere((d) => d.id == 'amex#from-store').name,
      'Amex (moved from Store)',
    );
  });

  test('a move is kept only because the plan costs less with it', () {
    final withMoves = planOf(run([store, amex], 30000));
    final without = planOf(
      calculate(
        debts: [store, amex],
        monthlyBudget: gbp(30000),
        strategy: const Strategy.avalanche(),
      ),
    );
    expect(withMoves.totalPaid < without.totalPaid, isTrue);
  });

  test('no offers means not applicable', () {
    expect(
      run([store, amex.copyWith(transferOffer: null)], 30000),
      const PayoffResult.notApplicable(
        strategyId: StrategyId.cardTransfers,
        reason: NotApplicableReason.noCardOffers,
      ),
    );
  });

  test('a move that costs more than it saves is not made', () {
    // 13% onto 12% with a 10% fee and no promo never pays for itself.
    final a = debt(id: 'a', balance: 10000, aprBps: 1300);
    final b = debt(
      id: 'b',
      balance: 10000,
      aprBps: 1200,
      transferOffer: TransferOffer(feeBps: 1000, availableCredit: gbp(50000)),
    );
    expect(
      run([a, b], 5000),
      const PayoffResult.notApplicable(
        strategyId: StrategyId.cardTransfers,
        reason: NotApplicableReason.noWorthwhileMoves,
      ),
    );
  });

  test('never moves onto a card whose rate is not lower', () {
    final b = amex.copyWith(
      aprBps: 3500,
      transferOffer: TransferOffer(feeBps: 0, availableCredit: gbp(60000)),
    );
    expect(cardMoveCandidates([store, b], const []), isEmpty);
  });

  test('never moves from a loan or onto the same card', () {
    final loan = debt(
      id: 'loan',
      type: DebtType.loan,
      balance: 100000,
      aprBps: 3000,
    );
    expect(
      cardMoveCandidates([loan, amex], const []).map((m) => m.fromDebtId),
      isNot(contains('loan')),
    );
    expect(
      cardMoveCandidates([amex], const []),
      isEmpty,
      reason: 'the only card with an offer cannot move onto itself',
    );
  });

  test('a card never both gives and receives money', () {
    // Both cards have offers and each could move to the other.
    final a = debt(
      id: 'a',
      name: 'A',
      balance: 100000,
      aprBps: 3000,
      transferOffer: TransferOffer(
        feeBps: 0,
        promo: zeroForAYear,
        availableCredit: gbp(200000),
      ),
    );
    final b = debt(
      id: 'b',
      name: 'B',
      balance: 100000,
      aprBps: 2500,
      transferOffer: TransferOffer(
        feeBps: 0,
        promo: zeroForAYear,
        availableCredit: gbp(200000),
      ),
    );
    final change =
        planOf(run([a, b], 30000)).change! as CardTransferChange;
    final sources = change.moves.map((m) => m.fromDebtId).toSet();
    final targets = change.moves.map((m) => m.toDebtId).toSet();
    expect(sources.intersection(targets), isEmpty);
  });

  test('never chooses moves that make the minimums unaffordable', () {
    // Amex's minimum is 50% of its balance: taking the store balance on
    // would push its minimum past the budget.
    final a = debt(
      id: 'a',
      type: DebtType.storeCard,
      balance: 10000,
      aprBps: 3000,
      minPaymentPercentBps: 300,
    );
    final b = debt(
      id: 'b',
      balance: 10000,
      aprBps: 1200,
      minPaymentPercentBps: 5000,
      transferOffer: TransferOffer(
        feeBps: 0,
        promo: zeroForAYear,
        availableCredit: gbp(20000),
      ),
    );
    expect(
      run([a, b], 5400),
      const PayoffResult.notApplicable(
        strategyId: StrategyId.cardTransfers,
        reason: NotApplicableReason.noWorthwhileMoves,
      ),
    );
  });

  test('stops after kMaxCardMoves moves', () {
    final sources = [
      for (var i = 0; i < 12; i++)
        debt(
          id: 's${i.toString().padLeft(2, '0')}',
          balance: 1000,
          aprBps: 3000,
        ),
    ];
    final target = debt(
      id: 't',
      balance: 1000,
      aprBps: 1200,
      transferOffer: TransferOffer(
        feeBps: 0,
        promo: zeroForAYear,
        availableCredit: gbp(1000000),
      ),
    );
    final change =
        planOf(run([...sources, target], 30000)).change!
            as CardTransferChange;
    expect(change.moves, hasLength(kMaxCardMoves));
  });
}
```

In `simulate_test.dart`, change the three `StrategyId.avalanche` placeholders from Task 2 to `StrategyId.cardTransfers`.

In `strategy_test.dart`, add `expect(const Strategy.cardTransfers().id, StrategyId.cardTransfers);`, and make the lineup test expect `[avalanche, snowball, customOrder, cardTransfers, consolidation, balanceTransfer]`.

In `invariants_test.dart`:
- In `randomDebts`, give roughly one card in three an offer:

```dart
        transferOffer: r.nextInt(3) == 0
            ? TransferOffer(
                feeBps: r.nextInt(501),
                promo: r.nextBool()
                    ? Promo(aprBps: r.nextInt(301), months: 1 + r.nextInt(24))
                    : null,
                availableCredit: gbp(1 + r.nextInt(500000)),
              )
            : null,
```

  Only pass it when `type` is `creditCard` or `storeCard`: compute `type` first, then use `isTransferable(type) && r.nextInt(3) == 0`.
- Add at the end of the `Feasible` arm:

```dart
            if (plan.change case CardTransferChange(:final moves)) {
              for (final target in debts.where((d) => d.transferOffer != null)) {
                final used = moves
                    .where((m) => m.toDebtId == target.id)
                    .fold(gbp(0), (s, m) => s + m.amount + m.fee);
                expect(
                  used <= target.transferOffer!.availableCredit,
                  isTrue,
                  reason: '$label: room exceeded on ${target.id}',
                );
              }
            }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd packages/payoff_engine && dart test`
Expected: compilation errors: `Strategy.cardTransfers`, `CardMove`, `CardTransferChange`, `cardMoveCandidates` and `kMaxCardMoves` are undefined.

- [ ] **Step 3: Implement the engine**

Create `packages/payoff_engine/lib/src/fee_fit.dart`, moving `_largestFitting` out of `restructure.dart`, which now imports this file:

```dart
/// The largest amount up to [max] that fits in [room] together with its fee.
/// The amount plus its fee rises with the amount, so a binary search finds it.
int largestFittingAmount(int room, int max, int Function(int) fee) {
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

In `strategy.dart`:
- Insert `cardTransfers` after `customOrder` in `StrategyId`.
- Add the factory:

```dart
  /// Move the most expensive card balances onto the user's own cards'
  /// transfer offers where that saves money, then pay off highest interest
  /// first.
  const factory Strategy.cardTransfers() = CardTransfers;
```

- Add `CardTransfers() => StrategyId.cardTransfers,` to `id`.
- Insert `const Strategy.cardTransfers(),` after `customOrder` in `standardStrategies`.

In `payoff_result.dart`:
- Add `noCardOffers, noWorthwhileMoves` to `NotApplicableReason`.
- Import `debt.dart` for `Promo`.
- Add:

```dart
/// A balance moved from one of the user's cards onto another's transfer
/// offer. [amount] left the source; [amount] plus [fee] joined the target.
@freezed
abstract class CardMove with _$CardMove {
  const factory CardMove({
    required String fromDebtId,
    required String fromName,
    required String toDebtId,
    required String toName,
    required Money amount,
    required Money fee,
    Promo? promo,
  }) = _CardMove;
}
```

and the `PlanChange` variant:

```dart
  /// [moves] in the order they were chosen; [fee] is their total fee.
  const factory PlanChange.cardTransfers({
    required List<CardMove> moves,
    required Money fee,
  }) = CardTransferChange;
```

Create `packages/payoff_engine/lib/src/card_transfers.dart`:

```dart
import 'package:payoff_engine/src/debt.dart';
import 'package:payoff_engine/src/debt_kind.dart';
import 'package:payoff_engine/src/fee_fit.dart';
import 'package:payoff_engine/src/money.dart';
import 'package:payoff_engine/src/payoff_result.dart';
import 'package:payoff_engine/src/rounding.dart';

/// Most moves the card-transfers strategy makes.
const int kMaxCardMoves = 10;

/// [debts] with [moves] applied: each source reduced by what left it (and
/// dropped if emptied), each target followed by a portion per move onto it.
/// [groups] lists each card's portions as indexes, its own debt first.
({List<Debt> debts, List<List<int>> groups}) applyCardMoves(
  List<Debt> debts,
  List<CardMove> moves,
) {
  final out = <Debt>[];
  final groups = <List<int>>[];
  for (final d in debts) {
    final left =
        d.balance.minor -
        moves
            .where((m) => m.fromDebtId == d.id)
            .fold(0, (s, m) => s + m.amount.minor);
    if (left <= 0) continue;
    final group = [out.length];
    out.add(d.copyWith(balance: Money(left, d.balance.currency)));
    for (final m in moves.where((m) => m.toDebtId == d.id)) {
      group.add(out.length);
      out.add(
        Debt(
          id: '${d.id}#from-${m.fromDebtId}',
          name: '${d.name} (moved from ${m.fromName})',
          type: d.type,
          balance: m.amount + m.fee,
          aprBps: d.aprBps,
          minPaymentPercentBps: 0,
          minPaymentFloor: Money.zero(d.balance.currency),
          allowsOverpayment: d.allowsOverpayment,
          promo: m.promo,
        ),
      );
    }
    groups.add(group);
  }
  return (debts: out, groups: groups);
}

/// The moves worth simulating next, on top of [moves]: from a transferable
/// debt that hasn't received money onto another debt with an offer that
/// hasn't given any, where money moved would pay a lower rate in month 1,
/// each for the most that fits the target's remaining room with its fee.
/// Ordered by source name, then target name (then ids).
List<CardMove> cardMoveCandidates(List<Debt> debts, List<CardMove> moves) {
  final gave = {for (final m in moves) m.fromDebtId};
  final received = {for (final m in moves) m.toDebtId};
  int byName(Debt a, Debt b) {
    final n = a.name.compareTo(b.name);
    return n != 0 ? n : a.id.compareTo(b.id);
  }

  final sorted = [...debts]..sort(byName);
  return [
    for (final from in sorted)
      if (isTransferable(from.type) && !received.contains(from.id))
        for (final to in sorted)
          if (to.transferOffer case final offer?)
            if (to.id != from.id &&
                !gave.contains(to.id) &&
                !moves.any((m) => m.fromDebtId == from.id && m.toDebtId == to.id))
              if (_candidate(from, to, offer, moves) case final move?) move,
  ];
}

CardMove? _candidate(
  Debt from,
  Debt to,
  TransferOffer offer,
  List<CardMove> moves,
) {
  final movedRate = offer.promo?.aprBps ?? to.aprBps;
  if (aprInMonth(from, 1) <= movedRate) return null;
  int fee(int amount) => divideHalfEven(amount * offer.feeBps, 10000);
  final left =
      from.balance.minor -
      moves
          .where((m) => m.fromDebtId == from.id)
          .fold(0, (s, m) => s + m.amount.minor);
  final room =
      offer.availableCredit.minor -
      moves
          .where((m) => m.toDebtId == to.id)
          .fold(0, (s, m) => s + m.amount.minor + m.fee.minor);
  final amount = largestFittingAmount(room, left, fee);
  if (amount == 0) return null;
  final currency = from.balance.currency;
  return CardMove(
    fromDebtId: from.id,
    fromName: from.name,
    toDebtId: to.id,
    toName: to.name,
    amount: Money(amount, currency),
    fee: Money(fee(amount), currency),
    promo: offer.promo,
  );
}
```

In `restructure.dart`, add `CardTransfers()` to the identity arm (`Avalanche() || Snowball() || CustomOrder() || CardTransfers() || MinimumsOnly()`) with a comment that `calculate` chooses its moves.

In `allocation_order.dart`, add `CardTransfers()` to the avalanche-style arm.

In `calculator.dart`:
- Add `CardTransfers() => true` to `looksAhead`.
- Before the `restructure` switch in `calculate`, add:

```dart
  if (strategy is CardTransfers) {
    return _cardTransfers(debts, monthlyBudget, strategy);
  }
```

- Add:

```dart
/// Greedy search for worthwhile moves between the user's own cards: each
/// round simulates every candidate on top of the moves kept so far and
/// keeps the one that makes the plan cheapest, until none helps or
/// [kMaxCardMoves] are made. A plan that isn't feasible is never preferred.
PayoffResult _cardTransfers(
  List<Debt> debts,
  Money budget,
  Strategy strategy,
) {
  if (!debts.any((d) => d.transferOffer != null)) {
    return PayoffResult.notApplicable(
      strategyId: strategy.id,
      reason: NotApplicableReason.noCardOffers,
    );
  }
  final zero = Money.zero(budget.currency);
  PayoffResult evaluate(List<CardMove> moves) {
    final applied = applyCardMoves(debts, moves);
    final fee = moves.fold(zero, (s, m) => s + m.fee);
    return _simulateBest(
      strategy: strategy,
      debts: applied.debts,
      groups: applied.groups,
      budget: budget,
      fees: fee,
      change: moves.isEmpty
          ? null
          : PlanChange.cardTransfers(moves: moves, fee: fee),
    );
  }

  var moves = const <CardMove>[];
  var best = evaluate(moves);
  while (moves.length < kMaxCardMoves) {
    List<CardMove>? roundMoves;
    var roundBest = best;
    for (final candidate in cardMoveCandidates(debts, moves)) {
      final tried = [...moves, candidate];
      final result = evaluate(tried);
      if (_better(result, roundBest)) {
        roundBest = result;
        roundMoves = tried;
      }
    }
    if (roundMoves == null) break;
    moves = roundMoves;
    best = roundBest;
  }
  if (moves.isEmpty) {
    return PayoffResult.notApplicable(
      strategyId: strategy.id,
      reason: NotApplicableReason.noWorthwhileMoves,
    );
  }
  return best;
}

bool _better(PayoffResult a, PayoffResult b) => switch ((a, b)) {
  (Feasible(plan: final pa), Feasible(plan: final pb)) => _cheaper(pa, pb),
  (Feasible(), _) => true,
  _ => false,
};
```

Export `src/card_transfers.dart` and `src/fee_fit.dart` from `payoff_engine.dart`.

- [ ] **Step 4: Generate and run the engine tests**

Run: `cd packages/payoff_engine && dart run build_runner build -d && dart format lib test && dart analyze --fatal-infos && dart test`
Expected: `All tests passed!`, with every pre-existing test unchanged apart from the lineup test.

- [ ] **Step 5: Make the app compile and say the right things**

Add to `lib/l10n/app_en.arb`:

```json
  "strategyCardTransfers": "Move balances between your cards",
  "strategyCardTransfersDescription": "Moves your most expensive balances onto your cards' transfer offers, then pays the highest interest first.",
  "strategyCardTransfersBestFor": "Only if you won't spend on the card you've moved money off.",
  "notApplicableNoCardOffers": "No card has a balance transfer offer yet. Add one on a card's details.",
  "notApplicableNoWorthwhileMoves": "No move between your cards would save money.",
  "changeCardMove": "Move {amount} from {from} to {to} (fee {fee})",
  "@changeCardMove": {"placeholders": {"amount": {"type": "String"}, "from": {"type": "String"}, "to": {"type": "String"}, "fee": {"type": "String"}}},
  "changeCardMovePromo": "Move {amount} from {from} to {to} (fee {fee}, {apr} for {months} months)",
  "@changeCardMovePromo": {"placeholders": {"amount": {"type": "String"}, "from": {"type": "String"}, "to": {"type": "String"}, "fee": {"type": "String"}, "apr": {"type": "String"}, "months": {"type": "int"}}},
  "changeCardMoveReminder": "Check your card's terms: most won't take a balance from a card by the same bank. This plan assumes payments above the minimum clear the highest-rate balance first, as UK and US law requires.",
```

In `lib/core/labels.dart`, add `StrategyId.cardTransfers` arms:
- `strategyName`: `l10n.strategyCardTransfers`
- `strategyDescription`: `l10n.strategyCardTransfersDescription`
- `strategyBestFor`: `l10n.strategyCardTransfersBestFor`
- `strategyNickname`: joins the `null` group

In `notApplicableReason`, add:

```dart
  NotApplicableReason.noCardOffers => l10n.notApplicableNoCardOffers,
  NotApplicableReason.noWorthwhileMoves => l10n.notApplicableNoWorthwhileMoves,
```

In `lib/features/strategies/domain/strategy_groups.dart`, add `StrategyId.cardTransfers` to the `false` arm.

In `lib/features/analysis/presentation/plan_change_lines.dart`, add the arm:

```dart
    CardTransferChange(:final moves) => [
      for (final m in moves)
        if (m.promo case final promo?)
          l10n.changeCardMovePromo(
            money(m.amount),
            m.fromName,
            m.toName,
            money(m.fee),
            formatPercent(promo.aprBps, locale),
            promo.months,
          )
        else
          l10n.changeCardMove(
            money(m.amount),
            m.fromName,
            m.toName,
            money(m.fee),
          ),
      l10n.changeCardMoveReminder,
    ],
```

In `test/features/strategies/plans_providers_test.dart`, change `hasLength(5)` to `hasLength(6)`. In `test/core/labels_test.dart`, add `StrategyId.cardTransfers` to the no-nickname list, and append:

```dart
  test('describes card moves, with and without a promo', () {
    final lines = planChangeLines(
      l10n,
      const PlanChange.cardTransfers(
        moves: [
          CardMove(
            fromDebtId: 's',
            fromName: 'Store',
            toDebtId: 'a',
            toName: 'Amex',
            amount: Money(58252, 'GBP'),
            fee: Money(1748, 'GBP'),
            promo: Promo(aprBps: 0, months: 12),
          ),
          CardMove(
            fromDebtId: 'v',
            fromName: 'Visa',
            toDebtId: 'a',
            toName: 'Amex',
            amount: Money(10000, 'GBP'),
            fee: Money(300, 'GBP'),
          ),
        ],
        fee: Money(2048, 'GBP'),
      ),
      'en_GB',
    );
    expect(lines, [
      'Move £582.52 from Store to Amex (fee £17.48, 0% for 12 months)',
      'Move £100.00 from Visa to Amex (fee £3.00)',
      "Check your card's terms: most won't take a balance from a card by "
          'the same bank. This plan assumes payments above the minimum clear '
          'the highest-rate balance first, as UK and US law requires.',
    ]);
  });
```

`labels_test.dart` needs `import 'package:debt_destroyer/features/analysis/presentation/plan_change_lines.dart';`.

- [ ] **Step 6: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test && (cd packages/payoff_engine && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && dart test)`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add packages/payoff_engine lib test
git commit -m "feat(engine): move balances between the user's own cards"
```

---

### Task 4: Schema 3: storing offers

**Files:**
- Modify: `lib/features/debts/data/app_database.dart`, `lib/features/debts/data/drift_debt_repository.dart`, `test/helpers/in_memory_debt_repository.dart`, `test/helpers/debts.dart`
- Generated and committed: `drift_schemas/app_database/drift_schema_v3.json`, `lib/features/debts/data/app_database.steps.dart`, `test/drift/app_database/generated/*`
- Test: `test/drift/app_database/migration_test.dart`, `test/features/debts/drift_debt_repository_test.dart`

**Interfaces:**
- Consumes: `TransferOffer` (Task 1).
- Produces:
  - the `debts` table gains nullable `offerFeeBps`, `offerPromoAprBps`, `offerPromoMonths` and `offerAvailableCreditMinor`
  - `schemaVersion == 3`
  - the repository round-trips `Debt.transferOffer`
  - `convertAmounts` rescales `offerAvailableCreditMinor`
  - `testDebt(…, TransferOffer? transferOffer)`

- [ ] **Step 1: Write the failing tests**

Add `TransferOffer? transferOffer` to `testDebt` in `test/helpers/debts.dart` and pass it through.

Append to `test/features/debts/drift_debt_repository_test.dart`:

```dart
  group('transfer offers', () {
    final offer = TransferOffer(
      feeBps: 300,
      promo: const Promo(aprBps: 0, months: 12),
      availableCredit: const Money(200000, 'GBP'),
    );

    test('round-trip with and without a promo', () async {
      await repo.add(testDebt(id: 'a', transferOffer: offer));
      await repo.add(
        testDebt(id: 'b', transferOffer: offer.copyWith(promo: null)),
      );
      final debts = await repo.loadAll('GBP');
      expect(debts[0].transferOffer, offer);
      expect(debts[1].transferOffer, offer.copyWith(promo: null));
    });

    test('saving without an offer clears it', () async {
      final d = testDebt(id: 'a', transferOffer: offer);
      await repo.add(d);
      await repo.update(d.copyWith(transferOffer: null));
      final row = await db.select(db.debtRows).getSingle();
      expect(row.offerFeeBps, isNull);
      expect(row.offerAvailableCreditMinor, isNull);
    });

    test('switching currency rescales the available credit', () async {
      await repo.convertAmounts(toCurrencyCode: 'GBP');
      await repo.add(testDebt(id: 'a', transferOffer: offer));
      await repo.convertAmounts(toCurrencyCode: 'JPY');
      expect(
        (await repo.loadAll('JPY')).single.transferOffer!.availableCredit,
        const Money(2000, 'JPY'),
      );
    });
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/debts/drift_debt_repository_test.dart`
Expected: the offer round-trip fails (the offer reads back as null), and `row.offerFeeBps` doesn't compile.

- [ ] **Step 3: Columns, schema version and migration**

In `DebtRows`, after `promoEndsYearMonth`:

```dart
  /// Balance-transfer offer on this card (see TransferOffer); all null when
  /// there is none. The promo columns are both null or both set.
  IntColumn get offerFeeBps => integer().nullable()();
  IntColumn get offerPromoAprBps => integer().nullable()();
  IntColumn get offerPromoMonths => integer().nullable()();
  IntColumn get offerAvailableCreditMinor => integer().nullable()();
```

Set `schemaVersion` to `3`, then run:

```bash
./tool/codegen.sh
dart run drift_dev make-migrations
```

Expected: `drift_schemas/app_database/drift_schema_v3.json`, a regenerated `app_database.steps.dart` with `from2To3`, and `test/drift/app_database/generated/schema_v3.dart`.

Add the step to the existing `stepByStep(…)` in `app_database.dart`:

```dart
      from2To3: (m, schema) async {
        await m.addColumn(schema.debts, schema.debts.offerFeeBps);
        await m.addColumn(schema.debts, schema.debts.offerPromoAprBps);
        await m.addColumn(schema.debts, schema.debts.offerPromoMonths);
        await m.addColumn(schema.debts, schema.debts.offerAvailableCreditMinor);
      },
```

Append to `test/drift/app_database/migration_test.dart`. Add `import 'generated/schema_v3.dart' as v3;`. The v2 companion takes raw storage types, as in the existing v1 test: `type` as a string, booleans and dates as ints. Match `generated/schema_v2.dart`.

```dart
  test('v2 debts survive the upgrade to v3 with no offer', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 2,
      newVersion: 3,
      createOld: v2.DatabaseAtV2.new,
      createNew: v3.DatabaseAtV3.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.debts,
          v2.DebtsCompanion.insert(
            id: 'a',
            name: 'Visa',
            type: 'creditCard',
            balanceMinor: 123456,
            aprBps: 1990,
            minPaymentPercentBps: 300,
            minPaymentFloorMinor: 2500,
            allowsOverpayment: 1,
            sortIndex: 0,
            createdAt: 1790000000,
            updatedAt: 1790000000,
          ),
        );
      },
      validateItems: (newDb) async {
        final row = await newDb.select(newDb.debts).getSingle();
        expect(row.balanceMinor, 123456);
        expect(row.offerFeeBps, isNull);
        expect(row.offerAvailableCreditMinor, isNull);
      },
    );
  });
```

- [ ] **Step 4: Repository mapping and rescaling**

In `DriftDebtRepository._toDebt`, add:

```dart
      transferOffer: switch ((row.offerFeeBps, row.offerAvailableCreditMinor)) {
        (final int fee, final int credit) => TransferOffer(
          feeBps: fee,
          promo: switch ((row.offerPromoAprBps, row.offerPromoMonths)) {
            (final int apr, final int months) =>
              Promo(aprBps: apr, months: months),
            _ => null,
          },
          availableCredit: Money(credit, currencyCode),
        ),
        _ => null,
      },
```

In `_toCompanion`:

```dart
    offerFeeBps: Value(debt.transferOffer?.feeBps),
    offerPromoAprBps: Value(debt.transferOffer?.promo?.aprBps),
    offerPromoMonths: Value(debt.transferOffer?.promo?.months),
    offerAvailableCreditMinor: Value(
      debt.transferOffer?.availableCredit.minor,
    ),
```

In `convertAmounts`' debt loop, add to the `DebtRowsCompanion`:

```dart
                  offerAvailableCreditMinor: Value(
                    switch (row.offerAvailableCreditMinor) {
                      final credit? => rescale(credit, min: 1),
                      null => null,
                    },
                  ),
```

In `test/helpers/in_memory_debt_repository.dart`:
- In `_labelled` and `convertAmounts`, relabel and rescale the offer's `availableCredit` too, using `d.transferOffer?.copyWith(availableCredit: …)`.
- The rescale uses `rescale(credit.minor, 1)`.

- [ ] **Step 5: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test && (cd packages/payoff_engine && dart test)`
Expected: all green, including both migration tests.

- [ ] **Step 6: Commit**

```bash
git add lib test drift_schemas
git commit -m "feat(data): schema 3 stores balance-transfer offers"
```

---

### Task 5: Offer section in the debt form, and a label on the Debts list

**Files:**
- Modify: `lib/features/debts/presentation/debt_form_screen.dart`, `lib/features/debts/presentation/debts_screen.dart` (`DebtTile`), `lib/l10n/app_en.arb`
- Test: `test/features/debts/debt_form_test.dart`, `test/features/debts/debts_screen_test.dart`

**Interfaces:**
- Consumes: `TransferOffer`, `isTransferable`, the offer validation errors (Task 1); persistence (Task 4).
- Produces: widget keys `ValueKey('offer')` (switch) and `ValueKey('offerPromo')` (promo switch); field labels "Transfer fee (%)", "Offer rate (APR %)", "Offer length (months)" and "Available credit".

- [ ] **Step 1: Write the failing tests**

Append to `test/features/debts/debt_form_test.dart`, using the file's existing `fill`, `save`, `field`, `chooseType` and `formList` helpers:

```dart
  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(key)),
      100,
      scrollable: formList,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String label, String text) async {
    await tester.scrollUntilVisible(field(label), 100, scrollable: formList);
    await tester.enterText(field(label), text);
  }

  testWidgets('records a balance transfer offer on a card', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester);
    await tapKey(tester, 'offer');
    await enter(tester, 'Transfer fee (%)', '3');
    await tapKey(tester, 'offerPromo');
    await enter(tester, 'Offer rate (APR %)', '0');
    await enter(tester, 'Offer length (months)', '12');
    await enter(tester, 'Available credit', '2000');
    await save(tester);
    expect(
      app.repository.stored.single.transferOffer,
      const TransferOffer(
        feeBps: 300,
        promo: Promo(aprBps: 0, months: 12),
        availableCredit: Money(200000, 'GBP'),
      ),
    );
  });

  testWidgets('loans have no offer section, and switching drops the offer', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      debts: [
        testDebt(
          id: 'a',
          transferOffer: const TransferOffer(
            feeBps: 300,
            availableCredit: Money(200000, 'GBP'),
          ),
        ),
      ],
      location: Routes.editDebt('a'),
    );
    await chooseType(tester, 'Loan');
    expect(find.byKey(const ValueKey('offer')), findsNothing);
    // The saved debt has a 3% minimum, so the loan keeps both minimum
    // fields (no single "Monthly payment" field); save as is.
    await save(tester);
    expect(app.repository.stored.single.transferOffer, isNull);
  });

  testWidgets('explains an offer with no available credit', (tester) async {
    final app = await pumpApp(tester, location: Routes.newDebt);
    await fill(tester);
    await tapKey(tester, 'offer');
    await enter(tester, 'Transfer fee (%)', '3');
    await enter(tester, 'Available credit', '0');
    await save(tester);
    await tester.scrollUntilVisible(
      find.text('Enter the credit still available on this card'),
      -100,
      scrollable: formList,
    );
    expect(
      find.text('Enter the credit still available on this card'),
      findsOneWidget,
    );
    expect(app.repository.stored, isEmpty);
  });
```

Append to `test/features/debts/debts_screen_test.dart`:

```dart
  testWidgets('marks a card that has a transfer offer', (tester) async {
    await pumpApp(
      tester,
      debts: [
        testDebt(
          id: 'a',
          name: 'Amex',
          transferOffer: const TransferOffer(
            feeBps: 300,
            availableCredit: Money(200000, 'GBP'),
          ),
        ),
      ],
    );
    expect(find.textContaining('Transfer offer'), findsOneWidget);
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/debts`
Expected: the new tests FAIL. `ValueKey('offer')` finds nothing, and there's no "Transfer offer" text.

- [ ] **Step 3: Implement**

Add to `lib/l10n/app_en.arb`:

```json
  "fieldOffer": "Balance transfer offer on this card",
  "fieldOfferHint": "What this card charges to take a balance from another card",
  "fieldOfferFee": "Transfer fee (%)",
  "fieldOfferPromo": "Lower rate on moved money",
  "fieldOfferPromoApr": "Offer rate (APR %)",
  "fieldOfferPromoMonths": "Offer length (months)",
  "fieldOfferCredit": "Available credit",
  "errorOfferCredit": "Enter the credit still available on this card",
  "errorOfferMonths": "Enter between 1 and {max} months",
  "@errorOfferMonths": {"placeholders": {"max": {"type": "int"}}},
  "debtTransferOffer": "Transfer offer",
```

In `debt_form_screen.dart`:
- Extend `_Field` with `offerFee, offerPromoApr, offerPromoMonths, offerCredit`.
- Add the state `late bool _hasOffer; late bool _hasOfferPromo;`.
- Initialise from `widget.existing?.transferOffer`: `_hasOffer = offer != null`, `_hasOfferPromo = offer?.promo != null`. The controllers are pre-filled with the offer's values: `percent(offer.feeBps)`, `percent(promo.aprBps)`, `'${promo.months}'` and `money(availableCredit)`. With no offer they are empty, except the promo rate, which defaults to `'0'`.
- After the promo section, when `isTransferable(_type)`:

```dart
          if (isTransferable(_type)) ...[
            SwitchListTile(
              key: const ValueKey('offer'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.fieldOffer),
              subtitle: Text(l10n.fieldOfferHint),
              value: _hasOffer,
              onChanged: (v) => setState(() => _hasOffer = v),
            ),
            if (_hasOffer) ...[
              field(
                _Field.offerFee,
                l10n.fieldOfferFee,
                keyboard: numberKeyboard,
                validator: (v) => percent(v, required: true),
              ),
              SwitchListTile(
                key: const ValueKey('offerPromo'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.fieldOfferPromo),
                value: _hasOfferPromo,
                onChanged: (v) => setState(() => _hasOfferPromo = v),
              ),
              if (_hasOfferPromo) ...[
                field(
                  _Field.offerPromoApr,
                  l10n.fieldOfferPromoApr,
                  keyboard: numberKeyboard,
                  validator: (v) => percent(v, required: true),
                ),
                field(
                  _Field.offerPromoMonths,
                  l10n.fieldOfferPromoMonths,
                  keyboard: TextInputType.number,
                  validator: (v) => parseWholeNumber(v ?? '') == null
                      ? l10n.errorWholeNumber
                      : null,
                ),
              ],
              field(
                _Field.offerCredit,
                l10n.fieldOfferCredit,
                keyboard: numberKeyboard,
                validator: (v) => amount(v, required: true),
              ),
            ],
          ],
```

- In `_save`, add to the `Debt(...)`:

```dart
      transferOffer: _hasOffer && isTransferable(_type)
          ? TransferOffer(
              feeBps: percent(_Field.offerFee),
              promo: _hasOfferPromo
                  ? Promo(
                      aprBps: percent(_Field.offerPromoApr),
                      months:
                          parseWholeNumber(
                            _controllers[_Field.offerPromoMonths]!.text,
                          ) ??
                          0,
                    )
                  : null,
              availableCredit: Money(amount(_Field.offerCredit), code),
            )
          : null,
```

- In `_showErrors`, replace Task 1's placeholder `break` with the mappings:

```dart
        case DebtValidationError.offerFeeOutOfRange:
          byField[_Field.offerFee] = l10n.errorPercentRange;
        case DebtValidationError.offerPromoAprOutOfRange:
          byField[_Field.offerPromoApr] = l10n.errorRateRange;
        case DebtValidationError.offerPromoMonthsOutOfRange:
          byField[_Field.offerPromoMonths] = l10n.errorOfferMonths(
            kMaxPromoMonths,
          );
        case DebtValidationError.offerCreditNotPositive:
          byField[_Field.offerCredit] = l10n.errorOfferCredit;
        case DebtValidationError.offerCreditTooLarge:
          byField[_Field.offerCredit] = l10n.errorTooLarge;
        case DebtValidationError.offerOnNonCard:
        case DebtValidationError.offerCurrencyMismatch:
          break; // not reachable: the form drops offers on non-cards and
          // uses one currency
```

In `DebtTile` (`debts_screen.dart`), append ` · ${l10n.debtTransferOffer}` to the subtitle when `debt.transferOffer != null`.

- [ ] **Step 4: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib test
git commit -m "feat(debts): record a balance transfer offer on a card"
```

---

### Task 6: Card moves on Strategies and in plan detail

**Files:**
- Modify: `lib/features/strategies/presentation/strategies_screen.dart` (`_FeasibleDetails`), `lib/l10n/app_en.arb`, `CLAUDE.md`
- Test: `test/features/strategies/strategies_screen_test.dart`, `test/features/analysis/plan_detail_test.dart`

**Interfaces:**
- Consumes: `CardTransferChange`, `planChangeLines` covering card moves (Task 3); offers (Tasks 1, 4, 5).

- [ ] **Step 1: Write the failing tests**

Shared fixture for both test files, declared inside each `main`:

```dart
  // Store card: 1,000.00 at 29.9%. Amex: 500.00 at 12.7% with an offer of
  // 0% for 12 months, 3% fee and 2,000.00 of room: all of the store
  // balance moves (1,000.00 + 30.00 fee).
  final store = testDebt(
    id: 's',
    name: 'Store',
    type: DebtType.storeCard,
    aprBps: 2990,
  );
  final amex = testDebt(
    id: 'a',
    name: 'Amex',
    balance: 50000,
    aprBps: 1270,
    transferOffer: const TransferOffer(
      feeBps: 300,
      promo: Promo(aprBps: 0, months: 12),
      availableCredit: Money(200000, 'GBP'),
    ),
  );
```

Append to `test/features/strategies/strategies_screen_test.dart`:

```dart
  testWidgets('shows the card moves and their fees', (tester) async {
    await pumpApp(
      tester,
      debts: [store, amex],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.strategies,
    );
    await tester.scrollUntilVisible(
      find.text('1 move · £30.00 in fees'),
      100,
    );
    expect(find.text('1 move · £30.00 in fees'), findsOneWidget);
  });

  testWidgets('says when no card has an offer', (tester) async {
    await pumpApp(
      tester,
      debts: [store],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.strategies,
    );
    const reason =
        "No card has a balance transfer offer yet. Add one on a card's details.";
    await tester.scrollUntilVisible(find.text(reason), 100);
    expect(find.text(reason), findsOneWidget);
  });
```

Append to `test/features/analysis/plan_detail_test.dart`:

```dart
  testWidgets('lists card moves and names the moved portion', (tester) async {
    await pumpApp(
      tester,
      debts: [store, amex],
      settings: {SettingsKeys.monthlyBudgetMinor: 30000},
      location: Routes.plan(StrategyId.cardTransfers),
    );
    const move =
        'Move £1,000.00 from Store to Amex (fee £30.00, 0% for 12 months)';
    await tester.scrollUntilVisible(
      find.text(move),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text(move), findsOneWidget);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Amex (moved from Store)'), findsWidgets);
  });
```

If the scrollable finder above doesn't match this screen, use the pattern from this file's existing "explains what a balance transfer changes" test. Change only the finder, never the assertions.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/strategies/strategies_screen_test.dart test/features/analysis/plan_detail_test.dart`
Expected: the moves-summary test FAILS, because there's no "1 move · …" text yet. The not-applicable and plan-detail tests may already pass, thanks to Task 3's labels and `planChangeLines`. That's fine; they pin the behaviour. If the engine chooses a different move than the fixture comment predicts, stop and report it (see the ruling on figures). Don't edit the expectation to match.

- [ ] **Step 3: Implement**

Add to `lib/l10n/app_en.arb`:

```json
  "cardMovesSummary": "{count, plural, =1{1 move} other{{count} moves}} · {fee} in fees",
  "@cardMovesSummary": {"placeholders": {"count": {"type": "int"}, "fee": {"type": "String"}}},
```

In `_FeasibleDetails.build` (`strategies_screen.dart`), add after the savings line:

```dart
        if (plan.change case CardTransferChange(:final moves, :final fee))
          Text(
            l10n.cardMovesSummary(moves.length, formatMoney(fee, locale)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
```

In `CLAUDE.md` "Gotchas", add:

```markdown
- Card transfers (`Strategy.cardTransfers`): `calculate` runs a greedy search (`cardMoveCandidates`, `applyCardMoves`, at most `kMaxCardMoves`) over the look-ahead avalanche. Moved money becomes a *portion* debt (`<card>#from-<source>`) grouped with its card: `simulate(groups:)` works out one minimum on the card total (lowest rate first) and pays extra highest current rate first within a card (the UK rule). Offers live on `Debt.transferOffer` (schema 3).
```

- [ ] **Step 4: Run all checks**

Run: `./tool/codegen.sh && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && flutter test && (cd packages/payoff_engine && dart analyze --fatal-infos && dart format --output=none --set-exit-if-changed lib test && dart test)`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib test CLAUDE.md
git commit -m "feat(strategies): show card moves and their fees"
```
