import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../db/quran_db.dart';
import '../services/recitation_listener.dart';
import '../state/app_state.dart';
import '../state/quran_review.dart';
import '../theme.dart';
import '../util/recitation.dart';
import '../widgets/brand.dart';
import '../widgets/sura_header.dart';
import 'benefit_edit.dart';

/// قارئ المصحف: صفحة بصفحة كترتيب مصحف المدينة (604 صفحات).
///
/// الصفحة تظهر كاملة على قد الشاشة، أو بخط مكبَّر تمرَّر فيه. ومع زر الميكروفون
/// يتابع التطبيق تلاوة القارئ آيةً آية، ويمرّر الصفحة ويقلبها معه.
class QuranReader extends StatefulWidget {
  final int page;
  final int? highlightSura;
  final int? highlightAya;

  /// صفحات ورد اليوم، تظهر في الأعلى إن مُرّرت.
  final List<int>? portion;
  final String? portionTitle;

  /// يُستدعى بزر «أتممت الورد» في آخر صفحة منه.
  final Future<void> Function()? onFinishPortion;
  const QuranReader({
    super.key,
    required this.page,
    this.highlightSura,
    this.highlightAya,
    this.portion,
    this.portionTitle,
    this.onFinishPortion,
  });

  @override
  State<QuranReader> createState() => _QuranReaderState();
}

class _QuranReaderState extends State<QuranReader> {
  late final PageController _pc;
  late int page;
  bool fullscreen = false;

  // التكبير بإصبعين
  final _pointers = <int, Offset>{};
  double? _pinchStartDist, _pinchBase, _pinchFont;
  double? _lastFitFont;

  // متابعة التلاوة
  final _listener = RecitationListener();
  bool following = false;
  RecitationTracker? _tracker;
  int? _currentKey;
  int _consumed = 0;
  double _level = 0;
  final _alert = MistakeAlert();
  final _pageStates = <int, Map<String, WordState>>{};
  RecitationTracker? _phraseTracker;
  int _phrasePage = 0;
  int _mistakeCount = 0;

  /// أخطاء التسميع كله عبر الصفحات: رقم الآية العام ← كلماتها.
  final _session = <int, Set<String>>{};
  final _sessionStart = DateTime.now();

  void _collect(RecitationTracker t) {
    for (final (key, word) in t.mistakeWords) {
      if (key > 0) _session.putIfAbsent(key, () => {}).add(word);
    }
  }

  /// اختبار الحفظ: يُخفى النص وتظهر كل كلمة حين يقرؤها القارئ.
  bool hideText = false;

