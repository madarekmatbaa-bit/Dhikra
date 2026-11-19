import 'dart:math' as math;
import 'dart:typed_data';

import 'recitation.dart' show MistakeInfo, MistakeKind, WordState;

// متابعة التلاوة بالأصوات: نموذج التلاوة يخرج ما قاله القارئ حرفاً وحركة أثناء القراءة،
// وهنا يُطابَق ذلك مع أصوات نص المصحف كلمةً كلمة، فيُعرف موضع القارئ وما أخطأ فيه.

const _fatha = 0x64E, _damma = 0x64F, _kasra = 0x650;
const _alif = 0x627, _waw = 0x6E5, _ya = 0x6E6; // حروف المد كما يكتبها النموذج
const _hamza = 0x621;

bool _isShort(int c) => c == _fatha || c == _damma || c == _kasra;
bool _isLong(int c) => c == _alif || c == _waw || c == _ya;
bool _isVowel(int c) => _isShort(c) || _isLong(c);

/// يبسّط أصوات النموذج إلى ما يهم في ضبط القراءة: الحرف وحركته والمد، دون مقدار المد
/// والغنّة والقلقلة وسائر أحكام التجويد. فالمكرر يصير حرفاً واحداً، والنون المخفاة نوناً،
/// والميم المقلوبة ميماً.
List<int> normalizePhonemes(String s) {
  final out = <int>[];
  for (var c in s.runes) {
    if (c == 0x6BA) c = 0x646; // ں → ن
    if (c == 0x6FE) c = 0x645; // ۾ → م
    if (c == 0x672) c = _alif; // ٲ
    if (c == 0x687 || c == 0x6DC || c == 0x6EA || c == 0x640 || c == 0x619) continue; // ڇ ۜ ۪ ـ ؙ
    if (out.isNotEmpty && out.last == c) continue;
    out.add(c);
  }
  return out;
}

/// يعرض أصواتاً مسموعة بكتابة تُقرأ («يَعمَلُون»).
String phonemesToText(List<int> syms) {
  final b = StringBuffer();
  for (final c in syms) {
    b.writeCharCode(c == _waw
        ? 0x648
        : c == _ya
        ? 0x64A
        : c);
  }
  return b.toString();
}

final _tanween = RegExp('[ً-ٍٖۭٗٞۢ]');
final _letters = RegExp('[^ء-يٱ]');

/// كلمة منتظرة من النص: مفتاح آيتها ورقمها بين الكلمات المعروضة، وأصواتها.
class PhonWord {
  final int key;
  final int disp;

  /// الكلمة كما تُعرض (بالرسم العثماني)، لشرح الخطأ.
  final String text;
  final List<int> ph;

  /// ما قبل [lead] من الأصوات همزة وصل تسقط في الوصل، وما بعد [core] آخر الكلمة الذي
  /// يتغير بالوقف والوصل (الحركة الأخيرة، التنوين، التاء المربوطة): لا يُحاسب عليهما.
  final int lead, core;

  PhonWord._(this.key, this.disp, this.text, this.ph, this.lead, this.core);

  factory PhonWord(int key, int disp, String text, String phonemes) {
    final ph = normalizePhonemes(phonemes);
    final word = text.replaceAll('۞', '').replaceAll(' ', ' ').trim().split(' ').first;
    final bare = word.replaceAll(_letters, '');
    var core = ph.length;
    while (core > 1 && _isVowel(ph[core - 1])) {
      core--;
    }
    if (_tanween.hasMatch(word)) {
      // التنوين: كل ما بعد آخر حركة قصيرة (نون أو إدغامها في ما بعدها).
      for (var i = ph.length - 1; i > 0; i--) {
        if (_isShort(ph[i])) {
          core = math.min(core, i);
          break;
        }
      }
    }
    if (bare.endsWith('ة')) {
      // التاء المربوطة تُقرأ هاءً عند الوقف.
      for (var i = ph.length - 1; i > 0; i--) {
        if (ph[i] == 0x62A) {
          core = math.min(core, i);
          break;
        }
      }
    }
    var lead = 0;
    if (word.startsWith('ٱ') && ph.length > 3 && ph[0] == _hamza && _isShort(ph[1])) lead = 2;
    if (core <= lead) core = math.min(ph.length, lead + 1);
    return PhonWord._(key, disp, word, ph, lead, core);
  }

  bool get wasl => text.startsWith('ٱ');

  PhonWord withCore(int c) => PhonWord._(key, disp, text, ph, lead, c < lead + 1 ? lead + 1 : c);
}

/// رموز النموذج: لكل رمز أصواته المبسّطة.
class PhonemeTokens {
  final List<List<int>> syms;
  final int blank;
  PhonemeTokens._(this.syms, this.blank);

  /// من ملف tokens.txt: «رمز رقم» في كل سطر.
  factory PhonemeTokens.parse(String text) {
    final map = <int, String>{};
    for (final l in text.split('\n')) {
      final i = l.lastIndexOf(' ');
      if (i <= 0) continue;
      final id = int.tryParse(l.substring(i + 1).trim());
      if (id != null) map[id] = l.substring(0, i);
    }
    final n = map.keys.fold(0, math.max) + 1;
    var blank = n - 1;
    final syms = List.generate(n, (i) {
      final t = map[i] ?? '';
      if (t.startsWith('<')) {
        blank = i;
        return const <int>[];
      }
      return normalizePhonemes(t);
    });
    return PhonemeTokens._(syms, blank);
  }

  int get length => syms.length;
}

class _Heard {
  final int sym;
  final int frame;
  double conf;
  _Heard(this.sym, this.frame, this.conf);
}

