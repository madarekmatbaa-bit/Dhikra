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

  test('الجديد يتخطى المحفوظ ويمضي في اتجاه الحفظ', () {
    final d = computeDay(const ReviewConfig(memorized: [1, 2, 3], newNext: 2, newPerDay: 2));
    expect(d.newPages, [4, 5]);
    final back = computeDay(const ReviewConfig(memorized: [604], newNext: 604, newPerDay: 1, descending: true));
    expect(back.newPages, [603]);
  });

  test('القريب آخر ما حُفظ، والبعيد يدور على الباقي', () {
    final mem = [for (var i = 1; i <= 100; i++) i];
    final c = ReviewConfig(
      memorized: mem,
      recentOrder: [for (var i = 81; i <= 100; i++) i],
      recentCount: 20,
      cycleDays: 10,
      oldNext: 75,
      newPerDay: 0,
    );
    final d = computeDay(c);
    expect(d.newPages, isEmpty);
    expect(d.recent, [for (var i = 81; i <= 100; i++) i]);
    // 80 صفحة قديمة على 10 أيام = 8 في اليوم، تبدأ من 75 وتلتف إلى البداية.
    expect(d.old, [1, 2, 75, 76, 77, 78, 79, 80]);
  });

  test('نص المصحف مضمّن في التطبيق', () async {
    final data = await rootBundle.load('assets/data/quran.db');
    expect(data.lengthInBytes, greaterThan(1000000));
    final font = await rootBundle.load('assets/fonts/KFGQPC-Hafs-18.ttf');
    expect(font.lengthInBytes, greaterThan(100000));
  });
}
