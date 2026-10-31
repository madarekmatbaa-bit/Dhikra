import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/quran_db.dart';
import '../services/notifications.dart';
import '../util/arabic.dart';
import '../util/ranges.dart';

/// إعدادات المراجعة: ما يحفظه المستخدم، وكم يحفظ جديداً، وفي كم يوم يدور على محفوظه القديم.
class ReviewConfig {
  final List<int> memorized; // مرتبة
  final List<int> recentOrder; // ترتيب الحفظ، الأحدث في الآخر
  final int newPerDay; // 0 = لا حفظ جديد، مراجعة فقط
  final bool descending; // الحفظ من آخر المصحف
  final int newNext;
  final int recentCount;
  final int cycleDays;
  final int oldNext;
  const ReviewConfig({
    required this.memorized,
    this.recentOrder = const [],
    this.newPerDay = 1,
    this.descending = false,
    this.newNext = 1,
    this.recentCount = 20,
    this.cycleDays = 14,
    this.oldNext = 1,
  });
}

class DayParts {
  final List<int> newPages;
  final List<int> recent;
  final List<int> old;
  const DayParts(this.newPages, this.recent, this.old);
}

/// يحسب ورد يوم واحد. دالة نقية لتسهل تجربتها.
DayParts computeDay(ReviewConfig c) {
  final mem = c.memorized.toSet();

  final newPages = <int>[];
  if (c.newPerDay > 0) {
    var p = c.newNext.clamp(1, quranPages);
    final step = c.descending ? -1 : 1;
    var guard = 0;
    while (newPages.length < c.newPerDay && p >= 1 && p <= quranPages && guard++ < quranPages) {
      if (!mem.contains(p)) newPages.add(p);
      p += step;
    }
    newPages.sort();
  }

  final recentSet = <int>{};
  for (final p in c.recentOrder.reversed) {
    if (recentSet.length >= c.recentCount) break;
    if (mem.contains(p)) recentSet.add(p);
  }
  final recent = recentSet.toList()..sort();

  final oldPool = [for (final p in c.memorized) if (!recentSet.contains(p)) p];
  final old = <int>[];
  if (oldPool.isNotEmpty) {
    final n = min((oldPool.length / max(1, c.cycleDays)).ceil(), oldPool.length);
    var i = oldPool.indexWhere((p) => p >= c.oldNext);
    if (i < 0) i = 0;
    for (var k = 0; k < n; k++) {
      old.add(oldPool[(i + k) % oldPool.length]);
    }
    old.sort();
  }
  return DayParts(newPages, recent, old);
}

class QuranLog {
  final String date;
  final List<int> newPages;
  final List<int> recent;
  final List<int> old;
  final bool newDone;
  final bool recentDone;
  final bool oldDone;
  const QuranLog(this.date, this.newPages, this.recent, this.old,
      {this.newDone = false, this.recentDone = false, this.oldDone = false});

  bool get complete =>
      (newPages.isEmpty || newDone) && (recent.isEmpty || recentDone) && (old.isEmpty || oldDone) && !isEmpty;
  bool get isEmpty => newPages.isEmpty && recent.isEmpty && old.isEmpty;
  int get partsTotal => [newPages, recent, old].where((l) => l.isNotEmpty).length;
  int get partsDone =>
      (newPages.isNotEmpty && newDone ? 1 : 0) + (recent.isNotEmpty && recentDone ? 1 : 0) + (old.isNotEmpty && oldDone ? 1 : 0);

  QuranLog copyWith({bool? newDone, bool? recentDone, bool? oldDone}) => QuranLog(date, newPages, recent, old,
      newDone: newDone ?? this.newDone, recentDone: recentDone ?? this.recentDone, oldDone: oldDone ?? this.oldDone);

  Map<String, Object?> toRow() => {
        'date': date,
        'new_pages': formatRanges(newPages),
        'recent_pages': formatRanges(recent),
        'old_pages': formatRanges(old),
        'new_done': newDone ? 1 : 0,
        'recent_done': recentDone ? 1 : 0,
        'old_done': oldDone ? 1 : 0,
      };

