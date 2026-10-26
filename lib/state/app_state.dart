import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/adhkar_data.dart';
import '../db/bukhari_db.dart';
import '../db/user_db.dart';
import '../services/home_widgets.dart';
import '../services/notifications.dart';
import '../services/prayer.dart';
import '../util/arabic.dart';

class Forecast {
  final int remaining;
  final int days;
  final DateTime date;
  final bool fromActualRate;
  const Forecast(this.remaining, this.days, this.date, this.fromActualRate);
}

class AppState extends ChangeNotifier {
  final bukhari = BukhariDb();
  final user = UserDb();
  final adhkar = AdhkarData();
  late final SharedPreferences _prefs;

  bool ready = false;
  WirdPlan? plan;
  int position = 1;
  List<WirdLog> logs = [];
  List<Benefit> benefits = [];
  List<String> tags = [];

  double fontSize = 20;
  ThemeMode themeMode = ThemeMode.light;
  String catchUp = 'postpone'; // postpone | compensate
  int khatmas = 0;

  DateTime Function() clock = DateTime.now;

  bool _widgetPending = false;

  @override
  void notifyListeners() {
    super.notifyListeners();
    _refreshWidgets();
  }

  /// يحدّث ويدجت الشاشة الرئيسية بعد أي تغيير، مرة واحدة لكل دفعة تغييرات.
  void _refreshWidgets() {
    if (!ready || plan == null || _widgetPending) return;
    _widgetPending = true;
    Future.delayed(const Duration(milliseconds: 500), () async {
      _widgetPending = false;
      try {
        await HomeWidgets.update(
          bukhari: bukhari,
          position: position,
          finished: finished,
          today: todayLog,
          perDay: plan!.perDay,
          benefit: benefitOfTheDay,
        );
      } catch (_) {
        // الويدجت ليست أساسية؛ لا نوقف التطبيق بسببها.
      }
    });
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    fontSize = _prefs.getDouble('fontSize') ?? 20;
    themeMode = _prefs.getString('theme') == 'dark' ? ThemeMode.dark : ThemeMode.light;
    catchUp = _prefs.getString('catchUp') ?? 'postpone';
    khatmas = _prefs.getInt('khatmas') ?? 0;
    await bukhari.open();
    await user.open();
    await adhkar.load();
    await _reload();
    ready = true;
    notifyListeners();
    reschedule().catchError((_) {});
  }

  /// يعيد جدولة كل التذكيرات (الورد، الصلاة، الأذكار).
  Future<void> reschedule() => Reminders.scheduleAll(ReminderPlan(
        wird: parseTime(plan?.reminder),
        sleep: sleepReminder,
        prayer: prayerConfig,
        prayerAlerts: prayerAlerts,
        morningAfterFajr: morningAfterFajr,
        eveningAfterAsr: eveningAfterAsr,
      ));

  Future<void> _reload() async {
    plan = await user.activePlan('bukhari');
    if (plan != null) {
      position = await user.position(plan!.id) ?? plan!.startPos;
      await ensureToday(notify: false);
      logs = await user.logs(plan!.id);
    }
    await reloadBenefits(notify: false);
  }

  // ---------- الورد ----------

  String get todayKey => dateKey(clock());
  bool get finished => plan != null && position > plan!.endPos;

  WirdLog? get todayLog {
    final k = todayKey;
    for (final l in logs.reversed) {
      if (l.date == k) return l;
    }
    return null;
  }

  /// ينشئ سجل اليوم عند أول فتح في يوم جديد.
  Future<void> ensureToday({bool notify = true}) async {
    final p = plan;
    if (p == null) return;
    logs = await user.logs(p.id);
    final k = todayKey;
    if (logs.any((l) => l.date == k)) return;
    if (position > p.endPos) return;
    var debt = 0;
    if (catchUp == 'compensate' && logs.isNotEmpty) {
      final last = logs.last;
      final leftover = (last.done || last.excused) ? 0 : max(0, last.target - last.readCount);
      final gap = max(0, dateOnly(clock()).difference(parseKey(last.date)).inDays - 1);
      debt = min(leftover + gap * p.perDay, p.perDay * 2);
    }
    final to = min(position + p.perDay + debt - 1, p.endPos);
    final log = WirdLog(k, position, to, 0, false, false);
    await user.putLog(p.id, log);
    logs = await user.logs(p.id);
    if (notify) notifyListeners();
  }

