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
    // آخر كلمة في العبارة تُعلَّق حتى يسكت القارئ أو يكمل بغيرها.
    expect(t.mistakes, isEmpty);
    expect(t.confirmTentative(), 1);
    expect(t.mistakes, {k});
    t.dismiss(k);
    expect(t.mistakes, isEmpty);
    expect(t.positionOf(t.displayKey(k)), k);
  });

  test('كلمة قُطع الصوت في وسطها ليست خطأً', () {
    final t = tracker();
    say(t, 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ الْحَمْدُ لِلَّهِ رَبِّ الْعَا');
    expect(t.tentative, isNotEmpty);
    say(t, 'لَمِينَ الرَّحْمَنِ الرَّحِيمِ');
    expect(t.tentative, isEmpty);
    expect(t.mistakes, isEmpty);
    expect(t.lateConfirmed, 0);
    expect(t.currentKey, 4);
  });

  test('كلمة مبدلة في آخر العبارة تتأكد حين يكمل القارئ بما بعدها', () {
    final t = tracker();
    say(t, 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ الْحَمْدُ لِلَّهِ رَبِّ النَّاسِ');
    expect(t.mistakes, isEmpty);
    say(t, 'الرَّحْمَنِ الرَّحِيمِ مَالِكِ يَوْمِ الدِّينِ');
    expect(t.lateConfirmed, 1);
    expect([for (final k in t.mistakes) t.voweledAt(k)], ['الْعَالَمِينَ']);
  });

  test('كلمة مبدلة في وسط العبارة يُعرف ما قيل مكانها', () {
    final t = tracker();
    say(t, 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ الشُّكْرُ لِلَّهِ رَبِّ الْعَالَمِينَ الرَّحْمَنِ');
    final k = t.mistakes.single;
    expect(t.voweledAt(k), 'الْحَمْدُ');
    expect(t.why[k]!.kind, MistakeKind.substituted);
    expect(t.why[k]!.heard, 'الشُّكْرُ');
    expect(t.correctedPhrase(k), contains('الرَّحِيمِ الْحَمْدُ لِلَّهِ'));
  });

  test('إعادة العبارة لا تُعدّ قفزاً إلى ما بعدها', () {
    final t = RecitationTracker([
      RecitedSegment(1, 'فَلَا تَقُلْ لَهُمَا أُفٍّ وَلَا تَنْهَرْهُمَا وَقُلْ لَهُمَا قَوْلًا كَرِيمًا'),
    ])..wholePhrases = true;
    say(t, 'فَلَا تَقُلْ لَهُمَا أُفٍّ');
    say(t, 'فَلَا تَقُلْ لَهُمَا أُفٍّ وَلَا تَنْهَرْهُمَا وَقُلْ لَهُمَا قَوْلًا كَرِيمًا');
    expect(t.mistakes, isEmpty);
    expect(t.finished, isTrue);
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