  @override
  void initState() {
    super.initState();
    page = widget.page.clamp(1, quranPages);
    _pc = PageController(initialPage: page - 1);
    if (widget.portion != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AppState>().quran.notePage(page);
      });
    }
    _listener
      ..onWords = _onWords
      ..onLevel = (l) {
        if (mounted && following) setState(() => _level = l);
      }
      ..onFatal = (m) {
        if (!mounted) return;
        setState(() => following = false);
        toast(context, m);
      };
  }

  @override
  void dispose() {
    _listener.stop();
    _alert.dispose();
    if (fullscreen) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pc.dispose();
    super.dispose();
  }

  void _go(int p) => _pc.jumpToPage(p.clamp(1, quranPages) - 1);

  Future<void> _openIndex() async {
    final p = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (c) => const QuranIndexSheet(),
    );
    if (p != null) _go(p);
  }

  Future<void> _jump() async {
    final ctl = TextEditingController();
    final p = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('اذهب إلى صفحة'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'من 1 إلى 604'),
          onSubmitted: (v) => Navigator.pop(c, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(ctl.text)), child: const Text('اذهب')),
        ],
      ),
    );
    if (p != null) _go(p);
  }

  void _setFullscreen(bool v) {
    setState(() => fullscreen = v);
    SystemChrome.setEnabledSystemUIMode(v ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    if (v) toast(context, 'اضغط على رأس الصفحة لإظهار الأزرار');
  }

  // ---------- التكبير ----------

  QuranReview get _q => context.read<AppState>().quran;

  void _zoomBy(double delta) {
    final q = _q;
    final base = q.fitPage ? (_lastFitFont ?? q.zoomFont) : q.zoomFont;
    q.setZoomFont(base + delta);
    q.setFitPage(false);
  }

  void _pointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      final q = _q;
      final v = _pointers.values.toList();
      _pinchStartDist = (v[0] - v[1]).distance;
      _pinchBase = q.fitPage ? (_lastFitFont ?? q.zoomFont) : q.zoomFont;
      setState(() {}); // نوقف قلب الصفحات أثناء التكبير
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length != 2 || _pinchStartDist == null || _pinchStartDist! < 10) return;
    final v = _pointers.values.toList();
    final ratio = (v[0] - v[1]).distance / _pinchStartDist!;
    final f = (_pinchBase! * ratio).clamp(16, 72).toDouble();
    if (_pinchFont == null && (ratio - 1).abs() < 0.04) return;
    setState(() => _pinchFont = f);
  }

  void _pointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2 && _pinchStartDist != null) {
      final f = _pinchFont;
      _pinchStartDist = null;
      if (f != null) {
        final q = _q;
        q.setZoomFont(f).then((_) => q.setFitPage(false)).then((_) {
          if (mounted) setState(() => _pinchFont = null);
        });
      } else {
        setState(() {});
      }
    }
  }

  // ---------- متابعة التلاوة ----------

  Future<void> _toggleFollow() async {
    if (following) {
      await _listener.stop();
      await Future.delayed(const Duration(milliseconds: 700)); // النتيجة النهائية الأخيرة
      if (!mounted) return;
      final t = _tracker;
      if (t != null) _collect(t);
      setState(() {
        following = false;
        hideText = false;
        _currentKey = null;
      });
      if (_session.isNotEmpty && mounted) await _showSummary();
      return;
    }
    final q = _q;
    if (!q.followIntroSeen) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('متابعة التلاوة'),
          content: const Text(
            'اقرأ بصوت واضح، أو شغّل تلاوة قارئ قرب الهاتف، فيتبعك التطبيق كلمةً كلمة: '
            'يلوّن الكلمة التي وصلت إليها، ويمرّر الصفحة ويقلبها معك. '
            'وإن أبدلت كلمة أو أسقطتها ظهرت بالأحمر مع نغمة تنبيه.\n\n'
            'ولمراجعة الحفظ اضغط زر العين فيُخفى النص، وتظهر كل كلمة حين تقرؤها.\n\n'
            'يبدأ من أول الصفحة، وإن بدأت من موضع آخر فاضغط على الآية التي تقرؤها.\n\n'
            'تعتمد المتابعة على خدمة التعرّف على الكلام في هاتفك (من Google عادة)، وقد ترسل الصوت إليها لتحويله إلى كلمات. '
            'ولا يُحفظ الصوت في التطبيق. الميزة تجريبية، وقد تتأخر أو تخطئ أحياناً.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ابدأ')),
          ],
        ),
      );
      if (ok != true) return;
      await q.setFollowIntroSeen();
    }
    await _buildTracker(page);
    final err = await _listener.start();
    if (!mounted) return;
    if (err != null) {
      toast(context, err);
      return;
    }
    setState(() => following = true);
  }

  /// ملخص التسميع: الآيات التي أخطأ فيها وكلماتها، مع حفظها في دفتر الغلطات.
  Future<void> _showSummary() async {
    final db = context.read<AppState>().quranDb;
    final ids = _session.keys.toList()..sort();
    final ayat = <Aya>[];
    for (final id in ids) {
      final a = await db.ayaById(id);
      if (a != null) ayat.add(a);
    }
    if (!mounted || ayat.isEmpty) return;
    final minutes = DateTime.now().difference(_sessionStart).inMinutes;
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) {
        final pal = Palette.of(c);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.75),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ملخص التسميع', style: TextStyle(fontFamily: readingFont, fontSize: 21, fontWeight: FontWeight.w700)),
                Text(
                  'أخطأت في ${ayat.length == 1 ? 'آية واحدة' : ayat.length == 2 ? 'آيتين' : '${ayat.length} آيات'}'
                  '${minutes > 0 ? ' خلال $minutes دقيقة' : ''}. راجعها قبل أن تنتقل.',
                  style: TextStyle(color: pal.muted, fontSize: 14),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: ayat.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: pal.line),
                    itemBuilder: (c, i) {
                      final a = ayat[i];
                      return InkWell(
                        onTap: () {
                          Navigator.pop(c);
                          _go(a.page);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('سورة ${db.suras[a.sura - 1].name} · الآية ${a.aya} · ص ${a.page}',
                                style: TextStyle(color: pal.muted, fontSize: 12.5)),
                            const SizedBox(height: 2),
                            Text(QuranDb.stripNumber(a.text),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontFamily: quranFont, fontSize: 19, height: 1.8)),
                            Text('الكلمات: ${_session[a.id]!.join('، ')}',
                                style: const TextStyle(color: mistakeColor, fontSize: 13.5, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(c, true),
                      icon: const Icon(Icons.sticky_note_2_outlined),
                      label: const Text('احفظها في دفتر الغلطات'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('لاحقاً')),
                ]),
              ]),
            ),
          ),
        );
      },
    );
    if (save != true || !mounted) return;
    final q = context.read<AppState>().quran;
    final now = DateTime.now().toIso8601String();
    for (final a in ayat) {
      await q.saveNote(QuranNote(
        sura: a.sura,
        aya: a.aya,
        kind: 'mistake',
        note: 'من التسميع: ${_session[a.id]!.join('، ')}',
        createdAt: now,
      ));
    }
    _session.clear();
    if (mounted) toast(context, 'حُفظت في دفتر الغلطات');
  }

  Future<void> _buildTracker(int p, {int? startKey}) async {
    final old = _tracker;
    if (old != null) _collect(old);
    final db = context.read<AppState>().quranDb;
    final ayat = await db.page(p);
    final segs = <RecitedSegment>[];
    for (final a in ayat) {
      if (a.aya == 1 && a.sura != 1 && a.sura != 9) {
        segs.add(RecitedSegment(-a.sura, db.basmalaPlain, uthmani: db.basmala));
      }
      segs.add(RecitedSegment(a.id, a.plain, uthmani: QuranDb.stripNumber(a.text)));
    }
    final t = RecitationTracker(segs)..strict = _q.strictLetters;
    if (startKey != null) t.startAt(startKey);
    if (!mounted || p != page) return;
    setState(() {
      _tracker = t;
      _currentKey = t.currentKey;
      _pageStates[p] = t.wordStates;
    });
  }

  void _onWords(List<List<String>> alternatives, bool newPhrase, bool isFinal) {
    if (!mounted) return;
    final t = _tracker;
    if (newPhrase) {
      _consumed = 0;
      t?.beginPhrase();
      _phraseTracker = t;
      _phrasePage = page;
    }
    var fresh = 0;
    if (isFinal && _phraseTracker != null) {
      // النتيجة النهائية أدق: نعيد العبارة كلها بها، ومنها وحدها نحكم على الأخطاء.
      final pt = _phraseTracker!;
      final r = pt.replayFinal(alternatives);
      fresh = r.$2;
      _collect(pt);
      _pageStates[_phrasePage] = pt.wordStates;
      _phraseTracker = null;
      if (!identical(pt, t)) {
        _report(fresh);
        setState(() {});
        return;
      }
      _consumed = r.$1;
    } else if (t != null) {
      _consumed = t.feed(t.best(alternatives, _consumed), _consumed, markMistakes: false).$1;
    } else {
      return;
    }
    _report(fresh);
    _pageStates[page] = t!.wordStates;
    if (t.finished && page < quranPages) {
      // انتهت الصفحة: نقلبها ونكمل بما بقي من العبارة نفسها.
      _collect(t);
      _tracker = null;
      _pc.nextPage(duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
      setState(() {});
      return;
    }
    setState(() => _currentKey = t.currentKey);
  }

  void _report(int fresh) {
    if (fresh <= 0) return;
    _mistakeCount += fresh;
    _alert.play(sound: _q.mistakeSound);
  }

  void _followFrom(Aya a) {
    final t = _tracker;
    if (t == null) return;
    t.startAt(a.id);
    setState(() {
      _currentKey = t.currentKey;
      _pageStates[page] = t.wordStates;
    });
  }

  Future<void> _toggleHide() async {
    if (hideText) {
      setState(() => hideText = false);
      return;
    }
    if (!following) await _toggleFollow();
    if (!mounted || !following) return;
    setState(() => hideText = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final db = s.quranDb;
    final pal = Palette.of(context);
    final sura = db.suraOfPage(page);
    final portion = widget.portion;
    final inPortion = portion?.indexOf(page) ?? -1;
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    // بالعرض تصغر الصفحة كثيراً لو حُشرت في الشاشة، فنعرضها بخط مقروء ونمرّرها.
    final fit = _pinchFont == null && s.quran.fitPage && !landscape;
    final zoomFont = _pinchFont ?? s.quran.zoomFont;
    final pinching = _pointers.length >= 2;

    final followBar = SafeArea(
      child: Container(
        color: pal.soft,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.all(4 + (_level.clamp(0, 10) / 10) * 4),
              decoration: BoxDecoration(color: AppColors.wheat.withValues(alpha: 0.35), shape: BoxShape.circle),
              child: const Icon(Icons.mic, color: AppColors.olive, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _currentKey == null
                    ? 'أستمع إلى التلاوة…'
                    : _currentKey! < 0
                    ? 'البسملة · سورة ${db.suras[-_currentKey! - 1].name}'
                    : hideText
                    ? 'اختبار الحفظ · صفحة $page'
                    : 'أتابعك في الصفحة $page',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
            if (_mistakeCount > 0)
              Container(
                margin: const EdgeInsetsDirectional.only(end: 4),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: mistakeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'أخطاء $_mistakeCount',
                  style: const TextStyle(fontSize: 13, color: mistakeColor, fontWeight: FontWeight.w500),
                ),
              ),
            IconButton(
              tooltip: hideText ? 'أظهر النص' : 'أخفِ النص لاختبار الحفظ',
              icon: Icon(hideText ? Icons.visibility_off : Icons.visibility_outlined),
              onPressed: _toggleHide,
            ),
            IconButton(tooltip: 'إيقاف', icon: const Icon(Icons.stop_circle_outlined), onPressed: _toggleFollow),
          ],
        ),
      ),
    );

    final portionBar = portion == null || portion.length < 2
        ? null
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: inPortion > 0 ? () => _go(portion[inPortion - 1]) : null,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('السابقة'),
                  ),
                  const Spacer(),
                  if (inPortion == portion.length - 1 && widget.onFinishPortion != null)
                    FilledButton.icon(
                      onPressed: () async {
                        await widget.onFinishPortion!();
                        if (!context.mounted) return;
                        toast(context, 'تقبّل الله، أتممت ورد اليوم');
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('أتممت الورد'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: inPortion >= 0 && inPortion < portion.length - 1
                          ? () => _go(portion[inPortion + 1])
                          : inPortion < 0
                          ? () => _go(portion.first)
                          : null,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(inPortion < 0 ? 'أول الورد' : 'التالية'),
                    ),
                ],
              ),
            ),
          );

    return Scaffold(
      appBar: fullscreen
          ? null
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('سورة ${sura.name}', style: const TextStyle(fontSize: 17)),
                  Text('الجزء ${db.juzOfPage(page)} · صفحة $page', style: TextStyle(fontSize: 12, color: pal.muted)),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: following ? 'أوقف متابعة التلاوة' : 'تابِع تلاوتي',
                  icon: Icon(following ? Icons.mic : Icons.mic_none, color: following ? AppColors.wheat : null),
                  onPressed: _toggleFollow,
                ),
                IconButton(tooltip: 'الفهرس', icon: const Icon(Icons.list), onPressed: _openIndex),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'jump':
                        _jump();
                      case 'fit':
                        s.quran.setFitPage(true);
                      case 'in':
                        _zoomBy(2);
                      case 'out':
                        _zoomBy(-2);
                      case 'full':
                        _setFullscreen(true);
                      case 'hide':
                        _toggleHide();
                      case 'sound':
                        s.quran.setMistakeSound(!s.quran.mistakeSound);
                      case 'strict':
                        s.quran.setStrictLetters(!s.quran.strictLetters);
                        _tracker?.strict = s.quran.strictLetters;
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'jump', child: Text('اذهب إلى صفحة')),
                    const PopupMenuItem(value: 'in', child: Text('كبّر الخط')),
                    const PopupMenuItem(value: 'out', child: Text('صغّر الخط')),
                    if (!s.quran.fitPage) const PopupMenuItem(value: 'fit', child: Text('الصفحة على قد الشاشة')),
                    const PopupMenuItem(value: 'full', child: Text('ملء الشاشة')),
                    PopupMenuItem(value: 'hide', child: Text(hideText ? 'أظهر النص' : 'اختبر حفظك (أخفِ النص)')),
                    CheckedPopupMenuItem(
                      value: 'sound',
                      checked: s.quran.mistakeSound,
                      child: const Text('نغمة عند الخطأ'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'strict',
                      checked: s.quran.strictLetters,
                      child: const Text('دقّق في الحروف'),
                    ),
                  ],
                ),
              ],
              bottom: portion == null
                  ? null
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(34),
                      child: Container(
                        height: 34,
                        color: pal.soft,
                        alignment: Alignment.center,
                        child: Text(
                          inPortion >= 0
                              ? '${widget.portionTitle ?? 'الورد'}: ${inPortion + 1} من ${portion.length}'
                              : '${widget.portionTitle ?? 'الورد'}: خارج صفحات الورد',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
            ),
      body: Listener(
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerUp,
        child: PageView.builder(
          controller: _pc,
          itemCount: quranPages,
          physics: pinching ? const NeverScrollableScrollPhysics() : null,
          onPageChanged: (i) {
            setState(() {
              page = i + 1;
              _currentKey = null;
            });
            s.quran.setLastPage(i + 1);
            if (widget.portion != null) s.quran.notePage(i + 1);
            if (following) _buildTracker(i + 1);
          },
          itemBuilder: (c, i) => QuranPageView(
            page: i + 1,
            fit: fit,
            zoomFont: zoomFont,
            highlightSura: widget.highlightSura,
            highlightAya: widget.highlightAya,
            currentKey: following && i + 1 == page ? _currentKey : null,
            wordStates: _pageStates[i + 1],
            hideText: hideText,
            onAyaTap: following ? _followFrom : null,
            onHeaderTap: fullscreen ? () => _setFullscreen(false) : null,
            onFitFont: (f) => _lastFitFont = f,
          ),
        ),
      ),
      bottomNavigationBar: following ? followBar : portionBar,
    );
  }
}

