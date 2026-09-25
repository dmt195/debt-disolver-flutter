/// Pay day 0 means the last day of each month.
const kLastDay = 0;

/// Reminders go out at nine in the morning, local time.
const _hour = 9;

DateTime _onDay(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day;
  final d = day == kLastDay || day > last ? last : day;
  return DateTime(year, month, d, _hour);
}

/// The next [count] pay days at 09:00 from [now]: this month's if it is
/// still to come, then one a month. [day] is 1–28, or [kLastDay].
List<DateTime> nextPayDays(DateTime now, int day, {int count = 3}) {
  var first = _onDay(now.year, now.month, day);
  if (!first.isAfter(now)) first = _onDay(now.year, now.month + 1, day);
  return [
    for (var i = 0; i < count; i++) _onDay(first.year, first.month + i, day),
  ];
}

/// The check-in nudge: [months] after [lastCheckIn], at 09:00. Null when
/// off (0), with no check-in yet, or when that moment has passed.
DateTime? nudgeAt(DateTime? lastCheckIn, int months, DateTime now) {
  if (months <= 0 || lastCheckIn == null) return null;
  final at = _onDay(
    lastCheckIn.year,
    lastCheckIn.month + months,
    lastCheckIn.day,
  );
  return at.isAfter(now) ? at : null;
}
