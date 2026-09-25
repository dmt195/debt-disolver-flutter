# Plan 8: Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Let people follow a plan and check in with their balances.
- See progress against the plan: paid off so far, ahead or behind, and the plan-vs-actual chart.
- Restart, with or without their history.
- Clear debts and celebrate each one.

**Architecture:**
- **Storage:** Schema 4 adds `debts.clearedAt` plus three tables in the same Drift database: `check_ins`, `check_in_balances` and `starting_points`.
- **Repositories:**
  - `DebtRepository` hides cleared debts from planning and exposes them separately.
  - A new `ProgressRepository` records check-ins and starting points. A check-in and its debt-balance updates happen in one transaction.
- **Domain:** pure functions in `lib/features/progress/domain/` decide what the app shows and when a starting point is due.
- **The reconciler:** one Riverpod provider records starting points automatically: first run, debt added or deleted, plan switched, and deferred while infeasible.
- **Screens:** they call a `ProgressController`.

**Tech Stack:** Flutter, Riverpod 3 (codegen), Drift (with `make-migrations`), go_router, fl_chart, share_plus.

**Spec:** `docs/superpowers/specs/2026-09-25-v3-ux-redesign-design.md`: §4.2 (Home progress), §4.3 (Cleared section), §4.4 (Mark as paid off), §4.5–4.6 (Following, Follow this plan), §4.8–4.10 (Check in, result, celebration), §6 (all), §8.1–8.2, §10. The designs are on the "A · Demolition crew" canvas page (Home, Check in, Check-in result, Restart sheet) and in "A · Debt cleared".

## Global Constraints

