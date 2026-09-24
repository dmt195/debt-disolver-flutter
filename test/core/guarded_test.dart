import 'package:debt_destroyer/core/crash_reporter.dart';
import 'package:debt_destroyer/core/guarded.dart';
import 'package:debt_destroyer/core/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/recording_crash_reporter.dart';

void main() {
  testWidgets('a failed action is reported and explained', (tester) async {
    final reporter = RecordingCrashReporter();
    final failure = Exception('disk full');
    Object? result = 'unset';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [crashReporterProvider.overrideWithValue(reporter)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await runGuarded<int>(
                  context,
                  () async => throw failure,
                ),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(reporter.errors.single, (failure, false));
    expect(
      find.text("Couldn't save your changes. Please try again."),
      findsOneWidget,
    );
  });
}
