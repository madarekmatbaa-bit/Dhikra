import 'package:dhikra/util/recitation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // الفاتحة بالنص المشكول كما يكتبه نموذج التلاوة.
  const ayat = [
    (1, 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ'),
    (2, 'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ'),
    (3, 'الرَّحْمَنِ الرَّحِيمِ'),
    (4, 'مَالِكِ يَوْمِ الدِّينِ'),
  ];
  RecitationTracker tracker({bool harakat = false}) =>
      RecitationTracker([for (final (id, t) in ayat) RecitedSegment(id, t)])
        ..wholePhrases = true
        ..harakat = harakat;

  void say(RecitationTracker t, String text) {
    final (words, raw) = pairWords(text);
    t.beginPhrase();
    t.replayFinal([words], raw: raw);
  }

  test('الكلمات المطبّعة تقابل الكلمات المشكولة', () {
    final (n, r) = pairWords('يَا أَيُّهَا النَّاسُ');
    expect(n, ['يا', 'ايها', 'الناس']);
    expect(r, ['يَا', 'أَيُّهَا', 'النَّاسُ']);
    expect(RecitedSegment(1, 'الْحَمْدُ لِلَّهِ').voweled, ['الْحَمْدُ', 'لِلَّهِ']);
  });

  test('الحركة المختلفة تُعرف ولا يُحكم بحركة آخر الكلمة', () {
    expect(harakatDiffer('الْحَمْدَ', 'الْحَمْدُ'), isFalse); // آخر الكلمة: وقف أو إعراب
    expect(harakatDiffer('الْحِمْدُ', 'الْحَمْدُ'), isTrue);
    expect(harakatDiffer('رُبِّ', 'رَبِّ'), isTrue);
    expect(harakatDiffer('الحمد', 'الْحَمْدُ'), isFalse); // بلا حركات: لا نحكم
    expect(harakatDiffer('الشكر', 'الْحَمْدُ'), isFalse); // كلمة أخرى، لا حركة
  });

  test('الوضع العادي لا يعدّ الحركات، وضبط الحركات يعدّها ويشرحها', () {
    const wrong = 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ الْحِمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ';
    final normal = tracker();
    say(normal, wrong);
    expect(normal.mistakes, isEmpty);

    final strict = tracker(harakat: true);
    say(strict, wrong);
    expect(strict.mistakes, {4});
    expect(strict.why[4]!.kind, MistakeKind.harakat);
    expect(explainMistake(strict.why[4], strict.voweledAt(4)), contains('بحركة مختلفة'));
    expect(strict.correctedPhrase(4), contains('الْحَمْدُ لِلَّهِ'));
  });

  test('الكلمة المبدلة يُشرح ما سُمع مكانها، والنص المصحَّح يضعها مكانه', () {
    final t = tracker();
    say(t, 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ');
    say(t, 'الرَّحْمَنِ الرَّحِيمِ مَالِكِ يَوْمِ الْحِسَابِ');
    final k = t.phraseMistakes.single;
    expect(t.voweledAt(k), 'الدِّينِ');
    expect(t.why[k]!.kind, MistakeKind.substituted);
    expect(explainMistake(t.why[k], t.voweledAt(k)), 'سُمعت «الْحِسَابِ» مكان «الدِّينِ».');
    expect(t.correctedPhrase(k), 'الرَّحْمَنِ الرَّحِيمِ مَالِكِ يَوْمِ الدِّينِ');
    t.dismiss(k);
    expect(t.mistakes, isEmpty);
    expect(t.positionOf(t.displayKey(k)), k);
  });

  test('الكلمة الساقطة تُدرج في النص المصحَّح', () {
    final t = tracker();
    say(t, 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ');
    say(t, 'الرَّحْمَنِ مَالِكِ يَوْمِ الدِّينِ');
    final k = t.phraseMistakes.single;
    expect(t.why[k]!.kind, MistakeKind.skipped);
    expect(t.correctedPhrase(k), 'الرَّحْمَنِ الرَّحِيمِ مَالِكِ يَوْمِ الدِّينِ');
  });
}
