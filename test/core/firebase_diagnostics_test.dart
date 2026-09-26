import 'package:debt_destroyer/core/diagnostics.dart';
import 'package:debt_destroyer/core/firebase_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('off in debug builds unless asked for', () async {
    var started = false;
    // Tests run as a debug build, where the default is off.
    final service = await startDiagnostics(
      initialize: () async => started = true,
    );
    expect(service, isA<NoDiagnostics>());
    expect(started, isFalse);
  });

  test('without Firebase config it sends nothing and carries on', () async {
    final service = await startDiagnostics(
      enabled: true,
      initialize: () async => throw Exception('no GoogleService-Info.plist'),
    );
    expect(service, isA<NoDiagnostics>());
  });
}