  Future<void> startPlan({required int perDay, required int startPos, TimeOfDay? reminder}) async {
    await user.createPlan(
      kind: 'bukhari',
      perDay: perDay,
      startPos: startPos,
      endPos: totalHadiths,
      startDate: todayKey,
      reminder: reminder == null ? null : timeKey(reminder),
    );
    await _reload();
    notifyListeners();
    if (reminder != null) await Reminders.requestPermission();
    await reschedule();
  }

  /// يُستدعى عند الضغط على «قرأته». لا يحتسب إلا إذا كان الحديث هو موضع الورد الحالي.
  Future<bool> markRead(int number) async {
    final p = plan;
    if (p == null || number != position || finished) return false;
    await ensureToday(notify: false);
    position++;
    await user.setPosition(p.id, position);
    final t = todayLog;
    if (t != null) {
      await user.putLog(
          p.id, WirdLog(t.date, t.fromPos, t.toPos, t.readCount + 1, t.done || position > t.toPos, t.excused));
    }
    if (position > p.endPos) {
      khatmas++;
      await _prefs.setInt('khatmas', khatmas);
    }
    logs = await user.logs(p.id);
    notifyListeners();
    return true;
  }

  Future<void> setPosition(int pos) async {
    final p = plan;
    if (p == null) return;
    position = pos.clamp(1, p.endPos);
    await user.setPosition(p.id, position);
    final t = todayLog;
    if (t != null && !t.done) {
      final to = min(position + p.perDay - 1, p.endPos);
      await user.putLog(p.id, WirdLog(t.date, position, to, t.readCount, false, t.excused));
    }
    await ensureToday(notify: false);
    logs = await user.logs(p.id);
    notifyListeners();
  }

  Future<void> setPerDay(int n) async {
    final p = plan;
    if (p == null) return;
    await user.updatePlan(p.id, {'per_day': n});
    plan = await user.activePlan('bukhari');
    final t = todayLog;
    if (t != null && !t.done) {
      final to = min(t.fromPos + n - 1, p.endPos);
      await user.putLog(p.id, WirdLog(t.date, t.fromPos, to, t.readCount, position > to, t.excused));
    }
    logs = await user.logs(p.id);
    notifyListeners();
  }

  Future<void> setReminder(TimeOfDay? time) async {
    final p = plan;
    if (p == null) return;
    await user.updatePlan(p.id, {'reminder': time == null ? null : timeKey(time)});
    plan = await user.activePlan('bukhari');
    notifyListeners();
    if (time != null) await Reminders.requestPermission();
    await reschedule();
  }

  Future<void> newKhatma() => setPosition(1);

  // ---------- الخط والعذر ----------

  bool _ok(WirdLog l) => l.done || l.excused;

  Set<String> get completedDays => {for (final l in logs) if (_ok(l)) l.date};

