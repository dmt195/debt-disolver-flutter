import 'package:debt_destroyer/features/reminders/domain/reminder_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('next pay days', () {
    test('this month when the day is still to come', () {
      expect(nextPayDays(DateTime(2026, 9, 24), 28), [
        DateTime(2026, 9, 28, 9),
        DateTime(2026, 10, 28, 9),
        DateTime(2026, 11, 28, 9),
      ]);
    });

    test("next month once today's reminder time has passed", () {
      expect(
        nextPayDays(DateTime(2026, 9, 28, 10), 28).first,
        DateTime(2026, 10, 28, 9),
      );
      expect(
        nextPayDays(DateTime(2026, 9, 28, 8), 28).first,
        DateTime(2026, 9, 28, 9),
      );
    });

    test('the last day of each month, leap years included', () {
      expect(nextPayDays(DateTime(2028, 2, 2), kLastDay), [
        DateTime(2028, 2, 29, 9),
        DateTime(2028, 3, 31, 9),
        DateTime(2028, 4, 30, 9),
      ]);
      expect(
        nextPayDays(DateTime(2027, 2, 2), kLastDay).first,
        DateTime(2027, 2, 28, 9),
      );
    });

    test('across the year end', () {
      expect(
        nextPayDays(DateTime(2026, 12, 31), 1).first,
        DateTime(2027, 1, 1, 9),
      );
    });
  });

  group('check-in nudge', () {
    test('months after the last check-in, at nine', () {
      expect(
        nudgeAt(DateTime(2026, 9, 3, 18), 2, DateTime(2026, 9, 24)),
        DateTime(2026, 11, 3, 9),
      );
    });

    test('a day the month lacks becomes its last day', () {
      expect(
        nudgeAt(DateTime(2027, 1, 31), 1, DateTime(2027, 2)),
        DateTime(2027, 2, 28, 9),
      );
    });

    test('off, never checked in, or already past', () {
      expect(nudgeAt(DateTime(2026, 9, 3), 0, DateTime(2026, 9, 24)), isNull);
      expect(nudgeAt(null, 2, DateTime(2026, 9, 24)), isNull);
      expect(nudgeAt(DateTime(2026, 1, 3), 2, DateTime(2026, 9, 24)), isNull);
    });
  });
}
