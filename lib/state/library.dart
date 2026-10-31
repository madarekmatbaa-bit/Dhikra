import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../services/notifications.dart';
import '../util/arabic.dart';

class Book {
  final int id;
  final String title;
  final String filePath;
  final int pages;
  final int perDay;
  final int position; // أول صفحة لم تُقرأ بعد
  final int lastPage; // آخر صفحة فُتحت
  final String addedAt;
  const Book(this.id, this.title, this.filePath, this.pages, this.perDay, this.position, this.lastPage, this.addedAt);

  bool get finished => position > pages;
  bool get fileExists => File(filePath).existsSync();
  double get progress => pages == 0 ? 0 : ((position - 1) / pages).clamp(0, 1).toDouble();

  factory Book.fromRow(Map<String, Object?> r) => Book(
        r['id'] as int,
        r['title'] as String,
        r['file_path'] as String,
        r['pages'] as int,
        r['per_day'] as int,
        r['position'] as int,
        r['last_page'] as int,
        r['added_at'] as String,
      );
}

class BookLog {
  final String date;
  final int fromPos;
  final int toPos;
  final int readCount;
  final bool done;
  const BookLog(this.date, this.fromPos, this.toPos, this.readCount, this.done);
  int get target => toPos - fromPos + 1;

  factory BookLog.fromRow(Map<String, Object?> r) => BookLog(
        r['date'] as String,
        r['from_pos'] as int,
        r['to_pos'] as int,
        r['read_count'] as int,
        r['done'] == 1,
      );
}

/// المكتبة: كتب PDF يرفعها المستخدم، لكل كتاب ورد يومي بالصفحات.
class Library {
  final Database Function() userDb;
  final SharedPreferences Function() prefs;
  final DateTime Function() clock;
  final VoidCallback changed;
  final Future<void> Function() reschedule;
  Library({
    required this.userDb,
    required this.prefs,
    required this.clock,
    required this.changed,
    required this.reschedule,
  });

  List<Book> books = [];
  final Map<int, List<BookLog>> _logs = {};

  String get _today => dateKey(clock());

  Future<void> load() async {
    books = (await userDb().query('books', orderBy: 'added_at')).map(Book.fromRow).toList();
    _logs.clear();
    for (final r in await userDb().query('book_logs', orderBy: 'date')) {
      final id = r['book_id'] as int;
      _logs.putIfAbsent(id, () => []).add(BookLog.fromRow(r));
    }
    await ensureToday(notify: false);
  }

  Book? byId(int id) => books.where((b) => b.id == id).firstOrNull;
  List<BookLog> logsOf(int id) => _logs[id] ?? const [];

  BookLog? todayOf(int id) {
    for (final l in logsOf(id).reversed) {
      if (l.date == _today) return l;
    }
    return null;
  }

