import 'arabic.dart';

/// مقطع يُتلى: آية (مفتاحها رقمها العام) أو بسملة قبل السورة (مفتاحها سالب).
///
/// [words] كلمات النص الإملائي المطبّعة، و[display] لكل كلمة منها رقمُ الكلمة
/// التي تقابلها في الرسم العثماني المعروض (قد تقابل كلمتان إملائيتان كلمة واحدة،
/// مثل «أَوَلَا» = «او لا»).
class RecitedSegment {
  final int key;
  final List<String> words;

  /// الكلمات بحركاتها كما في النص المشكول (إن كان مشكولاً)، مقابل [words] كلمةً كلمة.
  final List<String> voweled;
  final List<int> display;
  RecitedSegment._(this.key, this.words, this.voweled, this.display);

  factory RecitedSegment(int key, String text, {String? uthmani}) {
    final (words, raw) = pairWords(text);
    return RecitedSegment._(
        key, words, raw, uthmani == null ? List.generate(words.length, (i) => i) : mapToDisplay(uthmani, words));
  }
}

/// كلمات النص مطبّعة، ومعها كل كلمة كما كُتبت (بحركاتها)، بالترتيب نفسه.
(List<String>, List<String>) pairWords(String text) {
  final norm = <String>[], raw = <String>[];
  for (final t in text.trim().split(RegExp(r'\s+'))) {
    for (final w in recitationWords(t)) {
      norm.add(w);
      raw.add(t);
    }
  }
  return (norm, raw);
}

/// نوع الخطأ في كلمة، وما سُمع مكانها، ليُعرض سببه.
enum MistakeKind { substituted, skipped, letters, harakat, order }

class MistakeInfo {
  final MistakeKind kind;

  /// ما سُمع مكان الكلمة (بحركاته)، أو null إن سقطت.
  final String? heard;

  /// ما يقابل الخطأ من كلمات العبارة المسموعة: [from, to). فارغ إن سقطت الكلمة بلا بديل.
  final int from, to;

  /// كلمات النص التي يشملها الخطأ معاً: [group, groupEnd). تُتحقق وتُرفع معاً.
  final int group, groupEnd;
  const MistakeInfo(this.kind, this.heard, this.from, this.to, this.group, this.groupEnd);
}

