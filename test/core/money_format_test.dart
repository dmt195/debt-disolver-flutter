import 'package:debt_destroyer/core/money_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payoff_engine/payoff_engine.dart';

void main() {
  group('formatMoney', () {
    test('uses the locale and the currency symbol', () {
      expect(formatMoney(const Money(123456, 'GBP'), 'en_GB'), '£1,234.56');
      expect(formatMoney(const Money(123456, 'USD'), 'en_US'), r'$1,234.56');
      expect(formatMoney(const Money(1235, 'JPY'), 'en_GB'), '¥1,235');
      expect(
        formatMoney(const Money(123456, 'EUR'), 'de_DE'),
        contains('1.234,56'),
      );
    });

    test('shows whole amounts without dropping pence', () {
      expect(formatMoney(const Money(30000, 'GBP'), 'en_GB'), '£300.00');
      expect(formatMoney(const Money(5, 'GBP'), 'en_GB'), '£0.05');
    });
  });

  group('formatAmountInput', () {
    test('writes a plain number in the locale, no symbol or grouping', () {
      expect(formatAmountInput(const Money(123456, 'GBP'), 'en_GB'), '1234.56');
      expect(formatAmountInput(const Money(123456, 'EUR'), 'de_DE'), '1234,56');
      expect(formatAmountInput(const Money(1235, 'JPY'), 'en_GB'), '1235');
      expect(formatAmountInput(const Money(30000, 'GBP'), 'en_GB'), '300');
    });
  });

  group('parseAmountMinor', () {
    int? gb(String s) =>
        parseAmountMinor(s, currencyCode: 'GBP', locale: 'en_GB');

    test('parses whole and decimal amounts exactly', () {
      expect(gb('1234.56'), 123456);
      expect(gb('1,234.56'), 123456);
      expect(gb(' 300 '), 30000);
      expect(gb('0.5'), 50);
      expect(gb('.75'), 75);
    });

    test('rejects more decimals than the currency has', () {
      expect(gb('1.234'), isNull);
      expect(
        parseAmountMinor('10.5', currencyCode: 'JPY', locale: 'en_GB'),
        isNull,
      );
    });

    test('rejects text, signs, empty input and several decimal points', () {
      for (final bad in ['', ' ', 'abc', '-5', '+5', '1.2.3', '£5', '1e3']) {
        expect(gb(bad), isNull, reason: bad);
      }
    });

    test('follows the locale decimal separator', () {
      expect(
        parseAmountMinor('1.234,56', currencyCode: 'EUR', locale: 'de_DE'),
        123456,
      );
      expect(
        parseAmountMinor('1 234,56', currencyCode: 'EUR', locale: 'fr_FR'),
        123456,
      );
      expect(
        parseAmountMinor('1234 56', currencyCode: 'EUR', locale: 'fr_FR'),
        123456 * 100,
      );
    });

    test('rejects absurdly long numbers instead of overflowing', () {
      expect(gb('9' * 30), isNull);
    });
  });

  group('percent', () {
    test('formats basis points with up to two decimals', () {
      expect(formatPercent(1990, 'en_GB'), '19.9%');
      expect(formatPercent(400, 'en_GB'), '4%');
      expect(formatPercent(1234, 'en_GB'), '12.34%');
      expect(formatPercent(1990, 'de_DE'), '19,9\u00a0%');
    });

    test('formats input without the percent sign', () {
      expect(formatPercentInput(1990, 'en_GB'), '19.9');
      expect(formatPercentInput(0, 'en_GB'), '0');
    });

    test('parses percentages to basis points exactly', () {
      expect(parsePercentBps('19.9', 'en_GB'), 1990);
      expect(parsePercentBps('4', 'en_GB'), 400);
      expect(parsePercentBps('12.34', 'en_GB'), 1234);
      expect(parsePercentBps('19,9', 'de_DE'), 1990);
      expect(parsePercentBps('12.345', 'en_GB'), isNull);
      expect(parsePercentBps('x', 'en_GB'), isNull);
    });
  });

  test('parseWholeNumber accepts digits only', () {
    expect(parseWholeNumber('12'), 12);
    expect(parseWholeNumber(' 0 '), 0);
    expect(parseWholeNumber('1.5'), isNull);
    expect(parseWholeNumber('-1'), isNull);
    expect(parseWholeNumber(''), isNull);
  });
}