class _Op {
  /// 0 مطابقة أو إبدال، 1 صوت زائد مسموع، 2 صوت منتظر لم يُسمع.
  final int type;
  final int h, x;
  const _Op(this.type, this.h, this.x);
}

class _Visit {
  final int word;
  final ops = <_Op>[];
  bool complete = false;

  /// أُسقطت الكلمة بقفزة فوقها (لم يُسمع منها شيء).
  bool jumped = false;

  /// عدد الكلمات التي قُفز فوقها معها.
  int span = 0;
  int lastHeard = -1;
  _Visit(this.word);
}

/// يتابع القارئ في نص منتظر (صفحة وما بعدها) من إطارات النموذج المتتابعة.
class PhonemeTracker {
  final PhonemeTokens tokens;
  final List<PhonWord> words = [];

  PhonemeTracker(this.tokens, List<PhonWord> initial) {
    words.addAll(initial);
    _state = List.filled(words.length, 0, growable: true);
    _link(0);
  }

  /// صامت في آخر كلمة هو نفسه أول التالية (إدغام: «فَمَن يُّجير» = «فَمَي» + «يُجير») يُسمع مرة
  /// واحدة وتأخذه الكلمة التالية، فلا تُحاسب الأولى عليه.
  void _link(int from) {
    for (var w = math.max(0, from - 1); w + 1 < words.length; w++) {
      final a = words[w], b = words[w + 1];
      if (a.ph.length > 1 && b.ph.isNotEmpty && a.ph.last == b.ph.first && a.core == a.ph.length) {
        words[w] = a.withCore(a.ph.length - 1);
      }
    }
  }

  /// يضيف ما بعد آخر النص (الصفحة التالية) ليكمل القارئ دون انقطاع.
  void extend(List<PhonWord> more) {
    final n = words.length;
    words.addAll(more);
    _state.addAll(List.filled(more.length, 0));
    _link(n);
    _dirty = true;
  }

  // 0 لم تُقرأ، 1 قُرئت، 2 خطأ.
  late List<int> _state;
  final Map<int, MistakeInfo> why = {};
  final Set<int> mistakes = {};

  /// أخطاء رفعها القارئ بيده («قرأتها صحيحة»): لا تعود.
  final Set<int> _dismissed = {};

  /// الكلمة المنتظرة الآن.
  int pos = 0;

  /// عدد الأخطاء التي ثبتت منذ آخر سؤال (لنغمة التنبيه).
  int _fresh = 0;
  int takeFresh() {
    final f = _fresh;
    _fresh = 0;
    return f;
  }

  /// هل طابق شيء مما سُمع النصَّ؟
  bool everMatched = false;

  /// القارئ في موضع لا يطابق ما حول الموضع الحالي: آخر ما سُمع من أصوات، ليُبحث عنه في المصحف.
  List<int>? lostTail;

  // ---------- ما سُمع ----------

  final _h = <_Heard>[];
  int _frame = 0;
  int _prevId = -1;
  int _silent = 0;
  _Heard? _open; // آخر صوت من الرمز الجاري، لتُحدَّث ثقته

  // أرجح ثلاثة رموز في كل إطار، ليُسأل: هل كان الصوت المنتظر محتملاً هنا؟
  static const _top = 3;
  final _topId = <int>[];
  final _topP = <double>[];
  int _topBase = 0; // رقم أول إطار محفوظ

  /// عدد الأصوات المسموعة منذ البدء (للاختبار).
  int heardCount = 0;

  /// يضيف [n] إطاراً من مخرج النموذج (لوغاريتم الاحتمال، [tokens.length] قيمة لكل إطار).
  /// [speech]: هل في الصوت قراءة الآن؟ (السكوت الطويل يثبّت الخطأ المعلّق.)
  void addFrames(Float32List lp, int n, {bool speech = true}) {
    final v = tokens.length;
    final ids = Uint8List(n * _top);
    final probs = Float32List(n * _top);
    for (var f = 0; f < n; f++) {
      final o = f * v;
      var b0 = 0, b1 = 0, b2 = 0;
      var p0 = -1e30, p1 = -1e30, p2 = -1e30;
      for (var i = 0; i < v; i++) {
        final x = lp[o + i];
        if (x > p0) {
          p2 = p1;
          b2 = b1;
          p1 = p0;
          b1 = b0;
          p0 = x;
          b0 = i;
        } else if (x > p1) {
          p2 = p1;
          b2 = b1;
          p1 = x;
          b1 = i;
        } else if (x > p2) {
          p2 = x;
          b2 = i;
        }
      }
      ids[f * 3] = b0;
      ids[f * 3 + 1] = b1;
      ids[f * 3 + 2] = b2;
      probs[f * 3] = math.exp(p0);
      probs[f * 3 + 1] = math.exp(p1);
      probs[f * 3 + 2] = math.exp(p2);
    }
    addTop(ids, probs, n, speech: speech);
  }

