// ignore_for_file: avoid_print
// تقييم متابعة التلاوة بالأصوات على تسجيلات كثيرة. يعمل حين يُعيَّن PHON_EVAL (مجلد فيه
// لكل تسجيل ملف ‎.top‎ كما يكتبه tools/phon_eval/phon_dump.py).
// لكل آية حالات: صحيحة (كل خطأ كاذب)، وكلمة مبدلة، وكلمة ساقطة، وحرف مبدل، وحركة مبدلة،
// تُحقن في النص المنتظر فيصير المقروء مخالفاً له في موضع معلوم.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dhikra/util/phoneme_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dir = Platform.environment['PHON_EVAL'];
  test('تقييم المتابعة بالأصوات', () async {
    final env = Platform.environment;
    final tokens = PhonemeTokens.parse(File(env['PHON_TOKENS'] ?? 'assets/data/phoneme_tokens.txt').readAsStringSync());
    final text = <int, String>{}, phon = <int, List<String>>{}, ids = <String, int>{};
    for (final l in File(env['PHON_TSV']!).readAsLinesSync()) {
      final p = l.split('\t');
      final id = int.parse(p[0]);
      ids['${p[1]}:${p[2]}'] = id;
      text[id] = p[3];
      phon[id] = p[4].split(' ');
    }
    final all = phon.keys.toList()..sort();
    final only = env['PHON_ONLY'];
    final verbose = env['PHON_VERBOSE'] != null;
    final files = Directory(dir!).listSync().whereType<File>().where((f) => f.path.endsWith('.top')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final out = File(env['OUT'] ?? 'phon-eval.csv').openWrite()..writeln('reciter,aya,cond,truth,kind,heard,want');
    final tot = <String, List<int>>{}; // الحالة ← [حالات، التُقط، كاذب]
    var n = 0, wordsN = 0;
    final sw = Stopwatch()..start();
    for (final f in files) {
      final name = f.uri.pathSegments.last.replaceAll('.top', '');
      if (only != null && !name.contains(only)) continue;
      final dash = name.lastIndexOf('-');
      final reciter = name.substring(0, dash);
      final code = name.substring(dash + 1);
      final id = ids['${int.parse(code.substring(0, 3))}:${int.parse(code.substring(3))}'];
      if (id == null) continue;
      final rnd = Random(id * 31 + reciter.length);
      final disp = text[id]!.split(' ');
      final ph = phon[id]!;
      List<PhonWord> seg(int a, [List<String>? p]) => [
            for (var k = 0; k < (p ?? phon[a]!).length; k++)
              PhonWord(a, k, k < text[a]!.split(' ').length ? text[a]!.split(' ')[k] : '?', (p ?? phon[a]!)[k]),
          ];
      String other(String not) {
        while (true) {
          final w = phon[all[rnd.nextInt(all.length)]]!;
          final c = w[rnd.nextInt(w.length)];
          final a = normalizePhonemes(c), b = normalizePhonemes(not);
          if (a.length >= 5 && (a.length - b.length).abs() <= 3 && a.first != b.first && a[2] != b[2]) return c;
        }
      }

      // الحالات: كلمات الآية المنتظرة (قد تزيد كلمة)، وموضع الخطأ فيها.
      final conds = <String, (List<PhonWord>, int?)>{'ok': (seg(id), null)};
      final cand = [for (var i = 1; i < ph.length - 1; i++) if (normalizePhonemes(ph[i]).length >= 5) i];
      if (cand.isNotEmpty) {
        final at = cand[rnd.nextInt(cand.length)];
        conds['sub'] = (seg(id, [...ph]..[at] = other(ph[at])), at);
        final ins = [...ph]..insert(at, other(ph[at]));
        conds['skip'] = (
          [for (var k = 0; k < ins.length; k++) PhonWord(id, k, k == at ? '?' : disp[k > at ? k - 1 : k], ins[k])],
          at
        );
        // حرف مبدل: أول حرف صامت في الكلمة يصير حرفاً بعيداً عنه.
        const far = ['ب', 'ك', 'ف', 'ر', 'ع', 'ج', 'ش', 'ن', 'ل', 'م'];
        final w = ph[at];
        final first = w[0];
        final repl = far.where((c) => c != first && !PhonemeTracker.softPair(c.runes.first, first.runes.first)).toList();
        final c = repl[rnd.nextInt(repl.length)];
        var k = 0;
        while (k < w.length && w[k] == first) {
          k++;
        }
        conds['letter'] = (seg(id, [...ph]..[at] = c * k + w.substring(k)), at);
        // حركة مبدلة: أول حركة قصيرة في وسط الكلمة.
        final m = RegExp('[َُِ]').firstMatch(w);
        if (m != null && m.start < w.length - 2) {
          final v = (['َ', 'ُ', 'ِ']..remove(m[0]))[rnd.nextInt(2)];
          conds['vowel'] = (seg(id, [...ph]..[at] = w.replaceRange(m.start, m.end, v)), at);
        }
      }
      final bytes = f.readAsBytesSync();
      final frames = bytes.length ~/ 15;
      final topIds = Uint8List(frames * 3);
      final topP = Float32List(frames * 3);
      final bd = ByteData.sublistView(bytes);
      for (var i = 0; i < frames; i++) {
        for (var k = 0; k < 3; k++) {
          topIds[i * 3 + k] = bytes[i * 15 + k];
          topP[i * 3 + k] = bd.getFloat32(i * 15 + 3 + k * 4, Endian.little);
        }
      }
      for (final MapEntry(key: c, value: (mid, want)) in conds.entries) {
        final before = text[id - 1] != null ? seg(id - 1) : <PhonWord>[];
        final after = text[id + 1] != null ? seg(id + 1) : <PhonWord>[];
        final t = PhonemeTracker(tokens, [...before, ...mid, ...after])..startAtWord(id, 0);
        if (verbose && c == 'ok') t.debug = [];
        for (var i = 0; i < frames; i += 12) {
          final k = min(12, frames - i);
          t.addTop(Uint8List.sublistView(topIds, i * 3, (i + k) * 3), Float32List.sublistView(topP, i * 3, (i + k) * 3), k);
        }
        t.finish();
        final r = tot.putIfAbsent(c, () => [0, 0, 0, 0]);
        r[0]++;
        var hit = false;
        for (final w in t.mistakes) {
          final truth = want != null && w == before.length + want;
          if (truth) hit = true;
          if (!truth) r[2]++;
          final i = t.why[w]!;
          out.writeln([reciter, id, c, truth ? 1 : 0, i.kind.name, i.heard ?? '', phonemesToText(t.words[w].ph)].join(','));
          if (verbose && !truth && c == 'ok') {
            print('$name $c كاذب: ${i.kind.name} سُمع «${i.heard}» والمنتظر «${phonemesToText(t.words[w].ph)}» (${t.words[w].text})');
          }
        }
        if (hit) r[1]++;
        if (verbose && c == 'ok' && t.mistakes.isNotEmpty) {
          for (final w in t.mistakes) {
            print('   ${t.debug!.where((d) => d.startsWith('$w ')).toSet().join(' | ')}');
          }
        }
        if (want != null && !hit && verbose) print('$name $c فات: «${phonemesToText(mid[want].ph)}»');
        // هل بلغ آخر الآية؟
        if (t.pos >= before.length + mid.length - 1) r[3]++;
        if (c == 'ok') wordsN += mid.length;
      }
      n++;
    }
    await out.close();
    print('$n آية، $wordsN كلمة، ${sw.elapsed.inSeconds}s');
    for (final e in tot.entries) {
      final r = e.value;
      print('${e.key.padRight(7)} حالات ${r[0]}  التُقط ${r[1]}  كاذب ${r[2]}  أتمّ ${r[3]}');
    }
  }, skip: dir == null ? 'يعمل حين يُعيَّن PHON_EVAL' : false, timeout: const Timeout(Duration(hours: 3)));
}
