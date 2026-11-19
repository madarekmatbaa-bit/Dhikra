import 'dart:typed_data';

import 'phoneme_tracker.dart';
import 'recitation.dart' show MistakeInfo, WordState;

/// يقود متابعة التلاوة بالأصوات عبر صفحات المصحف: يبني المتابِع من الصفحة المفتوحة والتي
/// بعدها، ويمدّه كلما تقدّم القارئ، ويطلب قلب الصفحة حين يعبرها، ويبحث عن موضعه في المصحف
/// كله إن قرأ من غير الموضع المنتظر. لا يعرف شيئاً عن الواجهة، فيُختبر وحده.
class PhonemeFollower {
  final PhonemeTokens tokens;

  /// كلمات الصفحة بأصواتها (ومنها البسملة قبل أول السورة بمفتاح سالب).
  final Future<List<PhonWord>> Function(int page) pageWords;

  /// موضع ما سُمع في المصحف كله: (الآية، الكلمة التي انتهى عندها)، أو null.
  final Future<(int, int)?> Function(List<int> heard) locate;
  final Future<int?> Function(int aya) pageOfAya;
  final int lastPage;

  /// اطلب عرض الصفحة (عبرها القارئ، أو وُجد موضعه فيها).
  void Function(int page)? onGoto;

  /// عُرف موضع القارئ في آية (لإعلامه).
  void Function(int aya, int page)? onLocated;

  /// انتقل القارئ إلى آية ليست التالية لما قرأ: يُنبَّه ويبقى الموضع حيث وقف.
  void Function()? onWrongPlace;

  /// تغيّر شيء خارج [addTop] (بعد بحث أو بناء): حدّث العرض.
  void Function()? onChanged;

  /// متابِع انتهى عمله (أُعيد البناء أو أُوقفت المتابعة): اجمع أخطاءه.
  void Function(PhonemeTracker t)? onRetire;

  PhonemeFollower({
    required this.tokens,
    required this.pageWords,
    required this.locate,
    required this.pageOfAya,
    this.lastPage = 604,
  });

  PhonemeTracker? tracker;

  /// الصفحة المعروضة.
  int page = 0;

  /// حال كل كلمة قُرئت في الجلسة، بمفتاح «الآية:الكلمة» (المفاتيح لا تتكرر بين الصفحات).
  final states = <String, WordState>{};

  /// أسباب أخطاء متابِع سابق، لتُشرح بعد أن يمضي القارئ عنها.
  final oldWhy = <String, (MistakeInfo?, String)>{};

  final _pageFirst = <int, int>{};
  int _last = 0;
  int _gen = 0;
  bool _extending = false;
  bool _locating = false;
  int? _flip;
  (int, int)? _pending;
  int _framesAtLocate = -1000;
  int _frames = 0;
  bool located = false;

  int? get currentKey {
    final t = tracker;
    return t == null || t.finished ? null : t.currentKey;
  }

  /// يبدأ المتابعة من أول الصفحة [p] (أو من الموضع الذي وُجد فيها).
  Future<void> open(int p) async {
    final gen = ++_gen;
    page = p;
    _flip = null;
    _retire();
    states.updateAll((_, v) => v == WordState.current ? WordState.read : v);
    final words = await pageWords(p);
    final next = p < lastPage ? await pageWords(p + 1) : const <PhonWord>[];
    if (gen != _gen || words.isEmpty) return;
    final t = PhonemeTracker(tokens, words);
    _pageFirst
      ..clear()
      ..[p] = 0;
    _last = p;
    if (next.isNotEmpty) {
      _pageFirst[p + 1] = words.length;
      t.extend(next);
      _last = p + 1;
    }
    final pending = _pending;
    _pending = null;
    if (pending != null) t.startAfter(pending.$1, pending.$2);
    tracker = t;
    _sync();
    onChanged?.call();
  }

  void _retire() {
    final old = tracker;
    if (old == null) return;
    old.finish();
    for (final w in old.mistakes) {
      oldWhy[old.displayKey(w)] = (old.why[w], old.words[w].text);
    }
    states.addAll(old.wordStates);
    onRetire?.call(old);
    tracker = null;
  }

  /// يوقف المتابعة ويثبّت ما عُلّق من أخطاء.
  void stop() {
    _gen++;
    _retire();
    states.updateAll((_, v) => v == WordState.current ? WordState.read : v);
  }

  /// عُرضت الصفحة [p]: إن لم يكن المتابِع من طلبها فقد قلبها القارئ بيده، فيبدأ منها.
  Future<void> pageShown(int p) async {
    if (_flip == p) {
      _flip = null;
      page = p;
      return;
    }
    if (p == page && tracker != null) return;
    await open(p);
  }