- Money is integer minor units. A projection's totals are stored as integer minor units (a JSON array). Chart values are major units computed only for display.
- Cleared debts never reach the engine (`calculateAll` and friends only see `DebtRepository.loadAll`/`watchAll`, which exclude them). `balance > 0` validation stays as it is.
- Every UI string goes in `lib/l10n/app_en.arb`. Amounts use `formatMoney`; dates use `DateFormat` with `formatLocaleProvider`. There are no system dialogs: confirmations are bottom sheets or inline, as the v2 scenario delete already is.
- TDD for every task: failing test, minimal code, refactor. `dart analyze --fatal-infos` and `dart format lib test` must be clean at each commit. Run `./tool/codegen.sh` after any Riverpod, freezed or Drift change.
- Schema change: bump `schemaVersion` to 4, write `from3To4`, run `dart run drift_dev make-migrations`, and commit `drift_schemas/` and `test/drift/`.
- Hi-vis is never a text colour (the only exception is the bottom nav's selected tab). There are no ads on Home, Check in, the result screen, Celebration or any sheet.
- Widget tests use `pumpApp` with a fixed clock of 24 Sep 2026 and in-memory repositories. Use `useTallScreen` for long screens.
- Commit trailer:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01S3YJtSqzzA5Sf6buKinyKC
  ```

## Deliberate deviation from the spec (ruled here)

- **Keeping a deleted debt's check-in rows.** Spec §8.1 says deleting a debt deletes its `check_in_balances` rows, but the reconciler needs them to notice a deletion. Each row also stores the debt's name at the time, so a deletion can be labelled "Deleted Visa".
  - The rows are kept.
  - `paidOff` counts only debts that still exist, as §6.4 wants.
  - If this is wrong, the cost is a few orphan rows, removed by "Start fresh".

## Review Focus

1. **Clearing and re-opening:**
   - A debt entered as 0 is cleared once, with no restart.
   - Re-opening it is a `debtAdded` restart.
   - A cleared debt never reaches the engine or the "pay this month" list.

   Tests: Tasks 2, 4, 6.
2. **The reconciler never loops or double-records:** one starting point per trigger, even with several rebuilds in flight, and none while the plan is infeasible. Test: Task 6.
3. **Currency change** rescales check-in totals, check-in balances and every projected total, in the same transaction as the debts, in both the Drift and in-memory repositories. Tests: Tasks 2, 3.
4. **Month boundaries:** `monthIndex` across December to January, check-ins on the 31st, and a check-in beyond the projection's end (expected is 0). Test: Task 4.
5. **"Start fresh" and celebrations:** "Start fresh" deletes history but never debts, settings, the followed plan or `clearedAt`, so celebrations don't replay. Test: Task 7.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/features/debts/data/app_database.dart` | Schema 4: `debts.clearedAt`, `CheckInRows`, `CheckInBalanceRows`, `StartingPointRows` |
| `lib/features/debts/domain/debt_repository.dart` | + `watchCleared`, `reopen`; `watchAll`/`loadAll`/`reorder` cover only uncleared debts |
| `lib/features/debts/domain/cleared_debt.dart` | `ClearedDebt` value |
| `lib/features/debts/data/drift_debt_repository.dart` | The above, plus rescaling progress rows in `convertAmounts` |
| `lib/features/progress/domain/progress.dart` | `CheckIn`, `StartingPoint`, `StartReason`, `ProgressHistory` |
| `lib/features/progress/domain/progress_repository.dart` | The interface |
| `lib/features/progress/data/drift_progress_repository.dart` | The Drift implementation |
| `lib/features/progress/domain/progress_math.dart` | `monthIndex`, `projectedTotals`, `paidOff`, `aheadBehind`, `expectedBalances`, `nextStart`, `progressChartData` |
| `lib/features/settings/domain/app_settings.dart` (+ prefs, controller) | `followedStrategy` |
| `lib/features/strategies/presentation/current_plans.dart` | `homePlanProvider` follows the chosen plan; new states |
| `lib/features/progress/presentation/progress_providers.dart` | `clearedDebtsProvider`, `progressHistoryProvider`, `progressSummaryProvider`, `progressReconcilerProvider`, `ProgressController`, `CheckInOutcome` |
| `lib/core/charts/balance_line_chart.dart` | + xy points with square markers, a today line, restart ticks |
| `lib/features/home/presentation/home_screen.dart` (+ `home_progress.dart`) | The progress hero, plan vs actual, check-in card, restart and follow sheets |
| `lib/features/progress/presentation/check_in_screen.dart`, `check_in_result_screen.dart`, `celebration_screen.dart`, `restart_sheet.dart`, `follow_sheet.dart` | New screens and sheets |
| `test/helpers/in_memory_debt_repository.dart`, `in_memory_progress_repository.dart`, `pump_app.dart` | Test doubles |

---

### Task 1: Schema 4

**Files:**
- Modify: `lib/features/debts/data/app_database.dart`
- Generated: `drift_schemas/app_database/drift_schema_v4.json`, `test/drift/app_database/generated/*`
- Test: `test/drift/app_database/migration_test.dart`

**Interfaces:**
- Produces:
  - Tables `check_ins` (`CheckInRow`), `check_in_balances` (`CheckInBalanceRow`) and `starting_points` (`StartingPointRow`).
  - The `debts.clearedAt` column.
  - `AppDatabase.schemaVersion == 4`.

- [ ] **Step 1: Add the tables and column**

```dart
// in DebtRows:
  /// When the balance reached 0 through a check-in or "Mark as paid off";
  /// null while the debt is being paid (spec §6.6).
  DateTimeColumn get clearedAt => dateTime().nullable()();

/// A dated record of every uncleared debt's balance (spec §6.1).
@DataClassName('CheckInRow')
class CheckInRows extends Table {
  @override
  String get tableName => 'check_ins';

  TextColumn get id => text()();
  DateTimeColumn get at => dateTime()();

  /// Recorded as part of a starting point rather than by the user.
  BoolColumn get isStart => boolean()();

  /// Sum of the balances recorded, in minor units.
  IntColumn get totalMinor => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CheckInBalanceRow')
class CheckInBalanceRows extends Table {
  @override
  String get tableName => 'check_in_balances';

  TextColumn get checkInId => text()();
  TextColumn get debtId => text()();

  /// The debt's name at the time, so history survives its deletion.
  TextColumn get debtName => text()();
  IntColumn get balanceMinor => integer()();

  @override
  Set<Column<Object>> get primaryKey => {checkInId, debtId};
}

@DataClassName('StartingPointRow')
class StartingPointRows extends Table {
  @override
  String get tableName => 'starting_points';

  TextColumn get id => text()();
  TextColumn get checkInId => text()();
  DateTimeColumn get at => dateTime()();
  TextColumn get strategy => textEnum<StrategyId>()();
  TextColumn get reason => textEnum<StartReason>()();
  TextColumn get debtName => text().nullable()();

  /// JSON array of integer minor units: the followed plan's total owed at
  /// month 0 (the start) and after each month.
  TextColumn get projectedTotalsJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

`StartReason` lives in `lib/features/progress/domain/progress.dart` (Task 3). For now, create that file with just the enum:

```dart
/// Why a starting point was recorded (spec §6.3).
enum StartReason { initial, debtAdded, debtDeleted, planSwitched, restarted }
```

Register the new tables in `@DriftDatabase(tables: [...])`, set `schemaVersion => 4`, and add:

```dart
from3To4: (m, schema) async {
  await m.addColumn(schema.debts, schema.debts.clearedAt);
  await m.createTable(schema.checkIns);
  await m.createTable(schema.checkInBalances);
  await m.createTable(schema.startingPoints);
},
```

Run `./tool/codegen.sh`, then `dart run drift_dev make-migrations`. (It writes `drift_schema_v4.json`, the `schema_v4.dart` helper and step code. If `from3To4` doesn't compile until the steps are regenerated, run make-migrations first with `schemaVersion = 4` and an empty `from3To4`, then fill it in.)

- [ ] **Step 2: Write the data-integrity test (failing until the migration is right)**

Add to `migration_test.dart`:

```dart
test('v3 debts survive the upgrade to v4, uncleared, with no history', () async {
  final created = DateTime(2026, 9).millisecondsSinceEpoch ~/ 1000;
  await verifier.testWithDataIntegrity(
    oldVersion: 3,
    newVersion: 4,
    createOld: v3.DatabaseAtV3.new,
    createNew: v4.DatabaseAtV4.new,
    openTestedDatabase: AppDatabase.new,
    createItems: (batch, oldDb) {
      batch.insert(
        oldDb.debts,
        v3.DebtsCompanion.insert(
          id: 'a',
          name: 'Visa',
          type: 'creditCard',
          balanceMinor: 123456,
          aprBps: 1990,
          minPaymentPercentBps: 300,
          minPaymentFloorMinor: 2500,
          allowsOverpayment: 1,
          sortIndex: 0,
          createdAt: created,
          updatedAt: created,
        ),
      );
    },
    validateItems: (newDb) async {
      final row = await newDb.select(newDb.debts).getSingle();
      expect(row.balanceMinor, 123456);
      expect(row.clearedAt, isNull);
      expect(await newDb.select(newDb.checkIns).get(), isEmpty);
      expect(await newDb.select(newDb.startingPoints).get(), isEmpty);
    },
  );
});
```

(Match the v3 companion's exact required fields by opening `generated/schema_v3.dart`.)

- [ ] **Step 3: Run it**

Run: `flutter test test/drift/`
Expected: PASS, including the generated "simple migrations" 1→4, 2→4, 3→4.

- [ ] **Step 4: Commit**

```bash
git add lib/features drift_schemas test/drift
git commit -m "feat(data): schema 4 — cleared debts, check-ins and starting points"
```

---

### Task 2: Cleared debts in the debt repositories

**Files:**
- Create: `lib/features/debts/domain/cleared_debt.dart`
- Modify: `lib/features/debts/domain/debt_repository.dart`, `lib/features/debts/data/drift_debt_repository.dart`, `test/helpers/in_memory_debt_repository.dart`
- Test: `test/features/debts/drift_debt_repository_test.dart`, `test/features/debts/in_memory_debt_repository_test.dart` (new; the double must behave like the real thing)

**Interfaces:**
- Produces:

```dart
/// A debt paid off through a check-in or "Mark as paid off".
@immutable
class ClearedDebt {
  const ClearedDebt({required this.id, required this.name, required this.type, required this.clearedAt});
  final String id;
  final String name;
  final DebtType type;
  final DateTime clearedAt;
}
```

`DebtRepository` changes (update the doc comments to match):
- `watchAll` and `loadAll` return **uncleared** debts only.
- `Stream<List<ClearedDebt>> watchCleared()`: most recently cleared first.
- `Future<void> reopen(String id, Money balance)`: sets the balance, clears `clearedAt`, and moves the debt to the end of the list. Throws `StateError` if there is no such cleared debt.
- `reorder(idsInOrder)`: `idsInOrder` must list every **uncleared** id exactly once.
- `delete(id)`: works for cleared and uncleared debts alike. It does **not** delete check-in rows.
- `InMemoryDebtRepository` gains:
  - `applyCheckIn(Map<String, Money> balances, DateTime at)`, for Task 3's in-memory progress repository: sets each balance, and clears (`clearedAt = at`, balance 0) those at 0.
  - `final List<void Function(String from, String to)> onConvert`: callbacks run by `convertAmounts` when digits change.

- [ ] **Step 1: Failing tests (Drift)**

In `drift_debt_repository_test.dart`, following that file's existing setup (a `NativeDatabase.memory()` `AppDatabase` and a fixed clock):

```dart
test('cleared debts are left out of planning and listed apart', () async {
  await repo.add(testDebt(id: 'a', name: 'Visa'));
  await repo.add(testDebt(id: 'b', name: 'Loan'));
  await (db.update(db.debtRows)..where((t) => t.id.equals('a'))).write(
    DebtRowsCompanion(balanceMinor: const Value(0), clearedAt: Value(DateTime(2026, 9, 20))),
  );
  expect([for (final d in await repo.loadAll('GBP')) d.id], ['b']);
  final cleared = await repo.watchCleared().first;
  expect([for (final c in cleared) (c.id, c.name, c.clearedAt)], [('a', 'Visa', DateTime(2026, 9, 20))]);
});

test('reopening puts the debt back at the end with its new balance', () async {
  await repo.add(testDebt(id: 'a'));
  await repo.add(testDebt(id: 'b'));
  await (db.update(db.debtRows)..where((t) => t.id.equals('a'))).write(
    DebtRowsCompanion(balanceMinor: const Value(0), clearedAt: Value(DateTime(2026, 9, 20))),
  );
  await repo.reopen('a', const Money(5000, 'GBP'));
  final debts = await repo.loadAll('GBP');
  expect([for (final d in debts) d.id], ['b', 'a']);
  expect(debts.last.balance, const Money(5000, 'GBP'));
  expect(await repo.watchCleared().first, isEmpty);
});

test('reorder covers uncleared debts only', () async {
  await repo.add(testDebt(id: 'a'));
  await repo.add(testDebt(id: 'b'));
  await repo.add(testDebt(id: 'c'));
  await (db.update(db.debtRows)..where((t) => t.id.equals('b'))).write(
    DebtRowsCompanion(balanceMinor: const Value(0), clearedAt: Value(DateTime(2026, 9, 20))),
  );
  await repo.reorder(['c', 'a']);
  expect([for (final d in await repo.loadAll('GBP')) d.id], ['c', 'a']);
  expect(() => repo.reorder(['c', 'a', 'b']), throwsArgumentError);
});
```

(The repository test adds with the id the test gives: `DriftDebtRepository.add` stores `debt.id` as is. If the file's helper differs, follow it.)

Write the same three tests against `InMemoryDebtRepository` in the new `in_memory_debt_repository_test.dart`. Clear through `applyCheckIn({'a': Money(0,'GBP')}, DateTime(2026,9,20))` instead of the raw SQL update, and add:

```dart
test('applyCheckIn sets balances and clears the zeros', () async {
  final repo = InMemoryDebtRepository([testDebt(id: 'a'), testDebt(id: 'b')]);
  repo.applyCheckIn({'a': const Money(0, 'GBP'), 'b': const Money(4200, 'GBP')}, DateTime(2026, 9, 20));
  expect([for (final d in await repo.loadAll('GBP')) (d.id, d.balance.minor)], [('b', 4200)]);
  expect((await repo.watchCleared().first).single.id, 'a');
});
```

- [ ] **Step 2: Run them.** `flutter test test/features/debts/drift_debt_repository_test.dart test/features/debts/in_memory_debt_repository_test.dart`. Expected: FAIL (no `watchCleared`/`reopen`; cleared rows are still listed).

- [ ] **Step 3: Implement**

`DriftDebtRepository`:
- `_ordered()` adds `..where((t) => t.clearedAt.isNull())`.
- `watchCleared()`: `(select(debtRows)..where((t) => t.clearedAt.isNotNull())..orderBy([(t) => OrderingTerm.desc(t.clearedAt)])).watch().map(...)`, mapping to `ClearedDebt`.
- `reopen`: in a transaction, check the row exists with `clearedAt` not null (else `StateError`), find the max `sortIndex` of uncleared rows, then write `balanceMinor`, `clearedAt: const Value(null)`, `sortIndex: max + 1` and `updatedAt`.
- `reorder`: compare against uncleared ids only (`select(debtRows)..where(clearedAt.isNull())`).
- `add`: keep the max `sortIndex` over all rows (fine).

`InMemoryDebtRepository`: hold `final Map<String, DateTime> _clearedAt = {}` plus the cleared debts' last `Debt` value:
- `watchAll`/`loadAll` filter them out;
- `watchCleared` yields them (a stream like `watchAll`);
- `reopen` removes the id from the map and moves the debt to the end;
- `applyCheckIn` updates balances, puts zeros into the map, and notifies;
- `reorder` checks against uncleared ids;
- `convertAmounts` calls each `onConvert(from, to)` after rescaling, when `from != null && from != to`.

- [ ] **Step 4: Run** the two files plus `flutter test` (the whole suite, since `pumpApp` uses the in-memory repository). Expected: PASS.

- [ ] **Step 5: Commit** `feat(debts): cleared debts leave planning; reopen; uncleared-only reorder`.

---

### Task 3: Progress model and repository

**Files:**
- Modify: `lib/features/progress/domain/progress.dart`
- Create: `lib/features/progress/domain/progress_repository.dart`, `lib/features/progress/data/drift_progress_repository.dart`, `test/helpers/in_memory_progress_repository.dart`
- Modify: `lib/app/dependencies.dart` (`progressRepositoryProvider`), `lib/features/debts/data/drift_debt_repository.dart` (`convertAmounts`), `test/helpers/pump_app.dart`, `test/helpers/test_container.dart` (if it builds repositories; the Drift one uses the in-memory `AppDatabase`)
- Test: `test/features/progress/drift_progress_repository_test.dart`, `test/features/progress/in_memory_progress_repository_test.dart`

**Interfaces:**
- Produces (`progress.dart`):

```dart
import 'package:flutter/foundation.dart';
import 'package:payoff_engine/payoff_engine.dart';

enum StartReason { initial, debtAdded, debtDeleted, planSwitched, restarted }

@immutable
class CheckIn {
  const CheckIn({required this.id, required this.at, required this.isStart, required this.total, required this.balances});
  final String id;
  final DateTime at;
  final bool isStart;
  final Money total;

  /// Debt id → (name at the time, balance). Zero marks a debt cleared here.
  final Map<String, ({String name, Money balance})> balances;
}

@immutable
class StartingPoint {
  const StartingPoint({required this.id, required this.at, required this.checkInId, required this.strategy, required this.reason, required this.projectedTotals, this.debtName});
  final String id;
  final DateTime at;
  final String checkInId;
  final StrategyId strategy;
  final StartReason reason;
  final String? debtName;

  /// Total owed at month 0 (the start) and after each month, minor units.
  final List<int> projectedTotals;
}

/// Everything recorded, oldest first.
@immutable
class ProgressHistory {
  const ProgressHistory({this.checkIns = const [], this.starts = const []});
  final List<CheckIn> checkIns;
  final List<StartingPoint> starts;

  StartingPoint? get firstStart => starts.firstOrNull;
  StartingPoint? get latestStart => starts.lastOrNull;
  CheckIn? get lastCheckIn => checkIns.lastOrNull;
  CheckIn checkInFor(StartingPoint s) => checkIns.firstWhere((c) => c.id == s.checkInId);
}
```

- `ProgressRepository`:

```dart
abstract interface class ProgressRepository {
  Stream<ProgressHistory> watch(String currencyCode);
  Future<ProgressHistory> load(String currencyCode);

  /// Records a check-in of [balances] (debt id → balance) at [at] and, in
  /// the same transaction, sets each debt's balance; a zero clears that debt
  /// (clearedAt = [at]). Names are read from the debts.
  Future<CheckIn> saveCheckIn({required DateTime at, required Map<String, Money> balances});

  /// Records a starting point: a start check-in of the current [balances]
  /// (debts unchanged) and the start itself.
  Future<StartingPoint> recordStart({
    required DateTime at,
    required Map<String, Money> balances,
    required StrategyId strategy,
    required StartReason reason,
    required List<int> projectedTotals,
    String? debtName,
  });

  /// "Start fresh": deletes every check-in and starting point. Debts, their
  /// clearedAt and settings are untouched.
  Future<void> clearHistory();
}
```

- `progressRepositoryProvider` (keepAlive) → `DriftProgressRepository(appDatabase)`.
- `InMemoryProgressRepository(InMemoryDebtRepository debts)`: same behaviour, and registers an `onConvert` rescaler.
- `pumpApp` overrides `progressRepositoryProvider` with it and exposes `AppHarness.progress`.

- [ ] **Step 1: Failing tests** (Drift; mirror them for the in-memory double)

```dart
late AppDatabase db;
late DriftDebtRepository debts;
late DriftProgressRepository progress;
const gbp = 'GBP';
Money m(int minor) => Money(minor, gbp);

setUp(() async {
  db = AppDatabase(NativeDatabase.memory());
  debts = DriftDebtRepository(db, now: () => DateTime(2026, 9, 24));
  progress = DriftProgressRepository(db);
  await debts.convertAmounts(toCurrencyCode: gbp);
  await debts.add(testDebt(id: 'a', name: 'Visa', balance: 100000));
  await debts.add(testDebt(id: 'b', name: 'Loan', balance: 50000));
});
tearDown(() => db.close());

test('a check-in updates balances and clears zeros, in one go', () async {
  final c = await progress.saveCheckIn(at: DateTime(2026, 10, 3), balances: {'a': m(0), 'b': m(42000)});
  expect(c.total, m(42000));
  expect(c.balances['a']!.name, 'Visa');
  expect([for (final d in await debts.loadAll(gbp)) (d.id, d.balance.minor)], [('b', 42000)]);
  expect((await debts.watchCleared().first).single.clearedAt, DateTime(2026, 10, 3));
  final h = await progress.load(gbp);
  expect(h.checkIns.single.isStart, isFalse);
});

test('a starting point records a start check-in and leaves debts alone', () async {
  final s = await progress.recordStart(
    at: DateTime(2026, 9, 24),
    balances: {'a': m(100000), 'b': m(50000)},
    strategy: StrategyId.avalanche,
    reason: StartReason.initial,
    projectedTotals: [150000, 120000, 0],
  );
  final h = await progress.load(gbp);
  expect(h.starts.single.projectedTotals, [150000, 120000, 0]);
  expect(h.checkInFor(s).isStart, isTrue);
  expect(h.checkInFor(s).total, m(150000));
  expect((await debts.loadAll(gbp)).length, 2);
});

test('start fresh deletes history, never debts', () async {
  await progress.recordStart(at: DateTime(2026, 9, 24), balances: {'a': m(100000)}, strategy: StrategyId.avalanche, reason: StartReason.initial, projectedTotals: [100000, 0]);
  await progress.saveCheckIn(at: DateTime(2026, 10, 3), balances: {'a': m(0)});
  await progress.clearHistory();
  final h = await progress.load(gbp);
  expect(h.checkIns, isEmpty);
  expect(h.starts, isEmpty);
  expect(await debts.watchCleared().first, hasLength(1)); // clearedAt kept
});

test('a debt deleted later keeps its check-in rows and name', () async {
  await progress.recordStart(at: DateTime(2026, 9, 24), balances: {'a': m(100000), 'b': m(50000)}, strategy: StrategyId.avalanche, reason: StartReason.initial, projectedTotals: [150000, 0]);
  await debts.delete('b');
  final h = await progress.load(gbp);
  expect(h.checkIns.single.balances['b']!.name, 'Loan');
});

test('changing to a currency with other decimals rescales history', () async {
  await progress.recordStart(at: DateTime(2026, 9, 24), balances: {'a': m(100000)}, strategy: StrategyId.avalanche, reason: StartReason.initial, projectedTotals: [100000, 50000, 0]);
  await debts.convertAmounts(toCurrencyCode: 'JPY'); // 2 → 0 decimals
  final h = await progress.load('JPY');
  expect(h.checkIns.single.total, const Money(1000, 'JPY'));
  expect(h.checkIns.single.balances['a']!.balance, const Money(1000, 'JPY'));
  expect(h.starts.single.projectedTotals, [1000, 500, 0]);
});
```

- [ ] **Step 2: Run them.** Expected: FAIL (the types don't exist).

- [ ] **Step 3: Implement `DriftProgressRepository`**

```dart
class DriftProgressRepository implements ProgressRepository {
  DriftProgressRepository(this._db);

  static const _uuid = Uuid();
  final AppDatabase _db;

  @override
  Stream<ProgressHistory> watch(String currencyCode) {
    // Re-read whenever any of the three tables changes.
    final trigger = _db.tableUpdates(
      TableUpdateQuery.onAllTables([_db.checkInRows, _db.checkInBalanceRows, _db.startingPointRows]),
    );
    return Stream<void>.value(null)
        .followedBy(trigger)
        .asyncMap((_) => load(currencyCode));
  }

  @override
  Future<ProgressHistory> load(String currencyCode) async {
    Money money(int minor) => Money(minor, currencyCode);
    final checkIns = await (_db.select(_db.checkInRows)..orderBy([(t) => OrderingTerm(expression: t.at)])).get();
    final balances = await _db.select(_db.checkInBalanceRows).get();
    final starts = await (_db.select(_db.startingPointRows)..orderBy([(t) => OrderingTerm(expression: t.at)])).get();
    return ProgressHistory(
      checkIns: [
        for (final c in checkIns)
          CheckIn(
            id: c.id,
            at: c.at,
            isStart: c.isStart,
            total: money(c.totalMinor),
            balances: {
              for (final b in balances)
                if (b.checkInId == c.id) b.debtId: (name: b.debtName, balance: money(b.balanceMinor)),
            },
          ),
      ],
      starts: [
        for (final s in starts)
          StartingPoint(
            id: s.id,
            at: s.at,
            checkInId: s.checkInId,
            strategy: s.strategy,
            reason: s.reason,
            debtName: s.debtName,
            projectedTotals: [for (final v in jsonDecode(s.projectedTotalsJson) as List<Object?>) v! as int],
          ),
      ],
    );
  }

  Future<CheckIn> _insertCheckIn(DateTime at, Map<String, Money> balances, {required bool isStart}) async {
    final names = {for (final r in await _db.select(_db.debtRows).get()) r.id: r.name};
    final id = _uuid.v4();
    final total = balances.values.fold<int>(0, (s, b) => s + b.minor);
    await _db.into(_db.checkInRows).insert(
      CheckInRowsCompanion.insert(id: id, at: at, isStart: isStart, totalMinor: total),
    );
    for (final e in balances.entries) {
      await _db.into(_db.checkInBalanceRows).insert(
        CheckInBalanceRowsCompanion.insert(checkInId: id, debtId: e.key, debtName: names[e.key] ?? '', balanceMinor: e.value.minor),
      );
    }
    final currency = balances.values.firstOrNull?.currency ?? 'XXX';
    return CheckIn(
      id: id,
      at: at,
      isStart: isStart,
      total: Money(total, currency),
      balances: {for (final e in balances.entries) e.key: (name: names[e.key] ?? '', balance: e.value)},
    );
  }

  @override
  Future<CheckIn> saveCheckIn({required DateTime at, required Map<String, Money> balances}) =>
      _db.transaction(() async {
        for (final e in balances.entries) {
          await (_db.update(_db.debtRows)..where((t) => t.id.equals(e.key))).write(
            DebtRowsCompanion(
              balanceMinor: Value(e.value.minor),
              clearedAt: e.value.isZero ? Value(at) : const Value.absent(),
              updatedAt: Value(at),
            ),
          );
        }
        return _insertCheckIn(at, balances, isStart: false);
      });

  @override
  Future<StartingPoint> recordStart({
    required DateTime at,
    required Map<String, Money> balances,
    required StrategyId strategy,
    required StartReason reason,
    required List<int> projectedTotals,
    String? debtName,
  }) => _db.transaction(() async {
    final checkIn = await _insertCheckIn(at, balances, isStart: true);
    final id = _uuid.v4();
    await _db.into(_db.startingPointRows).insert(
      StartingPointRowsCompanion.insert(
        id: id,
        checkInId: checkIn.id,
        at: at,
        strategy: strategy,
        reason: reason,
        debtName: Value(debtName),
        projectedTotalsJson: jsonEncode(projectedTotals),
      ),
    );
    return StartingPoint(id: id, at: at, checkInId: checkIn.id, strategy: strategy, reason: reason, debtName: debtName, projectedTotals: projectedTotals);
  });

  @override
  Future<void> clearHistory() => _db.transaction(() async {
    await _db.delete(_db.startingPointRows).go();
    await _db.delete(_db.checkInBalanceRows).go();
    await _db.delete(_db.checkInRows).go();
  });
}
```

In `DriftDebtRepository.convertAmounts`, inside the `fromDigits != toDigits` branch and after the scenarios, rescale the progress rows (with `min: 0`):
- `checkInRows.totalMinor`;
- `checkInBalanceRows.balanceMinor`;
- each `startingPointRows.projectedTotalsJson` (decode, rescale each element, encode).

The in-memory repository keeps lists of `CheckIn`/`StartingPoint` and a broadcast `StreamController` like the debt double:
- `saveCheckIn` calls `debts.applyCheckIn(balances, at)` first;
- names come from `debts` (add `String? nameOf(String id)` to the in-memory debt repository, covering cleared debts too);
- `onConvert` rescales every stored amount.

Update `CLAUDE.md` gotcha: `DriftDebtRepository.convertAmounts` also rescales check-ins and starting points, and so does the in-memory pair.

- [ ] **Step 4: Run** the progress tests, then `flutter test`. Expected: PASS.

- [ ] **Step 5: Commit** `feat(progress): check-ins and starting points, stored with the debts`.

---

### Task 4: Progress maths

**Files:**
- Create: `lib/features/progress/domain/progress_math.dart`
- Test: `test/features/progress/progress_math_test.dart`

**Interfaces:**
- Consumes: `ProgressHistory` (Task 3), `ClearedDebt` (Task 2), `groupPlanDebts`/`baseDebtId` (Plan 7).
- Produces:

```dart
/// Whole calendar months from [from]'s month to [to]'s month.
int monthIndex(DateTime from, DateTime to);

/// The plan's total owed at month 0 and after each month, minor units.
List<int> projectedTotals(PayoffPlan plan);

/// Paid off since the first starting point (spec §6.4).
({Money amount, int percent, DateTime? since}) paidOff(
  ProgressHistory history,
  List<Debt> uncleared,
  List<ClearedDebt> cleared,
  String currency,
);

sealed class AheadBehind { const AheadBehind(); }
class NoProgressYet extends AheadBehind { const NoProgressYet(); }
class OnTrack extends AheadBehind { const OnTrack(); }
class AheadMonths extends AheadBehind { const AheadMonths(this.months); final int months; }
class AheadMoney extends AheadBehind { const AheadMoney(this.amount); final Money amount; }
class Behind extends AheadBehind { const Behind(this.amount); final Money amount; }

/// At the latest check-in, against the latest starting point (spec §6.5).
AheadBehind aheadBehind(ProgressHistory history, String currency);

/// What the plan expects each debt to owe [months] after it started
/// (0 = the balances it started from). Portions count with their card;
/// past the plan's end everything is 0.
Map<String, Money> expectedBalances(PayoffPlan plan, int months, List<Debt> debts);

/// The starting point due now, if any (spec §6.3). Null while the plan is
/// infeasible (pass [feasible] false), or when nothing has changed.
({StartReason reason, String? debtName})? nextStart({
  required ProgressHistory history,
  required List<Debt> uncleared,
  required List<ClearedDebt> cleared,
  required StrategyId followed,
  required bool feasible,
});

class ProgressChart {
  const ProgressChart({required this.actual, required this.current, required this.original, required this.markers, required this.today});

  /// (x, total owed in major units) per check-in; x = months since the first start.
  final List<(double, double)> actual;
  final List<(double, double)> current;   // latest start's projection
  final List<(double, double)>? original; // first start's, when restarted
  final List<({double x, StartReason reason, StrategyId strategy, String? debtName})> markers;
  final double today;
}

ProgressChart progressChartData(ProgressHistory history, DateTime now, String currency);
```

- [ ] **Step 1: Failing tests** (the complete list; write each)

```dart
Money gbp(int minor) => Money(minor, 'GBP');
CheckIn ci(String id, DateTime at, Map<String, int> b, {bool start = false}) => CheckIn(
  id: id, at: at, isStart: start,
  total: gbp(b.values.fold(0, (s, v) => s + v)),
  balances: {for (final e in b.entries) e.key: (name: e.key.toUpperCase(), balance: gbp(e.value))},
);
StartingPoint sp(String id, String checkIn, DateTime at, List<int> totals, {StrategyId s = StrategyId.avalanche, StartReason r = StartReason.initial, String? name}) =>
    StartingPoint(id: id, at: at, checkInId: checkIn, strategy: s, reason: r, projectedTotals: totals, debtName: name);

test('monthIndex counts calendar months across the year end', () {
  expect(monthIndex(DateTime(2026, 12, 31), DateTime(2027, 1, 1)), 1);
  expect(monthIndex(DateTime(2026, 9, 24), DateTime(2026, 9, 30)), 0);
  expect(monthIndex(DateTime(2026, 9, 24), DateTime(2028, 2, 1)), 17);
});

test('paid off counts from each debt's first recorded balance', () {
  final h = ProgressHistory(
    checkIns: [ci('s', DateTime(2026, 6, 1), {'a': 100000, 'b': 50000}, start: true), ci('c', DateTime(2026, 9, 1), {'a': 90000, 'b': 0}), ci('s2', DateTime(2026, 9, 2), {'a': 90000, 'n': 20000}, start: true)],
    starts: [sp('1', 's', DateTime(2026, 6, 1), [150000, 0]), sp('2', 's2', DateTime(2026, 9, 2), [110000, 0], r: StartReason.debtAdded)],
  );
  final r = paidOff(h, [testDebt(id: 'a', balance: 80000), testDebt(id: 'n', balance: 20000)],
      [ClearedDebt(id: 'b', name: 'B', type: DebtType.loan, clearedAt: DateTime(2026, 9, 1))], 'GBP');
  // a: 100,000 → 80,000; b: 50,000 → 0; n: 20,000 → 20,000.
  expect(r.amount, gbp(70000));
  expect(r.percent, 41); // 70,000 / 170,000
  expect(r.since, DateTime(2026, 6, 1));
});

