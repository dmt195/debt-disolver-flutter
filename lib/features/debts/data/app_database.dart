import 'package:debt_destroyer/features/debts/data/app_database.steps.dart';
import 'package:debt_destroyer/features/progress/domain/progress.dart';
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

  /// Promotional rate, if any; null when there is none.
  IntColumn get promoAprBps => integer().nullable()();

  /// Last month of the promotion as `yyyymm` (see promo_dates.dart).
  IntColumn get promoEndsYearMonth => integer().nullable()();

  /// Balance-transfer offer on this card (see TransferOffer); all null when
  /// there is none. The promo columns are both null or both set.
  IntColumn get offerFeeBps => integer().nullable()();
  IntColumn get offerPromoAprBps => integer().nullable()();
  IntColumn get offerPromoMonths => integer().nullable()();
  IntColumn get offerAvailableCreditMinor => integer().nullable()();

  /// Position in the user's own list order (0 first).
  IntColumn get sortIndex => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// When the balance reached 0 through a check-in or "Mark as paid off";
  /// null while the debt is being paid (spec §6.6).
  DateTimeColumn get clearedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Small key-value facts about the stored data.
@DataClassName('AppMetaRow')
class AppMeta extends Table {
  @override
  String get tableName => 'app_meta';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

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

/// One debt's balance in a check-in. Kept when the debt is deleted, so a
/// deletion can be noticed and named.
@DataClassName('CheckInBalanceRow')
class CheckInBalanceRows extends Table {
  @override
  String get tableName => 'check_in_balances';

  TextColumn get checkInId => text()();
  TextColumn get debtId => text()();

  /// The debt's name at the time.
  TextColumn get debtName => text()();
  IntColumn get balanceMinor => integer()();

  @override
  Set<Column<Object>> get primaryKey => {checkInId, debtId};
}

/// Where progress is measured from (spec §6.3).
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

@DriftDatabase(
  tables: [
    DebtRows,
    AppMeta,
    ScenarioRows,
    CheckInRows,
    CheckInBalanceRows,
    StartingPointRows,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// The on-device database file.
  factory AppDatabase.open() =>
      AppDatabase(driftDatabase(name: 'debt_destroyer'));

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.addColumn(schema.debts, schema.debts.promoAprBps);
        await m.addColumn(schema.debts, schema.debts.promoEndsYearMonth);
        await m.createTable(schema.scenarios);
      },
      from2To3: (m, schema) async {
        await m.addColumn(schema.debts, schema.debts.offerFeeBps);
        await m.addColumn(schema.debts, schema.debts.offerPromoAprBps);
        await m.addColumn(schema.debts, schema.debts.offerPromoMonths);
        await m.addColumn(schema.debts, schema.debts.offerAvailableCreditMinor);
      },
      from3To4: (m, schema) async {
        await m.addColumn(schema.debts, schema.debts.clearedAt);
        await m.createTable(schema.checkIns);
        await m.createTable(schema.checkInBalances);
        await m.createTable(schema.startingPoints);
      },
    ),
  );
}
