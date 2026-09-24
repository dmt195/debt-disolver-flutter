import 'package:debt_destroyer/core/currency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognises ISO currency codes', () {
    expect(isCurrencyCode('GBP'), isTrue);
    expect(isCurrencyCode('gbp'), isFalse);
    expect(isCurrencyCode('£'), isFalse);
    expect(isCurrencyCode('EURO'), isFalse);
  });

  test('derives the currency from the locale', () {
    expect(currencyCodeForLocale('en_GB'), 'GBP');
    expect(currencyCodeForLocale('en_US'), 'USD');
    expect(currencyCodeForLocale('ja_JP'), 'JPY');
    expect(currencyCodeForLocale('de_DE'), 'EUR');
  });

  test('falls back to GBP for an unknown locale', () {
    expect(currencyCodeForLocale('xx_YY'), kFallbackCurrencyCode);
  });

  test('knows how many decimal digits a currency uses', () {
    expect(currencyDecimalDigits('GBP'), 2);
    expect(currencyDecimalDigits('JPY'), 0);
    expect(currencyDecimalDigits('KWD'), 3);
  });

  group('rescaleMinor', () {
    test('keeps the amount when digits match', () {
      expect(rescaleMinor(12345, fromDigits: 2, toDigits: 2), 12345);
    });

    test('adds digits when the new currency has more', () {
      expect(rescaleMinor(1235, fromDigits: 0, toDigits: 2), 123500);
    });

    test('drops digits with half-even rounding', () {
      expect(rescaleMinor(123456, fromDigits: 2, toDigits: 0), 1235);
      expect(rescaleMinor(250, fromDigits: 2, toDigits: 0), 2);
      expect(rescaleMinor(350, fromDigits: 2, toDigits: 0), 4);
    });
  });
}
