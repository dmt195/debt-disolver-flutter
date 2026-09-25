import 'package:debt_destroyer/core/currency.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:payoff_engine/payoff_engine.dart';

part 'app_settings.freezed.dart';

/// Default monthly budget in major units (legacy Settings-screen value).
const int kDefaultMonthlyBudgetMajor = 300;

@freezed
abstract class AppSettings with _$AppSettings {
  const factory AppSettings({
    required String currencyCode,
    required Money monthlyBudget,
    required StrategyParameters strategyParameters,
    required bool onboardingComplete,

    /// The plan the user follows; null until the first starting point picks
    /// the cheapest (spec §6.2).
    StrategyId? followedStrategy,

    /// A monthly reminder of what to pay (spec §7).
    @Default(false) bool payDayReminder,

    /// Its day of the month: 1–28, or 0 for the last day.
    @Default(28) int payDay,

    /// Months after the last check-in to nudge; 0 is off.
    @Default(2) int checkInNudgeMonths,
  }) = _AppSettings;

  factory AppSettings.defaults(String currencyCode) => AppSettings(
    currencyCode: currencyCode,
    monthlyBudget: Money(
      rescaleMinor(
        kDefaultMonthlyBudgetMajor,
        fromDigits: 0,
        toDigits: currencyDecimalDigits(currencyCode),
      ),
      currencyCode,
    ),
    strategyParameters: const StrategyParameters(),
    onboardingComplete: false,
  );
}