  int get currentStreak {
    final ok = completedDays;
    var d = dateOnly(clock());
    if (!ok.contains(dateKey(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (ok.contains(dateKey(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  int get longestStreak {
    final days = completedDays.map(parseKey).toList()..sort();
    var best = 0, run = 0;
    DateTime? prev;
    for (final d in days) {
      run = (prev != null && d.difference(prev).inDays == 1) ? run + 1 : 1;
      best = max(best, run);
      prev = d;
    }
    return best;
  }

  int get totalRead => logs.fold(0, (s, l) => s + l.readCount);
  int get daysCompleted => logs.where((l) => l.done).length;

  static DateTime weekStart(DateTime d) => dateOnly(d).subtract(Duration(days: (d.weekday - DateTime.saturday) % 7));

  /// يوم عذر واحد في الأسبوع (يبدأ الأسبوع من السبت).
  bool excuseAvailable(DateTime day) {
    final ws = weekStart(day);
    return !logs.any((l) => l.excused && weekStart(parseKey(l.date)) == ws);
  }

  /// فاتَه ورد أمس، والخط قبله قائم، وما زال عنده عذر لذلك الأسبوع.
  bool get canExcuseYesterday {
    if (plan == null) return false;
    final y = dateOnly(clock()).subtract(const Duration(days: 1));
    if (parseKey(plan!.startDate).isAfter(y)) return false;
    final ok = completedDays;
    if (ok.contains(dateKey(y))) return false;
    final before = y.subtract(const Duration(days: 1));
    return ok.contains(dateKey(before)) && excuseAvailable(y);
  }

  Future<void> excuse(DateTime day) async {
    final p = plan;
    if (p == null) return;
    final k = dateKey(day);
    final existing = logs.where((l) => l.date == k).firstOrNull;
    final l = existing == null
        ? WirdLog(k, position, position - 1, 0, false, true)
        : WirdLog(k, existing.fromPos, existing.toPos, existing.readCount, existing.done, true);
    await user.putLog(p.id, l);
    logs = await user.logs(p.id);
    notifyListeners();
  }

  // ---------- الختم المتوقع ----------

  Forecast? get forecast {
    final p = plan;
    if (p == null) return null;
    final remaining = p.endPos - position + 1;
    if (remaining <= 0) return null;
    final today = dateOnly(clock());
    final since = today.difference(parseKey(p.startDate)).inDays + 1;
    double rate = p.perDay.toDouble();
    var actual = false;
    if (since >= 7) {
      final window = min(14, since);
      final from = today.subtract(Duration(days: window - 1));
      final read = logs.where((l) => !parseKey(l.date).isBefore(from)).fold<int>(0, (s, l) => s + l.readCount);
      if (read > 0) {
        rate = read / window;
        actual = true;
      }
    }
    final days = (remaining / rate).ceil();
    return Forecast(remaining, days, today.add(Duration(days: days)), actual);
  }

  // ---------- الفوائد ----------

  Future<void> reloadBenefits({bool notify = true}) async {
    benefits = await user.benefits();
    tags = await user.allTags();
    if (notify) notifyListeners();
  }

  Future<void> saveBenefit(Benefit b) async {
    await user.saveBenefit(b);
    await reloadBenefits();
  }

  Future<void> togglePin(Benefit b) async {
    await user.setPinned(b.id!, !b.pinned);
    await reloadBenefits();
  }

  Future<void> deleteBenefit(Benefit b) async {
    await user.deleteBenefit(b.id!);
    await reloadBenefits();
  }

  /// فائدة اليوم: ثابتة طوال اليوم، تتغير مع كل يوم.
  Benefit? get benefitOfTheDay {
    if (benefits.isEmpty) return null;
    final seed = dateOnly(clock()).millisecondsSinceEpoch ~/ 86400000;
    return benefits[Random(seed).nextInt(benefits.length)];
  }

  // ---------- الإعدادات ----------

  Future<void> setFontSize(double v) async {
    fontSize = v;
    notifyListeners();
    await _prefs.setDouble('fontSize', v);
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    await _prefs.setString('theme', m == ThemeMode.dark ? 'dark' : 'light');
  }

  Future<void> setCatchUp(String v) async {
    catchUp = v;
    notifyListeners();
    await _prefs.setString('catchUp', v);
  }

  // ---------- النسخ الاحتياطي ----------

  Future<String> exportJson() async {
    return const JsonEncoder.withIndent(' ').convert({
      'app': 'dhikra',
      'format': 1,
      'exported_at': clock().toIso8601String(),
      'settings': {'fontSize': fontSize, 'theme': _prefs.getString('theme'), 'catchUp': catchUp, 'khatmas': khatmas},
      'prefs': {
        for (final k in _prefs.getKeys())
          if (!k.startsWith('adhkar_')) k: _prefs.get(k),
      },
      'data': await user.exportAll(),
    });
  }

  Future<void> importJson(String raw) async {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    if (m['app'] != 'dhikra') throw const FormatException('ليس ملف نسخة احتياطية من ذِكرى');
    await user.importAll(m['data'] as Map<String, dynamic>);
    final prefs = (m['prefs'] as Map?) ?? {};
    for (final e in prefs.entries) {
      final k = e.key as String, v = e.value;
      if (v is num && const {'loc_lat', 'loc_lng', 'fontSize'}.contains(k)) {
        await _prefs.setDouble(k, v.toDouble());
        continue;
      }
      if (v is bool) await _prefs.setBool(k, v);
      if (v is int) await _prefs.setInt(k, v);
      if (v is double) await _prefs.setDouble(k, v);
      if (v is String) await _prefs.setString(k, v);
    }
    final s = (m['settings'] as Map?) ?? {};
    if (s['fontSize'] is num) await _prefs.setDouble('fontSize', (s['fontSize'] as num).toDouble());
    if (s['theme'] is String) await _prefs.setString('theme', s['theme'] as String);
    if (s['catchUp'] is String) await _prefs.setString('catchUp', s['catchUp'] as String);
    if (s['khatmas'] is int) await _prefs.setInt('khatmas', s['khatmas'] as int);
    fontSize = _prefs.getDouble('fontSize') ?? 20;
    themeMode = _prefs.getString('theme') == 'dark' ? ThemeMode.dark : ThemeMode.light;
    catchUp = _prefs.getString('catchUp') ?? 'postpone';
    khatmas = _prefs.getInt('khatmas') ?? 0;
    await _reload();
    notifyListeners();
    await reschedule();
  }

  // ---------- الصلاة والأذكار ----------

  PrayerConfig? get prayerConfig {
    final lat = _prefs.getDouble('loc_lat'), lng = _prefs.getDouble('loc_lng');
    if (lat == null || lng == null) return null;
    return PrayerConfig(
      lat: lat,
      lng: lng,
      place: _prefs.getString('loc_name') ?? '',
      method: _prefs.getString('calc_method') ?? 'muslim_world_league',
      hanafi: _prefs.getBool('hanafi') ?? false,
    );
  }

  Future<void> setLocation(double lat, double lng, String name) async {
    final first = prayerConfig == null;
    await _prefs.setDouble('loc_lat', lat);
    await _prefs.setDouble('loc_lng', lng);
    await _prefs.setString('loc_name', name);
    notifyListeners();
    if (first) await Reminders.requestPermission();
    await reschedule();
  }

  Future<void> setMethod(String m) async {
    await _prefs.setString('calc_method', m);
    notifyListeners();
    await reschedule();
  }

  Future<void> setHanafi(bool v) async {
    await _prefs.setBool('hanafi', v);
    notifyListeners();
    await reschedule();
  }

  Set<Salah> get prayerAlerts => {
        for (final s in fivePrayers)
          if (_prefs.getBool('alert_${s.name}') ?? true) s,
      };

  Future<void> setPrayerAlert(Salah s, bool on) async {
    await _prefs.setBool('alert_${s.name}', on);
    notifyListeners();
    await reschedule();
  }

  /// null = التذكير مطفأ.
  int? get morningAfterFajr => _offset('morning_after_fajr', 30);
  int? get eveningAfterAsr => _offset('evening_after_asr', 30);

  int? _offset(String key, int def) {
    final v = _prefs.getInt(key) ?? def;
    return v < 0 ? null : v;
  }

  Future<void> setMorningAfterFajr(int? minutes) async {
    await _prefs.setInt('morning_after_fajr', minutes ?? -1);
    notifyListeners();
    await reschedule();
  }

  Future<void> setEveningAfterAsr(int? minutes) async {
    await _prefs.setInt('evening_after_asr', minutes ?? -1);
    notifyListeners();
    await reschedule();
  }

  TimeOfDay? get sleepReminder => parseTime(_prefs.getString('sleep_reminder'));

  Future<void> setSleepReminder(TimeOfDay? t) async {
    if (t == null) {
      await _prefs.remove('sleep_reminder');
    } else {
      await _prefs.setString('sleep_reminder', timeKey(t));
      await Reminders.requestPermission();
    }
    notifyListeners();
    await reschedule();
  }

  bool adhkarDone(AdhkarSet set, [DateTime? day]) =>
      _prefs.getBool('adhkar_${set.name}_${dateKey(day ?? clock())}') ?? false;

  Future<void> markAdhkarDone(AdhkarSet set) async {
    await _prefs.setBool('adhkar_${set.name}_$todayKey', true);
    notifyListeners();
  }
}
