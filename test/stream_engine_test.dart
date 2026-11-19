// ignore_for_file: avoid_print
// يشغّل المحرّك كله على الحاسوب كما يعمل على الهاتف: خيط النموذج، ثم المتابِع، على ملفات صوت.
// يعمل حين تُعيَّن: STREAM_LIB (libdhikra_asr.so مبنية للحاسوب) وSTREAM_MODEL (ملف النموذج)
// وSTREAM_WAVS (ملفات wav بتردد 16 كيلوهرتز تُقرأ متتالية، أسماؤها تنتهي بـSSSAAA).
import 'dart:io';
import 'dart:typed_data';

import 'package:dhikra/services/quran_asr.dart';
import 'package:dhikra/util/phoneme_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final env = Platform.environment;
  test('المحرّك المتدفق يتابع آيات متتالية', () async {
    setAsrLibraryPath(env['STREAM_LIB']!);
    final tokens = PhonemeTokens.parse(File('assets/data/phoneme_tokens.txt').readAsStringSync());
    final phon = <String, (int, List<String>)>{};
    var id = 0;
    for (final l in File('tools/data/quran-phonemes.tsv').readAsLinesSync()) {
      final p = l.split('\t');
      phon['${p[0]}:${p[1]}'] = (++id, p[2].split(' '));
    }
    final words = <PhonWord>[];
    final pcm = <double>[];
    for (final path in env['STREAM_WAVS']!.split(',')) {
      final code = RegExp(r'(\d{3})(\d{3})\.wav$').firstMatch(path)!;
      final (aya, ph) = phon['${int.parse(code.group(1)!)}:${int.parse(code.group(2)!)}']!;
      for (var k = 0; k < ph.length; k++) {
        words.add(PhonWord(aya, k, ph[k], ph[k]));
      }
      final bytes = File(path).readAsBytesSync();
      final data = ByteData.sublistView(bytes, 44);
      for (var i = 0; i + 1 < data.lengthInBytes; i += 2) {
        pcm.add(data.getInt16(i, Endian.little) / 32768.0);
      }
    }
    final t = PhonemeTracker(tokens, words);
    if (env['STREAM_DEBUG'] != null) t.debug = [];
    final engine = StreamEngine();
    var frames = 0;
    engine.onFrames = (ids, probs, n) {
      frames += n;
      t.addTop(ids, probs, n);
      if (env['STREAM_DEBUG'] != null) print('f=$frames pos=${t.pos} m=${t.mistakes} h=${t.debugHeard}');
    };
    final sw = Stopwatch()..start();
    expect(await engine.load(env['STREAM_MODEL']!), isTrue, reason: engine.error);
    final loadMs = sw.elapsedMilliseconds;
    await engine.drain(reset: true);
    sw.reset();
    // قطع صغيرة كما تصل من الميكروفون.
    for (var o = 0; o < pcm.length; o += 1600) {
      engine.feed(Float32List.fromList(pcm.sublist(o, (o + 1600).clamp(0, pcm.length))));
    }
    engine.feed(Float32List(16000));
    await engine.drain(timeout: const Duration(minutes: 4));
    t.finish();
    final secs = pcm.length / 16000;
    print('تحميل ${loadMs}ms · ${secs.toStringAsFixed(1)}s صوت في ${sw.elapsedMilliseconds}ms · $frames إطاراً');
    print('الموضع ${t.pos}/${words.length} · أخطاء ${t.mistakeWords}');
    for (final w in t.mistakes) {
      print('${t.words[w].text}: ${t.why[w]?.kind} ${t.why[w]?.heard}');
    }
    t.debug?.forEach(print);
    expect(frames, greaterThan(secs * 24));
    expect(t.pos, words.length);
    expect(t.mistakes, isEmpty);
    engine.dispose();
  }, skip: env['STREAM_LIB'] == null, timeout: const Timeout(Duration(minutes: 5)));
}
