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

@DriftDatabase(tables: [DebtRows, AppMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// The on-device database file.
  factory AppDatabase.open() =>
      AppDatabase(driftDatabase(name: 'debt_destroyer'));

  @override
  int get schemaVersion => 1;
}