  /// كالسابق، وقد اختير لكل إطار أرجح ثلاثة رموز واحتمالاتها.
  void addTop(Uint8List ids, Float32List probs, int n, {bool speech = true}) {
    var added = false;
    for (var f = 0; f < n; f++) {
      final b0 = ids[f * 3];
      final p = probs[f * 3].toDouble();
      for (var k = 0; k < _top; k++) {
        _topId.add(ids[f * 3 + k]);
        _topP.add(probs[f * 3 + k]);
      }
      if (b0 != _prevId) {
        _open = null;
        if (b0 != tokens.blank) {
          for (final s in tokens.syms[b0]) {
            if (_h.isNotEmpty && _h.last.sym == s && _frame - _h.last.frame < 40) {
              _open = _h.last;
              continue;
            }
            final e = _Heard(s, _frame, p);
            _h.add(e);
            _open = e;
            heardCount++;
            added = true;
          }
        }
      } else if (b0 != tokens.blank) {
        final e = _open;
        if (e != null && p > e.conf) {
          // الثقة أعلى ما بلغه الرمز: كل أصوات الرمز الجاري تأخذها.
          for (var i = _h.length - 1; i >= 0 && _h[i].frame == e.frame; i--) {
            _h[i].conf = p;
          }
        }
      }
      _prevId = b0;
      _frame++;
    }
    _silent = speech ? 0 : _silent + n;
    if (added || _dirty) {
      _align();
    } else if (_silent >= _pauseFrames && _pending) {
      _settle();
    }
  }

  /// يثبّت ما عُلّق من أخطاء عند إيقاف المتابعة.
  void finish() {
    _silent = 1 << 20;
    if (_h.isNotEmpty) _align();
  }

  // ---------- المطابقة ----------

  static const _inf = 1 << 28;
  static const _jumpBack = 26, _jumpAhead = 46;
  static const _backWords = 30, _aheadSyms = 700;
  static const _pauseFrames = 30; // 1.2 ثانية
  static const _maxSkip = 12; // أكثر من ذلك انتقال إلى موضع آخر لا إسقاط

  /// أول كلمة يبدأ منها مسار المطابقة (ما قبلها ثبت وحُذف ما سُمع منه).
  int _start = 0;
  bool _dirty = false;
  bool _pending = false;

  // نافذة النص المنتظر
  int _lo = 0, _hi = 0;
  Uint16List _xs = Uint16List(0);
  Int32List _xw = Int32List(0);
  Int32List _wStart = Int32List(0); // موضع أول صوت لكل كلمة في النافذة (+ نهاية)
  final _rows = <Int32List>[];
  final _bt = <Uint8List>[];
  final _jumpSrc = <int, int>{};
  int _rowsFor = -1; // عدد الأصوات المسموعة التي حُسبت صفوفها

  // أزواج متقاربة المخرج يخلط بينها النموذج واللهجات (ذ ز، ث س، ظ ض، ظ ز، ذ ظ، س ص، ت ط، د ض،
  // د ذ، ت ث، ء هـ، ع ح، ح هـ، ح خ):
  // الفرق بينها من التجويد لا من ضبط الكلمة، فلا تُعدّ خطأ قراءة.
  static const _softPairs = <(int, int)>[
    (0x630, 0x632), (0x62B, 0x633), (0x638, 0x636), (0x638, 0x632), (0x630, 0x638), //
    (0x633, 0x635), (0x62A, 0x637), (0x62F, 0x636), (0x62F, 0x630), (0x62A, 0x62B), //
    (0x621, 0x647), (0x639, 0x62D), (0x62D, 0x647), (0x62D, 0x62E),
  ];

  static bool softPair(int a, int b) {
    for (final (x, y) in _softPairs) {
      if ((a == x && b == y) || (a == y && b == x)) return true;
    }
    return false;
  }

  static int _sub(int h, int x) {
    if (h == x) return 0;
    final hv = _isVowel(h), xv = _isVowel(x);
    if (hv != xv) return 10;
    if (hv) {
      if (_isShort(h) && _isShort(x)) return 6;
      // مد وحركة من جنسه (فتحة وألف، ضمة وواو، كسرة وياء): فرق في المقدار.
      if ((h == _fatha && x == _alif) || (h == _alif && x == _fatha) || (h == _damma && x == _waw) ||
          (h == _waw && x == _damma) || (h == _kasra && x == _ya) || (h == _ya && x == _kasra)) {
        return 3;
      }
      return 8;
    }
    return softPair(h, x) ? 6 : 10;
  }

  int _del(int j) {
    final w = words[_xw[j]];
    final k = j - _wStart[_xw[j] - _lo];
    if (k < w.lead || k >= w.core) return 2;
    return _isVowel(_xs[j]) ? 5 : 10;
  }

  static int _ins(int h) => _isVowel(h) ? 4 : 9;

  void _window() {
    _lo = math.max(0, _start - _backWords);
    var hi = math.max(_start, math.min(pos, words.length)), len = 0;
    while (hi < words.length && len < _h.length + _aheadSyms) {
      len += words[hi].ph.length;
      hi++;
    }
    _hi = hi;
    var m = 0;
    for (var w = _lo; w < _hi; w++) {
      m += words[w].ph.length;
    }
    _xs = Uint16List(m);
    _xw = Int32List(m);
    _wStart = Int32List(_hi - _lo + 1);
    var j = 0;
    for (var w = _lo; w < _hi; w++) {
      _wStart[w - _lo] = j;
      for (final c in words[w].ph) {
        _xs[j] = c;
        _xw[j] = w;
        j++;
      }
    }
    _wStart[_hi - _lo] = m;
    _rows.clear();
    _bt.clear();
    _jumpSrc.clear();
    _rowsFor = -1;
  }