/// مقطع من الصفحة: ترويسة سورة، أو بسملة، أو آيات متتابعة.
class _Block {
  final Sura? sura;
  final bool basmala;
  final List<Aya> ayat;
  _Block.header(this.sura) : basmala = false, ayat = const [];
  _Block.basmala(this.sura) : basmala = true, ayat = const [];
  _Block.text(this.ayat) : sura = null, basmala = false;
  bool get isText => ayat.isNotEmpty;
}

/// صفحة من المصحف.
/// لون الكلمة الخاطئة في متابعة التلاوة.
const mistakeColor = Color(0xFFB3261E);

class QuranPageView extends StatefulWidget {
  final int page;
  final bool fit;
  final double zoomFont;
  final int? highlightSura;
  final int? highlightAya;

  /// الآية التي يقرؤها القارئ الآن (رقمها العام)، أو سالب رقم السورة للبسملة.
  final int? currentKey;

  /// حال كل كلمة أثناء متابعة التلاوة («مفتاح المقطع:رقم الكلمة»).
  final Map<String, WordState>? wordStates;
  final bool hideText;
  final ValueChanged<Aya>? onAyaTap;
  final VoidCallback? onHeaderTap;
  final ValueChanged<double>? onFitFont;
  const QuranPageView({
    super.key,
    required this.page,
    required this.fit,
    required this.zoomFont,
    this.highlightSura,
    this.highlightAya,
    this.currentKey,
    this.wordStates,
    this.hideText = false,
    this.onAyaTap,
    this.onHeaderTap,
    this.onFitFont,
  });

