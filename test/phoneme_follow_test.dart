// المتابعة بالأصوات عبر الصفحات، على مخرجات النموذج الحقيقية لتلاوات محفوظة في test/data/top
// (لكل إطار أرجح ثلاثة رموز واحتمالاتها، كما يكتبها tools/phon_eval/phon_dump.py).
import 'dart:io';
import 'dart:typed_data';

import 'package:dhikra/util/phoneme_follow.dart';
import 'package:dhikra/util/phoneme_tracker.dart';
import 'package:dhikra/util/recitation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tokens = PhonemeTokens.parse(File('assets/data/phoneme_tokens.txt').readAsStringSync());
  final phon = <int, List<String>>{}, idOf = <String, int>{};
  final all = <(int, String)>[];
  var n = 0;
  for (final l in File('tools/data/quran-phonemes.tsv').readAsLinesSync()) {
    final p = l.split('\t');
    idOf['${p[0]}:${p[1]}'] = ++n;
    phon[n] = p[2].split(' ');
    all.add((n, p[2]));
  }
  final locator = PhonemeLocator(all);
  final mulk = idOf['67:1']!;
  // صفحات الاختبار: 1 الفاتحة، 2 البقرة 1-5، 3 البقرة 6-16، 562 الملك 1-12، 563 الملك 13-26.
  final pages = <int, List<int>>{
    1: [for (var i = 1; i <= 7; i++) i],
    2: [for (var i = 8; i <= 12; i++) i],
    3: [for (var i = 13; i <= 23; i++) i],
    562: [for (var i = 0; i < 12; i++) mulk + i],
    563: [for (var i = 12; i < 26; i++) mulk + i],
  };
  final basmala = phon[1]!;

  late List<int> gotos, locatedAt;
  var wrongPlace = 0;
  late Set<String> mistakes;

  PhonemeFollower make() {
    gotos = [];
    locatedAt = [];
    mistakes = {};
    wrongPlace = 0;
    late final PhonemeFollower f;
    f = PhonemeFollower(
      tokens: tokens,
      pageWords: (p) async => [
        for (final id in pages[p] ?? const <int>[]) ...[
          if (id == 8 || id == mulk)
            for (var k = 0; k < 4; k++) PhonWord(id == 8 ? -2 : -67, k, basmala[k], basmala[k]),
          for (var k = 0; k < phon[id]!.length; k++) PhonWord(id, k, phon[id]![k], phon[id]![k]),
        ],
      ],
      locate: (tail) async => locator.locate(tail),
      pageOfAya: (id) async => pages.entries.where((e) => e.value.contains(id)).firstOrNull?.key,
    );
    f
      ..onGoto = (p) {
        gotos.add(p);
      }
      ..onLocated = (aya, p) {
        locatedAt.add(aya);
      }
      ..onWrongPlace = () {
        wrongPlace++;
      }
      ..onRetire = (t) {
        mistakes.addAll([for (final w in t.mistakes) t.displayKey(w)]);
      };
    return f;
  }

  /// يقرأ التلاوات متتالية كما تصل من النموذج (12 إطاراً في المرة)، والواجهة تعرض ما يُطلب.
  Future<void> recite(PhonemeFollower f, List<String> clips, {int silence = 0}) async {
    Future<void> feed(Uint8List ids, Float32List pr, int m, bool speech) async {
      f.addTop(ids, pr, m, speech: speech);
      await Future<void>.delayed(Duration.zero); // ما طُلب من بحث أو مدّ يتم
      while (gotos.isNotEmpty && gotos.last != f.page) {
        await f.pageShown(gotos.last);
      }
    }

    for (final c in clips) {
      final b = File('test/data/top/$c.top').readAsBytesSync();
      final d = ByteData.sublistView(b);
      final frames = b.length ~/ 15;
      for (var o = 0; o < frames; o += 12) {
        final m = o + 12 > frames ? frames - o : 12;
        final ids = Uint8List(m * 3);
        final pr = Float32List(m * 3);
        for (var x = 0; x < m; x++) {
          for (var k = 0; k < 3; k++) {
            ids[x * 3 + k] = b[(o + x) * 15 + k];
            pr[x * 3 + k] = d.getFloat32((o + x) * 15 + 3 + k * 4, Endian.little);
          }
        }
        await feed(ids, pr, m, true);
      }
      for (var s = 0; s < silence; s += 12) {
        await feed(Uint8List(36)..fillRange(0, 36, tokens.blank), Float32List(36)..fillRange(0, 36, 1), 12, false);
      }
    }
  }

  String fatiha(int a) => 'Alafasy_128kbps-00100$a';
  String baqara(int a) => 'Husary_128kbps-00200$a';
  String mulkClip(int a) => 'Minshawy_Murattal_128kbps-06700$a';
  bool read(PhonemeFollower f, int aya) =>
      [for (var k = 0; k < phon[aya]!.length; k++) f.states['$aya:$k']].every((s) => s == WordState.read);

  test('صفحتان متتاليتان: تُقلب الصفحة وحدها ولا يُعدّ ترك البسملة خطأً', () async {
    final f = make();
    await f.open(1);
    await recite(f, [for (var a = 1; a <= 7; a++) fatiha(a), for (var a = 1; a <= 5; a++) baqara(a)]);
    f.stop();
    expect(gotos, [2, 3]);
    expect(mistakes, isEmpty);
    for (var id = 1; id <= 12; id++) {
      expect(read(f, id), isTrue, reason: 'الآية $id ${[for (var k = 0; k < phon[id]!.length; k++) f.states['$id:$k']]} ${phon[id]}');
    }
  });

  test('القراءة من سورة أخرى: يُعرف الموضع ويُنتقل إلى صفحته بلا أخطاء', () async {
    final f = make();
    await f.open(1);
    await recite(f, [for (var a = 1; a <= 3; a++) mulkClip(a)]);
    f.stop();
    expect(locatedAt, isNotEmpty);
    expect(locatedAt.first, inInclusiveRange(mulk, mulk + 2));
    expect(gotos.first, 562);
    expect(f.page, 562);
    expect(mistakes, isEmpty);
    expect(read(f, mulk + 2), isTrue);
  });

  test('البدء من وسط الصفحة ليس إسقاطاً لما قبله', () async {
    final f = make();
    await f.open(2);
    await recite(f, [for (var a = 3; a <= 5; a++) baqara(a)]);
    f.stop();
    expect(mistakes, isEmpty);
    expect(read(f, 11), isTrue);
    expect(read(f, 12), isTrue);
  });

  test('آية متروكة في وسط القراءة: خطأ ترتيب ويبقى الموضع عند الآية المتروكة', () async {
    final f = make();
    await f.open(1);
    await recite(f, [for (final a in [1, 2, 3, 5, 6, 7]) fatiha(a)]);
    expect(wrongPlace, greaterThan(0));
    expect(f.currentKey, 4);
    expect(f.tracker!.why[f.tracker!.positionOf('4:0')!]!.kind, MistakeKind.order);
    expect(read(f, 5), isFalse);
    expect(read(f, 7), isFalse);
    // يعود القارئ إلى الآية المتروكة ويكمل: يزول الخطأ.
    await recite(f, [for (var a = 4; a <= 7; a++) fatiha(a)]);
    f.stop();
    expect(mistakes, isEmpty);
    expect(read(f, 7), isTrue);
  });

  test('بعد ثبوت الموضع: القراءة من سورة أخرى خطأ ترتيب ولا تُقلب الصفحة', () async {
    final f = make();
    await f.open(1);
    await recite(f, [for (var a = 1; a <= 3; a++) fatiha(a), for (var a = 1; a <= 3; a++) mulkClip(a)]);
    expect(wrongPlace, greaterThan(0));
    expect(gotos, isEmpty);
    expect(f.page, 1);
    expect(f.currentKey, 4);
    f.stop();
    expect(mistakes, {'4:0'});
  });

  test('بعد خطأ الترتيب: الرجوع إلى آية سابقة مباح', () async {
    final f = make();
    await f.open(1);
    await recite(f, [for (final a in [1, 2, 3, 6, 7, 2, 3, 4, 5, 6, 7]) fatiha(a)]);
    f.stop();
    expect(mistakes, isEmpty);
    expect(read(f, 7), isTrue);
  });

  test('إعادة آيتين ثم الإكمال بلا أخطاء', () async {
    final f = make();
    await f.open(1);
    await recite(f, [for (final a in [1, 2, 3, 2, 3, 4, 5, 6, 7]) fatiha(a)]);
    f.stop();
    expect(mistakes, isEmpty);
    expect(gotos, [2]);
  });

  test('وقفات طويلة بين الآيات لا تُحدث أخطاء', () async {
    final f = make();
    await f.open(1);
    await recite(f, [for (var a = 1; a <= 7; a++) fatiha(a)], silence: 120);
    f.stop();
    expect(mistakes, isEmpty);
    expect(gotos, [2]);
  });
}
