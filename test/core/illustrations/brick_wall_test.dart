import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/illustrations/brick_wall.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('knockedOut', () {
    test('none at 0%, all at 100%', () {
      expect(knockedOut(0), isEmpty);
      expect(knockedOut(100), hasLength(30));
      expect(knockedOut(100).toSet(), hasLength(30));
    });

    test('takes the top-right bricks first', () {
      expect(knockedOut(11), [(0, 5), (0, 4), (0, 3)]);
      expect(knockedOut(25).last, (1, 4));
    });

    test('clamps out-of-range percentages', () {
      expect(knockedOut(-20), isEmpty);
      expect(knockedOut(250), hasLength(30));
    });

    test('grows with the percentage, never reshuffling', () {
      for (var p = 1; p <= 100; p++) {
        final before = knockedOut(p - 1);
        expect(knockedOut(p).take(before.length), before);
      }
    });

    test('other wall sizes', () {
      expect(knockedOut(50, rows: 2, cols: 2), [(0, 1), (0, 0)]);
      expect(knockedOut(50, rows: 0, cols: 0), isEmpty);
    });
  });

  for (final brightness in Brightness.values) {
    for (final percent in [0, 50, 100]) {
      for (final progress in [0.0, 0.5, 1.0]) {
        testWidgets('paints $percent% at $progress in ${brightness.name}', (
          tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(brightness),
              home: Center(
                child: SizedBox(
                  width: 120,
                  child: BrickWall(percent: percent, progress: progress),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
