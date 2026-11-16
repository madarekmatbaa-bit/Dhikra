import 'package:dhikra/util/recitation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RecitationTracker fatiha() => RecitationTracker([
    RecitedSegment(1, 'بسم الله الرحمن الرحيم'),
    RecitedSegment(2, 'الحمد لله رب العالمين'),
    RecitedSegment(3, 'الرحمن الرحيم'),
    RecitedSegment(4, 'مالك يوم الدين'),
    RecitedSegment(5, 'اياك نعبد واياك نستعين'),
    RecitedSegment(6, 'اهدنا الصراط المستقيم'),
    RecitedSegment(7, 'صراط الذين انعمت عليهم غير المغضوب عليهم ولا الضالين'),
  ]);

  test('يتابع القارئ كلمة كلمة', () {
    final t = fatiha();
    expect(t.currentKey, 1);
    var used = t.feed(recitationWords('بسم الله الرحمن الرحيم الحمد'), 0);
    expect(t.currentKey, 2);
    used = t.feed(recitationWords('بسم الله الرحمن الرحيم الحمد لله رب العالمين'), used);
    expect(t.currentKey, 3);
  });

  test('يتسامح مع اختلاف الإملاء والهمزات', () {
    final t = fatiha()..startAt(5);
    t.feed(recitationWords('إيّاكَ نعبد وإياك نستعين اهدنا'), 0);
    expect(t.currentKey, 6);
  });

  test('يقفز إن تخطى القارئ آيات، ولا يقفز بكلمة واحدة', () {
    final t = fatiha();
    t.feed(recitationWords('مالك'), 0);
    expect(t.currentKey, 1); // كلمة واحدة لا تكفي للقفز
    t.feed(recitationWords('مالك يوم الدين'), 0);
    expect(t.currentKey, 5);
  });

  test('ينتهي عند آخر الصفحة', () {
    final t = fatiha()..startAt(7);
    t.feed(recitationWords('صراط الذين أنعمت عليهم غير المغضوب عليهم ولا الضالين'), 0);
    expect(t.finished, isTrue);
  });

  test('تطابق الكلمات المتقاربة', () {
    expect(similarWord('العالمين', 'العلمين'), isTrue);
    expect(similarWord('والله', 'الله'), isTrue);
    expect(similarWord('من', 'ما'), isFalse);
  });
}
