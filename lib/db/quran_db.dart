import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../util/arabic.dart';

const quranPages = 604;

class Sura {
  final int id;
  final String name;
  final int ayat;
  final int firstPage;
  const Sura(this.id, this.name, this.ayat, this.firstPage);
}

class Aya {
  final int id;
  final int sura;
  final int aya;
  final int page;
  final int juz;
  final String text;
  const Aya(this.id, this.sura, this.aya, this.page, this.juz, this.text);
}

/// نص المصحف من مجمع الملك فهد لطباعة المصحف الشريف (رواية حفص، الإصدار 18).
/// يُنسخ من ملفات التطبيق عند أول تشغيل، وهو للقراءة فقط.
class QuranDb {
  static const _version = 1;
  late final Database _db;
  late final List<Sura> suras;
  late final String source;

  /// أول صفحة في كل جزء، juzStart[0] للجزء الأول.
  late final List<int> juzStart;

  /// نص البسملة كما في أول الفاتحة، دون رقم الآية.
  late final String basmala;

  final _pageCache = <int, List<Aya>>{};

  Future<void> open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'quran_v$_version.db');
    if (!File(path).existsSync()) {
      await Directory(dir).create(recursive: true);
      final data = await rootBundle.load('assets/data/quran.db');
      final tmp = '$path.tmp';
      await File(tmp).writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      await File(tmp).rename(path);
    }
    _db = await openDatabase(path, readOnly: true);
    final rows = await _db.query('suras', orderBy: 'id');
    suras = [
      for (final r in rows) Sura(r['id'] as int, r['name'] as String, r['ayat'] as int, r['first_page'] as int),
    ];
    final j = await _db.rawQuery('SELECT juz, MIN(page) AS p FROM ayat GROUP BY juz ORDER BY juz');
    juzStart = [for (final r in j) r['p'] as int];
    final m = await _db.query('meta', where: 'key = ?', whereArgs: ['source']);
    source = m.isEmpty ? 'مجمع الملك فهد لطباعة المصحف الشريف' : m.first['value'] as String;
    final b = await _db.query('ayat', columns: ['text'], where: 'id = 1');
    basmala = stripNumber(b.first['text'] as String);
  }

  static String stripNumber(String t) => t.replaceFirst(RegExp(r'[  ]*[٠-٩]+$'), '');

  Future<List<Aya>> page(int n) async {
    final c = _pageCache[n];
    if (c != null) return c;
    final rows = await _db.query('ayat', where: 'page = ?', whereArgs: [n], orderBy: 'id');
    final list = [
      for (final r in rows)
        Aya(r['id'] as int, r['sura'] as int, r['aya'] as int, r['page'] as int, r['juz'] as int, r['text'] as String),
    ];
    if (_pageCache.length > 40) _pageCache.clear();
    return _pageCache[n] = list;
  }

  Future<Aya?> aya(int sura, int aya) async {
    final r = await _db.query('ayat', where: 'sura = ? AND aya = ?', whereArgs: [sura, aya]);
    if (r.isEmpty) return null;
    final x = r.first;
    return Aya(x['id'] as int, sura, aya, x['page'] as int, x['juz'] as int, x['text'] as String);
  }

  int juzOfPage(int page) {
    var j = 1;
    for (var i = 0; i < juzStart.length; i++) {
      if (juzStart[i] <= page) j = i + 1;
    }
    return j;
  }

  /// صفحات الجزء [juz] (من 1 إلى 30).
  List<int> juzPages(int juz) {
    final from = juzStart[juz - 1];
    final to = juz == 30 ? quranPages : juzStart[juz] - 1;
    // الجزء قد يبدأ في منتصف صفحة؛ تلك الصفحة تُحسب للجزء الذي تبدأ فيه.
    return [for (var i = from; i <= to; i++) i];
  }

  /// اسم السورة التي تبدأ بها الصفحة أو تقع فيها.
  Sura suraOfPage(int page) {
    var s = suras.first;
    for (final x in suras) {
      if (x.firstPage <= page) s = x;
    }
    return s;
  }

  /// بحث بسيط في النص المجرد من التشكيل.
  Future<List<Aya>> search(String q, {int limit = 60}) async {
    final n = normalizeArabic(q);
    if (n.length < 2) return const [];
    final rows = await _db.query('ayat', where: 'plain LIKE ?', whereArgs: ['%$n%'], limit: limit, orderBy: 'id');
    return [
      for (final r in rows)
        Aya(r['id'] as int, r['sura'] as int, r['aya'] as int, r['page'] as int, r['juz'] as int, r['text'] as String),
    ];
  }
}