  factory QuranLog.fromRow(Map<String, Object?> r) => QuranLog(
        r['date'] as String,
        parseRanges(r['new_pages'] as String),
        parseRanges(r['recent_pages'] as String),
        parseRanges(r['old_pages'] as String),
        newDone: r['new_done'] == 1,
        recentDone: r['recent_done'] == 1,
        oldDone: r['old_done'] == 1,
      );
}

class QuranNote {
  final int? id;
  final int sura;
  final int aya;
  final String kind; // mistake | mutashabih | tadabbur
  final String note;
  final String createdAt;
  const QuranNote({this.id, required this.sura, required this.aya, required this.kind, this.note = '', required this.createdAt});

  factory QuranNote.fromRow(Map<String, Object?> r) => QuranNote(
        id: r['id'] as int,
        sura: r['sura'] as int,
        aya: r['aya'] as int,
        kind: r['kind'] as String,
        note: r['note'] as String,
        createdAt: r['created_at'] as String,
      );
}

const noteKinds = {'mistake': 'خطأ في الحفظ', 'mutashabih': 'متشابه', 'tadabbur': 'تدبّر'};

/// ورد مراجعة القرآن: الجديد والقريب والبعيد، مع سجل الأيام والملاحظات.
class QuranReview {
  final QuranDb db;
  final Database Function() userDb;
  final SharedPreferences Function() prefs;
  final DateTime Function() clock;
  final VoidCallback changed;
  final Future<void> Function() reschedule;
  QuranReview({
    required this.db,
    required this.userDb,
    required this.prefs,
    required this.clock,
    required this.changed,
    required this.reschedule,
  });

  List<QuranLog> logs = [];
  List<QuranNote> notes = [];

  SharedPreferences get _p => prefs();
  bool get enabled => _p.getBool('q_enabled') ?? false;

  ReviewConfig get config => ReviewConfig(
        memorized: parseRanges(_p.getString('q_memorized')),
        recentOrder: (_p.getString('q_recent') ?? '').split(',').where((e) => e.isNotEmpty).map(int.parse).toList(),
        newPerDay: _p.getInt('q_new_per_day') ?? 1,
        descending: _p.getString('q_dir') == 'desc',
        newNext: _p.getInt('q_new_next') ?? 1,
        recentCount: _p.getInt('q_recent_count') ?? 20,
        cycleDays: _p.getInt('q_cycle_days') ?? 14,
        oldNext: _p.getInt('q_old_next') ?? 1,
      );

  TimeOfDay? get reminder => parseTime(_p.getString('q_reminder'));
  int get lastPage => _p.getInt('q_last_page') ?? 1;
  Future<void> setLastPage(int p) => _p.setInt('q_last_page', p);

  String get _today => dateKey(clock());

  QuranLog? get today {
    final k = _today;
    for (final l in logs.reversed) {
      if (l.date == k) return l;
    }
    return null;
  }

  Future<void> load() async {
    logs = (await userDb().query('quran_logs', orderBy: 'date')).map(QuranLog.fromRow).toList();
    notes = (await userDb().query('quran_notes', orderBy: 'created_at DESC')).map(QuranNote.fromRow).toList();
    await ensureToday(notify: false);
  }

