import 'package:intl/intl.dart';

/// Currencies offered in the pickers; the current one is always added.
const List<String> kCurrencyCodes = [
  'GBP', 'EUR', 'USD', 'CAD', 'AUD', 'NZD', 'CHF', 'SEK', 'NOK', 'DKK', //
  'PLN', 'CZK', 'HUF', 'JPY', 'CNY', 'INR', 'SGD', 'HKD', 'ZAR', 'BRL', //
  'MXN',
];

/// [kCurrencyCodes] plus [current] if it isn't already listed.
List<String> currencyChoices(String current) => [
  if (!kCurrencyCodes.contains(current)) current,
  ...kCurrencyCodes,
];

/// e.g. `GBP (£)`.
String currencyLabel(String code, String locale) {
  final symbol = NumberFormat.simpleCurrency(
    locale: locale,
    name: code,
  ).currencySymbol;
  return symbol == code ? code : '$code ($symbol)';
}
