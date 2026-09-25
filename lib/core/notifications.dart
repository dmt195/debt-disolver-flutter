import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

part 'notifications.g.dart';

/// One scheduled notification.
typedef Reminder = ({int id, DateTime at, String title, String body});

/// Every reminder opens Check in (spec §7).
const kCheckInPayload = 'check-in';

/// Local notifications: nothing leaves the phone. Tests use a fake.
abstract interface class NotificationsService {
  /// Sets up the plugin and the time zone. [onTap] gets a tapped
  /// notification's payload while the app is running.
  Future<void> initialize({required void Function(String? payload) onTap});

  /// Asks the OS for permission to notify; true if granted.
  Future<bool> requestPermission();

  /// Replaces everything scheduled with [reminders] (empty cancels all).
  Future<void> replaceAll(List<Reminder> reminders);

  /// The payload of the notification that launched the app, if any.
  Future<String?> launchPayload();
}

class LocalNotificationsService implements NotificationsService {
  LocalNotificationsService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Pay-day reminders and check-in nudges',
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } on Object {
      tz.setLocalLocation(tz.UTC);
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is asked only when a reminder is switched on.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    await _plugin.cancelAll();
    for (final r in reminders) {
      await _plugin.zonedSchedule(
        id: r.id,
        // Reminder times are wall-clock times ("9 in the morning"), so build
        // them in the notification time zone rather than converting.
        scheduledDate: tz.TZDateTime(
          tz.local,
          r.at.year,
          r.at.month,
          r.at.day,
          r.at.hour,
          r.at.minute,
        ),
        notificationDetails: _details,
        // Never exact alarms: a reminder a few minutes late is fine.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
        payload: kCheckInPayload,
      );
    }
  }

  @override
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp ?? false
        ? details!.notificationResponse?.payload
        : null;
  }
}

@Riverpod(keepAlive: true)
NotificationsService notificationsService(Ref ref) =>
    LocalNotificationsService(FlutterLocalNotificationsPlugin());
