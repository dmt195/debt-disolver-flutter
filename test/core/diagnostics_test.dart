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

  group('the gate in front of Firebase', () {
    test('nothing gets through while off', () async {
      final inner = FakeDiagnostics();
      final gated = GatedDiagnostics(inner)
        ..logScreen('home')
        ..logEvent(const _Event())
        ..recordError(StateError('x'), StackTrace.empty);
      expect(inner.screens, isEmpty);
      expect(inner.events, isEmpty);
      expect(inner.errors, isEmpty);
      await gated.setCollectionEnabled(enabled: true);
      gated
        ..logScreen('home')
        ..logEvent(const _Event());
      expect(inner.screens, ['home']);
      expect(inner.events, hasLength(1));
      await gated.setCollectionEnabled(enabled: false);
      gated.logScreen('plans');
      expect(inner.screens, ['home']);
    });

    test('errors go without their text, only their type', () async {
      final inner = FakeDiagnostics();
      final gated = GatedDiagnostics(inner);
      await gated.setCollectionEnabled(enabled: true);
      gated.recordError(
        const _DatabaseError(),
        StackTrace.current,
        reason: 'building Text("Barclaycard")',
      );
      final sent = inner.errors.single;
      expect('$sent', isNot(contains('Barclaycard')));
      expect('$sent', isNot(contains('1234.56')));
      expect('$sent', contains('_DatabaseError'));
      expect(inner.reasons.single, isNull);
    });

    test('opting in passes on the request to discard stored reports', () async {
      final inner = FakeDiagnostics();
      await GatedDiagnostics(inner)
          .setCollectionEnabled(enabled: true, discardPending: true);
      expect(inner.discarded, [true]);
    });
  });
}

class _Event implements UsageEvent {
  const _Event();

  @override
  String get name => 'check_in_saved';

  @override
  Map<String, String> get parameters => const {};
}

/// Like a failed SQL insert: its message carries the values bound to it.
class _DatabaseError implements Exception {
  const _DatabaseError();

  @override
  String toString() =>
      'SqliteException(13): database or disk is full, '
      'parameters: Barclaycard, 1234.56';
}