test('a deleted debt drops out; owing more reads as a negative amount', () {
  final h = ProgressHistory(checkIns: [ci('s', DateTime(2026, 6, 1), {'a': 100000, 'gone': 5000}, start: true)], starts: [sp('1', 's', DateTime(2026, 6, 1), [105000, 0])]);
  final r = paidOff(h, [testDebt(id: 'a', balance: 110000)], const [], 'GBP');
  expect(r.amount, gbp(-10000));
  expect(r.percent, 0);
});

group('ahead or behind', () {
  // Start 1 Jun: 1,000.00 projected to fall 100.00 a month.
  final totals = [for (var i = 0; i <= 10; i++) 100000 - i * 10000];
  ProgressHistory at(DateTime when, int total) => ProgressHistory(
    checkIns: [ci('s', DateTime(2026, 6, 1), {'a': 100000}, start: true), ci('c', when, {'a': total})],
    starts: [sp('1', 's', DateTime(2026, 6, 1), totals)],
  );
  test('no check-in since the start', () {
    final h = ProgressHistory(checkIns: [ci('s', DateTime(2026, 6, 1), {'a': 100000}, start: true)], starts: [sp('1', 's', DateTime(2026, 6, 1), totals)]);
    expect(aheadBehind(h, 'GBP'), isA<NoProgressYet>());
  });
  test('within 1% is on track', () => expect(aheadBehind(at(DateTime(2026, 9, 1), 70500), 'GBP'), isA<OnTrack>()));
  test('months ahead when a later month is matched', () {
    expect((aheadBehind(at(DateTime(2026, 9, 1), 60000), 'GBP') as AheadMonths).months, 1);
  });
  test('money ahead when less than a month ahead', () {
    expect((aheadBehind(at(DateTime(2026, 9, 1), 65000), 'GBP') as AheadMoney).amount, gbp(5000));
  });
  test('behind', () => expect((aheadBehind(at(DateTime(2026, 9, 1), 78000), 'GBP') as Behind).amount, gbp(8000)));
  test('past the projection's end, anything owed is behind', () {
    expect((aheadBehind(at(DateTime(2027, 12, 1), 3000), 'GBP') as Behind).amount, gbp(3000));
  });
});

