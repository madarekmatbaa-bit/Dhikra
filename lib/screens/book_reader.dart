import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/library.dart';
import '../theme.dart';
import 'benefit_edit.dart';

/// قارئ كتب PDF: يفتح على آخر صفحة، ويحتسب الصفحات المقروءة في الورد.
class BookReader extends StatefulWidget {
  final Book book;
  const BookReader({super.key, required this.book});

  @override
  State<BookReader> createState() => _BookReaderState();
}

class _BookReaderState extends State<BookReader> {
  final _ctl = PdfViewerController();
  late int page;

  @override
  void initState() {
    super.initState();
    final b = widget.book;
    // نفتح على موضع الورد إن كان القارئ قد ابتعد عنه، وإلا على آخر صفحة فُتحت.
    page = (b.lastPage < b.position - 1 || b.lastPage > b.position + b.perDay * 3 ? b.position : b.lastPage)
        .clamp(1, b.pages);
  }

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
    if (n != null && _ctl.isReady) await _ctl.goToPage(pageNumber: n.clamp(1, widget.book.pages));
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
          IconButton(tooltip: 'اذهب إلى صفحة', icon: const Icon(Icons.numbers), onPressed: _jump),
          IconButton(
            tooltip: 'احفظ فائدة من هذه الصفحة',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BenefitEditScreen(sourceType: 'book', sourceRef: '${b.title} · ص $page'),
              ),
            ),
          ),
        ],
      ),
      body: Directionality(
        // ترتيب الصفحات في ملف PDF ثابت، فنعرضها من أعلى لأسفل دون قلب.
        textDirection: TextDirection.ltr,
        child: PdfViewer.file(
          b.filePath,
          controller: _ctl,
          initialPageNumber: page,
          params: PdfViewerParams(
            backgroundColor: pal.soft,
            onPageChanged: (n) {
              if (n == null || !mounted) return;
              setState(() => page = n);
              lib.pageViewed(b, n);
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
