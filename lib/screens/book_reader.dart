import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/library.dart';
import '../theme.dart';
import '../util/pdf_arabic.dart';
import '../widgets/brand.dart';
import 'benefit_edit.dart';

/// قارئ كتب PDF: نصاً مفرّغاً (كقارئ البخاري) أو صوراً للصفحات، يفتح على آخر صفحة ويحتسب الورد.
class BookReader extends StatefulWidget {
  final Book book;
  const BookReader({super.key, required this.book});

  @override
  State<BookReader> createState() => _BookReaderState();
}

class _BookReaderState extends State<BookReader> {
  final _ctl = PdfViewerController();
  PageController? _textPages;
  PdfDocument? _doc;
  final _texts = <int, Future<String>>{};
  late int page;
  late bool textMode;

  @override
  void initState() {
    super.initState();
    final b = widget.book;
    textMode = context.read<AppState>().library.textMode(b.id);
    _openDoc();
    // نفتح على موضع الورد إن كان القارئ قد ابتعد عنه، وإلا على آخر صفحة فُتحت.
    page = (b.lastPage < b.position - 1 || b.lastPage > b.position + b.perDay * 3 ? b.position : b.lastPage)
        .clamp(1, b.pages);
    _textPages = PageController(initialPage: page - 1);
  }

  Future<void> _openDoc() async {
    try {
      await pdfrxFlutterInitialize();
      final d = await PdfDocument.openFile(widget.book.filePath);
      if (!mounted) {
        await d.dispose();
        return;
      }
      setState(() => _doc = d);
    } catch (_) {
      if (mounted) setState(() => textMode = false);
    }
  }

  @override
  void dispose() {
    _textPages?.dispose();
    _doc?.dispose();
    super.dispose();
  }

  Future<String> _loadText(int n) async {
    if (_texts.length > 30) _texts.clear();
    final t = await _doc!.pages[n - 1].loadText();
    return tidyPageText(normalizePdfArabic(t?.fullText ?? ''));
  }

  void _pageChanged(int n) {
    if (!mounted) return;
    setState(() => page = n);
    context.read<AppState>().library.pageViewed(widget.book, n);
  }

  void _setMode(bool text) {
    final lib = context.read<AppState>().library;
    lib.setTextMode(widget.book.id, text);
    setState(() {
      textMode = text;
      _textPages?.dispose();
      _textPages = PageController(initialPage: page - 1);
    });
  }

  void _saveBenefit(String body) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BenefitEditScreen(
            initialBody: body,
            sourceType: 'book',
            sourceRef: '${widget.book.title} · ص $page',
          ),
        ),
      );

  Future<void> _jump() async {
    final ctl = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('اذهب إلى صفحة'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: 'من 1 إلى ${widget.book.pages}'),
          onSubmitted: (v) => Navigator.pop(c, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(ctl.text)), child: const Text('اذهب')),
        ],
      ),
    );
    if (n == null) return;
    final target = n.clamp(1, widget.book.pages);
    if (textMode) {
      _textPages?.jumpToPage(target - 1);
    } else if (_ctl.isReady) {
      await _ctl.goToPage(pageNumber: target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final lib = s.library;
    final b = lib.byId(widget.book.id) ?? widget.book;
    final t = lib.todayOf(b.id);
    final pal = Palette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(b.title, style: const TextStyle(fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('صفحة $page من ${b.pages}', style: TextStyle(fontSize: 12, color: pal.muted)),
        ]),
        actions: [
          IconButton(
            tooltip: textMode ? 'اعرض الصفحات كصور' : 'اعرض النص',
            icon: Icon(textMode ? Icons.image_outlined : Icons.notes),
            onPressed: () => _setMode(!textMode),
          ),
          if (textMode) ...[
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
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'jump') _jump();
              if (v == 'benefit') _saveBenefit('');
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'jump', child: Text('اذهب إلى صفحة')),
              PopupMenuItem(value: 'benefit', child: Text('فائدة من هذه الصفحة')),
            ],
          ),
        ],
      ),
      body: textMode
          ? (_doc == null
              ? const Center(child: CircularProgressIndicator())
              : PageView.builder(
                  controller: _textPages,
                  itemCount: b.pages,
                  onPageChanged: (i) => _pageChanged(i + 1),
                  itemBuilder: (c, i) => _TextPage(
                    text: _texts.putIfAbsent(i + 1, () => _loadText(i + 1)),
                    number: i + 1,
                    onSave: _saveBenefit,
                    onShowImage: () => _setMode(false),
                  ),
                ))
          : Directionality(
        // ترتيب الصفحات في ملف PDF ثابت، فنعرضها من أعلى لأسفل دون قلب.
        textDirection: TextDirection.ltr,
        child: PdfViewer.file(
          b.filePath,
          controller: _ctl,
          initialPageNumber: page,
          params: PdfViewerParams(
            backgroundColor: pal.soft,
            onPageChanged: (n) {
              if (n != null) _pageChanged(n);
            },
          ),
        ),
      ),
      bottomNavigationBar: t == null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(children: [
                  Icon(t.done ? Icons.check_circle : Icons.flag_outlined, color: t.done ? AppColors.sage : AppColors.wheat),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t.done
                          ? 'أتممت ورد اليوم'
                          : 'ورد اليوم حتى ص ${t.toPos} · بقي ${(t.toPos - b.position + 1).clamp(0, t.target)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}

/// صفحة من الكتاب نصاً قابلاً للتحديد.
class _TextPage extends StatelessWidget {
  final Future<String> text;
  final int number;
  final ValueChanged<String> onSave;
  final VoidCallback onShowImage;
  const _TextPage({required this.text, required this.number, required this.onSave, required this.onShowImage});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    return FutureBuilder<String>(
      future: text,
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final text = snap.data ?? '';
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 40),
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: pal.soft, borderRadius: BorderRadius.circular(10)),
                child: Text('صفحة $number', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ),
            ]),
            const SizedBox(height: 18),
            if (text.length < 15)
              SectionCard(
                color: pal.highlight,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('لا يوجد نص في هذه الصفحة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('قد تكون صفحة فارغة، أو صورة ممسوحة ضوئياً لا يُستخرج منها نص.', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: onShowImage, child: const Text('اعرض الصفحة كصورة')),
                ]),
              )
            else
              SelectableText(
                text,
                textAlign: TextAlign.justify,
                textDirection: TextDirection.rtl,
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
                            onSave(selected);
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

/// يصل أسطر الفقرة الواحدة، ويُبقي السطر الجديد بعد نهاية الجملة.
String tidyPageText(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n').map((l) => l.trim()).toList();
  final b = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.isEmpty) {
      if (b.isNotEmpty && !b.toString().endsWith('\n')) b.write('\n');
      continue;
    }
    b.write(l);
    final end = RegExp(r'[.:؟?!»"]$').hasMatch(l);
    if (i < lines.length - 1) b.write(end ? '\n' : ' ');
  }
  return b.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
}
