import 'package:intl/intl.dart';
import 'package:payoff_engine/payoff_engine.dart';

/// Currency used when the device locale has no recognisable currency.
const String kFallbackCurrencyCode = 'GBP';

final RegExp _currencyCode = RegExp(r'^[A-Z]{3}$');

/// Whether [code] looks like an ISO 4217 code (three capital letters).
bool isCurrencyCode(String code) => _currencyCode.hasMatch(code);

/// The ISO 4217 currency of [locale] (e.g. `en_GB` → `GBP`), or
/// [kFallbackCurrencyCode] if the locale isn't recognised.
String currencyCodeForLocale(String locale) {
  final verified = Intl.verifiedLocale(
    locale,
    NumberFormat.localeExists,
    onFailure: (_) => null,
  );
  if (verified == null) return kFallbackCurrencyCode;
  final code = NumberFormat.simpleCurrency(locale: verified).currencyName;
  return code != null && isCurrencyCode(code) ? code : kFallbackCurrencyCode;
}

/// Number of minor-unit digits for [currencyCode] (GBP 2, JPY 0).
int currencyDecimalDigits(String currencyCode) =>
    NumberFormat.currency(name: currencyCode).decimalDigits ?? 2;

/// Converts a non-negative [minor] amount between currencies with different
/// numbers of decimal digits, keeping the same major-unit value. Rounds half
/// to even when digits are dropped.
int rescaleMinor(int minor, {required int fromDigits, required int toDigits}) {
  if (toDigits >= fromDigits) return minor * _pow10(toDigits - fromDigits);
  return divideHalfEven(minor, _pow10(fromDigits - toDigits));
}

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