  /// يكمل الصف بالإسقاط والقفز: إسقاط أصوات منتظرة، أو قفزة إلى أول كلمة (رجوعاً لتكرار،
  /// أو تقدّماً فوق كلمات لم تُقرأ).
  void _relax(int i, Int32List cur, Uint8List bt) {
    final m = _xs.length;
    for (var j = 1; j <= m; j++) {
      final c = cur[j - 1] + _del(j - 1);
      if (c < cur[j]) {
        cur[j] = c;
        bt[j] = 2;
      }
    }
    // أقل كلفة قبل كل موضع وبعده.
    final nw = _hi - _lo;
    var changed = false;
    // قفزة إلى الأمام: من أي موضع قبل أول الكلمة.
    var best = _inf, bestJ = -1;
    var w = 0;
    for (var j = 0; j <= m && w < nw; j++) {
      if (j == _wStart[w]) {
        if (best + _jumpAhead < cur[j]) {
          cur[j] = best + _jumpAhead;
          bt[j] = 3;
          _jumpSrc[i * (m + 1) + j] = bestJ;
          changed = true;
        }
        w++;
      }
      if (cur[j] < best) {
        best = cur[j];
        bestJ = j;
      }
    }
    // قفزة إلى الخلف: من أي موضع بعد أول الكلمة.
    best = _inf;
    bestJ = -1;
    w = nw - 1;
    for (var j = m; j >= 0 && w >= 0; j--) {
      if (j == _wStart[w]) {
        if (best + _jumpBack < cur[j]) {
          cur[j] = best + _jumpBack;
          bt[j] = 3;
          _jumpSrc[i * (m + 1) + j] = bestJ;
          changed = true;
        }
        w--;
      }
      if (cur[j] < best && bt[j] != 3) {
        best = cur[j];
        bestJ = j;
      }
    }
    if (!changed) return;
    for (var j = 1; j <= m; j++) {
      final c = cur[j - 1] + _del(j - 1);
      if (c < cur[j]) {
        cur[j] = c;
        bt[j] = 2;
        _jumpSrc.remove(i * (m + 1) + j);
      }
    }
  }

  void _computeRows() {
    final m = _xs.length;
    if (_rowsFor < 0) {
      final cur = Int32List(m + 1)..fillRange(0, m + 1, _inf);
      final bt = Uint8List(m + 1);
      final s = _start < _hi ? _wStart[_start - _lo] : m;
      cur[s] = 0;
      bt[s] = 9; // البداية
      _relax(0, cur, bt);
      _rows.add(cur);
      _bt.add(bt);
      _rowsFor = 0;
    }
    while (_rowsFor < _h.length) {
      final i = _rowsFor + 1;
      final h = _h[i - 1].sym;
      final prev = _rows[i - 1];
      final cur = Int32List(m + 1);
      final bt = Uint8List(m + 1);
      final ins = _ins(h);
      cur[0] = prev[0] + ins;
      bt[0] = 1;
      for (var j = 1; j <= m; j++) {
        var c = prev[j - 1] + _sub(h, _xs[j - 1]);
        var b = 0;
        final u = prev[j] + ins;
        if (u < c) {
          c = u;
          b = 1;
        }
        cur[j] = c;
        bt[j] = b;
      }
      _relax(i, cur, bt);
      _rows.add(cur);
      _bt.add(bt);
      _rowsFor = i;
    }
  }

  /// مسار المطابقة الأرجح حتى آخر ما سُمع: زيارات الكلمات بترتيب السماع.
  List<_Visit> _trace() {
    final m = _xs.length, n = _h.length;
    final last = _rows[n];
    var j = 0;
    for (var k = 1; k <= m; k++) {
      if (last[k] < last[j]) j = k;
    }
    _endJ = j;
    // من النهاية إلى البداية.
    final rev = <_Op>[];
    var i = n;
    while (true) {
      final b = _bt[i][j];
      if (b == 9) break;
      if (b == 0) {
        rev.add(_Op(0, i - 1, j - 1));
        i--;
        j--;
      } else if (b == 1) {
        rev.add(_Op(1, i - 1, j));
        i--;
      } else if (b == 2) {
        rev.add(_Op(2, -1, j - 1));
        j--;
      } else {
        final src = _jumpSrc[i * (m + 1) + j]!;
        rev.add(_Op(3, j, src)); // h = الهدف، x = المصدر
        j = src;
      }
    }
    final visits = <_Visit>[];
    _Visit? cur;
    var lastH = -1;
    void close() {
      final v = cur;
      if (v == null) return;
      final w = words[v.word];
      final first = v.ops.firstWhere((o) => o.type != 1, orElse: () => const _Op(1, 0, 0));
      final lastX = v.ops.lastWhere((o) => o.type != 1, orElse: () => const _Op(1, 0, 0));
      final s = _wStart[v.word - _lo];
      v.complete = first.type != 1 && first.x == s && lastX.x - s >= w.core - 1;
      v.lastHeard = lastH;
      visits.add(v);
      cur = null;
    }

    for (var r = rev.length - 1; r >= 0; r--) {
      final o = rev[r];
      if (o.type == 3) {
        close();
        final from = o.x >= m ? _hi : _xw[o.x] + (o.x == _wStart[_xw[o.x] - _lo] ? 0 : 1);
        final to = o.h >= m ? _hi : _xw[o.h];
        // كلمات قُفز فوقها إلى الأمام: لم تُقرأ.
        for (var w = from; w < to; w++) {
          visits.add(_Visit(w)
            ..jumped = true
            ..complete = true
            ..span = to - from
            ..lastHeard = lastH);
        }
        continue;
      }
      if (o.type == 1) {
        lastH = o.h;
        // صوت زائد: ينسب إلى الكلمة الجارية إن لم تكتمل، وإلا فهو بين الكلمات.
        cur?.ops.add(o);
        continue;
      }
      final w = _xw[o.x];
      if (cur == null || cur!.word != w) {
        close();
        cur = _Visit(w);
      }
      cur!.ops.add(o);
      if (o.type == 0) lastH = o.h;
    }
    final open = cur;
    close();
    // الكلمة الجارية: التي لم تكتمل زيارتها في آخر المسار.
    if (open != null && !open.complete) {
      pos = open.word;
    } else if (open != null) {
      pos = open.word + 1;
    } else if (_endJ < m) {
      pos = _xw[_endJ];
    } else {
      pos = _hi;
    }
    return visits;
  }