/// كلمات النص بعد التطبيع، دون علامات الترقيم والأرقام.
List<String> recitationWords(String s) {
  final t = normalizeArabic(s).replaceAll(RegExp(r'[^ء-ي\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? const [] : t.split(' ');
}

final _uthmaniMarks = RegExp('[ؐ-ًؚ-ٰٟۖ-ۭـ]');

/// كلمة من الرسم العثماني بعد حذف علامات الضبط والوقف، لمقارنة طولها.
String uthmaniSkeleton(String w) => normalizeArabic(w.replaceAll(_uthmaniMarks, '').replaceAll('ٱ', 'ا'));

/// يقابل كل كلمة إملائية برقم الكلمة العثمانية المعروضة (بعد تقسيم النص بالمسافات).
/// علامة الحزب «۞» كلمة معروضة لا تُتلى، فتُتخطى.
List<int> mapToDisplay(String uthmani, List<String> plain) {
  final disp = uthmani.split(' ');
  final readable = <int>[
    for (var i = 0; i < disp.length; i++)
      if (uthmaniSkeleton(disp[i]).isNotEmpty) i,
  ];
  if (readable.length == plain.length) return readable;
  // تختلف الأعداد في نحو ستين آية («أَوَلَمۡ» = «او لم»، «هَٰٓأَنتُمۡ» = «ها انتم»):
  // نضم إلى الكلمة العثمانية كلمات إملائية حتى يقارب طولها طولها.
  final out = <int>[];
  var p = 0;
  for (var r = 0; r < readable.length && p < plain.length; r++) {
    final target = uthmaniSkeleton(disp[readable[r]]).length;
    final left = readable.length - r - 1;
    var len = 0;
    do {
      len += plain[p].length;
      out.add(readable[r]);
      p++;
    } while (p < plain.length && len < target - 1 && plain.length - p > left);
  }
  while (out.length < plain.length) {
    out.add(readable.isEmpty ? 0 : readable.last);
  }
  return out;
}

/// حال كلمة معروضة أثناء متابعة التلاوة.
enum WordState { ahead, current, read, mistake }

/// يتابع موضع القارئ في نص الصفحة من كلمات يسمعها التعرّف على الكلام.
///
/// يمضي كلمة كلمة مع النص، ويتسامح في المتابعة مع اختلاف حرف أو حرفين بحسب طول الكلمة.
/// ثم يحكم على الأخطاء بالنتيجة النهائية للعبارة وبكل البدائل التي سمعها التعرّف:
/// - كلمة أُبدلت أو سقطت: سمع ما لا يطابق ثم عاد القارئ إلى النص بعد كلمة إلى ثلاث.
/// - كلمة قيلت بحرف مختلف («يعملون» مكان «تعملون»): تطابق تقريبي لا يفسّره اختلاف
///   الإملاء (الهمزات والألف والتاء المربوطة والواو في أولها)، ولم يسمعها صحيحة في أي بديل.
/// وإن تخطى أكثر من ثلاث كلمات عُدّ انتقالاً إلى موضع آخر لا خطأً.
/// وإن رجع القارئ يكرر ما قرأه (ثلاث كلمات متتالية خلف موضعه) رجع معه.
class RecitationTracker {
  final List<int> _keys = [];
  final List<String> _words = [];
  final List<int> _wordSeg = [];
  final List<int> _wordDisp = [];
  final List<String> _vow = [];

  /// سبب كل خطأ: ما سُمع مكانه ونوعه.
  final Map<int, MistakeInfo> why = {};

  /// ضبط الحركات: تُعدّ الكلمة المقروءة بحركة مختلفة خطأً (اللحن الجلي).
  bool harakat = false;

  /// كلمات العبارة الحالية كما خرجت من النموذج بحركاتها، مقابل المسموع المطبّع.
  List<String> _raw = const [];

  /// موضع الكلمة التالية المنتظرة.
  int pos = 0;

  /// الكلمات التي عُدّت أخطاءً (مواضعها في النص كله).
  final Set<int> mistakes = {};

  /// هل طابقت كلمة في العبارة الحالية؟ أول قفزة في العبارة لا تُعدّ خطأً،
  /// لأن خدمة التعرّف تُسقط أحياناً كلمات عند إعادة تشغيلها بين العبارات.
  bool _matchedInPhrase = false;

  /// التشديد في الحروف: تُعدّ الكلمة المقروءة بحرف مختلف خطأً.
  bool strict = true;

  /// العبارات تأتي كاملة من نموذج التلاوة بعد كل وقفة، لا مقطوعة كما في خدمة Google:
  /// فتُعدّ الكلمات التي تخطاها القارئ في أول العبارة، والكلمة الأخيرة المبدلة في آخرها.
  bool wholePhrases = false;
  bool _everMatched = false;

  /// بدائل العبارة الحالية، ليُتحقق منها قبل عدّ كلمة خطأً.
  List<List<String>> _alts = const [];

  RecitationTracker(List<RecitedSegment> segments) {
    for (var i = 0; i < segments.length; i++) {
      _keys.add(segments[i].key);
      final s = segments[i];
      for (var k = 0; k < s.words.length; k++) {
        _words.add(s.words[k]);
        _wordSeg.add(i);
        _wordDisp.add(k < s.display.length ? s.display[k] : k);
        _vow.add(k < s.voweled.length ? s.voweled[k] : s.words[k]);
      }
    }
  }

  int get length => _words.length;

  /// الأخطاء مقرونة بمفتاح مقطعها والكلمة الصحيحة (الإملائية)، مرتبة.
  List<(int, String)> get mistakeWords => [
        for (final k in mistakes.toList()..sort()) (_keys[_wordSeg[k]], _words[k]),
      ];
  bool get finished => pos >= _words.length;

  /// مفتاح المقطع الذي يقرؤه الآن (آخر مقطع إن انتهت الصفحة).
  int? get currentKey {
    if (_words.isEmpty) return null;
    return _keys[_wordSeg[pos.clamp(0, _words.length - 1)]];
  }

  /// رقم الكلمة المعروضة المنتظرة الآن في مقطعها.
  int? get currentWord => finished || _words.isEmpty ? null : _wordDisp[pos];

  /// حال كل كلمة معروضة في الصفحة: مفتاحها «مفتاح المقطع:رقم الكلمة».
  Map<String, WordState> get wordStates {
    final parts = <String, List<WordState>>{};
    for (var i = 0; i < _words.length; i++) {
      final WordState s = mistakes.contains(i)
          ? WordState.mistake
          : i < pos
          ? WordState.read
          : i == pos
          ? WordState.current
          : WordState.ahead;
      parts.putIfAbsent('${_keys[_wordSeg[i]]}:${_wordDisp[i]}', () => []).add(s);
    }
    // كلمة معروضة قد تقابل كلمتين إملائيتين: الخطأ يغلب، ولا تُعدّ مقروءة حتى تُقرأ كلها.
    return parts.map((k, l) {
      if (l.contains(WordState.mistake)) return MapEntry(k, WordState.mistake);
      if (l.every((s) => s == WordState.read)) return MapEntry(k, WordState.read);
      if (l.every((s) => s == WordState.ahead)) return MapEntry(k, WordState.ahead);
      return MapEntry(k, WordState.current);
    });
  }

  /// هل طابق شيء من العبارة الأخيرة نصَّ الصفحة؟ إن لم يطابق فلعل القارئ في موضع آخر.
  bool get matchedInPhrase => _matchedInPhrase;

  /// يضع الموضع عند الكلمة [word] من المقطع [key]، بعد أن عُرف موضع القارئ من كلماته.
  void startAtWord(int key, int word) {
    final seg = _keys.indexOf(key);
    if (seg < 0) return;
    final i = _wordSeg.indexOf(seg);
    if (i < 0) return;
    pos = (i + word).clamp(0, _words.length);
    _matchedInPhrase = true;
    _everMatched = true;
  }

  /// يبدأ المتابعة من أول مقطع مفتاحه [key].
  void startAt(int key) {
    final seg = _keys.indexOf(key);
    if (seg < 0) return;
    final i = _wordSeg.indexOf(seg);
    if (i >= 0) {
      pos = i;
      _matchedInPhrase = false;
      _everMatched = false;
    }
  }

  /// يمرّر كلمات العبارة الحالية بدءاً من [from]، ويعيد عدد الكلمات المستهلكة منها،
  /// ومعه عدد الأخطاء الجديدة. الكلمة الأخيرة لا تُستهلك إن لم تطابق، لأن التعرّف
  /// قد يصححها في النتيجة التالية.
  (int, int) feed(List<String> heard, int from, {bool markMistakes = true, List<List<String>>? alternatives}) {
    if (from == 0) _matchedInPhrase = false;
    _alts = alternatives ?? [heard];
    var i = from;
    var lastMatch = from;
    var newMistakes = 0;
    while (i < heard.length && !finished) {
      if (similarWord(heard[i], _words[pos])) {
        if (markMistakes) {
          String? r = i < _raw.length ? _raw[i] : null;
          if (i == 0 && _clippedStart(heard[i], _words[pos])) {
            // أول العبارة قُطع أولُه («نبيين» من «والنبيين»): ليس خطأً.
          } else if (strict && _wrongLetters(heard[i], pos)) {
            if (mistakes.add(pos)) newMistakes++;
            why[pos] = MistakeInfo(MistakeKind.letters, r ?? heard[i], i, i + 1, pos, pos + 1);
          } else if (harakat && r != null && harakatDiffer(r, _vow[pos])) {
            if (mistakes.add(pos)) newMistakes++;
            why[pos] = MistakeInfo(MistakeKind.harakat, r, i, i + 1, pos, pos + 1);
          }
        }
        pos++;
        i++;
        lastMatch = i;
        _matchedInPhrase = _everMatched = true;
        continue;
      }
      var jump = _findAhead(heard, i, lastIsFinal: markMistakes);
      final back = _findBehind(heard, i);
      // تطابق أمام الموضع وآخر خلفه: القارئ يكرر إن كان ما خلفه أطول تطابقاً.
      if (jump != null && back != null && _run(heard, i, back.$1 - back.$2) > _run(heard, i, jump.$1 - jump.$2)) {
        jump = null;
      }
      if (jump != null) {
        final skipped = jump.$1 - jump.$2 - pos;
        final inContext = _matchedInPhrase || wholePhrases && _everMatched;
        if (markMistakes && inContext && skipped <= 3 && !_sameSounds(heard, lastMatch, i, pos, skipped)) {
          // ما سُمع بين آخر تطابق وهذا الموضع ولم يطابق شيئاً هو ما قيل مكان الساقط.
          final said = lastMatch < i && i <= _raw.length ? _raw.sublist(lastMatch, i).toSet().join(' ') : null;
          for (var k = pos; k < pos + skipped; k++) {
            // الأدوات القصيرة («من»، «لا») كثيراً ما يُسقطها التعرّف، فلا نعدّها خطأً.
            if (_words[k].length >= 3 && mistakes.add(k)) {
              newMistakes++;
              why[k] = MistakeInfo(said == null ? MistakeKind.skipped : MistakeKind.substituted, said,
                  said == null ? i : lastMatch, i, pos, pos + skipped);
            }
          }
        }
        pos = jump.$1;
        i += jump.$2;
        lastMatch = i;
        _matchedInPhrase = _everMatched = true;
        continue;
      }
      if (back != null) {
        // القارئ يعيد ما قرأه: نرجع معه دون أن نعدّ شيئاً.
        pos = back.$1;
        i += back.$2;
        lastMatch = i;
        _matchedInPhrase = true;
        continue;
      }
      if (i + 1 < heard.length) {
        i++; // كلمة زائدة أو لم يُتعرّف عليها جيداً
      } else {
        break;
      }
    }
    return (i, newMistakes);
  }

  // ---------- العبارة: نتابع بالنتائج الجزئية، ونحكم على الأخطاء بالنهائية ----------

  int _phrasePos = 0;
  Set<int> _phraseMistakes = {};

  /// يحفظ الموضع عند بدء عبارة جديدة، ليُعاد تمريرها كاملة حين تصل نتيجتها النهائية.
  void beginPhrase() {
    _phrasePos = pos;
    _phraseMistakes = {...mistakes};
  }

  /// يعيد العبارة من أولها بنتيجتها النهائية (وهي أدق من الجزئية)، ويعدّ أخطاءها.
  (int, int) replayFinal(List<List<String>> alternatives, {List<String>? raw}) {
    final before = mistakes.length;
    pos = _phrasePos;
    mistakes
      ..clear()
      ..addAll(_phraseMistakes);
    var heard = best(alternatives, 0);
    _raw = raw ?? const [];
    lateConfirmed = 0;
    // كلمة عُلّقت في آخر العبارة السابقة: إن بدأت هذه ببقيتها أو بإعادتها فقد قُطع الصوت
    // في وسطها ولم يخطئ القارئ. وإلا فهي خطأ مؤكد.
    if (tentative.isNotEmpty && heard.isNotEmpty) {
      final k = tentative.last;
      if (similarWord(heard.first, _words[k]) && k == pos - 1) {
        tentative.clear();
        why.remove(k);
        pos = k;
      } else if (_isTailOf(heard.first, _words[k]) ||
          _isHeadOf(_tentativeHeard, _words[k]) && pos < _words.length && !similarWord(heard.first, _words[pos])) {
        tentative.clear();
        why.remove(k);
        heard = heard.sublist(1);
        if (_raw.isNotEmpty) _raw = _raw.sublist(1);
      } else {
        lateConfirmed = confirmTentative();
      }
    }
    why.removeWhere((k, _) => !mistakes.contains(k) && !tentative.contains(k));
    var r = feed(heard, 0, alternatives: alternatives);
    if (wholePhrases && _matchedInPhrase) r = (_finishTail(heard, r.$1), r.$2);
    return (r.$1, (mistakes.length - before).clamp(0, 1 << 20));
  }

  /// كلمات عُدّت مبدلة في آخر العبارة ولم تُعرض بعد: قد يكون الصوت قُطع في وسط الكلمة
  /// (سكون حرف طويل في تلاوة متمهلة)، فيُنتظر ما بعدها أو سكوت القارئ.
  final Set<int> tentative = {};

  /// كم خطأً معلّقاً تأكد بوصول العبارة الأخيرة.
  int lateConfirmed = 0;

  /// يثبّت الأخطاء المعلّقة (سكت القارئ بعدها، أو أكمل بغيرها). يعيد عددها.
  int confirmTentative() {
    var n = 0;
    for (final k in tentative) {
      if (mistakes.add(k)) n++;
    }
    _phraseMistakes.addAll(tentative);
    tentative.clear();
    return n;
  }

  String _tentativeHeard = '';

  /// هل [heard] أول الكلمة [want] قبل أن يُقطع الصوت؟ («يحـ» من «يحسبن»)
  static bool _isHeadOf(String heard, String want) =>
      heard.length >= 2 && heard.length < want.length && want.startsWith(heard.substring(0, 2));

  /// هل [heard] بقية الكلمة [want] بعد أن قُطع أولها؟ («سبن» من «يحسبن»)
  static bool _isTailOf(String heard, String want) {
    if (heard.length < 2 || heard.length >= want.length) return false;
    if (want.endsWith(heard)) return true;
    // حرف أول مشوّه عند القطع: يكفي أن تطابق البقية بعده.
    return heard.length >= 3 && want.endsWith(heard.substring(1));
  }

  /// آخر العبارة لم يطابق النص ثم وقف القارئ: الكلمة المنتظرة أُبدلت (أو سقطت إن
  /// طابق المسموع ما بعدها). تُعدّ خطأً ويمضي الموضع، فلا تعلق المتابعة عندها.
  /// آخر كلمة في العبارة تُعلَّق ولا تُعرض حتى يتبيّن أنها لم تُقطع في وسطها.
  int _finishTail(List<String> heard, int i) {
    var n = 0;
    while (i < heard.length && !finished && n < 3) {
      final w = heard[i];
      if (w.length < 2) {
        i++;
        continue;
      }
      if (pos + 1 < _words.length && similarWord(w, _words[pos + 1])) {
        if (_words[pos].length >= 3 && mistakes.add(pos)) {
          why[pos] = MistakeInfo(MistakeKind.skipped, null, i, i, pos, pos + 1);
        }
        pos += 2;
      } else {
        why[pos] = MistakeInfo(MistakeKind.substituted, i < _raw.length ? _raw[i] : w, i, i + 1, pos, pos + 1);
        if (i == heard.length - 1) {
          tentative.add(pos);
          _tentativeHeard = w;
        } else {
          mistakes.add(pos);
        }
        pos++;
      }
      i++;
      n++;
    }
    return i;
  }

  /// الأخطاء التي عُدّت في العبارة الأخيرة (منذ beginPhrase) ومعها المعلّقة، ليُتحقق منها.
  List<int> get phraseMistakes =>
      [for (final k in mistakes) if (!_phraseMistakes.contains(k)) k, ...tentative]..sort();

  /// يرفع الخطأ عن الكلمة [k] وعمّا عُدّ معها إن لم يتأكد منه النموذج.
  void dismiss(int k) {
    final w = why[k];
    for (var j = w?.group ?? k; j < (w?.groupEnd ?? k + 1); j++) {
      mistakes.remove(j);
      tentative.remove(j);
      why.remove(j);
    }
  }

  /// الكلمة الصحيحة بحركاتها.
  String voweledAt(int k) => _vow[k];

  /// مفتاح المقطع ورقم الكلمة المعروضة للموضع [k].
  String displayKey(int k) => '${_keys[_wordSeg[k]]}:${_wordDisp[k]}';

  /// موضع أول كلمة إملائية تقابل الكلمة المعروضة [key] («مفتاح:رقم»)، أو null.
  int? positionOf(String key) {
    for (var i = 0; i < _words.length; i++) {
      if (displayKey(i) == key) return i;
    }
    return null;
  }

  /// نص العبارة لو قرأ القارئ الكلمة [k] (وما عُدّ معها) صحيحة، والباقي كما سمعه النموذج.
  /// يوازن النموذج بينه وبين ما سمعه: إن قارب احتماله فالخطأ غير مؤكد.
  String? correctedPhrase(int k) {
    final w = why[k];
    if (w == null || _raw.isEmpty || w.from > _raw.length || w.to > _raw.length) return null;
    final out = [..._raw.sublist(0, w.from), ..._vow.sublist(w.group, w.groupEnd), ..._raw.sublist(w.to)];
    // كلمة مقسومة على كلمتين مطبّعتين تتكرر: نحذف التكرار.
    final dedup = <String>[];
    for (var i = 0; i < out.length; i++) {
      if (i > 0 && identical(out[i], out[i - 1])) continue;
      dedup.add(out[i]);
    }
    return dedup.join(' ');
  }

  /// أول كلمة في العبارة سُمعت بلا أولها («صلاة» من «الصلاة»): الصوت قُطع عند بدئها.
  static bool _clippedStart(String heard, String want) {
    for (var n = 1; n <= 3 && want.length - n >= 3; n++) {
      if (similarWord(heard, want.substring(n))) return true;
    }
    return false;
  }

  /// هل ما سُمع بين آخر تطابق والموضع [i] هو حروف الكلمات المتخطاة نفسها تقريباً؟
  /// النموذج يقسم الكلمات أحياناً في غير مواضعها («اتبا عن ظن» = «اتباع الظن»)، وأول
  /// العبارة قد يُقطع أوله، فلا يُعدّ ذلك إبدالاً.
  bool _sameSounds(List<String> heard, int lastMatch, int i, int at, int skipped) {
    if (lastMatch >= i) return false;
    if (lastMatch == 0 && i == 1 && skipped == 1 && _clippedStart(heard[0], _words[at])) return true;
    final lead = lastMatch > 0 && at > 0 ? 1 : 0;
    final h = heard.sublist(lastMatch - lead, i).join();
    final w = _words.sublist(at - lead, at + skipped).join();
    final core = _words.sublist(at, at + skipped).join().length;
    final cap = (core * 0.45).floor();
    return cap >= 1 && (h.length - w.length).abs() <= cap && _distance(h, w, cap) <= cap;
  }

  /// طول التطابق المتتالي بين المسموع من [i] والنص من [j] (حتى ست كلمات).
  int _run(List<String> heard, int i, int j) {
    var n = 0;
    while (n < 6 && i + n < heard.length && j + n < _words.length && similarWord(heard[i + n], _words[j + n])) {
      n++;
    }
    return n;
  }

  /// كم كلمة من المسموع (بدءاً من [from]) تطابق كلمات قريبة أمام الموضع.
  /// به نختار أرجح البدائل التي تقترحها خدمة التعرّف.
  int score(List<String> heard, int from) {
    final end = (pos + 40).clamp(0, _words.length);
    final start = (pos - 3).clamp(0, _words.length);
    var n = 0;
    for (var i = from; i < heard.length; i++) {
      for (var j = start; j < end; j++) {
        if (similarWord(heard[i], _words[j])) {
          n++;
          break;
        }
      }
    }
    return n;
  }

  /// يختار من البدائل أكثرها مطابقة للنص.
  List<String> best(List<List<String>> alternatives, int from) {
    var b = alternatives.first;
    var bs = score(b, from);
    for (final a in alternatives.skip(1)) {
      final sc = score(a, from);
      if (sc > bs) {
        b = a;
        bs = sc;
      }
    }
    return b;
  }

  /// هل قُرئت الكلمة [k] بحرف مختلف حقاً؟ نعم إن لم يفسّر الفرقَ اختلافُ الإملاء،
  /// ولم تأتِ الكلمة صحيحة في أي من البدائل التي سمعها التعرّف.
  bool _wrongLetters(String heard, int k) {
    final want = _words[k];
    if (want.length < 3 || spellingVariant(heard, want)) return false;
    for (final alt in _alts) {
      for (final w in alt) {
        if (spellingVariant(w, want)) return false;
      }
    }
    return true;
  }

  /// يبحث خلف الموضع (حتى 40 كلمة) عن ثلاث كلمات متتالية تطابق المسموع: القارئ يكرر.
  (int, int)? _findBehind(List<String> heard, int i) {
    const need = 3;
    if (i + need > heard.length) return null;
    final start = (pos - 40).clamp(0, _words.length);
    for (var j = pos - 1; j >= start; j--) {
      var ok = true;
      for (var k = 0; k < need; k++) {
        if (j + k >= _words.length || !similarWord(heard[i + k], _words[j + k])) {
          ok = false;
          break;
        }
      }
      if (ok) return (j + need, need);
    }
    return null;
  }

  /// يبحث أمام الموضع عن تطابق كلمات متتالية تبدأ بالكلمة [i] من المسموع.
  (int, int)? _findAhead(List<String> heard, int i, {bool lastIsFinal = false}) {
    const window = 160;
    final end = (pos + window).clamp(0, _words.length);
    for (var j = pos + 1; j < end; j++) {
      if (!similarWord(heard[i], _words[j])) continue;
      // كلما بعدت القفزة احتجنا إلى تطابق أطول حتى لا نقفز خطأً.
      var need = j - pos <= 3 ? 2 : 3;
      if (i + need > heard.length) {
        // آخر كلمة في عبارة نهائية تطابق كلمة طويلة بعد كلمة أو كلمتين: سقط ما بينهما.
        // (يتحقق النموذج بعدها من أن الساقط لم يُقرأ.)
        if (!lastIsFinal || i != heard.length - 1 || j - pos > 2 || heard[i].length < 4 || !_everMatched) return null;
        need = 1;
      }
      var ok = true;
      for (var k = 1; k < need; k++) {
        if (j + k >= _words.length || !similarWord(heard[i + k], _words[j + k])) {
          ok = false;
          break;
        }
      }
      if (ok) return (j + need, need);
    }
    return null;
  }
}

/// الكلمتان واحدة وإن اختلف رسمهما: الرسم والإملاء والتعرّف على الكلام تختلف في
/// حروف المد والهمزات (الصلوة/الصلاة، شيـًٔا/شيئا، إسرٰءيل/إسرائيل)، وفي الحرف
/// المشدد يُكتب مرة أو مرتين، وفي الواو والفاء أول الكلمة، والهاء والتاء المربوطة آخرها.
/// ما عدا ذلك (حرف صحيح مكان آخر: «يعملون» و«تعملون») فرق حقيقي في القراءة.
bool spellingVariant(String a, String b) {
  if (a == b) return true;
  return _skeleton(a) == _skeleton(b);
}

final _weak = RegExp('[اأإآٱءئؤوىي]');

String _skeleton(String s) {
  var t = s;
  if (t.length > 3 && (t.startsWith('و') || t.startsWith('ف'))) t = t.substring(1);
  if (t.endsWith('ه') || t.endsWith('ة') || t.endsWith('ت') && t.length > 4) t = t.substring(0, t.length - 1);
  t = t.replaceAll(_weak, '');
  final out = StringBuffer();
  for (var i = 0; i < t.length; i++) {
    if (i == 0 || t[i] != t[i - 1]) out.write(t[i]);
  }
  return out.toString();
}

/// تطابق كلمتين مع تسامح يسير: الواو والفاء في أولها، والألف داخل الكلمة
/// (يكتبها الرسم ولا يكتبها الإملاء أو العكس)، وفرق حرف أو حرفين بحسب الطول.
bool similarWord(String a, String b) {
  if (a == b) return true;
  String strip(String s) => s.length > 3 && (s.startsWith('و') || s.startsWith('ف')) ? s.substring(1) : s;
  final x = strip(a), y = strip(b);
  if (x == y) return true;
  if (x.length > 3 && y.length > 3 && x.replaceAll('ا', '') == y.replaceAll('ا', '')) return true;
  final len = x.length < y.length ? y.length : x.length;
  if (len < 3) return false;
  final allowed = len >= 7 ? 2 : 1;
  if ((x.length - y.length).abs() > allowed) return false;
  return _distance(x, y, allowed) <= allowed;
}

int _distance(String a, String b, int cap) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    var best = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final v = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((p, q) => p < q ? p : q);
      cur[j] = v;
      if (v < best) best = v;
    }
    if (best > cap) return best;
    prev = cur;
  }
  return prev[b.length];
}

