import 'recitation.dart';

/// موضع عثر عليه في المصحف: الآية التي بدأ منها القارئ، والآية والكلمة التي وصل إليها.
class LocatedRecitation {
  final int startAya;
  final int endAya;

  /// رقم الكلمة التالية في [endAya] (من كلماتها الإملائية).
  final int nextWord;
  final int page;
  final int matched;
  const LocatedRecitation(this.startAya, this.endAya, this.nextWord, this.page, this.matched);

  @override
  String toString() => 'Located($startAya→$endAya:$nextWord p$page m$matched)';
}

/// يعرف من أين يقرأ القارئ في المصحف كله من بضع كلمات يسمعها.
///
/// كل كلمة مسموعة تقترح مواضع بدء ممكنة (موضعها في المصحف ناقص ترتيبها في العبارة)،
/// فيُجمع لكل موضع عدد الكلمات التي تؤيده، ثم يُتحقق من أقوى المواضع بمطابقة
/// الكلمات بالترتيب مع تسامح في كلمة زائدة أو ساقطة.
class QuranLocator {
  final List<String> _words = [];
  final List<int> _aya = [];
  final List<int> _wordInAya = [];
  final List<int> _page = [];
  final Map<String, List<int>> _index = {};

  QuranLocator(Iterable<(int id, int page, String plain)> ayat) {
    for (final (id, page, plain) in ayat) {
      final w = recitationWords(plain);
      for (var k = 0; k < w.length; k++) {
        _index.putIfAbsent(wordKey(w[k]), () => []).add(_words.length);
        _words.add(w[k]);
        _aya.add(id);
        _wordInAya.add(k);
        _page.add(page);
      }
    }
  }

  int get length => _words.length;

  /// موضع أول كلمة في الآية [id] (للقرب من الموضع الحالي).
  int? wordOfAya(int id) {
    final i = _aya.indexOf(id);
    return i < 0 ? null : i;
  }

  /// يعيد الموضع إن كان واضحاً، أو null إن قلّت الكلمات أو احتملت أكثر من موضع.
  /// [near] موضع كلمة يُفضَّل ما قرب منه عند تساوي موضعين (العبارات المتكررة).
  LocatedRecitation? locate(List<String> heard, {int? near}) {
    final n = heard.length;
    if (n < 3) return null;
    final votes = <int, int>{};
    for (var i = 0; i < n; i++) {
      if (heard[i].length < 2) continue;
      final hits = _index[wordKey(heard[i])];
      // الكلمات الشائعة جداً («من»، «الله») لا تميّز موضعاً.
      if (hits == null || hits.length > 1500) continue;
      for (final p in hits) {
        final s = p - i;
        // نجمع البدايات المتقاربة معاً، فكلمة زائدة أو ساقطة لا تفرّق الأصوات.
        final b = s >> 2;
        votes[b] = (votes[b] ?? 0) + 1;
      }
    }
    if (votes.isEmpty) return null;
    final top = votes.entries.where((e) => e.value >= 2).toList()..sort((a, b) => b.value.compareTo(a.value));
    final results = <(int start, int end, int matched)>[];
    for (final e in top.take(40)) {
      for (var s = (e.key << 2) - 3; s <= (e.key << 2) + 4; s++) {
        final r = _verify(heard, s);
        if (r != null) results.add(r);
      }
    }
    if (results.isEmpty) return null;
    results.sort((a, b) => b.$3.compareTo(a.$3));
    final best = results.first.$3;
    final need = n <= 4 ? n : (n * 0.6).ceil();
    if (best < need || best < 3) return null;
    // المواضع المختلفة التي تطابق بالقدر نفسه (آيات متكررة في المصحف).
    final ties = <(int, int, int)>[];
    for (final r in results) {
      if (r.$3 < best) break;
      if (ties.every((t) => (t.$1 - r.$1).abs() > n)) ties.add(r);
    }
    var pick = ties.first;
    if (ties.length > 1) {
      if (near == null) return null;
      ties.sort((a, b) => (a.$1 - near).abs().compareTo((b.$1 - near).abs()));
      pick = ties.first;
      // تكرار بعيد عن الموضع الحالي: لا نعرف أيهما يقصد.
      if ((pick.$1 - near).abs() > 400) return null;
    }
    final end = pick.$2.clamp(0, _words.length - 1);
    final last = pick.$2 - 1;
    final next = pick.$2 >= _words.length ? _words.length - 1 : pick.$2;
    final endAya = _aya[next];
    final nextWord = _aya[last] == endAya ? _wordInAya[next] : 0;
    return LocatedRecitation(_aya[pick.$1.clamp(0, _words.length - 1)], endAya, nextWord, _page[end], pick.$3);
  }

  /// يطابق المسموع بالترتيب ابتداءً من [start]، ويعيد (أول كلمة طابقت، ما بعد آخر كلمة طابقت، عدد المطابقات).
  (int, int, int)? _verify(List<String> heard, int start) {
    if (start < 0 || start >= _words.length) return null;
    var p = start, matched = 0, first = -1, last = -1;
    for (var i = 0; i < heard.length && p < _words.length; i++) {
      // نبحث عن الكلمة في الموضع المنتظر أو بعده بكلمة أو اثنتين.
      var found = -1;
      for (var d = 0; d <= 2 && p + d < _words.length; d++) {
        if (similarWord(heard[i], _words[p + d])) {
          found = p + d;
          break;
        }
      }
      if (found >= 0) {
        if (first < 0) first = found;
        matched++;
        last = found;
        p = found + 1;
      }
    }
    if (matched == 0 || first != start && first - start > 2) return null;
    return (first, last + 1, matched);
  }
}