test('expected balances: now, after k months, beyond the end, portions merged', () {
  final plan = PayoffPlan(
    debts: [PlanDebt(id: 'a', name: 'A', startingBalance: gbp(20000)), PlanDebt(id: 'b', name: 'B', startingBalance: gbp(30000)), PlanDebt(id: 'b#from-c', name: 'C', startingBalance: gbp(10000))],
    months: [
      MonthRow(month: 1, interest: [gbp(0), gbp(0), gbp(0)], payments: [gbp(0), gbp(0), gbp(0)], closingBalances: [gbp(10000), gbp(25000), gbp(8000)]),
      MonthRow(month: 2, interest: [gbp(0), gbp(0), gbp(0)], payments: [gbp(0), gbp(0), gbp(0)], closingBalances: [gbp(0), gbp(20000), gbp(0)]),
    ],
    totalPaid: gbp(60000), totalInterest: gbp(0), totalFees: gbp(0),
  );
  final debts = [testDebt(id: 'a', balance: 20000), testDebt(id: 'b', balance: 30000), testDebt(id: 'c', balance: 10000)];
  expect(expectedBalances(plan, 0, debts), {'a': gbp(20000), 'b': gbp(30000), 'c': gbp(10000)});
  // c was moved onto b: its own column is gone, so it expects 0.
  expect(expectedBalances(plan, 1, debts), {'a': gbp(10000), 'b': gbp(33000), 'c': gbp(0)});
  expect(expectedBalances(plan, 5, debts), {'a': gbp(0), 'b': gbp(0), 'c': gbp(0)});
});

