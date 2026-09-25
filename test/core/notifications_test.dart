import 'package:debt_destroyer/core/notifications.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Records what the service asks of the plugin.
class _RecordingPlugin implements FlutterLocalNotificationsPlugin {
  final calls = <String>[];
  final scheduled =
      <(int, tz.TZDateTime, String?, String?, AndroidScheduleMode)>[];

  @override
  Future<void> cancelAll() async => calls.add('cancelAll');

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    calls.add('schedule $id');
    scheduled.add((id, scheduledDate, title, payload, androidScheduleMode));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
  });

  test('replacing cancels everything, then schedules each gently', () async {
    final plugin = _RecordingPlugin();
    final service = LocalNotificationsService(plugin);
    await service.replaceAll([
      (id: 1, at: DateTime(2026, 9, 28, 9), title: 'Pay day', body: 'Visa'),
      (id: 10, at: DateTime(2026, 11, 3, 9), title: 'Check in', body: '…'),
    ]);
    expect(plugin.calls, ['cancelAll', 'schedule 1', 'schedule 10']);
    final first = plugin.scheduled.first;
    expect(first.$2, tz.TZDateTime(tz.local, 2026, 9, 28, 9));
    expect(first.$3, 'Pay day');
    expect(first.$4, kCheckInPayload);
    expect(first.$5, AndroidScheduleMode.inexactAllowWhileIdle);
  });

  test('an empty list just cancels', () async {
    final plugin = _RecordingPlugin();
    await LocalNotificationsService(plugin).replaceAll(const []);
    expect(plugin.calls, ['cancelAll']);
  });
}
