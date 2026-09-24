import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'debts_providers.freezed.dart';
part 'debts_providers.g.dart';

/// The user's debts, in their order, in the current currency. Rebuilds when
/// settings change so amounts are always labelled with the current currency.
@Riverpod(keepAlive: true)
Stream<List<Debt>> debts(Ref ref) async* {
  final settings = await ref.watch(settingsControllerProvider.future);
  yield* ref.watch(debtRepositoryProvider).watchAll(settings.currencyCode);
}

@freezed
sealed class DebtSaveOutcome with _$DebtSaveOutcome {
  const factory DebtSaveOutcome.saved(Debt debt) = DebtSaved;

  const factory DebtSaveOutcome.rejected({
    @Default(<DebtValidationError>{}) Set<DebtValidationError> errors,
    @Default(<DebtListValidationError>{})
    Set<DebtListValidationError> listErrors,
  }) = DebtRejected;
}

/// Validated changes to the debt list. Screens call these; nothing invalid
/// reaches the database.
@Riverpod(keepAlive: true)
class DebtActions extends _$DebtActions {
  static const _uuid = Uuid();

  @override
  void build() {}

  /// Adds [draft] with a new id (the draft's id is ignored).
  Future<DebtSaveOutcome> add(Debt draft) async {
    final debt = draft.copyWith(id: _uuid.v4());
    final existing = await _stored();
    final outcome = _validate(debt, [...existing, debt]);
    if (outcome is DebtSaved) await ref.read(debtRepositoryProvider).add(debt);
    return outcome;
  }

  Future<DebtSaveOutcome> update(Debt debt) async {
    final existing = await _stored();
    final list = [
      for (final d in existing)
        if (d.id == debt.id) debt else d,
    ];
    final outcome = _validate(debt, list);
    if (outcome is DebtSaved) {
      await ref.read(debtRepositoryProvider).update(debt);
    }
    return outcome;
  }

  Future<void> delete(String id) => ref.read(debtRepositoryProvider).delete(id);

  Future<void> reorder(List<String> idsInOrder) =>
      ref.read(debtRepositoryProvider).reorder(idsInOrder);

  // Read from the database, not debtsProvider: the stream may not have
  // caught up with a write made a moment ago.
  Future<List<Debt>> _stored() async {
    final settings = await ref.read(settingsControllerProvider.future);
    return await ref
        .read(debtRepositoryProvider)
        .loadAll(settings.currencyCode);
  }

  DebtSaveOutcome _validate(Debt debt, List<Debt> resultingList) {
    final errors = validateDebt(debt);
    final listErrors = validateDebtList(resultingList);
    return errors.isEmpty && listErrors.isEmpty
        ? DebtSaveOutcome.saved(debt)
        : DebtSaveOutcome.rejected(errors: errors, listErrors: listErrors);
  }
}
