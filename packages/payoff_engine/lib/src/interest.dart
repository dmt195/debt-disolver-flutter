import 'dart:async';

import 'package:payoff_engine/src/rounding.dart';

/// How a debt's APR becomes a monthly charge.
enum InterestMode {
  /// The APR is the true, compounded UK APR: each month charges
  /// (1 + APR)^(1/12) − 1 (spec §2.1). The engine's default.
  compound,

  /// APR ÷ 12, as the 2013 app did. Only for tests that check the legacy
  /// app's own figures.
  nominal,
}

const _modeKey = #payoffEngineInterestMode;

/// Runs [body] with interest charged the [mode] way.
R runWithInterestMode<R>(InterestMode mode, R Function() body) =>
    runZoned(body, zoneValues: {_modeKey: mode});

/// The mode for the code running now: compound unless inside
/// [runWithInterestMode].
InterestMode get currentInterestMode =>
    Zone.current[_modeKey] as InterestMode? ?? InterestMode.compound;

final _million = BigInt.from(1000000);
final _bps = BigInt.from(10000);
final BigInt _tenTo72 = BigInt.from(10).pow(72);
final _ppmByApr = <int, int>{};

/// (1 + ppm/10⁶)¹², scaled by 10⁷⁶ (10⁷² for the power, 10⁴ for basis
/// points).
BigInt _yearFactor(int ppm) => (_million + BigInt.from(ppm)).pow(12) * _bps;

/// The monthly rate, in parts per million, that compounds to [aprBps] over
/// twelve months: the whole number whose twelfth power is closest (ties go
/// to the lower rate). Exact integer arithmetic; memoised.
int monthlyRatePpm(int aprBps) {
  if (aprBps < 0) {
    throw ArgumentError.value(aprBps, 'aprBps', 'must be >= 0');
  }
  return _ppmByApr[aprBps] ??= _solvePpm(aprBps);
}

int _solvePpm(int aprBps) {
  final target = BigInt.from(10000 + aprBps) * _tenTo72;
  // 100% a month (1,000,000 ppm) compounds to 409,500% APR: far beyond
  // anything valid.
  var low = 0;
  var high = 1000000;
  while (low < high) {
    final mid = low + (high - low) ~/ 2;
    if (_yearFactor(mid) >= target) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  if (low > 0 && target - _yearFactor(low - 1) <= _yearFactor(low) - target) {
    return low - 1;
  }
  return low;
}

/// The APR, in basis points (half-even), that a monthly rate of [ppm]
/// compounds to.
int aprBpsFromMonthlyPpm(int ppm) {
  if (ppm < 0) throw ArgumentError.value(ppm, 'ppm', 'must be >= 0');
  final numerator = _yearFactor(ppm) - _bps * _tenTo72;
  final quotient = numerator ~/ _tenTo72;
  final twice = (numerator % _tenTo72) * BigInt.two;
  final roundUp = twice > _tenTo72 || (twice == _tenTo72 && quotient.isOdd);
  return (roundUp ? quotient + BigInt.one : quotient).toInt();
}

/// One month's interest on a balance at an APR, in minor units.
typedef MonthlyInterest = int Function(int balanceMinor, int aprBps);

/// The monthly interest for [mode] (the current mode when null). Read it
/// once per calculation, not per month: looking up the zone isn't free.
MonthlyInterest monthlyInterest([InterestMode? mode]) =>
    switch (mode ?? currentInterestMode) {
      InterestMode.compound => (balance, apr) => divideHalfEven(
        balance * monthlyRatePpm(apr),
        1000000,
      ),
      InterestMode.nominal => (balance, apr) => divideHalfEven(
        balance * apr,
        120000,
      ),
    };
