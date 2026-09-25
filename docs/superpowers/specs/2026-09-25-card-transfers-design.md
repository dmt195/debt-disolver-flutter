# Moving Balances Between Your Own Cards: Design

Date: 2026-09-25
Status: Draft for review
Builds on: the v1 spec (`2026-09-24-flutter-rebuild-design.md`) and the v2 spec (`2026-09-24-v2-planning-design.md`). Where this spec says nothing, they still apply.

## 1. Intent

Many cards offer balance transfers to existing customers ("0% for 12 months, 3% fee"). A user with an expensive card and a cheaper one could move money from the worst card to the best for a small fee, without taking on new credit. The app should find those moves, show what they save, and model how the moved money is really repaid.

**In scope**
- Recording a transfer offer on each of the user's cards: fee, optional promo, available credit.
- A new pay-off strategy, "Move balances between your cards", that suggests worthwhile moves and then pays off highest interest first.
- Modelling a card as one or more *portions* (its own balance plus moved balances), with one minimum on the whole card, and payments allocated by the UK rule.

**Out of scope**
- Offer deadlines, same-issuer restrictions (the app reminds the user instead), money transfers from overdrafts or loans, promo rates for purchases, card fees other than the transfer fee.
- The user choosing or editing moves themselves.
- Moving money onto a card with nothing owed on it: debts must have a positive balance, so an empty card can't be entered. Allowing zero-balance cards is a later change.
- Choosing partial amounts: a move always takes the largest amount that fits (§3.2).

**Unchanged constraints:** integer money (minor units and basis points, half-even rounding once a month); `payoff_engine` stays pure Dart; TDD is mandatory; banners stay on Debts and Strategies only; borrowing alternatives (consolidation, a new 0% card) stay apart and are never marked cheapest.

**Success criteria**
- With no transfer offers recorded, every existing plan gives exactly the same figures as today.
- Every card-transfer plan satisfies `totalPaid == Σ starting balances + totalInterest + totalFees`, and no card ever holds more moved money plus fees than its available credit.
- A move is suggested only if the whole plan, fees included, costs less with it than without it.

## 2. Recording a card's offer

### 2.1 Data

`Debt` gains `transferOffer: TransferOffer?`, allowed only where `isTransferable(type)` (credit cards and store cards):

| Field | Meaning | Valid range |
|---|---|---|
| `feeBps` | fee as a % of the amount moved | 0–10000 |
| `promo: Promo?` | rate and length for moved money (`Promo.months` = months from the move) | aprBps 0–10000, months 1–`kMaxPromoMonths` |
| `availableCredit: Money` | room left on the card; moves plus fees must fit | > 0, ≤ `kMaxAmountMinor` |

After the promo, moved money is charged the card's own `aprBps`. The promo is a *length*, not an end date: it starts when the money moves (the plan's month 1).

New `DebtValidationError` values: `offerOnNonCard`, `offerFeeOutOfRange`, `offerPromoAprOutOfRange`, `offerPromoMonthsOutOfRange`, `offerCreditNotPositive`, `offerCreditTooLarge`, `offerCurrencyMismatch`.

### 2.2 Storage (schema 3)

`debts` gains four nullable columns: `offerFeeBps`, `offerPromoAprBps`, `offerPromoMonths` and `offerAvailableCreditMinor`. A debt has an offer when `offerFeeBps` is not null; the promo columns are both null or both set. The migration from 2 to 3 adds the columns, and v2 rows get no offer. The migration test is generated with `make-migrations` and fills in a data-integrity check. `DriftDebtRepository.convertAmounts` rescales `offerAvailableCreditMinor` (minimum 1) with the other amounts.

### 2.3 Debt form

For credit cards and store cards, a switch **"Balance transfer offer on this card"** reveals:
- Transfer fee (%)
- An optional promo: rate (%) and length (months, a whole number)
- Available credit (amount, required)

Changing the kind to one that can't receive transfers hides the section, and saving then drops the offer. Errors are mapped from the domain validator. Forced errors are cleared in `onChanged`, as elsewhere.

The Debts list shows a "Transfer offer" label in the subtitle of a debt that has one.

## 3. Engine

### 3.1 Strategy

- `StrategyId.cardTransfers` and `Strategy.cardTransfers()` ("Move balances between your cards").
- `standardStrategies` order: avalanche, snowball, customOrder, **cardTransfers**, consolidation, balanceTransfer.
- It is a way to pay off: `isBorrowingAlternative(cardTransfers) == false`.
- After its moves, it allocates like avalanche, including the look-ahead ranking (v2 spec §3.2).

### 3.2 Choosing moves (restructure)

1. **Offers.** Targets are debts with a `transferOffer`. If there are none, the result is `NotApplicable(noCardOffers)`.
2. **Candidate move.** A candidate is a (source, target) pair where:
   - the source is transferable,
   - source ≠ target,
   - the source's current APR in month 1 is greater than the rate moved money would pay on the target in month 1 (the offer's promo rate, else the target's APR).

   The amount is the largest `x ≤ source balance` with `x + fee(x) ≤` the target's remaining room, where `fee(x) = halfEven(x × feeBps / 10000)` (the same integer search as the new-card transfer). `x = 0` means the pair isn't a candidate.
