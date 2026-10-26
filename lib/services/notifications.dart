import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// تذكير يومي واحد بالوقت الذي يختاره المستخدم، دون إنترنت.
class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _id = 1;
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // نبقى على التوقيت الافتراضي إن تعذر معرفة المنطقة.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_dhikra')),
    );
    _ready = true;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<bool> requestPermission() async {
    await init();
    return await _android?.requestNotificationsPermission() ?? true;
  }

  static Future<void> schedule(TimeOfDay time) async {
    await init();
    await _plugin.cancel(id: _id);
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: _id,
      scheduledDate: at,
      title: 'ذِكرى',
      body: 'حان وقت وردك من صحيح البخاري',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_wird',
          'تذكير الورد اليومي',
          channelDescription: 'تذكير واحد في اليوم بورد البخاري',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFF3F5A44),
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancel() async {
    await init();
    await _plugin.cancel(id: _id);
  }
}

String formatTime(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.period == DayPeriod.am ? 'صباحاً' : 'مساءً'}';
}

TimeOfDay? parseTime(String? s) {
  if (s == null) return null;
  final p = s.split(':');
  return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
}

String timeKey(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