  Future<void> _putLog(int bookId, BookLog l) async {
    await userDb().insert(
      'book_logs',
      {
        'book_id': bookId,
        'date': l.date,
        'from_pos': l.fromPos,
        'to_pos': l.toPos,
        'read_count': l.readCount,
        'done': l.done ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final list = _logs.putIfAbsent(bookId, () => [])..removeWhere((x) => x.date == l.date);
    list
      ..add(l)
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> ensureToday({bool notify = true}) async {
    var added = false;
    for (final b in books) {
      if (b.finished || todayOf(b.id) != null) continue;
      await _putLog(b.id, BookLog(_today, b.position, min(b.position + b.perDay - 1, b.pages), 0, false));
      added = true;
    }
    if (added && notify) changed();
  }

  /// ينسخ ملف PDF إلى مجلد التطبيق ويضيفه للمكتبة.
  Future<Book> addBook(String sourcePath, String title, {int perDay = 10}) async {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'books'));
    await dir.create(recursive: true);
    final dest = p.join(dir.path, 'book_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await File(sourcePath).copy(dest);
    final pages = await countPages(dest);
    final id = await userDb().insert('books', {
      'title': title,
      'file_path': dest,
      'pages': pages,
      'per_day': perDay,
      'position': 1,
      'last_page': 1,
      'added_at': clock().toIso8601String(),
    });
    await load();
    changed();
    return byId(id)!;
  }

  static Future<int> countPages(String path) async {
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openFile(path);
    try {
      return doc.pages.length;
    } finally {
      await doc.dispose();
    }
  }

  /// يربط الكتاب بملف جديد (مثلاً بعد استعادة نسخة احتياطية على هاتف آخر).
  Future<void> relink(Book b, String sourcePath) async {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'books'));
    await dir.create(recursive: true);
    final dest = p.join(dir.path, 'book_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await File(sourcePath).copy(dest);
    final pages = await countPages(dest);
    await userDb().update('books', {'file_path': dest, 'pages': pages}, where: 'id = ?', whereArgs: [b.id]);
    await load();
    changed();
  }

  Future<void> update(Book b, {String? title, int? perDay, int? position}) async {
    await userDb().update(
      'books',
      {'title': ?title, 'per_day': ?perDay, 'position': ?position},
      where: 'id = ?',
      whereArgs: [b.id],
    );
    await load();
    final nb = byId(b.id)!;
    final t = todayOf(b.id);
    if (t != null && !t.done && (perDay != null || position != null)) {
      final from = position ?? t.fromPos;
      await _putLog(b.id, BookLog(t.date, from, min(from + nb.perDay - 1, nb.pages), t.readCount, false));
    }
    changed();
  }

  Future<void> remove(Book b) async {
    await userDb().delete('book_logs', where: 'book_id = ?', whereArgs: [b.id]);
    await userDb().delete('books', where: 'id = ?', whereArgs: [b.id]);
    try {
      final f = File(b.filePath);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
    await load();
    changed();
  }

  /// يُستدعى كلما تغيّرت الصفحة في القارئ. الوصول إلى صفحة بعد الموضع يعني قراءة ما قبلها.
  Future<void> pageViewed(Book b, int page) async {
    final cur = byId(b.id);
    if (cur == null) return;
    final values = <String, Object?>{'last_page': page};
    // نعدّ الصفحة مقروءة حين ينتقل القارئ إلى التي بعدها، أو حين يصل إلى آخر الكتاب.
    final readUpTo = page >= cur.pages ? cur.pages : page - 1;
    var newPos = cur.position;
    if (readUpTo >= cur.position && readUpTo - cur.position < 50) newPos = readUpTo + 1;
    if (newPos != cur.position) values['position'] = newPos;
    await userDb().update('books', values, where: 'id = ?', whereArgs: [b.id]);
    if (newPos != cur.position) {
      await ensureToday(notify: false);
      final t = todayOf(b.id);
      if (t != null) {
        final read = t.readCount + (newPos - cur.position);
        await _putLog(b.id, BookLog(t.date, t.fromPos, t.toPos, read, t.done || newPos > t.toPos));
      }
    }
    books = (await userDb().query('books', orderBy: 'added_at')).map(Book.fromRow).toList();
    if (newPos != cur.position) changed();
  }

  /// «قرأت ورد اليوم» يدوياً، لمن يقرأ من نسخة ورقية.
  Future<void> markTodayDone(Book b) async {
    final t = todayOf(b.id);
    if (t == null) return;
    final newPos = max(b.position, t.toPos + 1);
    await userDb().update('books', {'position': newPos}, where: 'id = ?', whereArgs: [b.id]);
    await _putLog(b.id, BookLog(t.date, t.fromPos, t.toPos, max(t.readCount, t.target), true));
    books = (await userDb().query('books', orderBy: 'added_at')).map(Book.fromRow).toList();
    changed();
  }

  int streakOf(int id) {
    final ok = {for (final l in logsOf(id)) if (l.done) l.date};
    var d = dateOnly(clock());
    if (!ok.contains(dateKey(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (ok.contains(dateKey(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  DateTime? finishDate(Book b) {
    if (b.finished) return null;
    final left = b.pages - b.position + 1;
    return dateOnly(clock()).add(Duration(days: (left / max(1, b.perDay)).ceil() - 1));
  }

  /// طريقة العرض المفضلة لكل كتاب: نص مفرّغ (افتراضياً) أو صور الصفحات.
  bool textMode(int id) => prefs().getBool('book_text_$id') ?? true;
  Future<void> setTextMode(int id, bool v) => prefs().setBool('book_text_$id', v);

  TimeOfDay? get reminder => parseTime(prefs().getString('library_reminder'));

  Future<void> setReminder(TimeOfDay? t) async {
    if (t == null) {
      await prefs().remove('library_reminder');
    } else {
      await prefs().setString('library_reminder', timeKey(t));
      await Reminders.requestPermission();
    }
    changed();
    await reschedule();
  }
}
