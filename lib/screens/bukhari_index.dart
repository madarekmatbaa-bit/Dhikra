import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/bukhari_db.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/arabic.dart';
import 'reader.dart';

class BukhariIndexScreen extends StatefulWidget {
  const BukhariIndexScreen({super.key});

  @override
  State<BukhariIndexScreen> createState() => _BukhariIndexScreenState();
}

class _BukhariIndexScreenState extends State<BukhariIndexScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<SearchHit>? hits;
  bool searching = false;

  @override
  void dispose() {
    _q.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String v) async {
    final s = context.read<AppState>();
    final n = int.tryParse(v.trim());
    if (v.trim().isEmpty) {
      setState(() => hits = null);
      return;
    }
    if (n != null) {
      setState(() => hits = n >= 1 && n <= totalHadiths ? [SearchHit(n, s.bukhari.bookOf(n).id, 'انتقل إلى الحديث $n')] : []);
      return;
    }
    setState(() => searching = true);
    final r = await s.bukhari.search(v);
    if (!mounted || _q.text != v) return;
    setState(() {
      hits = r;
      searching = false;
    });
  }

  void _open(int n) => Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderScreen(start: n)));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final currentBook = s.bukhari.bookOf(s.position);
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('صحيح البخاري', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _q,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'ابحث في النص أو اكتب رقم حديث',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _q.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _q.clear();
                          setState(() => hits = null);
                        }),
              ),
            ),
          ]),
        ),
        Expanded(
          child: hits != null || searching
              ? _results(pal, s)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                  children: [
                    // فهرس الكتب كفهرس كتاب مطبوع: سطور يفصلها خط رفيع، والرقم بخط النسخ.
                    Card(
                      child: Column(children: [
                        for (final b in s.bukhari.books) ...[
                          if (b.id != s.bukhari.books.first.id) Divider(height: 1, indent: 16, endIndent: 16, color: pal.line),
                          _BookRow(book: b, here: b.id == currentBook.id),
                        ],
                      ]),
                    ),
                  ],
                ),
        ),
      ]),
    );
  }

  Widget _results(Palette pal, AppState s) {
    if (searching && hits == null) return const Center(child: CircularProgressIndicator());
    final h = hits ?? const [];
    if (h.isEmpty) {
      return Center(child: Text('لا نتائج', style: TextStyle(color: pal.muted, fontSize: 16)));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      itemCount: h.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Text(h.length >= 150 ? 'أول 150 نتيجة' : '${h.length} نتيجة',
              style: TextStyle(color: pal.muted, fontSize: 13));
        }
        final hit = h[i - 1];
        return Card(
          child: ListTile(
            title: Text('حديث ${hit.number} · كتاب ${s.bukhari.bookById(hit.bookId).title}',
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
            subtitle: Text(hit.snippet, style: const TextStyle(fontSize: 14, height: 1.6)),
            onTap: () => _open(hit.number),
          ),
        );
      },
    );
  }
}

class _BookRow extends StatelessWidget {
  final BukhariBook book;
  final bool here;
  const _BookRow({required this.book, required this.here});

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final b = book;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookScreen(book: b))),
      child: Container(
        decoration: here
            ? BoxDecoration(
                color: pal.highlight.withValues(alpha: 0.6),
                border: const BorderDirectional(start: BorderSide(color: AppColors.wheat, width: 3)),
              )
            : null,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          SizedBox(
            width: 34,
            child: Text('${b.id}',
                style: TextStyle(fontFamily: readingFont, fontSize: 17, color: here ? AppColors.olive : pal.muted)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('كتاب ${b.title}', style: const TextStyle(fontFamily: readingFont, fontSize: 18, fontWeight: FontWeight.w700, height: 1.4)),
              Text('${b.first} – ${b.last} · ${hadithWord(b.count)}', style: TextStyle(color: pal.muted, fontSize: 13)),
            ]),
          ),
          if (here) const Icon(Icons.bookmark, color: AppColors.wheat, size: 20),
        ]),
      ),
    );
  }
}

class BookScreen extends StatelessWidget {
  final BukhariBook book;
  const BookScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final pal = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('كتاب ${book.title}')),
      body: FutureBuilder<List<(int, String)>>(
        future: s.bukhari.previews(book.first, book.last),
        builder: (context, snap) {
          final items = snap.data;
          if (items == null) return const Center(child: CircularProgressIndicator());
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => Divider(color: pal.line),
            itemBuilder: (context, i) {
              final (n, text) = items[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 2),
                leading: SizedBox(
                  width: 48,
                  child: Text('$n',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                ),
                title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                trailing: n == s.position ? const Icon(Icons.bookmark, color: AppColors.wheat) : null,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderScreen(start: n))),
              );
            },
          );
        },
      ),
    );
  }
}
