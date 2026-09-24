import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'crash_reporter.g.dart';

/// Where unexpected errors go. The app logs them locally; a remote service
/// (for example Firebase Crashlytics, once a project is set up) can be
/// plugged in by overriding [crashReporterProvider].
abstract interface class CrashReporter {
  void recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  });
}

/// Writes errors to the developer log. Nothing leaves the device.
class LogCrashReporter implements CrashReporter {
  @override
  void recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) => log(
    reason ?? (fatal ? 'Uncaught error' : 'Handled error'),
    error: error,
    stackTrace: stackTrace,
    level: fatal ? 1000 : 900,
  );
}

@Riverpod(keepAlive: true)
CrashReporter crashReporter(Ref ref) => LogCrashReporter();

/// Sends uncaught framework and platform errors to [reporter], keeping any
/// handler that was already installed.
void installErrorHandlers(CrashReporter reporter) {
  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    reporter.recordError(
      details.exception,
      details.stack ?? StackTrace.empty,
      fatal: true,
      reason: details.context?.toString(),
    );
    previousFlutter?.call(details);
  };
  final previousPlatform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    reporter.recordError(error, stackTrace, fatal: true);
    return previousPlatform?.call(error, stackTrace) ?? true;
  };
}