  int _endJ = 0;

  /// هل كان الصوت [x] محتملاً بين الإطارين؟ (أحد أرجح الرموز فيهما يحويه باحتمال معتبر.)
  bool _plausible(int x, int fromFrame, int toFrame, [double minP = 0.08]) {
    final a = math.max(fromFrame, _topBase), b = math.min(toFrame, _frame - 1);
    for (var f = a; f <= b; f++) {
      final o = (f - _topBase) * _top;
      for (var k = 0; k < _top; k++) {
        if (_topP[o + k] < minP) break;
        final s = tokens.syms[_topId[o + k]];
        for (final c in s) {
          if (c == x) return true;
        }
      }
    }
    return false;
  }

  /// يحكم على زيارة كلمة: null إن قُرئت صحيحة، وإلا نوع الخطأ وما سُمع.
  MistakeInfo? _judge(_Visit v) {
    final w = words[v.word];
    final s = _wStart[v.word - _lo];
    if (v.jumped) return MistakeInfo(MistakeKind.skipped, null, 0, 0, v.word, v.word + 1);
    var cons = 0, issues = 0, matched = 0, vowelIssues = 0, heardCons = 0;
    final heard = <int>[];
    // أول صامت بعد سكتة: بداية الصوت تُسمع همزة أو يضيع أولها، فلا يُحاسب عليه.
    var firstCons = -1;
    for (var k = w.lead; k < w.core; k++) {
      if (!_isVowel(w.ph[k])) {
        firstCons = k;
        break;
      }
    }
    var afterPause = false;
    for (final o in v.ops) {
      if (o.h >= 0 && o.type != 2) {
        afterPause = o.h == 0 ? _h[0].frame < 20 || _start == v.word : _h[o.h].frame - _h[o.h - 1].frame >= 12;
        break;
      }
    }
    for (var q = 0; q < v.ops.length; q++) {
      final o = v.ops[q];
      if (o.type == 1) {
        final e = _h[o.h];
        heard.add(e.sym);
        if (!_isVowel(e.sym)) heardCons++;
        continue;
      }
      final k = o.x - s;
      final x = _xs[o.x];
      final strict = k >= w.lead && k < w.core;
      final isCons = !_isVowel(x);
      if (strict && isCons) cons++;
      if (o.type == 0) {
        final e = _h[o.h];
        heard.add(e.sym);
        if (!_isVowel(e.sym)) heardCons++;
        if (e.sym == x) {
          if (strict && isCons) matched++;
          continue;
        }
        if (!strict) continue;
        if (isCons) {
          if (softPair(e.sym, x)) {
            matched++;
            continue;
          }
          if (afterPause && k == firstCons && e.sym == _hamza) continue;
          // حرف مكان حرف: خطأ إن وثق النموذج بما سمع ولم يكن المنتظر محتملاً هناك.
          if (!_isVowel(e.sym) && e.conf < 0.5) continue;
          if (_plausible(x, e.frame - 2, e.frame + 2)) continue;
          issues++;
          debug?.add('${v.word} sub ${String.fromCharCode(e.sym)}/${String.fromCharCode(x)} conf ${e.conf.toStringAsFixed(2)} ${_topAt(e.frame)}');
        } else if (_isShort(x) && _isShort(e.sym)) {
          if (e.conf >= 0.85 && !_plausible(x, e.frame - 1, e.frame + 1, 0.04)) vowelIssues++;
        }
      } else {
        if (!strict || !isCons) continue;
        // الهاء والهمزة خفيّتان: سقوطهما من السمع ليس إسقاطاً من القراءة.
        if (x == _hamza || x == 0x647) continue;
        if (afterPause && k == firstCons) continue;
        // حرف منتظر لم يُسمع: خطأ إن لم يكن محتملاً بين ما سُمع قبله وبعده.
        var a = -1, b = -1;
        for (var p = q - 1; p >= 0; p--) {
          if (v.ops[p].h >= 0 && v.ops[p].type != 2) {
            a = _h[v.ops[p].h].frame;
            break;
          }
        }
        for (var p = q + 1; p < v.ops.length; p++) {
          if (v.ops[p].h >= 0 && v.ops[p].type != 2) {
            b = _h[v.ops[p].h].frame;
            break;
          }
        }
        if (a < 0 && b < 0) {
          issues++;
          debug?.add('${v.word} del ${String.fromCharCode(x)} no context');
          continue;
        }
        if (a < 0) a = b - 6;
        if (b < 0) b = a + 6;
        if (_plausible(x, a - 1, b + 1)) continue;
        issues++;
        debug?.add('${v.word} del ${String.fromCharCode(x)} frames $a-$b');
      }
    }
    if (issues == 0 && vowelIssues == 0) return null;
    final text = heard.isEmpty ? null : phonemesToText(heard);
    if (issues > 0) {
      if (matched == 0 && heardCons == 0) return MistakeInfo(MistakeKind.skipped, null, 0, 0, v.word, v.word + 1);
      final kind = issues * 2 > cons ? MistakeKind.substituted : MistakeKind.letters;
      return MistakeInfo(kind, text, 0, 0, v.word, v.word + 1);
    }
    if (!judgeHarakat) return null;
    return MistakeInfo(MistakeKind.harakat, text, 0, 0, v.word, v.word + 1);
  }

  /// للاختبار: تفاصيل ما عُدّ خطأً.
  List<String>? debug;

