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
