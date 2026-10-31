import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/quran_db.dart';
import '../state/app_state.dart';
import '../state/quran_review.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import 'benefit_edit.dart';

/// قارئ المصحف: صفحة بصفحة كترتيب مصحف المدينة (604 صفحات).
class QuranReader extends StatefulWidget {
  final int page;
  final int? highlightSura;
  final int? highlightAya;

  /// صفحات ورد المراجعة، تظهر في الأعلى إن مُرّرت.
  final List<int>? portion;
  final String? portionTitle;
  const QuranReader({
    super.key,
    required this.page,
    this.highlightSura,
    this.highlightAya,
    this.portion,
    this.portionTitle,
  });

  @override
  State<QuranReader> createState() => _QuranReaderState();
}

class _QuranReaderState extends State<QuranReader> {
  late final PageController _pc;
  late int page;

  @override
  void initState() {
    super.initState();
    page = widget.page.clamp(1, quranPages);
    _pc = PageController(initialPage: page - 1);
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final db = s.quranDb;
    final pal = Palette.of(context);
    final sura = db.suraOfPage(page);
    final portion = widget.portion;
    final inPortion = portion?.indexOf(page) ?? -1;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('سورة ${sura.name}', style: const TextStyle(fontSize: 17)),
          Text('الجزء ${db.juzOfPage(page)} · صفحة $page', style: TextStyle(fontSize: 12, color: pal.muted)),
        ]),
        actions: [
          IconButton(tooltip: 'الفهرس', icon: const Icon(Icons.list), onPressed: _openIndex),
          IconButton(tooltip: 'اذهب إلى صفحة', icon: const Icon(Icons.numbers), onPressed: _jump),
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
      body: PageView.builder(
        controller: _pc,
        itemCount: quranPages,
        onPageChanged: (i) {
          setState(() => page = i + 1);
          s.quran.setLastPage(i + 1);
        },
        itemBuilder: (c, i) => _QuranPage(
          page: i + 1,
          highlightSura: widget.highlightSura,
          highlightAya: widget.highlightAya,
        ),
      ),
      bottomNavigationBar: portion == null || portion.length < 2
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(children: [
                  OutlinedButton.icon(
                    onPressed: inPortion > 0 ? () => _go(portion[inPortion - 1]) : null,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('السابقة'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: inPortion >= 0 && inPortion < portion.length - 1
                        ? () => _go(portion[inPortion + 1])
                        : inPortion < 0
                            ? () => _go(portion.first)
                            : null,
                    icon: const Icon(Icons.arrow_back),
                    label: Text(inPortion < 0 ? 'أول الورد' : 'التالية'),
                  ),
                ]),
              ),
            ),
    );
  }
}

class _QuranPage extends StatefulWidget {
  final int page;
  final int? highlightSura;
  final int? highlightAya;
  const _QuranPage({required this.page, this.highlightSura, this.highlightAya});

  @override
  State<_QuranPage> createState() => _QuranPageState();
}

class _QuranPageState extends State<_QuranPage> {
  late Future<List<Aya>> _ayat;
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _ayat = context.read<AppState>().quranDb.page(widget.page);
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _tap(Aya a) {
    final r = TapGestureRecognizer()..onTap = () => showAyaSheet(context, a);
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final ink = Theme.of(context).colorScheme.onSurface;
    return FutureBuilder<List<Aya>>(
      future: _ayat,
      builder: (c, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        for (final r in _recognizers) {
          r.dispose();
        }
        _recognizers.clear();
        final ayat = snap.data!;
        // نقسم الصفحة إلى مقاطع: كل سورة تبدأ في الصفحة لها ترويسة.
        final blocks = <Widget>[];
        var spans = <InlineSpan>[];
        void flush() {
          if (spans.isEmpty) return;
          blocks.add(Text.rich(
            TextSpan(children: spans),
            textAlign: TextAlign.justify,
            style: TextStyle(fontFamily: quranFont, fontSize: s.fontSize + 5, height: 2.05, color: ink),
          ));
          spans = [];
        }

        for (final a in ayat) {
          if (a.aya == 1) {
            flush();
            blocks.add(_SuraHeader(name: s.quranDb.suras[a.sura - 1].name));
            if (a.sura != 1 && a.sura != 9) {
              blocks.add(Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(s.quranDb.basmala,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: quranFont, fontSize: s.fontSize + 4, height: 2, color: ink)),
              ));
            }
          }
          final notes = s.quran.notesOf(a.sura, a.aya);
          final marked = a.sura == widget.highlightSura && a.aya == widget.highlightAya;
          Color? bg;
          if (marked) {
            bg = pal.highlight;
          } else if (notes.any((n) => n.kind == 'mistake')) {
            bg = const Color(0x33C7A85A);
          } else if (notes.isNotEmpty) {
            bg = const Color(0x226E8B6A);
          }
          spans.add(TextSpan(text: '${a.text} ', recognizer: _tap(a), style: TextStyle(backgroundColor: bg)));
        }
        flush();
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          children: [
            ...blocks,
            const SizedBox(height: 10),
            Center(child: Text('${widget.page}', style: TextStyle(color: pal.muted, fontSize: 13))),
          ],
        );
      },
    );
  }
}

class _SuraHeader extends StatelessWidget {
  final String name;
  const _SuraHeader({required this.name});

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: pal.soft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.wheat.withValues(alpha: 0.6)),
      ),
      alignment: Alignment.center,
      child: Text('سورة $name', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    );
  }
}

/// ما يظهر عند الضغط على آية: ملاحظاتها وإضافة ملاحظة.
Future<void> showAyaSheet(BuildContext context, Aya a) {
  final s = context.read<AppState>();
  final suraName = s.quranDb.suras[a.sura - 1].name;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => Consumer<AppState>(builder: (c, s, _) {
      final pal = Palette.of(c);
      final notes = s.quran.notesOf(a.sura, a.aya);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('سورة $suraName · الآية ${a.aya}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
            Wrap(spacing: 8, runSpacing: 8, children: [
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
            ]),
          ]),
        ),
      );
    }),
  );
}

IconData noteIcon(String kind) => switch (kind) {
      'mistake' => Icons.error_outline,
      'mutashabih' => Icons.compare_arrows,
      _ => Icons.lightbulb_outline,
    };

Future<void> editQuranNote(BuildContext context, int sura, int aya, {String kind = 'mistake', QuranNote? existing}) async {
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
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, children: [
            for (final e in noteKinds.entries)
              ChoiceChip(label: Text(e.value), selected: k == e.key, onSelected: (_) => set(() => k = e.key)),
          ]),
          const SizedBox(height: 10),
          TextField(controller: ctl, minLines: 2, maxLines: 5, decoration: InputDecoration(hintText: hint)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  await s.quran.saveNote(QuranNote(
    id: existing?.id,
    sura: sura,
    aya: aya,
    kind: k,
    note: ctl.text.trim(),
    createdAt: existing?.createdAt ?? DateTime.now().toIso8601String(),
  ));
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
      builder: (c, sc) => Column(children: [
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
              ? ListView(controller: sc, children: [
                  for (var j = 1; j <= 30; j++)
                    ListTile(
                      title: Text('الجزء $j'),
                      trailing: Text('ص ${db.juzStart[j - 1]}', style: TextStyle(color: pal.muted)),
                      onTap: () => Navigator.pop(context, db.juzStart[j - 1]),
                    ),
                ])
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
      ]),
    );
  }
}
