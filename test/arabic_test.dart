import 'package:dhikra/state/app_state.dart';
import 'package:dhikra/util/arabic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeArabic يتجاهل الحركات والهمزات', () {
    expect(normalizeArabic('إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ'), 'انما الاعمال بالنيات');
    expect(normalizeArabic('مُوسَى وَفَاطِمَةُ'), 'موسي وفاطمه');
  });

  test('dateKey و parseKey متعاكسان', () {
    final d = DateTime(2026, 3, 7);
    expect(dateKey(d), '2026-03-07');
    expect(parseKey(dateKey(d)), d);
  });

  test('الأسبوع يبدأ من السبت', () {
    expect(AppState.weekStart(DateTime(2026, 10, 24)), DateTime(2026, 10, 24)); // سبت
    expect(AppState.weekStart(DateTime(2026, 10, 30)), DateTime(2026, 10, 24)); // جمعة
    expect(AppState.weekStart(DateTime(2026, 10, 31)), DateTime(2026, 10, 31));
  });

  test('صيغ العدد', () {
    expect(daysWord(1), 'يوم واحد');
    expect(daysWord(5), '5 أيام');
    expect(daysWord(12), '12 يوماً');
    expect(roughDuration(757), 'حوالي سنتين وشهر');
  });
}
