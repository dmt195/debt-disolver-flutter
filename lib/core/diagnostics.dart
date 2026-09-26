import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'diagnostics.g.dart';

/// An anonymous usage event: a fixed name, and parameters that are only ever
/// enum names. The app's catalogue is `DiagnosticEvent`.
abstract interface class UsageEvent {
  String get name;
  Map<String, String> get parameters;
}

/// Anonymous usage statistics and crash reports (diagnostics spec §2). Sent
/// only while collection is enabled, which follows the user's choice.
abstract interface class DiagnosticsService {
  /// Turns collection on or off. [discardPending] (on opting in) first
  /// deletes crash reports stored on the device while it was off, so
  /// consent never reaches back to before it was given.
  Future<void> setCollectionEnabled({
    required bool enabled,
    bool discardPending = false,
  });

  void recordError(
    Object error,
    StackTrace stack, {
    bool fatal = false,
    String? reason,
  });

  void logScreen(String name);

  void logEvent(UsageEvent event);

  /// The analytics app instance ID, for deletion requests; null when there
  /// is no analytics.
  Future<String?> appInstanceId();
}

/// Sends nothing: tests, debug builds, and whenever Firebase can't start.
class NoDiagnostics implements DiagnosticsService {
  @override
  Future<void> setCollectionEnabled({
    required bool enabled,
    bool discardPending = false,
  }) async {}

  @override
  void recordError(
    Object error,
    StackTrace stack, {
    bool fatal = false,
    String? reason,
  }) {}

  @override
  void logScreen(String name) {}

  @override
  void logEvent(UsageEvent event) {}

  @override
  Future<String?> appInstanceId() async => null;
}

/// Stands in front of a real service: while collection is off nothing
/// reaches it, and errors never carry their text (which can hold debt names
/// and amounts, e.g. a failed SQL insert), only their type and stack trace.
class GatedDiagnostics implements DiagnosticsService {
  GatedDiagnostics(this._inner);

  final DiagnosticsService _inner;
  var _enabled = false;

  @override
  Future<void> setCollectionEnabled({
    required bool enabled,
    bool discardPending = false,
  }) {
    _enabled = enabled;
    return _inner.setCollectionEnabled(
      enabled: enabled,
      discardPending: discardPending,
    );
  }

  @override
  void recordError(
    Object error,
    StackTrace stack, {
    bool fatal = false,
    String? reason,
  }) {
    if (!_enabled) return;
    // The reason is dropped too: a framework description can quote a
    // widget, and a widget can quote what was typed.
    _inner.recordError(RedactedError(error), stack, fatal: fatal);
  }

  @override
  void logScreen(String name) {
    if (_enabled) _inner.logScreen(name);
  }

  @override
  void logEvent(UsageEvent event) {
    if (_enabled) _inner.logEvent(event);
  }

  @override
  Future<String?> appInstanceId() => _inner.appInstanceId();
}

/// An error reduced to its type, for crash reports.
class RedactedError implements Exception {
  RedactedError(Object error) : type = '${error.runtimeType}';

  final String type;

  @override
  String toString() => type;
}

/// The diagnostics service; `main` swaps in Firebase when it can start.
@Riverpod(keepAlive: true)
DiagnosticsService diagnostics(Ref ref) => NoDiagnostics();
