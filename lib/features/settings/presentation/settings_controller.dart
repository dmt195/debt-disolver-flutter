import 'package:debt_destroyer/app/dependencies.dart';
import 'package:debt_destroyer/core/currency.dart';
import 'package:debt_destroyer/features/settings/domain/app_settings.dart';
import 'package:payoff_engine/payoff_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_controller.g.dart';

/// The app's settings. Every change is validated, saved, then published.
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  /// The mutation in progress; each new one waits for it.
  Future<void> _pending = Future<void>.value();

  @override
  Future<AppSettings> build() async {
    final settings = await ref.watch(settingsRepositoryProvider).load();
    // Bring stored debts into the settings currency. This records it on
    // first run and repairs a currency switch interrupted between converting
    // the debts and saving the settings.
    await ref
        .read(debtRepositoryProvider)
        .convertAmounts(toCurrencyCode: settings.currencyCode);
    return settings;
  }

  /// Sets the monthly budget, in minor units of the current currency.
  /// Returns the problems found; nothing is saved unless it is empty.
  Future<Set<BudgetValidationError>> setMonthlyBudget(int minor) =>
      _serialised(() async {
        final current = await future;
        final budget = Money(minor, current.currencyCode);
        final errors = validateBudget(budget);
        if (errors.isEmpty) {
          await _save(current.copyWith(monthlyBudget: budget));
        }
        return errors;
      });

  Future<Set<StrategyParametersValidationError>> setStrategyParameters(
    StrategyParameters parameters,
  ) => _serialised(() async {
    final errors = validateStrategyParameters(parameters);
    if (errors.isEmpty) {
      await _save((await future).copyWith(strategyParameters: parameters));
    }
    return errors;
  });

  /// Switches currency. Amounts keep their major-unit values: when the
  /// number of decimal digits changes (e.g. GBP → JPY) the budget and every
  /// stored debt are rescaled. Throws [ArgumentError] for a malformed code.
  Future<void> setCurrency(String currencyCode) {
    if (!isCurrencyCode(currencyCode)) {
      throw ArgumentError.value(currencyCode, 'currencyCode');
    }
    return _serialised(() async {
      final current = await future;
      if (currencyCode == current.currencyCode) return;
      await ref
          .read(debtRepositoryProvider)
          .convertAmounts(toCurrencyCode: currencyCode);
      final budgetMinor = rescaleMinor(
        current.monthlyBudget.minor,
        fromDigits: currencyDecimalDigits(current.currencyCode),
        toDigits: currencyDecimalDigits(currencyCode),
      );
      await _save(
        current.copyWith(
          currencyCode: currencyCode,
          // Keep the rescaled budget valid: never zero, never over the limit.
          monthlyBudget: Money(
            budgetMinor.clamp(1, kMaxAmountMinor),
            currencyCode,
          ),
        ),
      );
    });
  }

  Future<void> completeOnboarding() => _serialised(() async {
    await _save((await future).copyWith(onboardingComplete: true));
  });

  /// Runs [operation] after every earlier mutation has finished, so each one
  /// reads the settings the previous one saved.
  Future<T> _serialised<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _save(AppSettings next) async {
    await ref.read(settingsRepositoryProvider).save(next);
    state = AsyncData(next);
  }
}
