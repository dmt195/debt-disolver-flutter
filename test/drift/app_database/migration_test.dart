import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;

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
    final created = DateTime(2026, 9).millisecondsSinceEpoch ~/ 1000;
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
            allowsOverpayment: 1,
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

  test(
    'v3 debts survive the upgrade to v4, uncleared, with no history',
    () async {
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
              createdAt: 1790000000,
              updatedAt: 1790000000,
            ),
          );
        },
        validateItems: (newDb) async {
          final row = await newDb.select(newDb.debts).getSingle();
          expect(row.balanceMinor, 123456);
          expect(row.clearedAt, isNull);
          expect(await newDb.select(newDb.checkIns).get(), isEmpty);
          expect(await newDb.select(newDb.checkInBalances).get(), isEmpty);
          expect(await newDb.select(newDb.startingPoints).get(), isEmpty);
        },
      );
    },
  );
}
