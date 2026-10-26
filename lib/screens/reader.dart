import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../db/bukhari_db.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import 'benefit_edit.dart';

/// قارئ الحديث: حديث بعد حديث، مع تحديد النص وحفظه فائدة.
class ReaderScreen extends StatefulWidget {
  final int start;
  final bool wirdMode;
  const ReaderScreen({super.key, required this.start, this.wirdMode = false});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final PageController _pages;
  late int current;

  @override
  void initState() {
    super.initState();
    current = widget.start.clamp(1, totalHadiths);
    _pages = PageController(initialPage: current - 1);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int number) {
    if (number < 1 || number > totalHadiths) return;
    _pages.animateToPage(number - 1, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  Future<void> _readAndNext() async {
    final s = context.read<AppState>();
    final wasDone = s.todayLog?.done ?? false;
    final counted = await s.markRead(current);
    if (!mounted) return;
    if (counted && !wasDone && (s.todayLog?.done ?? false)) {
      toast(context, 'أتممت ورد اليوم، بارك الله فيك');
    }
    if (s.finished && counted) {
      toast(context, 'ختمت صحيح البخاري، الحمد لله');
      return;
    }
    _go(current + 1);
  }

  void _saveBenefit({String body = ''}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BenefitEditScreen(
          initialBody: body,
          sourceType: 'hadith',
          sourceRef: '$current',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final book = s.bukhari.bookOf(current);
    final log = s.todayLog;
    final inWird = widget.wirdMode && log != null && current >= log.fromPos && current <= log.toPos;
    final counts = current == s.position && !s.finished;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('كتاب ${book.title}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text(
            inWird ? 'حديث $current · ${current - log.fromPos + 1} من ${log.target} في ورد اليوم' : 'حديث $current',
            style: TextStyle(fontSize: 13, color: pal.muted, fontWeight: FontWeight.w400),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: 'تصغير الخط',
            icon: const Icon(Icons.text_decrease),
            onPressed: s.fontSize > 15 ? () => s.setFontSize(s.fontSize - 1) : null,
          ),
          IconButton(
            tooltip: 'تكبير الخط',
            icon: const Icon(Icons.text_increase),
            onPressed: s.fontSize < 34 ? () => s.setFontSize(s.fontSize + 1) : null,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: totalHadiths,
        onPageChanged: (i) => setState(() => current = i + 1),
        itemBuilder: (context, i) => _HadithPage(
          number: i + 1,
          onSaveSelection: (text) => _saveBenefit(body: text),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: pal.line)),
          ),
          child: Row(children: [
            IconButton.outlined(
              tooltip: 'السابق',
              onPressed: current > 1 ? () => _go(current - 1) : null,
              icon: const Icon(Icons.arrow_forward),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'احفظ فائدة',
              onPressed: () => _saveBenefit(),
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: counts ? _readAndNext : (current < totalHadiths ? () => _go(current + 1) : null),
                child: Text(counts ? 'قرأته · التالي' : 'التالي'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _HadithPage extends StatelessWidget {
  final int number;
  final ValueChanged<String> onSaveSelection;
  const _HadithPage({required this.number, required this.onSaveSelection});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    return FutureBuilder<Hadith>(
      future: s.bukhari.hadith(number),
      builder: (context, snap) {
        final h = snap.data;
        if (h == null) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 40),
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: pal.soft, borderRadius: BorderRadius.circular(10)),
                child: Text('حديث ${h.number}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ),
            ]),
            const SizedBox(height: 18),
            if (h.mergedInto != null)
              SectionCard(
                color: pal.highlight,
                child: Text(
                  'هذا الرقم داخل في نص الحديث ${h.mergedInto} قبله في هذه النسخة، فلا نص مستقل له.',
                  style: const TextStyle(fontSize: 16),
                ),
              )
            else
              SelectableText(
                h.text,
                textAlign: TextAlign.justify,
                style: TextStyle(fontFamily: readingFont, fontSize: s.fontSize, height: 1.9),
                contextMenuBuilder: (context, state) {
                  final v = state.textEditingValue;
                  final selected = v.selection.textInside(v.text).trim();
                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: state.contextMenuAnchors,
                    buttonItems: [
                      if (selected.isNotEmpty)
                        ContextMenuButtonItem(
                          label: 'احفظ فائدة',
                          onPressed: () {
                            ContextMenuController.removeAny();
                            onSaveSelection(selected);
                          },
                        ),
                      if (selected.isNotEmpty)
                        ContextMenuButtonItem(
                          label: 'نسخ',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: selected));
                            ContextMenuController.removeAny();
                          },
                        ),
                      ContextMenuButtonItem(
                        label: 'تحديد الكل',
                        onPressed: () => state.selectAll(SelectionChangedCause.toolbar),
                      ),
                    ],
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
