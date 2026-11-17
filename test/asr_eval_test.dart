// ignore_for_file: avoid_print
// تقييم واسع لمتابعة التلاوة على تسجيلات قرّاء كثيرين، يعمل في GitHub Actions فقط
// (asr-eval.yml) حين يُعيَّن ASR_EVAL. لكل آية ثلاث حالات:
// - صحيحة: النص المنتظر هو ما قُرئ، فكل خطأ يُعدّ خطأً كاذباً.
// - مبدلة: تُبدل كلمة في النص المنتظر بكلمة من آية أخرى، فيصير المقروء كلمة مختلفة عن المكتوب.
// - ساقطة: تُدرج في النص المنتظر كلمة لم تُقرأ، فكأن القارئ أسقطها.
// ويُكتب لكل خطأ مرشّح فرقُ الاحتمال (Δ) ليُختار به حدّ التحقق.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dhikra/services/quran_asr.dart';
import 'package:dhikra/util/recitation.dart';
import 'package:dhikra/util/speech_segmenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dir = Platform.environment['ASR_EVAL'];
  test('تقييم التسميع على تلاوات كثيرة', () async {
    final env = Platform.environment;
    setAsrLibraryPath(env['ASR_LIB']!);
    final vow = <int, String>{};
    for (final l in File(env['VOWELED']!).readAsLinesSync()) {
      final p = l.split('\t');
      vow[int.parse(p[0])] = p[1];
    }
    final ids = vow.keys.toList()..sort();
    final e = WhisperEngine();
    expect(await e.load(env['MODEL']!), isTrue);
    final out = File(env['OUT'] ?? 'eval.csv').openWrite()
      ..writeln('reciter,aya,cond,truth,kind,delta,heard,want');
    final files = Directory(dir!).listSync().whereType<File>().where((f) => f.path.endsWith('.wav')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    var n = 0, words = 0, audio = 0.0;
    final sw = Stopwatch()..start();
    for (final f in files) {
      final name = f.uri.pathSegments.last.replaceAll('.wav', '');
      final dash = name.lastIndexOf('-');
      final reciter = name.substring(0, dash);
      final code = name.substring(dash + 1);
      final id = _ayaId(int.parse(code.substring(0, 3)), int.parse(code.substring(3)));
      final text = vow[id];
      if (text == null) continue;
      final rnd = Random(id * 31 + reciter.hashCode);
      final raw = text.split(' ');

      // الحالات: النص المنتظر للآية، وموضع الخطأ الحقيقي فيه (كلمة إملائية).
      final conds = <String, (String, int?)>{'ok': (text, null)};
      final cand = [for (var i = 1; i < raw.length - 1; i++) if (recitationWords(raw[i]).join().length >= 3) i];
      if (cand.isNotEmpty) {
        final at = cand[rnd.nextInt(cand.length)];
        final other = _otherWord(vow, ids, rnd, recitationWords(raw[at]).join());
        final sub = [...raw]..[at] = other;
        conds['sub'] = (sub.join(' '), _normIndex(sub, at));
        final ins = [...raw]..insert(at, _otherWord(vow, ids, rnd, recitationWords(raw[at]).join()));
        conds['skip'] = (ins.join(' '), _normIndex(ins, at));
      }
      final trackers = <String, RecitationTracker>{};
      final offset = <String, int>{};
      for (final MapEntry(key: c, value: (t, _)) in conds.entries) {
        final segs = [
          if (vow[id - 1] != null) RecitedSegment(id - 1, vow[id - 1]!),
          RecitedSegment(id, t),
          if (vow[id + 1] != null) RecitedSegment(id + 1, vow[id + 1]!),
        ];
        trackers[c] = RecitationTracker(segs)
          ..wholePhrases = true
          ..startAt(id);
        offset[c] = vow[id - 1] == null ? 0 : segs.first.words.length;
      }

      final phrases = <Float32List>[];
      final seg = SpeechSegmenter(onPhrase: (s, fin) {
        if (fin) phrases.add(s);
      });
      final b = f.readAsBytesSync();
      seg.addSamples(Float32List(8000));
      seg.addPcm16(Uint8List.sublistView(b, 44));
      seg.addSamples(Float32List(16000));
      seg.flush();
      audio += (b.length - 44) / 32000;

      for (final p in phrases) {
        final heard = await e.transcribe(p) ?? '';
        final judge = PhraseJudge(heard, e.score);
        final hyp = await e.score(heard);
        for (final MapEntry(key: c, value: t) in trackers.entries) {
          t.beginPhrase();
          t.replayFinal([recitationWords(heard)], raw: judge.raw);
          for (final k in t.phraseMistakes) {
            final corrected = t.correctedPhrase(k);
            final cs = corrected == null ? null : await e.score(corrected);
            final delta = cs == null || cs > 0 || hyp > 0 ? 999.0 : hyp - cs;
            final want = conds[c]!.$2;
            final truth = want != null && k == offset[c]! + want;
            final w = t.why[k];
            out.writeln([
              reciter, id, c, truth ? 1 : 0, w?.kind.name ?? '-', delta.toStringAsFixed(2),
              _csv(w?.heard ?? ''), _csv(t.voweledAt(k)),
            ].join(','));
          }
        }
      }
      for (final c in conds.keys) {
        out.writeln('#case,$c,$id,${trackers[c]!.pos >= offset[c]! + RecitedSegment(id, conds[c]!.$1).words.length ? 1 : 0}');
      }
      words += raw.length;
      n++;
      if (n % 25 == 0) {
        print('$n/${files.length} آيات، ${audio.toStringAsFixed(0)}s صوت في ${sw.elapsed.inSeconds}s');
      }
    }
    // الحالات التي فيها خطأ حقيقي: يُكتب عددها ليُحسب منه الالتقاط.
    out.writeln('#total,$n,$words');
    await out.close();
    print('انتهى: $n آية، $words كلمة، ${audio.toStringAsFixed(0)}s صوت في ${sw.elapsed.inSeconds}s');
  }, skip: dir == null ? 'يعمل في asr-eval.yml فقط' : false, timeout: const Timeout(Duration(hours: 5)));
}

String _csv(String s) => s.replaceAll(',', ' ');

/// رقم أول كلمة إملائية للكلمة المكتوبة [at].
int _normIndex(List<String> raw, int at) => recitationWords(raw.take(at).join(' ')).length;

/// كلمة من آية أخرى، طويلة بما يكفي، لا تشبه الكلمة [not].
String _otherWord(Map<int, String> vow, List<int> ids, Random rnd, String not) {
  while (true) {
    final w = vow[ids[rnd.nextInt(ids.length)]]!.split(' ');
    final c = w[rnd.nextInt(w.length)];
    final norm = recitationWords(c).join();
    if (norm.length >= 3 && recitationWords(c).length == 1 && !similarWord(norm, not)) return c;
  }
}

const _ayatPerSura = [
  7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135, 112, 78, 118, 64, 77,
  227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60, 49, 62, 55,
  78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36,
  25, 22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
];

int _ayaId(int sura, int aya) {
  var id = 0;
  for (var s = 1; s < sura; s++) {
    id += _ayatPerSura[s - 1];
  }
  return id + aya;
}
