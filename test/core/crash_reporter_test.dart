import 'package:debt_destroyer/core/crash_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/recording_crash_reporter.dart';

void main() {
  test('uncaught framework and platform errors reach the reporter', () {
    final flutterBefore = FlutterError.onError;
    final platformBefore = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = flutterBefore;
      PlatformDispatcher.instance.onError = platformBefore;
    });
    var previousCalled = false;
    FlutterError.onError = (_) => previousCalled = true;
    final reporter = RecordingCrashReporter();

    installErrorHandlers(reporter);
    final framework = Exception('build failed');
    FlutterError.onError!(FlutterErrorDetails(exception: framework));
    final platform = StateError('channel closed');
    final handled = PlatformDispatcher.instance.onError!(
      platform,
      StackTrace.current,
    );

    expect(reporter.errors, [(framework, true), (platform, true)]);
    expect(previousCalled, isTrue, reason: 'earlier handler still runs');
    expect(handled, isTrue);
  });

  test('the local reporter accepts errors without throwing', () {
    LogCrashReporter().recordError(Exception('x'), StackTrace.current);
  });
}
