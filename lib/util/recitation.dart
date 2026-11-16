import 'arabic.dart';

/// مقطع يُتلى: آية (مفتاحها رقمها العام) أو بسملة قبل السورة (مفتاحها سالب).
class RecitedSegment {
  final int key;
  final List<String> words;
  RecitedSegment(this.key, String plain) : words = recitationWords(plain);
}

/// كلمات النص بعد التطبيع، دون علامات الترقيم والأرقام.
List<String> recitationWords(String s) {
  final t = normalizeArabic(s).replaceAll(RegExp(r'[^ء-ي\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? const [] : t.split(' ');
}

/// يتابع موضع القارئ في نص الصفحة من كلمات يسمعها التعرّف على الكلام.
///
/// يمضي كلمة كلمة مع النص، ويتسامح مع خطأ حرف أو حرفين في الكلمة،
/// ويقفز إلى الأمام إن تطابقت كلمتان متتاليتان أو أكثر (إذا تخطى القارئ شيئاً
/// أو أخطأ التعرّف في كلمة). لا يرجع إلى الوراء من نفسه.
class RecitationTracker {
  final List<int> _keys = [];
  final List<String> _words = [];
  final List<int> _wordSeg = [];

  /// موضع الكلمة التالية المنتظرة.
  int pos = 0;

  RecitationTracker(List<RecitedSegment> segments) {
    for (var i = 0; i < segments.length; i++) {
      _keys.add(segments[i].key);
      for (final w in segments[i].words) {
        _words.add(w);
        _wordSeg.add(i);
      }
    }
  }

  int get length => _words.length;
  bool get finished => pos >= _words.length;

  /// مفتاح المقطع الذي يقرؤه الآن (آخر مقطع إن انتهت الصفحة).
  int? get currentKey {
    if (_words.isEmpty) return null;
    return _keys[_wordSeg[pos.clamp(0, _words.length - 1)]];
  }

  /// يبدأ المتابعة من أول مقطع مفتاحه [key].
  void startAt(int key) {
    final seg = _keys.indexOf(key);
    if (seg < 0) return;
    final i = _wordSeg.indexOf(seg);
    if (i >= 0) pos = i;
  }

  /// يمرّر كلمات العبارة الحالية بدءاً من [from]، ويعيد عدد الكلمات المستهلكة منها.
  /// الكلمة الأخيرة لا تُستهلك إن لم تطابق، لأن التعرّف قد يصححها في النتيجة التالية.
  int feed(List<String> heard, int from) {
    var i = from;
    while (i < heard.length && !finished) {
      if (similarWord(heard[i], _words[pos])) {
        pos++;
        i++;
        continue;
      }
      final jump = _findAhead(heard, i);
      if (jump != null) {
        pos = jump.$1;
        i += jump.$2;
        continue;
      }
      if (i + 1 < heard.length) {
        i++; // كلمة زائدة أو لم يُتعرّف عليها جيداً
      } else {
        break;
      }
    }
    return i;
  }

  /// يبحث أمام الموضع عن تطابق كلمات متتالية تبدأ بالكلمة [i] من المسموع.
  (int, int)? _findAhead(List<String> heard, int i) {
    const window = 160;
    final end = (pos + window).clamp(0, _words.length);
    for (var j = pos + 1; j < end; j++) {
      if (!similarWord(heard[i], _words[j])) continue;
      // كلما بعدت القفزة احتجنا إلى تطابق أطول حتى لا نقفز خطأً.
      final need = j - pos <= 12 ? 2 : 3;
      if (i + need > heard.length) return null; // ننتظر كلمات أكثر
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

/// تطابق كلمتين مع تسامح يسير: الواو والفاء في أولها، وفرق حرف أو حرفين بحسب الطول.
bool similarWord(String a, String b) {
  if (a == b) return true;
  String strip(String s) => s.length > 3 && (s.startsWith('و') || s.startsWith('ف')) ? s.substring(1) : s;
  final x = strip(a), y = strip(b);
  if (x == y) return true;
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