group('next starting point', () {
  final a = testDebt(id: 'a', name: 'Visa');
  final b = testDebt(id: 'b', name: 'Loan');
  final base = ProgressHistory(
    checkIns: [ci('s', DateTime(2026, 6, 1), {'a': 100000, 'b': 50000}, start: true)],
    starts: [sp('1', 's', DateTime(2026, 6, 1), [150000, 0])],
  );
  test('the first one is initial', () {
    expect(nextStart(history: const ProgressHistory(), uncleared: [a], cleared: const [], followed: StrategyId.avalanche, feasible: true)!.reason, StartReason.initial);
  });
  test('none while infeasible', () {
    expect(nextStart(history: const ProgressHistory(), uncleared: [a], cleared: const [], followed: StrategyId.avalanche, feasible: false), isNull);
  });
  test('none when nothing changed', () {
    expect(nextStart(history: base, uncleared: [a, b], cleared: const [], followed: StrategyId.avalanche, feasible: true), isNull);
  });
  test('a plan switch', () {
    expect(nextStart(history: base, uncleared: [a, b], cleared: const [], followed: StrategyId.snowball, feasible: true)!.reason, StartReason.planSwitched);
  });
  test('an added debt, named', () {
    final r = nextStart(history: base, uncleared: [a, b, testDebt(id: 'n', name: 'Amex')], cleared: const [], followed: StrategyId.avalanche, feasible: true)!;
    expect((r.reason, r.debtName), (StartReason.debtAdded, 'Amex'));
  });
  test('a deleted debt, named from history', () {
    final r = nextStart(history: base, uncleared: [a], cleared: const [], followed: StrategyId.avalanche, feasible: true)!;
    expect((r.reason, r.debtName), (StartReason.debtDeleted, 'B'));
  });
  test('clearing is progress, not a restart', () {
    final h = ProgressHistory(checkIns: [...base.checkIns, ci('c', DateTime(2026, 8, 1), {'a': 90000, 'b': 0})], starts: base.starts);
    expect(nextStart(history: h, uncleared: [a], cleared: [ClearedDebt(id: 'b', name: 'Loan', type: DebtType.loan, clearedAt: DateTime(2026, 8, 1))], followed: StrategyId.avalanche, feasible: true), isNull);
  });
  test('re-opening a cleared debt counts as added', () {
    final h = ProgressHistory(checkIns: [...base.checkIns, ci('c', DateTime(2026, 8, 1), {'a': 90000, 'b': 0})], starts: base.starts);
    expect(nextStart(history: h, uncleared: [a, b], cleared: const [], followed: StrategyId.avalanche, feasible: true)!.reason, StartReason.debtAdded);
  });
});

test('chart: actual across restarts, latest projection, original, markers', () {
  final h = ProgressHistory(
    checkIns: [ci('s', DateTime(2026, 6, 1), {'a': 100000}, start: true), ci('c', DateTime(2026, 7, 1), {'a': 90000}), ci('s2', DateTime(2026, 8, 1), {'a': 80000}, start: true)],
    starts: [sp('1', 's', DateTime(2026, 6, 1), [100000, 90000, 0]), sp('2', 's2', DateTime(2026, 8, 1), [80000, 40000, 0], s: StrategyId.snowball, r: StartReason.planSwitched)],
  );
  final chart = progressChartData(h, DateTime(2026, 8, 16), 'GBP');
  expect(chart.actual, [(0.0, 1000.0), (1.0, 900.0), (2.0, 800.0)]);
  expect(chart.current, [(2.0, 800.0), (3.0, 400.0), (4.0, 0.0)]);
  expect(chart.original, [(0.0, 1000.0), (1.0, 900.0), (2.0, 0.0)]);
  expect(chart.markers.single.strategy, StrategyId.snowball);
  expect(chart.today, closeTo(2.5, 0.05));
});

