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
/// Accepts the locale's grouping and decimal separators. Returns null for
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

/// Parses a percentage with up to two decimals into basis points.
int? parsePercentBps(String text, String locale) =>
    _parseScaled(text, maxFractionDigits: 2, locale: locale);

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

/// Characters accepted as digit grouping, whatever the locale uses.
const _groupingChars = {',', '.', ' ', ' ', ' ', "'"};

int? _parseScaled(
  String text, {
  required int maxFractionDigits,
  required String locale,
}) {
  final symbols = NumberFormat.decimalPattern(locale).symbols;
  final decimalSep = symbols.DECIMAL_SEP;
  final grouping = {..._groupingChars, symbols.GROUP_SEP}..remove(decimalSep);

  final trimmed = text.trim();
  final buffer = StringBuffer();
  for (final char in trimmed.split('')) {
    if (grouping.contains(char)) continue;
    buffer.write(char);
  }
  final parts = buffer.toString().split(decimalSep);
  if (parts.length > 2) return null;
  final whole = parts[0];
  final fraction = parts.length == 2 ? parts[1] : '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  final digitsOnly = RegExp(r'^\d*$');
  if (!digitsOnly.hasMatch(whole) || !digitsOnly.hasMatch(fraction)) {
    return null;
  }
  if (fraction.length > maxFractionDigits) return null;
  // Long enough to be nonsense; also keeps the result inside 64 bits.
  if (whole.length + maxFractionDigits > 15) return null;
  final padded = fraction.padRight(maxFractionDigits, '0');
  return int.parse('${whole.isEmpty ? '0' : whole}$padded');
}
