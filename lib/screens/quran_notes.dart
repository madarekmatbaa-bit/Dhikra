import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/quran_db.dart';
import '../state/app_state.dart';
import '../state/quran_review.dart';
import '../theme.dart';
import 'quran_reader.dart';
import 'quran_tab.dart';

/// دفتر الغلطات والمتشابهات والتدبر، مرتب حسب المصحف.
class QuranNotesScreen extends StatefulWidget {
  const QuranNotesScreen({super.key});

  @override
  State<QuranNotesScreen> createState() => _QuranNotesScreenState();
}

class _QuranNotesScreenState extends State<QuranNotesScreen> {
  String? kind;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final list = [for (final n in s.quran.notes) if (kind == null || n.kind == kind) n]
      ..sort((a, b) => a.sura != b.sura ? a.sura.compareTo(b.sura) : a.aya.compareTo(b.aya));
    return Scaffold(
      appBar: AppBar(title: const Text('الغلطات والمتشابهات')),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            ChoiceChip(label: const Text('الكل'), selected: kind == null, onSelected: (_) => setState(() => kind = null)),
            for (final e in noteKinds.entries) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('${e.value} · ${s.quran.notes.where((n) => n.kind == e.key).length}'),
                selected: kind == e.key,
                onSelected: (_) => setState(() => kind = e.key),
              ),
            ],
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'لا شيء هنا بعد. أثناء القراءة في المصحف اضغط على الآية التي أخطأت فيها أو اشتبهت عليك لتسجّلها، فتعود إليها في المراجعة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: pal.muted, fontSize: 15, height: 1.7),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (c, i) => _NoteCard(note: list[i]),
                ),
        ),
      ]),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final QuranNote note;
  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final pal = Palette.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Aya?>(
        future: s.quranDb.aya(note.sura, note.aya),
        builder: (c, snap) {
          final a = snap.data;
          return InkWell(
            onTap: a == null ? null : () => openMushaf(context, a.page, sura: a.sura, aya: a.aya),
            onLongPress: () => editQuranNote(context, note.sura, note.aya, existing: note),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(noteIcon(note.kind), size: 18, color: AppColors.wheat),
                  const SizedBox(width: 6),
                  Text(noteKinds[note.kind] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${s.quranDb.suras[note.sura - 1].name} · ${note.aya}',
                      style: TextStyle(color: pal.muted, fontSize: 13)),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') editQuranNote(context, note.sura, note.aya, existing: note);
                      if (v == 'del') s.quran.deleteNote(note);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('تعديل')),
                      PopupMenuItem(value: 'del', child: Text('حذف')),
                    ],
                  ),
                ]),
                if (a != null)
                  Text(a.text,
                      style: TextStyle(fontFamily: quranFont, fontSize: s.fontSize + 2, height: 1.9),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis),
                if (note.note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(note.note, style: const TextStyle(fontSize: 14)),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }
}
