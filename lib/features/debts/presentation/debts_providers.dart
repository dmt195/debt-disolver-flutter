import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/app/diagnostic_events.dart';
import 'package:debt_destroyer/core/diagnostics.dart';
import 'package:debt_destroyer/features/debts/domain/cleared_debt.dart';
import 'package:debt_destroyer/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'debts_providers.freezed.dart';
part 'debts_providers.g.dart';

/// The user's debts, in their order, labelled with the current currency.
/// Re-subscribes to the database only when the currency changes (not on
/// every settings change), and stays loading until settings have loaded.
@Riverpod(keepAlive: true)
Stream<List<Debt>> debts(Ref ref) {
  final (currencyCode, error) = ref.watch(
    settingsControllerProvider.select((s) => (s.value?.currencyCode, s.error)),
  );
  if (error != null) return Stream.error(error);
  if (currencyCode == null) return const Stream.empty();
  return ref.watch(debtRepositoryProvider).watchAll(currencyCode);
}

/// Debts paid off, most recently cleared first (spec §6.6).
@Riverpod(keepAlive: true)
Stream<List<ClearedDebt>> clearedDebts(Ref ref) {
  final loaded = ref.watch(
    settingsControllerProvider.select((s) => s.hasValue),
  );
  if (!loaded) return const Stream.empty();
  return ref.watch(debtRepositoryProvider).watchCleared();
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

  /// The change in progress; each new one waits for it, so a check (such
  /// as the debt count) and its write can't interleave with another.
  Future<void> _pending = Future<void>.value();

  @override
  void build() {}

  /// Adds [draft] with a new id (the draft's id is ignored).
  Future<DebtSaveOutcome> add(Debt draft) => _serialised(() async {
    final debt = draft.copyWith(id: _uuid.v4());
    final existing = await _stored();
    final outcome = _validate(debt, [...existing, debt]);
    if (outcome is DebtSaved) {
      await ref.read(debtRepositoryProvider).add(debt);
      ref
          .read(diagnosticsProvider)
          .logEvent(DiagnosticEvent.debtAdded(debt.type));
    }
    return outcome;
  });

  Future<DebtSaveOutcome> update(Debt debt) => _serialised(() async {
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
  });

  Future<void> delete(String id) =>
      _serialised(() => ref.read(debtRepositoryProvider).delete(id));

  Future<void> reorder(List<String> idsInOrder) =>
      _serialised(() => ref.read(debtRepositoryProvider).reorder(idsInOrder));

  Future<T> _serialised<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

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
