import 'package:debt_destroyer/core/notifications.dart';

/// A [NotificationsService] that schedules nothing, for tests.
class FakeNotificationsService implements NotificationsService {
  FakeNotificationsService({this.granted = true, this.launch});

  /// What [requestPermission] answers.
  bool granted;

  /// The payload the app was "launched" from.
  String? launch;

  /// The last list passed to [replaceAll].
  List<Reminder> scheduled = const [];
  int replaceCount = 0;
  bool initialized = false;
  int requests = 0;
  void Function(String? payload)? _onTap;

  /// Simulates tapping a notification.
  void tap(String? payload) => _onTap?.call(payload);

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    _onTap = onTap;
    initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    requests++;
    return granted;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    replaceCount++;
    scheduled = List.unmodifiable(reminders);
  }

  @override
  Future<String?> launchPayload() async => launch;
}