  int _pageOfWord(int w) {
    var best = page, first = -1;
    _pageFirst.forEach((p, f) {
      if (f <= w && f > first) {
        first = f;
        best = p;
      }
    });
    return best;
  }

  void _sync() {
    final t = tracker;
    if (t != null) states.addAll(t.wordStates);
  }

  /// إطارات جديدة من النموذج. يعيد عدد الأخطاء التي ثبتت بها (لنغمة التنبيه).
  int addTop(Uint8List ids, Float32List probs, int n, {bool speech = true}) {
    final t = tracker;
    if (t == null) return 0;
    _frames += n;
    t.addTop(ids, probs, n, speech: speech);
    final fresh = t.takeFresh();
    if (t.takeOrderBreak()) onWrongPlace?.call();
    if (t.everMatched) located = true;
    if (!t.finished) {
      final pg = _pageOfWord(t.pos);
      if (pg != page && _flip != pg && t.everMatched) {
        _flip = pg;
        onGoto?.call(pg);
      }
      if (pg >= _last && _last < lastPage && !_extending) _extend(t);
    }
    // بحث كل ثانية ونصف على الأكثر.
    if (t.lostTail != null && !_locating && _frames - _framesAtLocate >= 38) _locate(t);
    _sync();
    return fresh;
  }

  Future<void> _extend(PhonemeTracker t) async {
    _extending = true;
    try {
      final p = _last + 1;
      final more = await pageWords(p);
      if (!identical(t, tracker) || p != _last + 1 || more.isEmpty) return;
      _pageFirst[p] = t.words.length;
      t.extend(more);
      _last = p;
    } finally {
      _extending = false;
    }
  }

  /// ما سُمع لا يطابق ما حول الموضع: نبحث عنه في المصحف كله وننتقل إليه.
  Future<void> _locate(PhonemeTracker t) async {
    final tail = t.lostTail;
    if (tail == null) return;
    _locating = true;
    try {
      if (isIstiadha(tail)) {
        t.startAtIndex(t.engaged ? t.resumeAt : t.pos);
        return;
      }
      final hit = await locate(tail);
      if (hit == null || !identical(t, tracker)) return;
      if (t.engaged && hit.$1 > t.lastReadAya + 1) {
        // بعد أن ثبت الموضع لا يُتبع القارئ إلى آية أبعد من التالية: خطأ ترتيب، ويبقى حيث وقف.
        t.breakOrder();
        t.takeOrderBreak();
        _sync();
        onWrongPlace?.call();
        onChanged?.call();
        return;
      }
      final p = await pageOfAya(hit.$1);
      if (p == null || !identical(t, tracker)) return;
      if (!located || p != page) onLocated?.call(hit.$1, p);
      located = true;
      if (t.startAfter(hit.$1, hit.$2)) {
        _sync();
        final pg = _pageOfWord(t.pos);
        if (pg != page) {
          _flip = pg;
          onGoto?.call(pg);
        }
        onChanged?.call();
      } else {
        _pending = hit;
        if (p == page) {
          await open(p);
        } else {
          onGoto?.call(p); // الواجهة تعرضها ثم تستدعي pageShown فيُبنى المتابِع فيها
        }
      }
    } finally {
      _framesAtLocate = _frames;
      _locating = false;
    }
  }

  /// يبدأ من أول الآية [aya] (اختارها القارئ بيده).
  void startAtAya(int aya) {
    final t = tracker;
    if (t == null) return;
    t.startAtWord(aya, 0);
    located = true;
    _sync();
  }

  /// يرفع الخطأ عن الكلمة [key] («قرأتها صحيحة»). يعيد نص الكلمة إن كان عليها خطأ.
  String? dismiss(String key) {
    final t = tracker;
    final k = t?.positionOf(key);
    String? word;
    if (t != null && k != null && t.mistakes.contains(k)) {
      word = t.words[k].text;
      t.dismiss(k);
    }
    word ??= oldWhy[key]?.$2;
    oldWhy.remove(key);
    if (word != null) states[key] = WordState.read;
    return word;
  }

  /// الكلمة [key] وسبب خطئها، أو null إن لم يكن عليها خطأ.
  (String, MistakeInfo?)? whyOf(String key) {
    final t = tracker;
    final k = t?.positionOf(key);
    if (t != null && k != null && t.mistakes.contains(k)) return (t.words[k].text, t.why[k]);
    final old = oldWhy[key];
    return old == null ? null : (old.$2, old.$1);
  }
}
