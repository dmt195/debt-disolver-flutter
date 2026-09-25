import 'package:debt_destroyer/features/debts/data/app_database.dart';
import 'package:debt_destroyer/features/debts/data/drift_debt_repository.dart';
import 'package:debt_destroyer/features/progress/data/drift_progress_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'progress_repository_contract.dart';

void main() {
  progressRepositoryContract(() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return (
      DriftDebtRepository(db, now: () => DateTime(2026, 9, 24)),
      DriftProgressRepository(db),
    );
  });
}
