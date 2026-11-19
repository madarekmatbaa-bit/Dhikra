import 'package:dhikra/state/quran_review.dart';
import 'package:dhikra/util/ranges.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('قراءة نطاقات الصفحات وكتابتها', () {
    expect(parseRanges('1-3, 7,٩-١٠'), [1, 2, 3, 7, 9, 10]);
    expect(parseRanges('5-3،700'), [3, 4, 5]);
    expect(formatRanges([10, 9, 1, 2, 3, 7]), '1-3,7,9-10');
    expect(parseRanges(formatRanges([582, 583, 604])), [582, 583, 604]);
  });

  test('ورد اليوم يمضي بالترتيب ولا يتجاوز آخر المصحف', () {
    expect(wirdPages(1, 20), [for (var i = 1; i <= 20; i++) i]);
    expect(wirdPages(595, 20), [for (var i = 595; i <= 604; i++) i]);
    expect(wirdPages(604, 10), [604]);
  });

  test('سجل الورد: الصفحات المقروءة والسجلات القديمة', () {
    final l = QuranLog('2026-11-17', wirdPages(21, 10), reached: 25);
    expect(l.readCount, 5);
    final back = QuranLog.fromRow(l.toRow());
    expect(back.pages, l.pages);
    expect(back.reached, 25);
    expect(back.done, false);
    // سجل مراجعة من الإصدارات السابقة
    final old = QuranLog.fromRow({
      'date': '2026-11-01', 'new_pages': '5', 'recent_pages': '1-4', 'old_pages': '100-103',
      'new_done': 1, 'recent_done': 1, 'old_done': 1,
    });
    expect(old.pages, [5, 100, 101, 102, 103]);
    expect(old.complete, true);
  });

  test('نص المصحف مضمّن في التطبيق', () async {
    final data = await rootBundle.load('assets/data/quran.db');
    expect(data.lengthInBytes, greaterThan(1000000));
    final font = await rootBundle.load('assets/fonts/KFGQPC-Hafs-18.ttf');
    expect(font.lengthInBytes, greaterThan(100000));
  });
}