  @override
  State<QuranPageView> createState() => _QuranPageViewState();
}

class _QuranPageViewState extends State<QuranPageView> {
  late Future<List<Aya>> _ayat;
  final _recognizers = <TapGestureRecognizer>[];
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  final _blockKeys = <GlobalKey>[];

  /// موضع كل آية: رقم المقطع، وبداية نصها ونهايته فيه.
  final _ayaPos = <int, (int, int, int)>{};

  static final _fitCache = <String, double>{};

  @override
  void initState() {
    super.initState();
    _ayat = context.read<AppState>().quranDb.page(widget.page);
  }

  @override
  void didUpdateWidget(QuranPageView old) {
    super.didUpdateWidget(old);
    if (widget.currentKey != null && widget.currentKey != old.currentKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  TapGestureRecognizer _tap(Aya a) {
    final r = TapGestureRecognizer()
      ..onTap = () {
        final f = widget.onAyaTap;
        if (f != null) {
          f(a);
        } else {
          showAyaSheet(context, a);
        }
      };
    _recognizers.add(r);
    return r;
  }

  /// يمرّر الصفحة حتى تظهر الآية الجارية في ثلثها الأعلى.
  void _scrollToCurrent() {
    if (!mounted || !_scroll.hasClients) return;
    final key = widget.currentKey;
    if (key == null) return;
    final viewport = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return;
    double? top;
    if (key < 0) {
      // البسملة: نمرّر إلى ترويسة السورة قبلها
      for (final k in _blockKeys) {
        final ro = k.currentContext?.findRenderObject();
        if (ro is RenderBox && k.currentWidget is SuraHeader && (k.currentWidget as SuraHeader).number == -key) {
          top = viewport.globalToLocal(ro.localToGlobal(Offset.zero)).dy;
        }
      }
    } else {
      final pos = _ayaPos[key];
      if (pos == null) return;
      final ro = _blockKeys[pos.$1].currentContext?.findRenderObject();
      if (ro is! RenderParagraph) return;
      final boxes = ro.getBoxesForSelection(TextSelection(baseOffset: pos.$2, extentOffset: pos.$3));
      if (boxes.isEmpty) return;
      top = viewport.globalToLocal(ro.localToGlobal(Offset(0, boxes.first.top))).dy;
    }
    if (top == null) return;
    final h = viewport.size.height;
    // لا نحرّك الصفحة ما دامت الآية ظاهرة في نصفها الأعلى
    if (top > h * 0.08 && top < h * 0.5) return;
    final target = (_scroll.offset + top - h * 0.2).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
  }

  /// شكل الكلمة بحسب حالها في التلاوة: الخطأ أحمر، والجارية مظللة، وفي اختبار
  /// الحفظ تُخفى الكلمة حتى تُقرأ ويبقى تحتها خط يدل على مكانها.
  TextStyle? _wordStyle(WordState? st, Palette pal) {
    if (st == WordState.mistake) {
      return TextStyle(color: mistakeColor, backgroundColor: mistakeColor.withValues(alpha: 0.10));
    }
    final hidden = widget.hideText && st != WordState.read;
    if (hidden) {
      return TextStyle(
        color: Colors.transparent,
        backgroundColor: st == WordState.current && widget.currentKey != null
            ? AppColors.wheat.withValues(alpha: 0.35)
            : null,
        decoration: TextDecoration.underline,
        decorationColor: pal.line,
        decorationThickness: 1.4,
      );
    }
    if (st == WordState.current && widget.currentKey != null) {
      return TextStyle(backgroundColor: AppColors.wheat.withValues(alpha: 0.55));
    }
    return null;
  }

  List<_Block> _blocks(List<Aya> ayat, QuranDb db) {
    final out = <_Block>[];
    var run = <Aya>[];
    for (final a in ayat) {
      if (a.aya == 1) {
        if (run.isNotEmpty) out.add(_Block.text(run));
        run = [];
        final sura = db.suras[a.sura - 1];
        out.add(_Block.header(sura));
        if (a.sura != 1 && a.sura != 9) out.add(_Block.basmala(sura));
      }
      run.add(a);
    }
    if (run.isNotEmpty) out.add(_Block.text(run));
    return out;
  }

  static const _fitLine = 1.85, _zoomLine = 2.05;
  static double _headerHeight(double fs) => math.max(48, fs * 2.3 + 14);

  /// ارتفاع الصفحة كلها بخط حجمه [fs] وعرض [width].
  double _measure(List<_Block> blocks, QuranDb db, double fs, double width, TextScaler scaler) {
    var h = 0.0;
    for (final b in blocks) {
      if (b.sura != null && !b.basmala) {
        h += _headerHeight(fs);
        continue;
      }
      final text = b.basmala ? db.basmala : b.ayat.map((a) => '${a.text} ').join();
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontFamily: quranFont, fontSize: b.basmala ? fs * 0.95 : fs, height: _fitLine),
        ),
        textDirection: TextDirection.rtl,
        textAlign: b.basmala ? TextAlign.center : TextAlign.justify,
        textScaler: scaler,
      )..layout(maxWidth: width);
      h += tp.height;
      tp.dispose();
    }
    return h;
  }

  /// أكبر خط تتسع به الصفحة كلها في المساحة المتاحة.
  double _fitFont(List<_Block> blocks, QuranDb db, Size area, TextScaler scaler) {
    final cacheKey = '${widget.page}:${area.width.round()}x${area.height.round()}:${scaler.scale(10)}';
    final c = _fitCache[cacheKey];
    if (c != null) return c;
    var lo = 10.0, hi = 34.0;
    if (_measure(blocks, db, hi, area.width, scaler) <= area.height) {
      lo = hi;
    } else {
      for (var i = 0; i < 9; i++) {
        final mid = (lo + hi) / 2;
        if (_measure(blocks, db, mid, area.width, scaler) <= area.height) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
    }
    if (_fitCache.length > 60) _fitCache.clear();
    return _fitCache[cacheKey] = lo;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final db = s.quranDb;
    final pal = Palette.of(context);
    final ink = Theme.of(context).colorScheme.onSurface;
    return FutureBuilder<List<Aya>>(
      future: _ayat,
      builder: (c, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final ayat = snap.data!;
        final blocks = _blocks(ayat, db);
        return LayoutBuilder(
          builder: (c, box) {
            for (final r in _recognizers) {
              r.dispose();
            }
            _recognizers.clear();
            _ayaPos.clear();
            final fit = widget.fit;
            const hPad = 14.0, frame = 6.0;
            const topRow = 30.0, footer = 26.0;
            final scaler = MediaQuery.textScalerOf(context);
            final innerW = box.maxWidth - 2 * (hPad + frame + 8);
            final double fs;
            if (fit) {
              final avail = box.maxHeight - 2 * (frame + 8) - topRow - footer - 12;
              fs = _fitFont(blocks, db, Size(innerW, avail), scaler);
              widget.onFitFont?.call(fs);
            } else {
              fs = widget.zoomFont;
            }
            final line = fit ? _fitLine : _zoomLine;

            while (_blockKeys.length < blocks.length) {
              _blockKeys.add(GlobalKey());
            }
            final children = <Widget>[];
            for (var bi = 0; bi < blocks.length; bi++) {
              final b = blocks[bi];
              if (b.sura != null && !b.basmala) {
                children.add(
                  SuraHeader(
                    key: _blockKeys[bi],
                    number: b.sura!.id,
                    name: b.sura!.name,
                    ayat: b.sura!.ayat,
                    height: _headerHeight(fs) - 14,
                    fontSize: fs * 0.95,
                  ),
                );
                continue;
              }
              if (b.basmala) {
                final key = -b.sura!.id;
                final words = db.basmala.split(' ');
                children.add(
                  Text.rich(
                    TextSpan(
                      style: TextStyle(backgroundColor: widget.currentKey == key ? pal.highlight : null),
                      children: [
                        for (var k = 0; k < words.length; k++)
                          TextSpan(
                            text: k < words.length - 1 ? '${words[k]} ' : words[k],
                            style: _wordStyle(widget.wordStates?['$key:$k'], pal),
                          ),
                      ],
                    ),
                    key: _blockKeys[bi],
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: quranFont, fontSize: fs * 0.95, height: line, color: ink),
                  ),
                );
                continue;
              }
              final spans = <InlineSpan>[];
              var offset = 0;
              for (final a in b.ayat) {
                final text = '${a.text} ';
                _ayaPos[a.id] = (bi, offset, offset + text.length - 1);
                offset += text.length;
                final notes = s.quran.notesOf(a.sura, a.aya);
                final marked = a.sura == widget.highlightSura && a.aya == widget.highlightAya;
                Color? bg;
                if (a.id == widget.currentKey) {
                  bg = AppColors.wheat.withValues(alpha: 0.18);
                } else if (marked) {
                  bg = pal.highlight;
                } else if (notes.any((n) => n.kind == 'mistake')) {
                  bg = const Color(0x33C7A85A);
                } else if (notes.isNotEmpty) {
                  bg = const Color(0x226E8B6A);
                }
                final rec = _tap(a);
                final body = QuranDb.stripNumber(a.text);
                final words = body.split(' ');
                spans.add(
                  TextSpan(
                    style: TextStyle(backgroundColor: bg),
                    children: [
                      for (var k = 0; k < words.length; k++)
                        TextSpan(
                          text: k < words.length - 1 ? '${words[k]} ' : words[k],
                          recognizer: rec,
                          style: _wordStyle(widget.wordStates?['${a.id}:$k'], pal),
                        ),
                      TextSpan(text: '${a.text.substring(body.length)} ', recognizer: rec),
                    ],
                  ),
                );
              }
              children.add(
                Text.rich(
                  TextSpan(children: spans),
                  key: _blockKeys[bi],
                  textAlign: TextAlign.justify,
                  style: TextStyle(fontFamily: quranFont, fontSize: fs, height: line, color: ink),
                ),
              );
            }

            final sura = db.suraOfPage(widget.page);
            final head = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onHeaderTap,
              child: SizedBox(
                height: topRow,
                child: Row(
                  children: [
                    Text(
                      'سورة ${sura.name}',
                      style: TextStyle(fontSize: 13, color: pal.muted, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Text(
                      'الجزء ${db.juzOfPage(widget.page)}',
                      style: TextStyle(fontSize: 13, color: pal.muted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            );
            final foot = SizedBox(
              height: footer,
              child: Center(
                child: Text('${widget.page}', style: TextStyle(color: pal.muted, fontSize: 13)),
              ),
            );

            if (fit) {
              final body = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  head,
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        key: _viewportKey,
                        controller: _scroll,
                        physics: const ClampingScrollPhysics(),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                      ),
                    ),
                  ),
                  foot,
                ],
              );
              // إطار رفيع مزدوج كإطار صفحات المصحف المطبوع.
              return Padding(
                padding: const EdgeInsets.fromLTRB(hPad, 6, hPad, 6),
                child: CustomPaint(
                  painter: PageFramePainter(color: AppColors.wheat),
                  child: Padding(padding: const EdgeInsets.all(frame + 8), child: body),
                ),
              );
            }
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [head, ...children, const SizedBox(height: 10), foot],
            );
            return SingleChildScrollView(
              key: _viewportKey,
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              child: content,
            );
          },
        );
      },
    );
  }
}

