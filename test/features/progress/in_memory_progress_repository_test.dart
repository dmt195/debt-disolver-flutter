import '../../helpers/in_memory_debt_repository.dart';
import '../../helpers/in_memory_progress_repository.dart';
import 'progress_repository_contract.dart';

void main() {
  progressRepositoryContract(() async {
    final debts = InMemoryDebtRepository();
    return (debts, InMemoryProgressRepository(debts));
  });
}