  String _topAt(int f) {
    if (f < _topBase || f >= _frame) return '';
    final o = (f - _topBase) * _top;
    return [
      for (var k = 0; k < _top; k++) '${phonemesToText(tokens.syms[_topId[o + k]])}:${_topP[o + k].toStringAsFixed(2)}',
    ].join(' ');
  }

  /// هل تُحسب الحركة المبدلة في وسط الكلمة خطأً؟
  bool judgeHarakat = true;

  void _align() {
    if (_dirty || _rowsFor < 0 || _start < _lo || _needWider()) _window();
    _dirty = false;
    _computeRows();
    _settle();
    _commit();
  }

  bool _needWider() {
    // اقترب القارئ من آخر النافذة وفي النص بعدها بقية.
    return _hi < words.length && _xs.length - _endJ < 160;
  }

  void _setState(int w, MistakeInfo? info) {
    // البسملة بين السورتين قد لا يقرؤها القارئ: تركها ليس خطأً.
    if (info != null && info.kind == MistakeKind.skipped && words[w].key < 0) {
      mistakes.remove(w);
      why.remove(w);
      return;
    }
    if (info == null || _dismissed.contains(w)) {
      _state[w] = 1;
      mistakes.remove(w);
      why.remove(w);
    } else {
      _state[w] = 2;
      why[w] = info;
      if (mistakes.add(w)) _fresh++;
    }
  }

  List<_Visit> _visits = const [];

  /// هل ثبتت قراءة قبل أول ما بقي مما سُمع؟ (فالقفزة بعدها إسقاط لا بدء من وسط الصفحة.)
  bool _anchored = false;

  /// يحكم على الزيارات ويثبّت ما آن أن يثبت.
  void _settle() {
    if (_rowsFor < 0) return;
    final visits = _trace();
    final verdicts = List<MistakeInfo?>.generate(visits.length, (q) => visits[q].complete ? _judge(visits[q]) : null);
    _visits = visits;
    final n = _h.length;
    final paused = _silent >= _pauseFrames;
    _pending = false;
    // ما رُجع إليه وأُعيد يُحكم عليه بآخر قراءة.
    var badRun = 0, okAll = 0;
    var anchored = _anchored;
    bool okAt(int r) => visits[r].complete && !visits[r].jumped && verdicts[r] == null;
    for (var q = 0; q < visits.length; q++) {
      final v = visits[q];
      if (!v.complete) continue;
      final info = verdicts[q];
      if (info == null) {
        if (!v.jumped) {
          anchored = true;
          badRun = 0;
          okAll++;
          if (okAll >= 2) everMatched = true;
          _setState(v.word, null);
        }
        continue;
      }
      // الكلمة المتروكة ليست ضياعاً للموضع: الضياع كلمات متتالية سُمع مكانها غيرها.
      if (!v.jumped) badRun++;
      // خطأ: يثبت إن صحّ ما بعده (فالقارئ مضى في النص)، أو سكت القارئ بعده وقد صحّ ما قبله.
      final lag = n - 1 - v.lastHeard;
      var okAfter = 0;
      for (var r = q + 1; r < visits.length && r <= q + 4; r++) {
        if (okAt(r)) okAfter++;
      }
      // ما صحّ قبله من الكلمات الثلاث السابقة (ومنها ما ثبت وحُذف من أول ما سُمع).
      var okBeforeN = 0;
      for (var k = 1; k <= 3; k++) {
        final r = q - k;
        if (r >= 0) {
          if (okAt(r)) okBeforeN++;
        } else {
          final w = v.word + r;
          if (w >= 0 && w < _start && _state[w] == 1) okBeforeN++;
        }
      }
      // قفزة من أول السماع (بدأ القارئ من وسط الصفحة) انتقال لا إسقاط، وكذا القفزة البعيدة.
      final skippedFar = v.jumped && (v.span > _maxSkip || !anchored);
      // لا يُحكم بخطأ إلا والقراءة حوله مطابقة للنص: ثلاث كلمات صحيحة قبله وبعده، وإلا فالقارئ
      // في موضع آخر تشابهت منه كلمة.
      final around = okBeforeN + okAfter >= 3;
      final confirmed = !skippedFar &&
          everMatched &&
          around &&
          ((okAfter >= 2 && lag >= 6) || (okAfter >= 1 && lag >= 14) || (paused && okBeforeN >= 2 && !v.jumped));
      if (confirmed) {
        _setState(v.word, info);
      } else {
        // معلّق: لا يُعرض خطأً حتى يتبيّن (والانتقال البعيد ليس إسقاطاً).
        if (!skippedFar) _pending = true;
        if (!v.jumped && _state[v.word] == 0) _state[v.word] = 1;
      }
    }
    // ضاع الموضع: كلمات متتالية لا تطابق، أو لم يطابق شيء أصلاً بعد أصوات كثيرة.
    lostTail = null;
    if ((badRun >= 4 || (!everMatched && n >= 30)) && n >= 24) {
      lostTail = [for (var i = math.max(0, n - 40); i < n; i++) _h[i].sym];
    }
  }