/// إطار الصفحة: خطان رفيعان وزخرفة صغيرة في الزوايا.
class PageFramePainter extends CustomPainter {
  final Color color;
  PageFramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final inner = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final r1 = Offset.zero & size;
    final r2 = r1.deflate(5);
    canvas.drawRRect(RRect.fromRectAndRadius(r1.deflate(0.8), const Radius.circular(6)), outer);
    canvas.drawRRect(RRect.fromRectAndRadius(r2, const Radius.circular(4)), inner);
    final fill = Paint()..color = color;
    for (final c in [r2.topLeft, r2.topRight, r2.bottomLeft, r2.bottomRight]) {
      final p = Path();
      const d = 5.0;
      p
        ..moveTo(c.dx, c.dy - d)
        ..lineTo(c.dx + d, c.dy)
        ..lineTo(c.dx, c.dy + d)
        ..lineTo(c.dx - d, c.dy)
        ..close();
      canvas.drawPath(p, fill);
    }
    // معيّنات صغيرة في منتصف الأضلاع
    final mids = [
      Offset(size.width / 2, r2.top),
      Offset(size.width / 2, r2.bottom),
      Offset(r2.left, size.height / 2),
      Offset(r2.right, size.height / 2),
    ];
    for (final c in mids) {
      canvas.drawCircle(c, 2.6, fill);
    }
  }

  @override
  bool shouldRepaint(covariant PageFramePainter old) => old.color != color;
}

