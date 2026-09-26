import 'package:debt_destroyer/core/diagnostics.dart';

/// Records what the app would send, without Firebase.
class FakeDiagnostics implements DiagnosticsService {
  FakeDiagnostics({this.appId});

  final String? appId;
  final enabled = <bool>[];
  final events = <UsageEvent>[];
  final screens = <String>[];
  final errors = <Object>[];

  @override
  Future<void> setCollectionEnabled({required bool enabled}) async =>
      this.enabled.add(enabled);

  @override
  void recordError(
    Object error,
    StackTrace stack, {
    bool fatal = false,
    String? reason,
  }) => errors.add(error);

  @override
  void logScreen(String name) => screens.add(name);

  @override
  void logEvent(UsageEvent event) => events.add(event);

  @override
  Future<String?> appInstanceId() async => appId;
}