test('chart: one start has no original line', () {
  final h = ProgressHistory(checkIns: [ci('s', DateTime(2026, 6, 1), {'a': 100000}, start: true)], starts: [sp('1', 's', DateTime(2026, 6, 1), [100000, 0])]);
  expect(progressChartData(h, DateTime(2026, 6, 1), 'GBP').original, isNull);
});
```

(x of a date = `monthIndex(firstStart.at, date) + (date.day - 1) / daysInMonth(date)`; a check-in on the 1st sits exactly on the month.)

- [ ] **Step 2: Run it.** Expected: FAIL.

- [ ] **Step 3: Implement.** The rules, in full:
- **`paidOff`:**
  - First balance per debt = its balance in the earliest check-in that lists it.
  - Existing debts = uncleared ids plus cleared ids; the current balance is 0 for cleared ones.
  - `amount = Σ(first − current)` over existing debts that have a first balance.
  - `percent = amount ≤ 0 ? 0 : (amount × 100 ~/ Σ first).clamp(0, 100)`.
  - `since = firstStart?.at`.
- **`aheadBehind`:**
  - Take the latest start `S` and the last check-in `C`. If there's no start, or `C` is `S`'s own check-in or earlier, return `NoProgressYet`.
  - `m = monthIndex(S.at, C.at)`, and `expected = m < totals.length ? totals[m] : 0`.
  - `diff = expected − C.total`, and `tol = max(expected ~/ 100, oneMajorUnit)`.
  - `|diff| ≤ tol` → `OnTrack`.
  - `diff > 0`: `k` = the largest `j > m` with `totals[j] ≥ C.total` (within the list), minus `m`. `k ≥ 1` → `AheadMonths(k)`, else `AheadMoney(diff)`.
  - Otherwise → `Behind(−diff)`.
- **`expectedBalances`:**
  - `months ≤ 0` → the debts' balances.
  - `months > plan.monthsToClear` → zeros.
  - Otherwise `row = plan.months[months − 1]`: sum the closing balances per `groupPlanDebts` group id. Any listed debt missing from the groups gets 0.
- **`nextStart`:** follow the order in the tests. `latestMention(id)` = the balance in the most recent check-in that lists `id`.
  1. Infeasible → `null`.
  2. No start → `initial`.
  3. `followed ≠ latest.strategy` → `planSwitched`.
  4. First uncleared `d` with no mention, or a latest mention of 0 → `debtAdded(d.name)`.
  5. First id in the latest start's check-in with balance > 0 that is neither uncleared nor cleared → `debtDeleted(its name)`.
  6. Otherwise `null`.
- **`progressChartData`:**
  - `actual` = every check-in (x, total major).
  - `current` = the latest start's totals from `x0 = monthIndex(first.at, latest.at)`, at integer steps.
  - `original` = the first start's totals from 0, only when `starts.length > 1`.
  - `markers` = the starts after the first, at their x.
  - `today` = x of `now`.

- [ ] **Step 4: Run it.** Expected: PASS.

- [ ] **Step 5: Commit** `feat(progress): paid off, ahead/behind, expected balances, restarts, chart data`.

---

### Task 5: Following a plan

**Files:**
- Modify: `lib/features/settings/domain/app_settings.dart` (`StrategyId? followedStrategy`, default null), `prefs_settings_repository.dart` (key `followedStrategy`, stored by `name`; an unknown name reads as null), `settings_controller.dart` (`Future<void> followStrategy(StrategyId id)`)
- Modify: `lib/features/strategies/presentation/current_plans.dart`
- Test: `test/features/settings/prefs_settings_repository_test.dart`, `settings_controller_test.dart`, `test/features/strategies/current_plans_test.dart`

**Interfaces:**
- `HomePlan` gains:
  - `HomeFollowedUnavailable(StrategyId strategyId, PayoffResult result)`;
  - `HomeAllCleared()`, for no uncleared debts with at least one cleared.
- `homePlanProvider`:
  - uses `settings.followedStrategy` when set: `Feasible` → `HomeFollowing`, anything else → `HomeFollowedUnavailable`;
  - when unset, uses `bestPayOffMethod` as before;
  - with no uncleared debts: `HomeAllCleared` if `clearedDebtsProvider` (Task 6) has any, else `HomeNoDebts`.

  Task 6 creates `clearedDebtsProvider`. In this task, read `ref.watch(debtRepositoryProvider).watchCleared()` through a small `@riverpod Stream<List<ClearedDebt>> clearedDebts(Ref ref)` placed in `lib/features/debts/presentation/debts_providers.dart` (keepAlive, like `debts`; empty stream until settings load). Task 6 reuses it.

- [ ] **Step 1: Failing tests**
- The prefs round trip saves and reads `followedStrategy: StrategyId.snowball`; a stored `'nonsense'` reads as null.
- `settingsController.followStrategy(StrategyId.snowball)` persists.
- In `current_plans_test.dart`:
  - `'follows the chosen plan, not the cheapest'`: `followStrategy(snowball)` on two debts where avalanche is cheapest gives `HomeFollowing` with `result.strategyId == snowball`.
  - `'a chosen plan that no longer works is shown as unavailable'`: follow `balanceTransfer` with a 0% debt (NotApplicable) → `HomeFollowedUnavailable`.
  - `'all cleared'`: add a debt, clear it through `debtRepository.applyCheckIn`, or through `ProgressRepository.saveCheckIn` with the Drift test container → `HomeAllCleared`.
- [ ] **Step 2: Run them. Expected: FAIL.**
- [ ] **Step 3: Implement** as described. Keep `homePlanProvider`'s existing order of checks.
- [ ] **Step 4: Run** `flutter test test/features/settings test/features/strategies`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(progress): follow a chosen plan; unavailable and all-cleared states`.

---

### Task 6: Progress providers, the reconciler and the controller

**Files:**
- Create: `lib/features/progress/presentation/progress_providers.dart`
- Modify: `lib/app/app.dart` (keep the reconciler alive: `ref.watch(progressReconcilerProvider)` inside `DebtDestroyerApp.build`)
- Test: `test/features/progress/progress_providers_test.dart` (unit, `createTestContainer`) and `test/features/progress/reconciler_widget_test.dart` (`pumpApp`)

**Interfaces:**

```dart
/// Everything recorded, in the current currency.
@Riverpod(keepAlive: true)
Stream<ProgressHistory> progressHistory(Ref ref);

/// What Home's progress hero and chart show.
typedef ProgressSummary = ({
  ({Money amount, int percent, DateTime? since}) paid,
  AheadBehind standing,
  CheckIn? lastCheckIn,
  ProgressChart? chart, // null until there is a starting point
});
@riverpod
Future<ProgressSummary> progressSummary(Ref ref);

/// Records a starting point whenever [nextStart] says one is due. Watched by
/// the app for its whole life. Never records two at once.
@Riverpod(keepAlive: true)
class ProgressReconciler extends _$ProgressReconciler {
  @override
  void build();   // listens to homePlanProvider, debtsProvider, clearedDebtsProvider, progressHistoryProvider
}

/// One cleared debt to celebrate.
typedef Cleared = ({String debtId, String name, Money gone, Money? rollsOn, String? next, int clearedCount, int totalCount});

/// What a check-in changed, for the result and celebration screens.
typedef CheckInOutcome = ({
  List<Cleared> cleared,
  List<({String name, Money up})> wentUp,
  int? monthsBefore, // the followed plan's months to clear before saving
});

@Riverpod(keepAlive: true)
class ProgressController extends _$ProgressController {
  @override
  CheckInOutcome? build() => null; // the last outcome

  Future<CheckInOutcome> saveCheckIn(Map<String, Money> balances);
  Future<CheckInOutcome> markPaidOff(String debtId);
  Future<void> follow(StrategyId id);          // settings; the reconciler records planSwitched
  Future<void> restart({required bool clearHistory}); // clear: history deleted, reconciler records initial; keep: restarted start now
  Future<void> reopen(String debtId, Money balance);  // the reconciler records debtAdded
  Future<void> recordStart(StartReason reason, {String? debtName}); // used by the reconciler
}
```

**The reconciler's logic:**
1. On every change, read the latest values.
2. If any of them is still loading, or a recording is in flight (`bool _busy`), do nothing.
3. Otherwise compute `nextStart(...)`, with:
   - `followed` = `settings.followedStrategy ?? the HomeFollowing result's strategyId`;
   - `feasible` = `homePlan is HomeFollowing`.
4. If a start is due:
   - set `_busy`;
   - if `settings.followedStrategy == null`, first call `followStrategy(followed)` (spec §6.2);
   - `await controller.recordStart(...)`;
   - clear `_busy` in `finally`.

   The history stream then re-emits and the check re-runs, finding nothing due.

**`recordStart`:**
- `balances` = the current uncleared debts' balances.
- `projectedTotals(homePlan.result.plan)`, `strategy`, `reason`, `debtName`, and `at: clock()`.

**`saveCheckIn`:** before saving, read the following plan, the debts and the history, then compute:
- **`cleared`:** each entered zero whose debt was positive. For each:
  - `gone` = its first recorded balance (history), or else its current balance;
  - `rollsOn` = its payment in the plan's first month;
  - `next` = the next group in the plan's clearing order that isn't also being cleared;
  - `clearedCount` = cleared debts after save;
  - `totalCount` = cleared + uncleared after save.
- **`wentUp`:** each entered balance higher than the debt's current balance.
- **`monthsBefore`:** the plan's `monthsToClear`.

Then call `repository.saveCheckIn(at: clock(), balances)`, set `state = outcome` and return it.

**`markPaidOff(id)`:** `saveCheckIn({...current balances, id: 0})`.

- [ ] **Step 1: Failing tests (unit, Drift test container)**
  - The first run with one debt and a feasible plan records one `initial` start and sets `followedStrategy` to avalanche.
  - Adding a debt records one `debtAdded` start named after it, with no duplicate after several `pump()`s.
  - While the budget is below the minimums, nothing is recorded; raising the budget records `initial`.
  - `saveCheckIn` with a zero:
    - the outcome lists the cleared debt with its `gone` amount and `next`;
    - no new start is recorded (clearing is progress);
    - the debt leaves `debtsProvider`.
  - `restart(clearHistory: true)`: afterwards the history has exactly one `initial` start, and `followedStrategy` and cleared debts are untouched.
  - `restart(clearHistory: false)` adds a `restarted` start and keeps the earlier ones.
  - `follow(snowball)` records `planSwitched`.
  - `reopen` records `debtAdded`.
  - Month boundary: the clock is 31 Jan; `saveCheckIn` then lands at month index 1 relative to a 1 Jan start (via `aheadBehind` in `progressSummary`).
- [ ] **Step 2: Run them. Expected: FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the new tests, then `flutter test`. Existing widget tests now get a starting point recorded automatically, because the in-memory progress repository is in `pumpApp` (Task 3); they must still pass. If a test counts exact repository writes, update its expectation and say so in a ruling.
- [ ] **Step 5: Commit** `feat(progress): reconciler records starting points; check-in, restart, follow, reopen`.

