import 'dart:developer';

import 'package:debt_destroyer/core/diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'crash_reporter.g.dart';

/// Where unexpected errors go. The app logs them locally, and forwards them
/// to Crashlytics only with the user's consent ([ConsentingCrashReporter]).
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

/// Logs every error locally, and forwards it to [DiagnosticsService],
/// which sends it only while the user has chosen to share crash reports.
class ConsentingCrashReporter implements CrashReporter {
  ConsentingCrashReporter(this._local, this._diagnostics);

  final CrashReporter _local;
  final DiagnosticsService _diagnostics;

  @override
  void recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) {
    _local.recordError(error, stackTrace, fatal: fatal, reason: reason);
    _diagnostics.recordError(error, stackTrace, fatal: fatal, reason: reason);
  }
}

@Riverpod(keepAlive: true)
CrashReporter crashReporter(Ref ref) =>
    ConsentingCrashReporter(LogCrashReporter(), ref.watch(diagnosticsProvider));

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
