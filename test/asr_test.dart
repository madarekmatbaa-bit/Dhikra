import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dhikra/util/quran_locator.dart';
import 'package:dhikra/util/recitation.dart';
import 'package:dhikra/util/speech_segmenter.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List tone(double secs, {double amp = 0.2}) {
  final n = (secs * 16000).round();
  return Float32List.fromList([for (var i = 0; i < n; i++) amp * math.sin(i * 2 * math.pi * 220 / 16000)]);
}

Float32List quiet(double secs) {
  final r = math.Random(1);
  return Float32List.fromList([for (var i = 0; i < (secs * 16000).round(); i++) (r.nextDouble() - 0.5) * 0.002]);
}

const fatiha = [
  (1, 1, 'بسم الله الرحمن الرحيم'),
  (2, 1, 'الحمد لله رب العالمين'),
  (3, 1, 'الرحمن الرحيم'),
  (4, 1, 'مالك يوم الدين'),
  (5, 1, 'اياك نعبد واياك نستعين'),
  (6, 1, 'اهدنا الصراط المستقيم'),
  (7, 1, 'صراط الذين انعمت عليهم غير المغضوب عليهم ولا الضالين'),
];
const ikhlas = [
  (6222, 604, 'قل هو الله احد'),
  (6223, 604, 'الله الصمد'),
  (6224, 604, 'لم يلد ولم يولد'),
  (6225, 604, 'ولم يكن له كفوا احد'),
];

List<String> w(String s) => recitationWords(s);

void main() {
  group('تقطيع الصوت', () {
    test('عبارتان بينهما وقفة', () {
      final out = <(int, bool)>[];
      final seg = SpeechSegmenter(onPhrase: (s, f) => out.add((s.length, f)));
      for (final part in [quiet(1), tone(3), quiet(0.8), tone(2), quiet(1)]) {
        seg.addSamples(part);
      }
      final finals = out.where((e) => e.$2).toList();
      expect(finals.length, 2);
      expect(finals.first.$1 / 16000, closeTo(3.4, 0.5));
      expect(out.any((e) => !e.$2), isTrue, reason: 'نتيجة جزئية أثناء العبارة الأولى');
    });

    test('نقرة قصيرة ليست عبارة', () {
      final out = <bool>[];
      final seg = SpeechSegmenter(onPhrase: (s, f) => out.add(f));
      for (final part in [quiet(1), tone(0.15), quiet(1)]) {
        seg.addSamples(part);
      }
      expect(out, isEmpty);
    });

    test('قراءة متصلة بلا وقف تُقطع قبل عشرين ثانية', () {
      final out = <int>[];
      final seg = SpeechSegmenter(onPhrase: (s, f) {
        if (f) out.add(s.length);
      });
      seg.addSamples(quiet(0.5));
      seg.addSamples(tone(30));
      seg.flush();
      expect(out.length, greaterThanOrEqualTo(2));
      expect(out.every((n) => n <= 20.5 * 16000), isTrue);
    });
  });

  group('معرفة الموضع', () {
    final loc = QuranLocator([...fatiha, ...ikhlas]);

    test('من أول كلمات آية', () {
      final r = loc.locate(w('الحمد لله رب العالمين'))!;
      expect(r.startAya, 2);
      expect(r.endAya, 3);
      expect(r.nextWord, 0);
    });

    test('في وسط آية مع كلمة لم تُسمع جيداً', () {
      final r = loc.locate(w('قل هو الله احد الله الصمد لم'))!;
      expect(r.page, 604);
      expect(r.endAya, 6224);
      expect(r.nextWord, 1);
    });

    test('كلمتان لا تكفيان', () {
      expect(loc.locate(w('الله الصمد')), isNull);
    });
  });

  group('الحكم على العبارات الكاملة', () {
    RecitationTracker tracker() =>
        RecitationTracker([for (final (id, _, t) in fatiha) RecitedSegment(id, t)])..wholePhrases = true;

    test('تلاوة صحيحة بلا أخطاء', () {
      final t = tracker();
      for (final p in ['بسم الله الرحمن الرحيم الحمد لله رب العالمين', 'الرحمن الرحيم مالك يوم الدين']) {
        t.beginPhrase();
        t.replayFinal([w(p)]);
      }
      expect(t.mistakes, isEmpty);
      expect(t.currentKey, 5);
    });

    test('آخر كلمة في الآية مبدلة ثم وقف', () {
      final t = tracker()..startAt(4);
      t.beginPhrase();
      t.replayFinal([w('مالك يوم القيامه')]);
      expect(t.mistakes, isEmpty, reason: 'تُعلَّق حتى يسكت القارئ');
      expect(t.confirmTentative(), 1);
      expect(t.mistakeWords.single.$2, 'الدين');
      expect(t.currentKey, 5, reason: 'لا تعلق المتابعة عند الكلمة المبدلة');
    });

    test('كلمة متخطاة في أول العبارة التالية', () {
      final t = tracker()..startAt(5);
      t.beginPhrase();
      t.replayFinal([w('اياك نعبد واياك نستعين')]);
      t.beginPhrase();
      t.replayFinal([w('الصراط المستقيم')]);
      expect(t.mistakeWords.map((m) => m.$2), ['اهدنا']);
    });
  });
}
