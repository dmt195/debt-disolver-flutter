import 'package:debt_destroyer/app/theme.dart';
import 'package:debt_destroyer/core/widgets/rate_field.dart';
import 'package:debt_destroyer/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const locale = 'en_GB';
  const key = ValueKey('rate');
  final formKey = GlobalKey<FormState>();

  Future<RateController> show(WidgetTester tester, {int? aprBps}) async {
    final controller = RateController(aprBps: aprBps, locale: locale);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          locale: const Locale('en', 'GB'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Form(
              key: formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  RateField(
                    controller: controller,
                    fieldKey: key,
                    aprLabel: 'Interest rate (APR %)',
                    monthlyLabel: 'Interest rate (% a month)',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  Future<void> tapUnit(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('rate-unit')),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester) =>
      tester.widget<TextFormField>(find.byKey(key)).controller!.text;

  testWidgets('opens in APR, with the monthly rate underneath', (tester) async {
    final c = await show(tester, aprBps: 2530);
    expect(text(tester), '25.3');
    expect(c.unit, RateUnit.year);
    expect(find.text('Interest rate (APR %)'), findsOneWidget);
    expect(find.text('= 1.897% a month'), findsOneWidget);
  });

  testWidgets('switching converts, and switching back restores', (
    tester,
  ) async {
    final c = await show(tester, aprBps: 2530);
    await tapUnit(tester, 'a month');
    expect(c.unit, RateUnit.month);
    expect(text(tester), '1.897');
    expect(find.text('Interest rate (% a month)'), findsOneWidget);
    expect(find.text('= 25.3% APR'), findsOneWidget);
    await tapUnit(tester, 'a year');
    expect(text(tester), '25.3');
    expect(c.aprBps(locale), 2530);
  });

  testWidgets('an edit per month is converted on the way back', (tester) async {
    final c = await show(tester);
    await tapUnit(tester, 'a month');
    await tester.enterText(find.byKey(key), '1.9');
    await tester.pump();
    expect(c.aprBps(locale), 2534);
    expect(find.text('= 25.34% APR'), findsOneWidget);
    await tapUnit(tester, 'a year');
    expect(text(tester), '25.34');
    expect(find.text('= 1.9% a month'), findsOneWidget);
  });

  testWidgets('text that is not a rate is left alone', (tester) async {
    final c = await show(tester);
    await tester.enterText(find.byKey(key), 'abc');
    await tapUnit(tester, 'a month');
    expect(text(tester), 'abc');
    expect(c.aprBps(locale), isNull);
  });

  testWidgets('validates in the unit showing', (tester) async {
    await show(tester);
    await tester.enterText(find.byKey(key), 'abc');
    formKey.currentState!.validate();
    await tester.pump();
    expect(find.text('Enter a rate, e.g. 19.9'), findsOneWidget);
    await tapUnit(tester, 'a month');
    formKey.currentState!.validate();
    await tester.pump();
    expect(find.text('Enter a rate, e.g. 1.9'), findsOneWidget);
    await tester.enterText(find.byKey(key), '6');
    formKey.currentState!.validate();
    await tester.pump();
    expect(
      find.text("That's more than 100% APR. Enter up to 5.946% a month."),
      findsOneWidget,
    );
  });

  testWidgets('setAprBps writes in the unit showing', (tester) async {
    final c = await show(tester);
    c.setAprBps(1268, locale);
    await tester.pump();
    expect(text(tester), '12.68');
    await tapUnit(tester, 'a month');
    c.setAprBps(1268, locale);
    await tester.pump();
    expect(text(tester), '1');
  });

  testWidgets('large text fits a small phone', (tester) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(360 * 3, 740 * 3);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await show(tester, aprBps: 2530);
    await tapUnit(tester, 'a month');
    expect(tester.takeException(), isNull);
  });
}
