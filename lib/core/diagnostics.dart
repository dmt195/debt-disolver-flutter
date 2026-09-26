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
  Future<void> setCollectionEnabled({required bool enabled});

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
  Future<void> setCollectionEnabled({required bool enabled}) async {}

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

/// The diagnostics service; `main` swaps in Firebase when it can start.
@Riverpod(keepAlive: true)
DiagnosticsService diagnostics(Ref ref) => NoDiagnostics();
