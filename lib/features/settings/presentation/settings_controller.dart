import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_controller.g.dart';

/// The app's settings. Every change is validated, saved, then published.
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  @override
  Future<AppSettings> build() => ref.watch(settingsRepositoryProvider).load();

  /// Sets the monthly budget, in minor units of the current currency.
  /// Returns the problems found; nothing is saved unless it is empty.
  Future<Set<BudgetValidationError>> setMonthlyBudget(int minor) async {
    final current = await future;
    final budget = Money(minor, current.currencyCode);
    final errors = validateBudget(budget);
    if (errors.isEmpty) await _save(current.copyWith(monthlyBudget: budget));
    return errors;
  }

  Future<Set<StrategyParametersValidationError>> setStrategyParameters(
    StrategyParameters parameters,
  ) async {
    final errors = validateStrategyParameters(parameters);
    if (errors.isEmpty) {
      await _save((await future).copyWith(strategyParameters: parameters));
    }
    return errors;
  }

  /// Switches currency. Amounts keep their major-unit values: when the
  /// number of decimal digits changes (e.g. GBP → JPY) the budget and every
  /// stored debt are rescaled. Throws [ArgumentError] for a malformed code.
  Future<void> setCurrency(String currencyCode) async {
    if (!isCurrencyCode(currencyCode)) {
      throw ArgumentError.value(currencyCode, 'currencyCode');
    }
    final current = await future;
    if (currencyCode == current.currencyCode) return;
    final fromDigits = currencyDecimalDigits(current.currencyCode);
    final toDigits = currencyDecimalDigits(currencyCode);
    if (fromDigits != toDigits) {
      await ref
          .read(debtRepositoryProvider)
          .rescaleAmounts(fromDigits: fromDigits, toDigits: toDigits);
    }
    final budgetMinor = rescaleMinor(
      current.monthlyBudget.minor,
      fromDigits: fromDigits,
      toDigits: toDigits,
    );
    await _save(
      current.copyWith(
        currencyCode: currencyCode,
        // Never let rounding push a valid budget to zero.
        monthlyBudget: Money(budgetMinor < 1 ? 1 : budgetMinor, currencyCode),
      ),
    );
  }

  Future<void> completeOnboarding() async {
    await _save((await future).copyWith(onboardingComplete: true));
  }

  Future<void> _save(AppSettings next) async {
    await ref.read(settingsRepositoryProvider).save(next);
    state = AsyncData(next);
  }
}
