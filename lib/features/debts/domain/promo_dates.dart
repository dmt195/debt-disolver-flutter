/// Promotions are stored by their last calendar month (`yyyymm`) and handed
/// to the engine as "months left, counting this one", so a stored promo
/// shortens by itself as time passes.
library;

/// [date]'s calendar month as `yyyymm`, e.g. September 2026 → 202609.
int yearMonthOf(DateTime date) => date.year * 100 + date.month;

/// Months from [now]'s month to [endYearMonth], counting both: a promo that
/// ends this month has 1 month left. Zero or less means it has ended.
int promoMonthsLeft(int endYearMonth, DateTime now) =>
    _index(endYearMonth) - _index(yearMonthOf(now)) + 1;

/// The last month of a promo with [months] left, counting from [now].
int promoEndYearMonth(int months, DateTime now) {
  final index = _index(yearMonthOf(now)) + months - 1;
  return (index ~/ 12) * 100 + index % 12 + 1;
}

/// Months since year 0, so months can be subtracted.
int _index(int yearMonth) => (yearMonth ~/ 100) * 12 + yearMonth % 100 - 1;
