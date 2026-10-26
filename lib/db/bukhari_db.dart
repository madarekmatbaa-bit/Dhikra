import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../util/arabic.dart';

const totalHadiths = 7563;

class BukhariBook {
  final int id;
  final String title;
  final int first;
  final int last;
  const BukhariBook(this.id, this.title, this.first, this.last);
  int get count => last - first + 1;
}

class Hadith {
  final int number;
  final int bookId;
  final String text;
  final int? mergedInto;
  const Hadith(this.number, this.bookId, this.text, this.mergedInto);
}

class SearchHit {
  final int number;
  final int bookId;
  final String snippet;
  const SearchHit(this.number, this.bookId, this.snippet);
}

/// نص صحيح البخاري، للقراءة فقط، يُنسخ من ملفات التطبيق عند أول تشغيل.
class BukhariDb {
  static const _version = 1;
  late final Database _db;
  late final List<BukhariBook> books;
  final _cache = <int, Hadith>{};

  Future<void> open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'bukhari_v$_version.db');
    if (!File(path).existsSync()) {
      await Directory(dir).create(recursive: true);
      final data = await rootBundle.load('assets/data/bukhari.db');
      final tmp = '$path.tmp';
      await File(tmp).writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      await File(tmp).rename(path);
    }
    _db = await openDatabase(path, readOnly: true);
    final rows = await _db.query('books', orderBy: 'id');
    books = [
      for (final r in rows) BukhariBook(r['id'] as int, r['title'] as String, r['first'] as int, r['last'] as int),
    ];
  }

  BukhariBook bookOf(int number) {
    for (final b in books) {
      if (number >= b.first && number <= b.last) return b;
    }
    return books.last;
  }

  BukhariBook bookById(int id) => books.firstWhere((b) => b.id == id);

  Future<Hadith> hadith(int number) async {
    final c = _cache[number];
    if (c != null) return c;
    final rows = await _db.query('hadiths',
        columns: ['number', 'book_id', 'text', 'merged_into'], where: 'number = ?', whereArgs: [number]);
    final r = rows.first;
    final h = Hadith(r['number'] as int, r['book_id'] as int, r['text'] as String, r['merged_into'] as int?);
    if (_cache.length > 200) _cache.clear();
    _cache[number] = h;
    return h;
  }

  /// أول سطر من كل حديث في نطاق، لعرض قائمة الكتاب.
  Future<List<(int, String)>> previews(int from, int to) async {
    final rows = await _db.rawQuery(
        'SELECT number, substr(text_plain, 1, 140) AS s, merged_into FROM hadiths WHERE number BETWEEN ? AND ? ORDER BY number',
        [from, to]);
    return [
      for (final r in rows)
        (r['number'] as int, r['merged_into'] != null ? 'مدمج مع الحديث ${r['merged_into']}' : r['s'] as String),
    ];
  }

  /// بحث يتجاهل الحركات والهمزات.
  Future<List<SearchHit>> search(String query, {int limit = 150}) async {
    final q = normalizeArabic(query);
    if (q.length < 2) return [];
    final escaped = q.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
    final rows = await _db.rawQuery(
        "SELECT number, book_id, text_plain FROM hadiths WHERE text_plain LIKE ? ESCAPE '\\' ORDER BY number LIMIT ?",
        ['%$escaped%', limit]);
    return [
      for (final r in rows) SearchHit(r['number'] as int, r['book_id'] as int, _snippet(r['text_plain'] as String, q)),
    ];
  }

  static String _snippet(String text, String q) {
    final i = text.indexOf(q);
    if (i < 0) return text.length > 120 ? '${text.substring(0, 120)}…' : text;
    final start = (i - 50).clamp(0, text.length);
    final end = (i + q.length + 70).clamp(0, text.length);
    return '${start > 0 ? '…' : ''}${text.substring(start, end)}${end < text.length ? '…' : ''}';
  }
}
