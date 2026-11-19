import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/quran_db.dart';
import '../services/notifications.dart';
import '../util/arabic.dart';
import '../util/ranges.dart';

/// صفحات ورد يوم واحد: من [next] عدد [perDay] صفحة، ولا يتجاوز آخر المصحف
/// (يُختم المصحف في آخر يوم ثم يبدأ الورد من أوله). دالة نقية لتسهل تجربتها.
List<int> wirdPages(int next, int perDay) {
  final from = next.clamp(1, quranPages);
  final to = min(from + max(1, perDay) - 1, quranPages);
  return [for (var p = from; p <= to; p++) p];
}

/// سجل ورد القرآن ليوم. يُحفظ في جدول quran_logs القديم: الصفحات في new_pages
/// وأعلى صفحة بلغها في recent_pages، والإتمام في new_done.
class QuranLog {
  final String date;
  final List<int> pages;
  final int reached;
  final bool done;
  const QuranLog(this.date, this.pages, {this.reached = 0, this.done = false});

  bool get isEmpty => pages.isEmpty;
  bool get complete => done && !isEmpty;

  /// كم صفحة قرأ منها (بحسب أبعد صفحة فتحها).
  int get readCount => done ? pages.length : pages.where((p) => p <= reached).length;

  QuranLog copyWith({int? reached, bool? done}) =>
      QuranLog(date, pages, reached: reached ?? this.reached, done: done ?? this.done);

  Map<String, Object?> toRow() => {
        'date': date,
        'new_pages': formatRanges(pages),
        'recent_pages': reached > 0 ? '$reached' : '',
        'old_pages': '',
        'new_done': done ? 1 : 0,
        'recent_done': 0,
        'old_done': 0,
      };

  factory QuranLog.fromRow(Map<String, Object?> r) {
    // سجلات المراجعة القديمة: نعدّ صفحاتها كلها، وتمامها تمام أجزائها.
    final pages = {
      ...parseRanges(r['new_pages'] as String),
      ...parseRanges(r['old_pages'] as String),
    }.toList()
      ..sort();
    final reached = int.tryParse(r['recent_pages'] as String? ?? '') ?? 0;
    final oldStyle = (r['old_pages'] as String).isNotEmpty || ((r['recent_pages'] as String).contains('-') || (r['recent_pages'] as String).contains(','));
    final done = oldStyle
        ? (r['new_done'] == 1 || (r['new_pages'] as String).isEmpty) && (r['old_done'] == 1 || (r['old_pages'] as String).isEmpty)
        : r['new_done'] == 1;
    return QuranLog(r['date'] as String, pages, reached: oldStyle ? 0 : reached, done: done);
  }
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

/// ورد القرآن اليومي: عدد ثابت من الصفحات يمضي في المصحف بالترتيب، مع سجل الأيام والملاحظات.
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

  /// عدد صفحات الورد كل يوم (10 أو 20 أو 30 أو غيرها).
  int get perDay => _p.getInt('q_wird_pages') ?? 20;

  /// أول صفحة في ورد الغد.
  int get next => _p.getInt('q_wird_next') ?? 1;

  int get khatmas => _p.getInt('q_khatmas') ?? 0;

  TimeOfDay? get reminder => parseTime(_p.getString('q_reminder'));
  int get lastPage => _p.getInt('q_last_page') ?? 1;
  Future<void> setLastPage(int p) => _p.setInt('q_last_page', p);

  /// عرض المصحف: الصفحة على قد الشاشة (افتراضياً)، أو خط مكبَّر تمرَّر فيه الصفحة.
  bool get fitPage => _p.getBool('q_fit_page') ?? true;
  Future<void> setFitPage(bool v) async {
    await _p.setBool('q_fit_page', v);
    changed();
  }

  /// حجم خط المصحف في وضع التكبير.
  double get zoomFont => _p.getDouble('q_zoom_font') ?? 30;
  /// نغمة التنبيه عند الخطأ في متابعة التلاوة.
  bool get mistakeSound => _p.getBool('q_mistake_sound') ?? true;
  Future<void> setMistakeSound(bool v) async {
    await _p.setBool('q_mistake_sound', v);
    changed();
  }

  /// تُعدّ الكلمة المقروءة بحرف مختلف خطأً (لا الكلمة الساقطة أو المبدلة فقط).
  bool get strictLetters => _p.getBool('q_strict') ?? true;
  Future<void> setStrictLetters(bool v) async {
    await _p.setBool('q_strict', v);
    changed();
  }

  /// محرّك التسميع: نموذج التلاوة على الهاتف (أدق، بلا إنترنت) أو خدمة Google.
  bool get useQuranModel => _p.getBool('q_asr_model') ?? true;
  Future<void> setUseQuranModel(bool v) async {
    await _p.setBool('q_asr_model', v);
    changed();
  }

  bool get followIntroSeen => _p.getBool('q_follow_intro') ?? false;
  Future<void> setFollowIntroSeen() => _p.setBool('q_follow_intro', true);

  Future<void> setZoomFont(double v) => _p.setDouble('q_zoom_font', v.clamp(16, 72).toDouble());

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
    await _put(QuranLog(_today, wirdPages(next, perDay)));
    if (notify) changed();
  }

  /// يحفظ عدد صفحات الورد وموضع البدء، ويعيد حساب ورد اليوم إن لم يُتمّه.
  Future<void> setup({required int perDay, int? start}) async {
    await _p.setBool('q_enabled', true);
    await _p.setInt('q_wird_pages', perDay.clamp(1, 604));
    final t = today;
    if (start != null) {
      await _p.setInt('q_wird_next', start.clamp(1, quranPages));
    } else if (t != null && !t.done && t.pages.isNotEmpty) {
      await _p.setInt('q_wird_next', t.pages.first);
    }
    if (t == null || !t.done) {
      await userDb().delete('quran_logs', where: 'date = ?', whereArgs: [_today]);
      logs.removeWhere((l) => l.date == _today);
      await ensureToday(notify: false);
    }
    changed();
  }

  /// يسجّل أبعد صفحة فتحها من ورد اليوم.
  Future<void> notePage(int page) async {
    final t = today;
    if (t == null || t.done || !t.pages.contains(page) || page <= t.reached) return;
    await _put(t.copyWith(reached: page));
    changed();
  }

  /// يعلّم ورد اليوم مقروءاً (أو يلغي ذلك)، فيتقدم موضع الورد أو يرجع.
  Future<void> markDone(bool done) async {
    final t = today;
    if (t == null || t.isEmpty || t.done == done) return;
    if (done) {
      var n = t.pages.last + 1;
      if (n > quranPages) {
        n = 1;
        await _p.setInt('q_khatmas', khatmas + 1);
      }
      await _p.setInt('q_wird_next', n);
    } else {
      if (t.pages.last == quranPages && next == 1) await _p.setInt('q_khatmas', max(0, khatmas - 1));
      await _p.setInt('q_wird_next', t.pages.first);
    }
    await _put(t.copyWith(done: done));
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

  /// كم يوماً بقي على ختم المصحف بهذا الورد (بعد ورد اليوم إن أتمّه).
  int get daysToKhatma {
    final t = today;
    final from = t != null && !t.done ? t.pages.first : next;
    return ((quranPages - from + 1) / perDay).ceil();
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
