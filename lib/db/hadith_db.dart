import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../util/arabic.dart';

/// كتاب من الكتب الستة.
class HadithCollection {
  final String id;
  final String title;
  final String author;
  final int total;
  const HadithCollection(this.id, this.title, this.author, this.total);
}

/// باب كبير («كتاب») داخل المصنَّف، بمدى أرقام أحاديثه.
class HadithBook {
  final int id;
  final String title;
  final int first;
  final int last;
  const HadithBook(this.id, this.title, this.first, this.last);
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

/// نصوص الكتب الستة، للقراءة فقط، تُنسخ من ملفات التطبيق عند أول تشغيل.
/// النص بحركاته مضغوط بـ zlib، والبحث في النص المجرد.
class HadithDb {
  static const _version = 2;
  late final Database _db;
  late final List<HadithCollection> collections;
  final _books = <String, List<HadithBook>>{};
  final _cache = <int, Hadith>{};
  String _current = 'bukhari';

  Future<void> open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'hadith_v$_version.db');
    if (!File(path).existsSync()) {
      await Directory(dir).create(recursive: true);
      final data = await rootBundle.load('assets/data/hadith.db');
      final tmp = '$path.tmp';
      await File(tmp).writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      await File(tmp).rename(path);
      // نسخة البخاري القديمة لم تعد لازمة.
      final old = File(p.join(dir, 'bukhari_v1.db'));
      if (old.existsSync()) old.deleteSync();
    }
    _db = await openDatabase(path, readOnly: true);
    collections = [
      for (final r in await _db.query('collections', orderBy: 'ord'))
        HadithCollection(r['id'] as String, r['title'] as String, r['author'] as String, r['total'] as int),
    ];
    for (final r in await _db.query('books', orderBy: 'collection, id')) {
      _books
          .putIfAbsent(r['collection'] as String, () => [])
          .add(HadithBook(r['id'] as int, r['title'] as String, r['first'] as int, r['last'] as int));
    }
  }

  String get currentId => _current;
  HadithCollection get current => collection(_current);
  HadithCollection collection(String id) => collections.firstWhere((c) => c.id == id, orElse: () => collections.first);

  /// الكتاب الذي يلي [id] في ترتيب الكتب الستة، أو null إن كان آخرها.
  HadithCollection? nextAfter(String id) {
    final i = collections.indexWhere((c) => c.id == id);
    return i >= 0 && i + 1 < collections.length ? collections[i + 1] : null;
  }

  void select(String id) {
    if (id == _current || !collections.any((c) => c.id == id)) return;
    _current = id;
    _cache.clear();
  }

  int get total => current.total;
  List<HadithBook> get books => _books[_current] ?? const [];

  HadithBook bookOf(int number) {
    for (final b in books) {
      if (number >= b.first && number <= b.last) return b;
    }
    return books.last;
  }

  HadithBook bookById(int id) => books.firstWhere((b) => b.id == id);

  Future<Hadith> hadith(int number) async {
    final c = _cache[number];
    if (c != null) return c;
    final rows = await _db.query(
      'hadiths',
      columns: ['number', 'book_id', 'text', 'merged_into'],
      where: 'collection = ? AND number = ?',
      whereArgs: [_current, number],
    );
    final r = rows.first;
    final text = _inflate(r['text']);
    final h = Hadith(r['number'] as int, r['book_id'] as int, text, r['merged_into'] as int?);
    if (_cache.length > 200) _cache.clear();
    _cache[number] = h;
    return h;
  }

  static String _inflate(Object? blob) {
    if (blob is String) return blob;
    final bytes = blob as List<int>;
    return utf8.decode(zlib.decode(bytes));
  }

  /// أول سطر من كل حديث في نطاق، لعرض قائمة الكتاب.
  Future<List<(int, String)>> previews(int from, int to) async {
    final rows = await _db.rawQuery(
      'SELECT number, substr(text_plain, 1, 140) AS s, merged_into FROM hadiths '
      'WHERE collection = ? AND number BETWEEN ? AND ? ORDER BY number',
      [_current, from, to],
    );
    return [
      for (final r in rows)
        (r['number'] as int, r['merged_into'] != null ? 'مدمج مع الحديث ${r['merged_into']}' : r['s'] as String),
    ];
  }

  /// بحث في الكتاب الحالي يتجاهل الحركات والهمزات.
  Future<List<SearchHit>> search(String query, {int limit = 150}) async {
    final q = normalizeArabic(query);
    if (q.length < 2) return [];
    final escaped = q.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
    final rows = await _db.rawQuery(
      "SELECT number, book_id, text_plain FROM hadiths WHERE collection = ? AND text_plain LIKE ? ESCAPE '\\' "
      'ORDER BY number LIMIT ?',
      [_current, '%$escaped%', limit],
    );
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
