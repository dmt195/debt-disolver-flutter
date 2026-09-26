import 'package:debt_destroyer/core/currency.dart';
import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// [money] for display, e.g. `£1,234.56` in `en_GB`.
String formatMoney(Money money, String locale) {
  final format = NumberFormat.simpleCurrency(
    locale: locale,
    name: money.currency,
  );
  return format.format(_toMajor(money.minor, format.decimalDigits ?? 2));
}

/// [money] as a plain number for an input field: the locale's decimal
/// separator, no symbol or grouping, and no trailing zero decimals.
String formatAmountInput(Money money, String locale) => _plainNumber(
  money.minor,
  digits: currencyDecimalDigits(money.currency),
  locale: locale,
);

/// Parses what a user typed as an amount of [currencyCode], in minor units.
/// See [_parseScaled] for the separators accepted. Returns null for
/// anything else, including more decimals than the currency has.
int? parseAmountMinor(
  String text, {
  required String currencyCode,
  required String locale,
}) => _parseScaled(
  text,
  maxFractionDigits: currencyDecimalDigits(currencyCode),
  locale: locale,
);

/// [bps] as a percentage for display, e.g. 1990 → `19.9%`.
String formatPercent(int bps, String locale) => (NumberFormat.percentPattern(
  locale,
)..maximumFractionDigits = 2).format(bps / 10000);

/// [bps] as a plain number for an input field, e.g. 1990 → `19.9`.
String formatPercentInput(int bps, String locale) =>
    _plainNumber(bps, digits: 2, locale: locale);

/// Parses a percentage with up to two decimals into basis points. Either
/// '.' or ',' may be the decimal point; grouping is never accepted.
int? parsePercentBps(String text, String locale) => _parseScaled(
  text,
  maxFractionDigits: 2,
  locale: locale,
  allowGrouping: false,
);

/// A monthly rate in parts per million as a plain number for an input
/// field, with up to three decimals: 18973 → `1.897`.
String formatMonthlyRateInput(int ppm, String locale) =>
    _plainNumber(divideHalfEven(ppm, 10), digits: 3, locale: locale);

/// A monthly rate in parts per million as a percentage for display:
/// 18973 → `1.897%`.
String formatMonthlyRate(int ppm, String locale) =>
    (NumberFormat.percentPattern(
      locale,
    )..maximumFractionDigits = 3).format(divideHalfEven(ppm, 10) / 100000);

/// Parses a monthly rate with up to three decimals into parts per million.
/// Either '.' or ',' may be the decimal point; grouping is never accepted.
int? parseMonthlyRatePpm(String text, String locale) {
  final thousandths = _parseScaled(
    text,
    maxFractionDigits: 3,
    locale: locale,
    allowGrouping: false,
  );
  return thousandths == null ? null : thousandths * 10;
}

/// Parses a non-negative whole number.
int? parseWholeNumber(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.length > 9) return null;
  if (!RegExp(r'^\d+$').hasMatch(trimmed)) return null;
  return int.parse(trimmed);
}

double _toMajor(int minor, int digits) {
  var divisor = 1;
  for (var i = 0; i < digits; i++) {
    divisor *= 10;
  }
  return minor / divisor;
}

String _plainNumber(int scaled, {required int digits, required String locale}) {
  final format = NumberFormat.decimalPattern(locale)
    ..minimumFractionDigits = 0
    ..maximumFractionDigits = digits
    ..turnOffGrouping();
  return format.format(_toMajor(scaled, digits));
}

/// Characters people use to group digits, besides '.' and ','.
const _spaceLikeGrouping = {' ', ' ', ' ', "'", '’'};

final _digits = RegExp(r'^\d*$');
final _threeDigits = RegExp(r'^\d{3}$');

/// Parses [text] as a non-negative number with at most [maxFractionDigits]
/// decimals, returned scaled by 10^[maxFractionDigits].
///
/// The locale's decimal separator is the decimal point. If it's absent, a
/// single '.' or ',' not followed by exactly three digits is taken as the
/// decimal point instead, because many keypads only offer '.'. Grouping
/// (when [allowGrouping]) must come in groups of exactly three digits, so
/// ambiguous input such as `1,23,4` is refused rather than guessed.
int? _parseScaled(
  String text, {
  required int maxFractionDigits,
  required String locale,
  bool allowGrouping = true,
}) {
  final symbols = NumberFormat.decimalPattern(locale).symbols;
  final decimal = symbols.DECIMAL_SEP;
  final other = decimal == '.' ? ',' : '.';
  final s = text.trim();
  if (s.isEmpty || s.length > 40) return null;

  String? point;
  if (s.contains(decimal)) {
    point = decimal;
  } else if (other.allMatches(s).length == 1) {
    final after = s.substring(s.indexOf(other) + 1);
    if (!allowGrouping || !_threeDigits.hasMatch(after)) point = other;
  }

  var whole = s;
  var fraction = '';
  if (point != null) {
    final parts = s.split(point);
    if (parts.length != 2) return null;
    (whole, fraction) = (parts[0], parts[1]);
  }
  if (!_digits.hasMatch(fraction) || fraction.length > maxFractionDigits) {
    return null;
  }

  final grouping = {..._spaceLikeGrouping, symbols.GROUP_SEP, '.', ','}
    ..remove(point);
  final groups = whole.split(RegExp('[${grouping.map(RegExp.escape).join()}]'));
  if (groups.length > 1) {
    if (!allowGrouping) return null;
    final first = groups.first;
    if (first.isEmpty || first.length > 3 || !_digits.hasMatch(first)) {
      return null;
    }
    if (!groups.skip(1).every(_threeDigits.hasMatch)) return null;
  } else if (!_digits.hasMatch(whole)) {
    return null;
  }
  final wholeDigits = groups.join();
  if (wholeDigits.isEmpty && fraction.isEmpty) return null;
  // Long enough to be nonsense; also keeps the result inside 64 bits.
  if (wholeDigits.length + maxFractionDigits > 15) return null;
  final padded = fraction.padRight(maxFractionDigits, '0');
  return int.parse('${wholeDigits.isEmpty ? '0' : wholeDigits}$padded');
}