/// ما يظهر عند الضغط على آية: ملاحظاتها وإضافة ملاحظة.
Future<void> showAyaSheet(BuildContext context, Aya a) {
  final s = context.read<AppState>();
  final suraName = s.quranDb.suras[a.sura - 1].name;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => Consumer<AppState>(
      builder: (c, s, _) {
        final pal = Palette.of(c);
        final notes = s.quran.notesOf(a.sura, a.aya);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'سورة $suraName · الآية ${a.aya}',
                  style: const TextStyle(fontFamily: readingFont, fontSize: 17, fontWeight: FontWeight.w700, height: 1.45),
                ),
                const SizedBox(height: 4),
                Text('الصفحة ${a.page} · الجزء ${a.juz}', style: TextStyle(color: pal.muted, fontSize: 13)),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final n in notes)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(noteIcon(n.kind), color: AppColors.wheat),
                      title: Text(noteKinds[n.kind] ?? ''),
                      subtitle: n.note.isEmpty ? null : Text(n.note),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => s.quran.deleteNote(n),
                      ),
                      onTap: () => editQuranNote(c, a.sura, a.aya, existing: n),
                    ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in noteKinds.entries)
                      ActionChip(
                        avatar: Icon(noteIcon(e.key), size: 18),
                        label: Text(e.value),
                        onPressed: () => editQuranNote(c, a.sura, a.aya, kind: e.key),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: const Text('فائدة في الدفتر'),
                      onPressed: () {
                        Navigator.pop(c);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BenefitEditScreen(
                              sourceType: 'quran',
                              sourceRef: 'سورة $suraName · الآية ${a.aya}',
                              initialBody: '',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

IconData noteIcon(String kind) => switch (kind) {
  'mistake' => Icons.error_outline,
  'mutashabih' => Icons.compare_arrows,
  _ => Icons.lightbulb_outline,
};

Future<void> editQuranNote(
  BuildContext context,
  int sura,
  int aya, {
  String kind = 'mistake',
  QuranNote? existing,
}) async {
  final s = context.read<AppState>();
  final ctl = TextEditingController(text: existing?.note ?? '');
  var k = existing?.kind ?? kind;
  final hint = switch (k) {
    'mistake' => 'ما الذي أخطأت فيه؟ (اختياري)',
    'mutashabih' => 'بماذا تشتبه؟ مثلاً: البقرة 58 والأعراف 161',
    _ => 'ما الذي استوقفك؟',
  };
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(noteKinds[k]!),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              children: [
                for (final e in noteKinds.entries)
                  ChoiceChip(label: Text(e.value), selected: k == e.key, onSelected: (_) => set(() => k = e.key)),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctl,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(hintText: hint),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  await s.quran.saveNote(
    QuranNote(
      id: existing?.id,
      sura: sura,
      aya: aya,
      kind: k,
      note: ctl.text.trim(),
      createdAt: existing?.createdAt ?? DateTime.now().toIso8601String(),
    ),
  );
  if (context.mounted) toast(context, 'حُفظت الملاحظة');
}

/// فهرس السور والأجزاء. يعيد رقم الصفحة المختارة.
class QuranIndexSheet extends StatefulWidget {
  const QuranIndexSheet({super.key});

  @override
  State<QuranIndexSheet> createState() => _QuranIndexSheetState();
}

class _QuranIndexSheetState extends State<QuranIndexSheet> {
  bool juz = false;

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppState>().quranDb;
    final pal = Palette.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (c, sc) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('السور')),
                ButtonSegment(value: true, label: Text('الأجزاء')),
              ],
              selected: {juz},
              onSelectionChanged: (v) => setState(() => juz = v.first),
            ),
          ),
          Expanded(
            child: juz
                ? ListView(
                    controller: sc,
                    children: [
                      for (var j = 1; j <= 30; j++)
                        ListTile(
                          title: Text('الجزء $j'),
                          trailing: Text('ص ${db.juzStart[j - 1]}', style: TextStyle(color: pal.muted)),
                          onTap: () => Navigator.pop(context, db.juzStart[j - 1]),
                        ),
                    ],
                  )
                : ListView.builder(
                    controller: sc,
                    itemCount: db.suras.length,
                    itemBuilder: (c, i) {
                      final x = db.suras[i];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: pal.soft,
                          child: Text('${x.id}', style: const TextStyle(fontSize: 12)),
                        ),
                        title: Text(x.name),
                        subtitle: Text('${x.ayat} آية'),
                        trailing: Text('ص ${x.firstPage}', style: TextStyle(color: pal.muted)),
                        onTap: () => Navigator.pop(context, x.firstPage),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
