import 'package:debt_destroyer/core/crash_reporter.dart';
import 'package:debt_destroyer/core/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_diagnostics.dart';
import '../helpers/recording_crash_reporter.dart';

void main() {
  test('crash reports are logged locally and forwarded', () {
    final local = RecordingCrashReporter();
    final diagnostics = FakeDiagnostics();
    ConsentingCrashReporter(
      local,
      diagnostics,
    ).recordError(StateError('boom'), StackTrace.empty, fatal: true);
    expect(local.errors, hasLength(1));
    expect(diagnostics.errors.single, isA<StateError>());
  });

  test('nothing is sent by default', () async {
    final none = NoDiagnostics();
    await none.setCollectionEnabled(enabled: true);
    none
      ..logScreen('home')
      ..recordError(StateError('x'), StackTrace.empty);
    expect(await none.appInstanceId(), isNull);
  });
}
