import 'package:debt_destroyer/features/debts/domain/promo_dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sep2026 = DateTime(2026, 9, 24);

  test('a calendar month as yyyymm', () {
    expect(yearMonthOf(sep2026), 202609);
  });

  test('months left counts this month and the last one', () {
    expect(promoMonthsLeft(202609, sep2026), 1);
    expect(promoMonthsLeft(202703, sep2026), 7);
    expect(promoMonthsLeft(202608, sep2026), 0); // ended last month
  });

  test('the end month for a number of months left', () {
    expect(promoEndYearMonth(1, sep2026), 202609);
    expect(promoEndYearMonth(4, sep2026), 202612);
    expect(promoEndYearMonth(5, sep2026), 202701);
    expect(promoEndYearMonth(7, sep2026), 202703);
  });

  test('the two conversions round-trip', () {
    for (var months = 1; months <= 120; months++) {
      expect(
        promoMonthsLeft(promoEndYearMonth(months, sep2026), sep2026),
        months,
      );
    }
  });

  test('months until a calendar month', () {
    expect(monthsUntil(202609, sep2026), 0);
    expect(monthsUntil(202610, sep2026), 1);
    expect(monthsUntil(202909, sep2026), 36);
    expect(monthsUntil(202608, sep2026), -1);
  });

  test('the calendar month a number of months on', () {
    expect(yearMonthAfter(4, sep2026), 202701);
    expect(yearMonthAfter(12, sep2026), 202709);
    expect(yearMonthAfter(27, sep2026), 202812);
    expect(monthsUntil(yearMonthAfter(1200, sep2026), sep2026), 1200);
  });
}