3. **Greedy search.**
   - Start from the debts with no moves, simulated as avalanche. Each round, simulate every candidate applied on top of the moves kept so far, and keep the one that lowers `totalPaid` the most (ties: fewer months, then source name, then target name).
   - Stop when no candidate lowers `totalPaid`, or after 10 moves.
   - Each move uses up room on its target. A source can be moved more than once (to different targets) until it's empty.
   - A moved portion is never moved again. A card that has received money can't be a source, and a card money has been moved off can't be a target, so money never shuffles back and forth.
4. **Nothing helps.** If no move lowers the cost, the result is `NotApplicable(noWorthwhileMoves)`.
   - If the no-move plan is not feasible, a move that makes it feasible is kept; the Strategies card then shows the only affordable plan.
5. **Output.** `Restructured` gains a list of card groups (§3.3), and `PlanChange.cardTransfers(moves: …, fee: …)`, where `fee` is the total of the move fees and each `CardMove` is `(fromDebtId, fromName, toDebtId, toName, amount, fee, promo: Promo?)` in the order the moves were chosen.

### 3.3 Cards made of portions (simulate)

- **Portions.** A move reduces the source by `x`, and adds a portion to the target with balance `x + fee(x)`, rate = the card's `aprBps`, and promo = the offer's promo. Portion ids are `<targetId>#from-<sourceId>`, and the engine names portions "<target name> (moved from <source name>)" (the app is English-only). A source reduced to zero is removed, as with the new-card transfer.
- **Groups.** `simulate` takes an optional `groups: List<List<int>>` (indexes into the simulated list; the card's own portion first). Without groups, every debt is its own group, so today's behaviour is unchanged.
- **Monthly steps for a group:**
  1. Interest per portion, at that portion's current APR.
  2. **Minimum:** `minimumPaymentMinor(card's own debt, group total)`, using the card's own percentage and floor. It's allocated to portions in ascending current APR (ties: list order) until each is cleared or the minimum is used up.
  3. **Extra:** the strategy's order ranks groups. A group's score is its best portion's score under the strategy's rule. Within a group, extra goes to portions in *descending current APR*: the UK rule that payments above the minimum clear the highest-rate balance first.
- **Clearing order and columns** stay per portion (v2 spec §3.3).
- **Infeasibility.** `Infeasible` compares the sum of group minimums with the budget, as today.
- **Fees.** The move fees are added to `totalFees`, never to interest.

### 3.4 Results

- `NotApplicableReason` gains `noCardOffers` and `noWorthwhileMoves`.
- `PlanChange` gains `cardTransfers({required List<CardMove> moves, required Money fee})`.
- `PayoffPlan` is otherwise unchanged.

## 4. Screens

- **Strategies:** a new card in "Ways to pay off":
  - **Name:** "Move balances between your cards".
  - **Description:** "Moves your most expensive balances onto your cards' transfer offers, then pays the highest interest first."
  - **Best for:** "Only if you won't spend on the card you've moved money off."
  - **Feasible plans** add a line, e.g. "2 moves · £84.00 in fees".
  - **Not-applicable reasons:** "No card has a balance transfer offer yet. Add one on a card's details." and "No move between your cards would save money."
- **Plan detail and exports:**
  - The "What changes" lines and export notes list each move: "Move £1,200.00 from Visa red to Amex Blue (fee £36.00, 0% for 12 months)", or "(fee £36.00)" without a promo.
  - Then the reminder "Check your card's terms: most won't take a balance from a card by the same bank. This plan assumes payments above the minimum clear the highest-rate balance first, as UK and US law requires." Outside the UK and US a provider may pay the cheapest balance first; a setting for that is deferred until users ask for it.
  - A portion's column is named "Amex Blue (moved from Visa red)", the engine's name for it.

All new text goes in `app_en.arb`.

## 5. Testing

TDD as before.

**Engine**
- **Portions:**
  - the minimum is worked out on the card total with the card's own rule
  - the minimum clears the lowest-rate portion first
  - extra clears the highest current rate first, so a 0% portion is cleared last
  - a worked example with hand-checked figures
- **Moves:**
  - a single worthwhile move is chosen, with the exact amount and fee
  - the room limit counts the fee
  - no move onto the same card, and no move from a non-card
  - no move where the target's rate isn't lower
  - `noCardOffers` and `noWorthwhileMoves`
  - the 10-move cap
- **Invariants** (randomised, extended with offers):
  - total paid = starting balances + interest + fees
  - moved money plus fees ≤ available credit
  - figures are unchanged when there are no offers
- **Regression:** every existing engine test is unchanged.

**App**
- **Migration and repository:** the 2 → 3 migration test (v2 rows get no offer), the offer round-trip, and currency rescaling of available credit.
- **Debt form:** offer entry, hidden for non-cards, and validation messages.
- **Strategies:**
  - the new card with its moves line
  - both not-applicable reasons
  - it can be marked cheapest
- **Plan detail:** the move lines, the reminder, and the portion column names. The export notes include the moves.