/// مفتاح الكلمة للبحث: هيكلها بلا حروف المد والهمزات.
String wordKey(String s) => _skeleton(s);

final _marks = RegExp('[\u064b-\u0652]');
const _hamzaSeats = {'أ', 'إ', 'آ', 'ٱ'};

/// حركات الكلمة حرفاً حرفاً: لكل حرف مجموعة علاماته (بلا السكون).
List<(String, String)> _letterMarks(String w) {
  final out = <(String, String)>[];
  for (final ch in w.split('')) {
    if (_marks.hasMatch(ch)) {
      if (out.isEmpty || ch == '\u0652') continue;
      final (l, m) = out.removeLast();
      out.add((l, m + ch));
    } else if (RegExp('[ء-ي]').hasMatch(ch)) {
      out.add((ch, ''));
    }
  }
  return [for (final (l, m) in out) (l, (m.split('')..sort()).join())];
}

/// هل قُرئت الكلمة بحرفها نفسه وحركة مختلفة؟ تُقارن حركات كل الحروف إلا الأخير
/// (يتغير بالوقف والوصل)، وحروف المد بلا حركة لا تُقارن.
bool harakatDiffer(String heard, String want) {
  if (normalizeArabic(heard) != normalizeArabic(want)) return false;
  final a = _letterMarks(heard), b = _letterMarks(want);
  if (a.length != b.length || a.length < 2) return false;
  for (var i = 0; i < a.length - 1; i++) {
    final (la, ma) = a[i];
    final (lb, mb) = b[i];
    // همزة القطع مفتوحة أو مكسورة (أ / إ) فرق في الحركة.
    if (la != lb && _hamzaSeats.contains(la) && _hamzaSeats.contains(lb) && (la == 'إ') != (lb == 'إ')) return true;
    if (ma.isEmpty || mb.isEmpty) continue; // حرف بلا حركة في أحدهما: لا نحكم
    if (ma != mb) return true;
  }
  return false;
}

/// وصف الخطأ بالعربية لمن يسأل عن سببه.
String explainMistake(MistakeInfo? w, String want) {
  if (w == null) return 'عُدّت هذه الكلمة خطأً.';
  switch (w.kind) {
    case MistakeKind.skipped:
      return 'لم تُقرأ هذه الكلمة: انتقلتَ إلى ما بعدها.';
    case MistakeKind.substituted:
      return 'سُمعت «${w.heard}» مكان «$want».';
    case MistakeKind.letters:
      return 'قُرئت «${w.heard}» بحرف مختلف عن «$want».';
    case MistakeKind.harakat:
      return 'قُرئت «${w.heard}» بحركة مختلفة، والصواب «$want».';
    case MistakeKind.order:
      return 'انتقلتَ إلى آية أخرى قبل أن تقرأ من هنا. أكمل من هذه الكلمة.';
  }
}