  /// يحذف ما ثبت من أول ما سُمع، ليبقى الحساب صغيراً.
  void _commit() {
    if (_h.length < 140) return;
    // أول زيارة من آخر عشر زيارات مكتملة: ما قبلها يثبت ويُحذف.
    var q = _visits.length - 1, kept = 0;
    while (q > 0 && kept < 10) {
      if (_visits[q].complete && !_visits[q].jumped) kept++;
      q--;
    }
    if (q <= 0) {
      if (_h.length < 400) return;
      // أصوات كثيرة بلا مطابقة: نبدأ من جديد من الموضع الحالي.
      _h.clear();
      _start = pos.clamp(0, words.length - 1);
      _dirty = true;
      _window();
      _computeRows();
      _visits = const [];
      return;
    }
    final v = _visits[q];
    final firstOp = v.ops.firstWhere((o) => o.h >= 0 && o.type != 2, orElse: () => const _Op(2, -1, 0));
    if (firstOp.h <= 0 || v.jumped) return;
    // ما لم يثبته [_settle] قبل نقطة الحذف (وقد سُمع بعده عشر كلمات) لا يثبت: لم تصحّ القراءة حوله.
    _h.removeRange(0, firstOp.h);
    _start = v.word;
    _anchored = true;
    final drop = (_frame - 400 - _topBase).clamp(0, _topId.length ~/ _top);
    if (drop > 0) {
      _topId.removeRange(0, drop * _top);
      _topP.removeRange(0, drop * _top);
      _topBase += drop;
    }
    _dirty = true;
    _window();
    _computeRows();
    _visits = _trace();
  }

  // ---------- للشاشة ----------

  bool get finished => pos >= words.length;

  int? get currentKey => words.isEmpty ? null : words[pos.clamp(0, words.length - 1)].key;

  String displayKey(int w) => '${words[w].key}:${words[w].disp}';

  /// حال كل كلمة معروضة: مفتاحها «مفتاح الآية:رقم الكلمة».
  Map<String, WordState> get wordStates {
    final out = <String, WordState>{};
    for (var w = 0; w < words.length; w++) {
      out[displayKey(w)] = mistakes.contains(w)
          ? WordState.mistake
          : w == pos
          ? WordState.current
          : _state[w] == 1
          ? WordState.read
          : WordState.ahead;
    }
    return out;
  }

  int? positionOf(String key) {
    for (var w = 0; w < words.length; w++) {
      if (displayKey(w) == key) return w;
    }
    return null;
  }

  /// الأخطاء مقرونة بمفتاح آيتها والكلمة الصحيحة.
  List<(int, String)> get mistakeWords => [
        for (final w in mistakes.toList()..sort()) (words[w].key, words[w].text),
      ];

  void dismiss(int w) {
    _dismissed.add(w);
    mistakes.remove(w);
    why.remove(w);
    _state[w] = 1;
  }

  /// يضع الموضع عند الكلمة [disp] من الآية [key] (اختارها القارئ بيده).
  void startAtWord(int key, int disp) {
    var w = words.indexWhere((x) => x.key == key && x.disp >= disp);
    if (w < 0) w = words.indexWhere((x) => x.key == key);
    if (w >= 0) startAtIndex(w);
  }

  /// يضع الموضع بعد الكلمة [disp] من الآية [key] (آخر ما سُمع حين عُرف موضع القارئ).
  /// يعيد false إن لم تكن الآية في النص المنتظر.
  bool startAfter(int key, int disp) {
    final w = words.lastIndexWhere((x) => x.key == key && x.disp <= disp);
    if (w < 0) return false;
    // الموضع هو ما نحن عليه تقريباً: نبقى، فلا يضيع ما سُمع من الكلمة الجارية.
    if ((w + 1 - pos).abs() <= 2 && everMatched) return true;
    startAtIndex(math.min(w + 1, words.length - 1));
    return true;
  }

  /// يبدأ السماع من جديد عند الكلمة [w]، وينسى ما سُمع قبلها.
  void startAtIndex(int w) {
    w = w.clamp(0, words.length - 1);
    _start = w;
    pos = w;
    _h.clear();
    _prevId = -1;
    _open = null;
    everMatched = false;
    _anchored = false;
    lostTail = null;
    for (var i = w; i < words.length; i++) {
      if (_state[i] == 1) _state[i] = 0;
    }
    _dirty = true;
    _window();
    _computeRows();
    _visits = const [];
  }

  /// للاختبار: ما سُمع من أصوات لم يُحذف بعد.
  String get debugHeard => phonemesToText([for (final e in _h) e.sym]);
}

final _istiadha = normalizePhonemes('ءَعُۥۥذُبِللَااهِمِنَششَيطَاانِررَجِۦۦۦۦم');

/// هل ما سُمع استعاذة («أعوذ بالله من الشيطان الرجيم»)؟ ليست من نص الصفحة، فلا يُبحث عنها.
bool isIstiadha(List<int> heard) {
  final p = _istiadha, n = p.length;
  if (heard.length < n - 6) return false;
  // أقل كلفة لمطابقة الاستعاذة كلها في أي موضع مما سُمع.
  var prev = Int32List(n + 1), cur = Int32List(n + 1);
  for (var i = 0; i <= n; i++) {
    prev[i] = i * 10;
  }
  var best = 1 << 28;
  for (final h in heard) {
    cur[0] = 0;
    for (var i = 1; i <= n; i++) {
      var c = prev[i - 1] + PhonemeTracker._sub(h, p[i - 1]);
      final d = prev[i] + PhonemeTracker._ins(h);
      if (d < c) c = d;
      final e = cur[i - 1] + (_isVowel(p[i - 1]) ? 5 : 10);
      if (e < c) c = e;
      cur[i] = c;
    }
    if (cur[n] < best) best = cur[n];
    final t = prev;
    prev = cur;
    cur = t;
  }
  return best <= n * 1.6;
}

/// يجد موضع القارئ في المصحف كله من أصوات سمعها.
class PhonemeLocator {
  final Uint16List _text;
  final Int32List _aya; // رقم الآية العام لكل صوت
  final Int32List _word; // رقم الكلمة المعروضة في آيتها

