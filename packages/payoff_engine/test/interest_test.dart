import 'package:payoff_engine/payoff_engine.dart';
import 'package:test/test.dart';

void main() {
  group('monthlyRatePpm', () {
    test('pinned values', () {
      expect(monthlyRatePpm(0), 0);
      expect(monthlyRatePpm(1), 8);
      expect(monthlyRatePpm(600), 4868);
      expect(monthlyRatePpm(1200), 9489);
      expect(monthlyRatePpm(1268), 9998);
      expect(monthlyRatePpm(2530), 18973);
      expect(monthlyRatePpm(3000), 22104);
      expect(monthlyRatePpm(10000), 59463);
    });

    test('never falls as the APR rises', () {
      var previous = 0;
      for (var bps = 0; bps <= 10000; bps++) {
        final ppm = monthlyRatePpm(bps);
        expect(ppm, greaterThanOrEqualTo(previous), reason: '$bps');
        previous = ppm;
      }
    });

    test('rejects a negative APR', () {
      expect(() => monthlyRatePpm(-1), throwsArgumentError);
    });
  });

  group('aprBpsFromMonthlyPpm', () {
    test('1% a month is 12.68% APR', () {
      expect(aprBpsFromMonthlyPpm(10000), 1268);
      expect(aprBpsFromMonthlyPpm(0), 0);
    });

    test('round-trips every APR exactly', () {
      for (var bps = 0; bps <= 10000; bps++) {
        expect(aprBpsFromMonthlyPpm(monthlyRatePpm(bps)), bps, reason: '$bps');
      }
    });

    test('rejects a negative rate', () {
      expect(() => aprBpsFromMonthlyPpm(-1), throwsArgumentError);
    });
  });

  group('interest mode', () {
    test('compound outside any zone', () {
      expect(currentInterestMode, InterestMode.compound);
      expect(monthlyInterest()(120000, 1200), 1139);
    });

    test('nominal inside its zone, innermost wins', () {
      runWithInterestMode(InterestMode.nominal, () {
        expect(currentInterestMode, InterestMode.nominal);
        expect(monthlyInterest()(120000, 1200), 1200);
        runWithInterestMode(InterestMode.compound, () {
          expect(monthlyInterest()(120000, 1200), 1139);
        });
      });
    });

    test('rounds half-even', () {
      // 12% nominal: 1% a month. 50 × 1% = 0.5 → 0; 150 × 1% = 1.5 → 2.
      final nominal = monthlyInterest(InterestMode.nominal);
      expect(nominal(50, 1200), 0);
      expect(nominal(150, 1200), 2);
    });

    test('stays in 64-bit at the balance ceiling and 100% APR', () {
      expect(
        monthlyInterest()(kBalanceCeilingMinor, 10000),
        594630000000, // 10^13 × 59,463 / 10^6
      );
    });
  });
}
