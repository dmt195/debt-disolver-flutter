import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/illustrations/illustration.dart';
import 'package:debt_destroyer/core/illustrations/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every part of the kit, drawn in a 200×120 design box.
class _KitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    fitDesign(canvas, size, const Size(200, 120));
    drawGround(canvas, 200, 110);
    drawBrick(canvas, const Rect.fromLTWH(10, 80, 30, 18));
    drawBrick(
      canvas,
      const Rect.fromLTWH(50, 60, 30, 18),
      fill: kHiVis,
      turn: 0.4,
    );
    drawBall(canvas, const Offset(120, 60), 20, anchor: const Offset(120, 0));
    drawFlag(canvas, const Offset(170, 110), 80, raise: 0.5);
  }

  @override
  bool shouldRepaint(_KitPainter oldDelegate) => false;
}

void main() {
  Future<void> paintIn(WidgetTester tester, Size box, {Brightness? b}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(b ?? Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: box,
                child: Illustration(painter: _KitPainter()),
              ),
            ),
          ),
        ),
      );

  for (final box in const [Size(40, 40), Size(800, 600), Size.zero]) {
    testWidgets('paints the kit in a ${box.width}×${box.height} box', (
      tester,
    ) async {
      await paintIn(tester, box);
      expect(tester.takeException(), isNull);
      final paint = tester.getSize(find.byType(CustomPaint).last);
      expect(paint.width, lessThanOrEqualTo(box.width));
      expect(paint.height, lessThanOrEqualTo(box.height));
    });
  }

  testWidgets('paints in dark mode', (tester) async {
    await paintIn(tester, const Size(300, 200), b: Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('decorative unless labelled', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            SizedBox(width: 100, child: Illustration(painter: _KitPainter())),
            SizedBox(
              width: 100,
              child: Illustration(
                painter: _KitPainter(),
                semanticLabel: 'A wall',
              ),
            ),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('A wall'), findsOneWidget);
    expect(tester.getSemantics(find.byType(Illustration).first).label, isEmpty);
    handle.dispose();
  });

  test('fitDesign scales uniformly and centres', () {
    expect(designScale(const Size(400, 120), const Size(200, 120)), 1);
    expect(designScale(const Size(100, 600), const Size(200, 120)), 0.5);
    expect(designScale(Size.zero, const Size(200, 120)), 0);
  });
}