---

### Task 7: Chart kit, plan against actual

**Files:**
- Modify: `lib/core/charts/balance_line_chart.dart`
- Test: `test/core/charts_test.dart`

**Interfaces:**
- `ChartLine` gains:
  - `List<(double, double)>? points`: when set, these are the x/y spots and `values` is ignored;
  - `bool squares = false`: draws 8px square markers with a 2px surface ring (`FlDotSquarePainter`).
- `BalanceLineChart` gains:
  - `double? todayX`: a vertical `c.today` line (`ExtraLinesData`);
  - `List<({double x, String label})> markers`: short ticks on the axis (`VerticalLine` of 8px at the baseline, via `HorizontalRangeAnnotation`-free `ExtraLinesData` with `dashArray`), with their labels in the touch tooltip-free legend below. Tests just check the lines exist.
- `maxX` accounts for `points`.

- [ ] **Step 1: Failing test**

```dart
testWidgets('plots points, squares, a today line and restart ticks', (tester) async {
  await tester.pumpWidget(host(const BalanceLineChart(
    semanticLabel: 'Progress',
    todayX: 2.5,
    markers: [(x: 2, label: 'Switched to Snowball')],
    lines: [
      ChartLine(points: [(0, 1000), (1, 900), (2, 800)], color: Colors.blue, squares: true),
      ChartLine(points: [(2, 800), (4, 0)], color: Colors.black, style: LineStyle.dashed),
    ],
  )));
  final data = tester.widget<LineChart>(find.byType(LineChart)).data;
  expect(data.maxX, 4);
  expect(data.lineBarsData.last.spots.map((s) => s.x), [0, 1, 2]); // first line on top
  expect(data.lineBarsData.last.dotData.show, isTrue);
  expect(data.extraLinesData.verticalLines.map((l) => l.x), containsAll([2.5, 2.0]));
});
```

- [ ] **Steps 2–4:** run (FAIL), implement, then run the chart tests plus `flutter test test/features/home test/features/strategies` (PASS).
- [ ] **Step 5: Commit** `feat(charts): plan-vs-actual points, today line and restart ticks`.

---

### Task 8: Home, with progress

**Files:**
- Modify: `lib/features/home/presentation/home_screen.dart`
- Create: `lib/features/home/presentation/home_progress.dart` (hero ring, standing chip, progress chart card, check-in card), `lib/features/progress/presentation/follow_sheet.dart`
- Modify: `lib/l10n/app_en.arb`
- Test: `test/features/home/home_screen_test.dart`

**Interfaces / behaviour** (spec §4.2, canvas "A · Demolition crew" Home):
1. **Hero (`HiVisBlock`):**
   - A progress ring on the left: an 84px `CircularProgressIndicator` with `value: percent/100`, stroke 10, track `onHiVis` at 20%, value `onHiVis`, and the `percent%` label in `displayStyle(18)`.
   - Then "Debt-free by" and the date (as now).
   - `homePaidOff(amount, month)`: "£1,350 knocked down since June". When the amount is negative: `homeOwesMore(amount)`: "£X more owed than at the start".
   - The standing chip: a navy fill with white text, from `AheadBehind`:
     - `homeAheadMonths(n)` → "{n} month(s) ahead" (plural);
     - `homeAheadMoney(amount)` → "£X ahead";
     - `homeOnTrack` → "On track";
     - `homeBehind(amount)` → "£X behind";
     - `homeCheckInToTrack` → "Check in to track progress" (NoProgressYet).
   - The strategy name is a `TextButton` ("{name} ▾" via `homeFollowing(name)`) that opens the **follow sheet**:
     - a list of the feasible pay-off methods (`raceStrategies`), with the current one ticked;
     - tapping another shows an inline confirmation (`followConfirm`: "Your history stays. We'll project from today with this plan.") with a "Follow {name}" button calling `ProgressController.follow`.
2. **Chart card:** "Plan vs actual" (`homeProgressTitle`), a `BalanceLineChart` built from `progressSummary.chart`:
   - actual: `points`, `series[0]`, `squares: true`, width 3;
   - current: `c.ink`, dashed;
   - original, when present: `c.faint`, dotted, width 2;
   - `todayX`, and the markers labelled by reason:
     - `restartSwitched(strategy name)` → "Switched to {name}";
     - `restartAdded(name)` → "Added {name}";
     - `restartDeleted(name)` → "Deleted {name}";
     - `restartRestarted` → "Restarted".

   The legend has the three keys, using `_LineSwatch` moved to `lib/core/charts/line_swatch.dart`, which also fixes Plan 7's Home legend minor. The semantics label gives the owed total, the expected-versus-actual difference and the debt-free date. Before the first start (the chart is null), show Plan 7's projection chart.
3. **Check-in card** (`OutlinedCard`):
   - `homeLastCheckIn(date)` ("Last check-in 3 Sep"), or `homeNoCheckInYet`;
   - a `FilledButton` "Check in now" (`homeCheckInNow`) that pushes `/check-in`;
   - a `TextButton` "Restart from here" (`homeRestart`) that opens the restart sheet (Task 11).
4. **Next milestone:** the hazard bar's fraction = (the latest start's balance for that debt − its current balance) / the start balance, clamped to 0.04–1.
5. **Pay this month:** unchanged.
6. **States:**
   - `HomeAllCleared`: a `HiVisBlock` with `homeAllCleared` ("Debt free! You knocked down {amount}.") and an `OutlinedButton` "Add a debt".
   - `HomeFollowedUnavailable`: an `OutlinedCard` with `homeFollowedUnavailable(name)` ("{name} doesn't work with your debts and budget right now.") and a `FilledButton` "Choose another plan", which opens the follow sheet.

- [ ] **Step 1: Failing widget tests** (`pumpApp`, `useTallScreen`):
  - After the first frame the reconciler has recorded `initial`: expect "Check in to track progress", the ring's semantics ("0% paid off"), and "Check in now" pushing `CheckInScreen`.
  - After `app.progress.saveCheckIn` lower than the plan: the chip says "… ahead" and the chart has a line with `squares: true`.
  - After a plan switch through the follow sheet: the tap opens the sheet, choosing Snowball asks for confirmation, and after confirming Home's trailing strategy name is "Smallest balance first" and the chart has an `original` dotted line.
  - `HomeAllCleared` after clearing the only debt through `app.progress.saveCheckIn({'a': 0})`.
  - `HomeFollowedUnavailable` with "Choose another plan".
  - Large text (phone width, `textScaleFactorTestValue = 2`): no exception.
- [ ] **Steps 2–5:** FAIL, implement, PASS; commit `feat(home): progress ring, standing, plan vs actual, check-in card, follow sheet`.

---

### Task 9: Check in and the result

**Files:**
- Create: `lib/features/progress/presentation/check_in_screen.dart`, `check_in_result_screen.dart`
- Modify: `lib/app/router.dart` (`Routes.checkIn = '/check-in'`, `Routes.checkInResult = '/check-in/result'`, both on the root navigator), `lib/l10n/app_en.arb`
- Test: `test/features/progress/check_in_screen_test.dart`

**Behaviour** (spec §4.8–4.9, canvas "Check in" and "Check-in result"):

**Check in:**
- An app bar with a close button and the title "Check in".
- A heading, `checkInHeading` ("What do you owe today?"), in `displayStyle(28)`, and the intro `checkInIntro` ("We've filled in what the plan expected. Change anything that's different.").
- One `OutlinedCard` per uncleared debt:
  - its avatar, name and "plan {amount}" (`checkInPlan`);
  - a `TextFormField` labelled "Owe today" (`checkInOweToday`), pre-filled with `expectedBalances(plan, k, debts)[id]`, where `k = monthIndex(lastCheckIn.at, now)`.
- Entering 0 shows a hi-vis chip "Paid off!" (`checkInPaidOff`). A value above the current balance shows `checkInWentUp(amount)` ("{amount} more than expected. New spending? Your plan will adjust.").
- Validation is as for the debt form's balance: 0 is allowed, and more than `kMaxAmountMinor` gives `errorTooLarge`. Use `forceErrorText`, cleared in `onChanged`.
- A "+ A new debt since last time?" link (`checkInNewDebt`) pushes `Routes.newDebt`.
- "Save check-in" (`checkInSave`) calls `ProgressController.saveCheckIn` and then `context.pushReplacement(Routes.checkInResult)`.

**Result:**
- Reads `progressControllerProvider` (the outcome) and `progressSummaryProvider`.
- The headline in `displayStyle(56)`:
  - `resultAhead(amount)` ("£110" plus "ahead of plan");
  - `resultOnTrack` ("Right on track");
  - `resultBehind(amount)`;
  - `resultAheadMonths(n)`.