  // فهرس الصوامت: كل ثلاثة صوامت متتالية ومواضعها، ليُحصر البحث في مواضع قليلة.
  final Int32List _cons; // موضع كل صامت في النص
  final Int64List _keys; // مفاتيح الثلاثيات مرتبة
  final Int32List _keyPos; // رقم الصامت الأول لكل مفتاح
  PhonemeLocator._(this._text, this._aya, this._word, this._cons, this._keys, this._keyPos);

  static int _key(int a, int b, int c) => (a << 32) | (b << 16) | c;

  /// [ayat]: رقم الآية العام وكلمات أصواتها (مفصولة بمسافات)، بترتيب المصحف.
  factory PhonemeLocator(Iterable<(int, String)> ayat) {
    final t = <int>[], a = <int>[], w = <int>[];
    for (final (id, words) in ayat) {
      var k = 0;
      for (final word in words.split(' ')) {
        for (final c in normalizePhonemes(word)) {
          t.add(c);
          a.add(id);
          w.add(k);
        }
        k++;
      }
    }
    final cons = <int>[
      for (var i = 0; i < t.length; i++)
        if (!_isVowel(t[i])) i,
    ];
    final n = cons.length - 2;
    final order = List<int>.generate(n < 0 ? 0 : n, (i) => i);
    final keyOf = Int64List(order.length);
    for (var i = 0; i < order.length; i++) {
      keyOf[i] = _key(t[cons[i]], t[cons[i + 1]], t[cons[i + 2]]);
    }
    order.sort((x, y) => keyOf[x].compareTo(keyOf[y]));
    return PhonemeLocator._(
      Uint16List.fromList(t),
      Int32List.fromList(a),
      Int32List.fromList(w),
      Int32List.fromList(cons),
      Int64List.fromList([for (final i in order) keyOf[i]]),
      Int32List.fromList(order),
    );
  }

  /// أقرب موضع في المصحف لما سُمع: (الآية، الكلمة التي انتهى عندها السماع)، أو null إن لم
  /// يكن التطابق واضحاً أو تكرر في أكثر من موضع.
  (int aya, int word)? locate(List<int> heard) {
    final n = heard.length;
    if (n < 20) return null;
    // المواضع المرشحة: حيث تتوالى ثلاثيات الصوامت المسموعة في النص بالترتيب نفسه.
    final hc = [
      for (final c in heard)
        if (!_isVowel(c)) c,
    ];
    final votes = <int, int>{};
    for (var i = 0; i + 2 < hc.length; i++) {
      final key = _key(hc[i], hc[i + 1], hc[i + 2]);
      var lo = 0, hi = _keys.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (_keys[mid] < key) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      for (var k = lo; k < _keys.length && _keys[k] == key && k - lo < 4000; k++) {
        final d = (_keyPos[k] - i) >> 3;
        votes[d] = (votes[d] ?? 0) + 1;
      }
    }
    if (votes.isEmpty) return null;
    // صوت القطعة وجارتها معاً (الإزاحة تنزلق مع صامت زائد أو ناقص).
    final scored = <(int, int)>[
      for (final e in votes.entries) (e.value + (votes[e.key + 1] ?? 0), e.key),
    ]..sort((x, y) => y.$1.compareTo(x.$1));
    final top = scored.first.$1;
    if (top < 3) return null;
    var best = _inf2, bestJ = -1, second = _inf2;
    final seen = <int>[];
    var tried = 0;
    for (final (score, d) in scored) {
      if (tried >= 40 || score < 3 || score * 3 < top) break;
      final c0 = (d << 3) - 6;
      if (seen.any((x) => (x - c0).abs() < 12)) continue;
      seen.add(c0);
      tried++;
      final from = _cons[c0.clamp(0, _cons.length - 1)];
      final to = _cons[(c0 + hc.length + 28).clamp(0, _cons.length - 1)];
      final (cost, j) = _scan(heard, math.max(0, from - 4), math.min(_text.length, to + 6));
      if (j < 0) continue;
      if (cost < best) {
        if (bestJ >= 0 && (j - bestJ).abs() > n * 2) second = best;
        best = cost;
        bestJ = j;
      } else if (cost < second && (j - bestJ).abs() > n * 2) {
        second = cost;
      }
    }
    if (bestJ < 0 || best > n * 2.2) return null; // أكثر من نحو خُمس الأصوات مختلف
    if (second - best < n * 0.8) return null; // موضعان متشابهان: لا يُجزم
    return (_aya[bestJ - 1], _word[bestJ - 1]);
  }

  /// أقل كلفة لمطابقة [heard] كله منتهياً داخل النص [from, to)، وموضع نهايته.
  (int, int) _scan(List<int> heard, int from, int to) {
    final n = heard.length;
    var prev = Int32List(n + 1), cur = Int32List(n + 1);
    for (var i = 0; i <= n; i++) {
      prev[i] = i * 10;
    }
    var best = _inf2, bestJ = -1;
    for (var j = from + 1; j <= to; j++) {
      final x = _text[j - 1];
      cur[0] = 0;
      for (var i = 1; i <= n; i++) {
        var c = prev[i - 1] + PhonemeTracker._sub(heard[i - 1], x);
        final d = prev[i] + (_isVowel(x) ? 5 : 10);
        if (d < c) c = d;
        final e = cur[i - 1] + PhonemeTracker._ins(heard[i - 1]);
        if (e < c) c = e;
        cur[i] = c;
      }
      if (cur[n] < best) {
        best = cur[n];
        bestJ = j;
      }
      final t = prev;
      prev = cur;
      cur = t;
    }
    return (best, bestJ);
  }

  static const _inf2 = 1 << 28;
}
