import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'prayer.dart';

/// ما يجب التذكير به. أوقات الصلاة تتغير كل يوم، فتُجدول لأسبوعين وتتجدد كلما فُتح التطبيق.
class ReminderPlan {
  final TimeOfDay? wird;
  final TimeOfDay? sleep;
  final PrayerConfig? prayer;
  final Set<Salah> prayerAlerts;
  final int? morningAfterFajr; // دقائق بعد الفجر، أو null إذا كان مطفأً
  final int? eveningAfterAsr; // دقائق بعد العصر
  const ReminderPlan({
    this.wird,
    this.sleep,
    this.prayer,
    this.prayerAlerts = const {},
    this.morningAfterFajr,
    this.eveningAfterAsr,
  });
}

class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _days = 14;

  /// يُستدعى عند الضغط على إشعار، ومعه الحمولة (wird, morning, evening, sleep, prayer).
  static void Function(String payload)? onOpen;

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
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null) onOpen?.call(p);
      },
    );
    _ready = true;
  }

  /// الحمولة إن كان التطبيق قد فُتح بالضغط على إشعار.
  static Future<String?> launchPayload() async {
    await init();
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d?.didNotificationLaunchApp ?? false) return d!.notificationResponse?.payload;
    return null;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<bool> requestPermission() async {
    await init();
    return await _android?.requestNotificationsPermission() ?? true;
  }

  static NotificationDetails _details(String channel, String name) => NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          name,
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFF3F5A44),
        ),
      );

  static tz.TZDateTime _nextDaily(TimeOfDay t) {
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, t.hour, t.minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return at;
  }

  static Future<void> _daily(int id, TimeOfDay t, String title, String body, String channel, String channelName,
      String payload) {
    return _plugin.zonedSchedule(
      id: id,
      scheduledDate: _nextDaily(t),
      title: title,
      body: body,
      notificationDetails: _details(channel, channelName),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  static Future<void> _once(int id, DateTime at, String title, String body, String channel, String channelName,
      String payload) {
    return _plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      title: title,
      body: body,
      notificationDetails: _details(channel, channelName),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  static Future<void> scheduleAll(ReminderPlan plan) async {
    await init();
    await _plugin.cancelAll();
    if (plan.wird != null) {
      await _daily(1, plan.wird!, 'ذِكرى', 'حان وقت وردك من صحيح البخاري', 'daily_wird', 'تذكير الورد اليومي', 'wird');
    }
    if (plan.sleep != null) {
      await _daily(2, plan.sleep!, 'أذكار النوم', 'قبل أن تنام: أذكار النوم', 'adhkar', 'تذكير الأذكار', 'sleep');
    }
    final p = plan.prayer;
    if (p == null) return;
    final now = DateTime.now();
    for (var d = 0; d < _days; d++) {
      final day = DateTime(now.year, now.month, now.day + d);
      final times = p.timesFor(day);
      final base = 1000 + d * 10;
      for (final (i, s) in fivePrayers.indexed) {
        final at = times[s]!;
        if (!plan.prayerAlerts.contains(s) || !at.isAfter(now)) continue;
        await _once(base + i, at, 'صلاة ${salahNames[s]}', 'حان الآن وقت صلاة ${salahNames[s]}', 'prayer',
            'مواقيت الصلاة', 'prayer');
      }
      if (plan.morningAfterFajr != null) {
        final at = times[Salah.fajr]!.add(Duration(minutes: plan.morningAfterFajr!));
        if (at.isAfter(now)) {
          await _once(base + 5, at, 'أذكار الصباح', 'ابدأ يومك بأذكار الصباح', 'adhkar', 'تذكير الأذكار', 'morning');
        }
      }
      if (plan.eveningAfterAsr != null) {
        final at = times[Salah.asr]!.add(Duration(minutes: plan.eveningAfterAsr!));
        if (at.isAfter(now)) {
          await _once(base + 6, at, 'أذكار المساء', 'حان وقت أذكار المساء', 'adhkar', 'تذكير الأذكار', 'evening');
        }
      }
    }
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