- A hi-vis block with `resultDateMoved(before, after)` ("Debt-free moved from Nov 2028 to Oct 2028") when `monthsBefore` differs from the current plan's months.
- The plan vs actual chart (reuse the Home chart card widget).
- One `OutlinedCard` per `wentUp` entry: `resultWentUp(name, amount)`.
- Continue:
  - with cleared debts, "Continue: {n} debt(s) demolished" (`resultContinueCleared(n)`), which goes to `/cleared/<first id>`;
  - otherwise `resultDone` ("Done"), which goes Home.

- [ ] **Step 1: Failing tests:**
  - The pre-fill: the Current plan after 0 months equals today's balances. Then set the clock one month on by overriding `clockProvider` in `pumpApp`, and the fields hold the plan's month-1 balances.
  - Entering 0 shows "Paid off!".
  - Saving updates the repository and the result says the standing.
  - A higher balance produces the "went up" note.
  - Invalid text is refused without saving.
  - Close pops without saving.
  - Continue with a cleared debt opens the celebration route.
- [ ] **Steps 2–5:** FAIL, implement, PASS; commit `feat(progress): check in with pre-filled balances; result screen`.

---

### Task 10: Celebration

**Files:**
- Create: `lib/features/progress/presentation/celebration_screen.dart`
- Modify: `lib/app/router.dart` (`Routes.cleared(id) => '/cleared/$id'` and `Routes.debtFree = '/debt-free'`, root navigator, `fullscreenDialog: true` via `pageBuilder`), `lib/l10n/app_en.arb`
- Test: `test/features/progress/celebration_screen_test.dart`

**Behaviour** (spec §4.10, canvas "A · Debt cleared"):
- The whole screen is hi-vis with navy text and a close button.
- A static placeholder illustration (a `CustomPaint` of a navy circle and three white outlined bricks; the real painter comes in Plan 10).
- The headline `celebrationTitle(name)` ("{name} demolished."), in `displayStyle(54)`.
- `celebrationGone(amount)` ("That's {amount} gone for good.").
- A white card with:
  - `celebrationRollsOn(amount, next)` ("Its {amount} a month now goes to your {next}.") when there is a next debt;
  - a row of `totalCount` blocks with `clearedCount` filled;
  - `celebrationCount(k, n)` ("{k} of {n} debts down").
- Buttons:
  - "Share" (`celebrationShare`) calls `SharePlus.instance.share(ShareParams(text: celebrationShareText(name, amount)))`, through a small injectable `TextSharer` provider so tests can record it;
  - "Keep going" (`celebrationKeepGoing`) goes to the next cleared id in the outcome. After the last one: `Routes.debtFree` if no uncleared debts remain, else Home.
- Debt-free variant (`/debt-free`):
  - `debtFreeTitle` ("Debt free!");
  - `debtFreeBody(amount, months)` ("You knocked down {amount} in {months}."), with the amount from `paidOff` and the months from the first start to now;
  - Share, and "Done", which goes Home.

The screen reads the outcome from `progressControllerProvider`. If the outcome is null (a deep link), it pops to Home.

- [ ] **Step 1: Failing tests:**
  - Two cleared debts: "Keep going" moves from the first to the second, then Home.
  - The last debt cleared ends on "Debt free!".
  - Share records the text.
  - A deep link with no outcome goes Home.
- [ ] **Steps 2–5:** FAIL, implement, PASS; commit `feat(progress): celebration and debt-free screens`.

---

### Task 11: Restart sheet

**Files:**
- Create: `lib/features/progress/presentation/restart_sheet.dart` (`Future<void> showRestartSheet(BuildContext context)`)
- Test: `test/features/progress/restart_sheet_test.dart`

**Behaviour** (spec §6.8, canvas "Restart sheet"): a modal bottom sheet, drag handle, 16px top corners.
- The title `restartTitle` ("Restart from here") and the body `restartBody`.
- Two radio cards (`RadioGroup`/`RadioListTile`, with the selected one on hi-vis):
  - "Start fresh" (`restartFresh` / `restartFreshBody`), the default;
  - "Keep my history" (`restartKeep` / `restartKeepBody`).
- Buttons: "Cancel", and the primary button, which is labelled by the choice.
- **Start fresh** replaces the sheet's content with a confirmation: `restartConfirm` ("This clears your check-in history and progress. Your debts and plans aren't changed. This can't be undone.") and a "Clear history" button (`restartConfirmButton`), which calls `restart(clearHistory: true)`.
- **Keep my history** calls `restart(clearHistory: false)` directly.
- Restart is disabled (with `restartUnavailable` shown) when Home isn't `HomeFollowing`.

- [ ] **Step 1: Failing tests:**
  - Keep: one more start, reason `restarted`.
  - Fresh: nothing is deleted until the second confirmation; after it the history is only a new `initial`, the debts are unchanged, and `followedStrategy` is unchanged.
  - Cancel changes nothing.
- [ ] **Steps 2–5:** FAIL, implement, PASS; commit `feat(progress): restart sheet — start fresh or keep history`.

---

### Task 12: Follow from Plans and Plan detail

**Files:**
- Modify: `lib/features/strategies/presentation/strategies_screen.dart` (the Following chip), `lib/features/analysis/presentation/plan_detail_screen.dart` (the Follow button)
- Test: `test/features/strategies/strategies_screen_test.dart`, `test/features/analysis/plan_detail_test.dart`

**Behaviour:**
- **Plans:** the card for the followed strategy (`settings.followedStrategy ?? bestPayOffMethod`) shows a "Following" chip (`l10n.following`, navy fill, `c.ground` text) beside Cheapest, if any.
- **Plan detail:** in the hero, a "Follow this plan" `FilledButton` (`followThisPlan`), navy on hi-vis. It's hidden when:
  - this is already the followed strategy;
  - a saved scenario is active and this isn't the Current view;
  - the strategy is `minimumsOnly`;
  - the result isn't Feasible.

  Tapping it opens the inline confirmation sheet from Task 8 (reuse `follow_sheet.dart`'s `showFollowConfirm(context, id)`), which calls `follow(id)`. For borrowing alternatives, the confirmation repeats `alternativesNote`.

- [ ] **Step 1: Failing tests:**
  - The Following chip is on the cheapest card before any choice.
  - After following Snowball from its detail page, the chip moves to Snowball, and the history has a `planSwitched` start.
  - There's no Follow button on the followed plan, on minimums-only, or with a saved scenario selected.
- [ ] **Steps 2–5:** FAIL, implement, PASS; commit `feat(plans): follow a plan from its detail; Following chip`.

---

### Task 13: Cleared debts on Debts; Mark as paid off

**Files:**
- Modify: `lib/features/debts/presentation/debts_screen.dart`, `lib/features/debts/presentation/debt_form_screen.dart`, `lib/l10n/app_en.arb`
- Test: `test/features/debts/debts_screen_test.dart`, `test/features/debts/debt_form_test.dart`

**Behaviour:**
- **Debts:** below the list (in the `ReorderableListView` footer), a collapsible section `debtsCleared(n)` ("Cleared ({n})"), shown only when n > 0 and collapsed by default. Each row has:
  - the type avatar (greyed, `c.track` fill);
  - the name;
  - `debtClearedOn(date)`;
  - a "Reopen" `TextButton`: a bottom sheet with a balance field, which calls `ProgressController.reopen(id, balance)`;
  - a delete `IconButton`, which asks in a bottom sheet (`deleteDebtTitle`/`deleteDebtBody`, as now) and calls `debtActions.delete`.
- **Debt form:** when editing an existing debt, a `TextButton` "Mark as paid off" (`markPaidOff`) below Save. It calls `ProgressController.markPaidOff(id)`, then `context.go(Routes.cleared(id))`.

- [ ] **Step 1: Failing tests:**
  - A cleared debt is listed under "Cleared (1)" and not in the main list.
  - Reopening with 500 puts it back in the main list and records a `debtAdded` start.
  - Deleting a cleared debt removes it.
  - "Mark as paid off" opens the celebration, and the debt moves to Cleared.
- [ ] **Steps 2–5:** FAIL, implement, PASS; commit `feat(debts): cleared section with reopen; mark a debt as paid off`.

---

### Task 14: Docs and full verification

- [ ] **Step 1:** `CLAUDE.md`:
  - Tick Plan 8.
  - Gotchas:
    - cleared debts (`clearedAt`, excluded from `watchAll`/`loadAll`, `watchCleared`, `reopen`);
    - `ProgressRepository`, and `saveCheckIn` updating debts in the same transaction;
    - `progressReconcilerProvider` recording starting points (so widget tests always have one after the first frame);
    - the follow flow through `ProgressController.follow`;
    - `convertAmounts` covering progress;
    - `AppHarness.progress` in tests.
- [ ] **Step 2:** `./tool/codegen.sh && dart format lib test && dart analyze --fatal-infos && flutter test && (cd packages/payoff_engine && dart test)`. All clean and passing.
- [ ] **Step 3:** On the simulator (`flutter run --no-resident --route=...` and `xcrun simctl io booted screenshot`), check against the canvas:
  - Home (light and dark);
  - `/check-in`;
  - the result;
  - a celebration.
- [ ] **Step 4: Commit** `docs: Plan 8 progress — CLAUDE.md`.