  Future<void> _put(QuranLog l) async {
    await userDb().insert('quran_logs', l.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
    logs = (await userDb().query('quran_logs', orderBy: 'date')).map(QuranLog.fromRow).toList();
  }

  Future<void> ensureToday({bool notify = true}) async {
    if (!enabled) return;
    if (today != null) return;
    final d = computeDay(config);
    await _put(QuranLog(_today, d.newPages, d.recent, d.old));
    if (notify) changed();
  }

  /// يحفظ الإعدادات ويعيد حساب ورد اليوم إن لم يُنجز منه شيء.
  Future<void> setup({
    required List<int> memorized,
    required int newPerDay,
    required bool descending,
    required int recentCount,
    required int cycleDays,
    int? newStart,
  }) async {
    final first = !enabled;
    await _p.setBool('q_enabled', true);
    await _p.setString('q_memorized', formatRanges(memorized));
    await _p.setInt('q_new_per_day', newPerDay);
    await _p.setString('q_dir', descending ? 'desc' : 'asc');
    await _p.setInt('q_recent_count', recentCount);
    await _p.setInt('q_cycle_days', cycleDays);
    final mem = memorized.toSet();
    if (newStart != null) {
      await _p.setInt('q_new_next', newStart);
    } else if (first || mem.contains(config.newNext)) {
      // أول صفحة غير محفوظة في اتجاه الحفظ.
      final pages = descending
          ? [for (var i = quranPages; i >= 1; i--) i]
          : [for (var i = 1; i <= quranPages; i++) i];
      await _p.setInt('q_new_next', pages.firstWhere((p) => !mem.contains(p), orElse: () => pages.first));
    }
    final recent = config.recentOrder.where(mem.contains).toList();
    await _p.setString('q_recent', recent.join(','));
    final t = today;
    if (t == null || (!t.newDone && !t.recentDone && !t.oldDone)) {
      await userDb().delete('quran_logs', where: 'date = ?', whereArgs: [_today]);
      logs.removeWhere((l) => l.date == _today);
      await ensureToday(notify: false);
    }
    changed();
  }

  Future<void> markNew(bool done) async {
    final t = today;
    if (t == null || t.newPages.isEmpty || t.newDone == done) return;
    final c = config;
    final mem = c.memorized.toSet();
    final order = [...c.recentOrder];
    if (done) {
      mem.addAll(t.newPages);
      order
        ..removeWhere(t.newPages.contains)
        ..addAll(t.newPages);
      final edge = c.descending ? t.newPages.first - 1 : t.newPages.last + 1;
      await _p.setInt('q_new_next', edge.clamp(1, quranPages));
    } else {
      mem.removeAll(t.newPages);
      order.removeWhere(t.newPages.contains);
      await _p.setInt('q_new_next', c.descending ? t.newPages.last : t.newPages.first);
    }
    final trimmed = order.length > 300 ? order.sublist(order.length - 300) : order;
    await _p.setString('q_memorized', formatRanges(mem));
    await _p.setString('q_recent', trimmed.join(','));
    await _put(t.copyWith(newDone: done));
    changed();
  }

  Future<void> markRecent(bool done) async {
    final t = today;
    if (t == null) return;
    await _put(t.copyWith(recentDone: done));
    changed();
  }

  Future<void> markOld(bool done) async {
    final t = today;
    if (t == null || t.old.isEmpty || t.oldDone == done) return;
    if (done) {
      final pool = config.memorized;
      final after = pool.where((p) => p > t.old.last);
      await _p.setInt('q_old_next', after.isEmpty ? 1 : after.first);
    } else {
      await _p.setInt('q_old_next', t.old.first);
    }
    await _put(t.copyWith(oldDone: done));
    changed();
  }

  Future<void> setReminder(TimeOfDay? t) async {
    if (t == null) {
      await _p.remove('q_reminder');
    } else {
      await _p.setString('q_reminder', timeKey(t));
      await Reminders.requestPermission();
    }
    changed();
    await reschedule();
  }

  // ---------- الخط ----------

  Set<String> get completedDays => {for (final l in logs) if (l.complete) l.date};

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

  /// كم يوماً يحتاج لإتمام حفظ المصحف بالمعدل الحالي.
  int? get daysToFinish {
    final c = config;
    if (c.newPerDay <= 0) return null;
    final left = quranPages - c.memorized.length;
    if (left <= 0) return null;
    return (left / c.newPerDay).ceil();
  }

  // ---------- الملاحظات ----------

  Future<void> saveNote(QuranNote n) async {
    final values = {'sura': n.sura, 'aya': n.aya, 'kind': n.kind, 'note': n.note, 'created_at': n.createdAt};
    if (n.id == null) {
      await userDb().insert('quran_notes', values);
    } else {
      await userDb().update('quran_notes', values, where: 'id = ?', whereArgs: [n.id]);
    }
    await _reloadNotes();
  }

  Future<void> deleteNote(QuranNote n) async {
    await userDb().delete('quran_notes', where: 'id = ?', whereArgs: [n.id]);
    await _reloadNotes();
  }

  Future<void> _reloadNotes() async {
    notes = (await userDb().query('quran_notes', orderBy: 'created_at DESC')).map(QuranNote.fromRow).toList();
    changed();
  }

  /// ملاحظات آية بعينها.
  List<QuranNote> notesOf(int sura, int aya) => [for (final n in notes) if (n.sura == sura && n.aya == aya) n];
}
