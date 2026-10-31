import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../services/notifications.dart';
import '../state/app_state.dart';
import '../state/library.dart';
import '../theme.dart';
import '../util/arabic.dart';
import '../widgets/brand.dart';
import 'book_reader.dart';
import 'home_shell.dart';

class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final lib = s.library;
    final pal = Palette.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => addBookFlow(context),
        icon: const Icon(Icons.add),
        label: const Text('أضف كتاباً'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 96),
          children: [
            Row(children: [
              Expanded(child: Text('المكتبة', style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                tooltip: 'تذكير ورد الكتب',
                icon: Icon(lib.reminder == null ? Icons.notifications_none : Icons.notifications_active_outlined),
                onPressed: () => _reminder(context),
              ),
            ]),
            const SizedBox(height: 14),
            if (lib.books.isEmpty)
              SectionCard(
                color: pal.soft,
                onTap: () => addBookFlow(context),
                child: const Row(children: [
                  Icon(Icons.local_library_outlined, color: AppColors.olive),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'أضف كتاباً بصيغة PDF من هاتفك، وحدد كم صفحة تقرأ منه كل يوم. يتذكر التطبيق أين وصلت ويحسب لك موعد الختم.',
                      style: TextStyle(fontSize: 15, height: 1.6),
                    ),
                  ),
                ]),
              ),
            for (final b in lib.books) ...[
              BookCard(book: b),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _reminder(BuildContext context) async {
    final lib = context.read<AppState>().library;
    if (lib.reminder != null) {
      final off = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('تذكير ورد الكتب'),
          content: Text('التذكير مضبوط على ${formatTime(lib.reminder!)}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('أطفئه')),
            FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('غيّر الوقت')),
          ],
        ),
      );
      if (off == null || !context.mounted) return;
      if (off) {
        await lib.setReminder(null);
        return;
      }
    }
    if (!context.mounted) return;
    final t = await showTimePicker(context: context, initialTime: lib.reminder ?? const TimeOfDay(hour: 21, minute: 0));
    if (t != null) await lib.setReminder(t);
  }
}

Future<String?> _pickPdf() async {
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
  if (files.isEmpty) return null;
  return files.first.path;
}

Future<void> addBookFlow(BuildContext context) async {
  final lib = context.read<AppState>().library;
  final path = await _pickPdf();
  if (path == null || !context.mounted) return;
  final res = await showDialog<(String, int)>(
    context: context,
    builder: (c) => _BookDialog(title: p.basenameWithoutExtension(path), perDay: 10),
  );
  if (res == null || !context.mounted) return;
  try {
    final b = await lib.addBook(path, res.$1, perDay: res.$2);
    if (context.mounted) toast(context, 'أُضيف «${b.title}» · ${b.pages} صفحة');
  } catch (_) {
    if (context.mounted) toast(context, 'تعذر فتح الملف. تأكد أنه PDF سليم.');
  }
}

class _BookDialog extends StatefulWidget {
  final String title;
  final int perDay;
  final bool editing;
  const _BookDialog({required this.title, required this.perDay, this.editing = false});

  @override
  State<_BookDialog> createState() => _BookDialogState();
}

class _BookDialogState extends State<_BookDialog> {
  late final TextEditingController title = TextEditingController(text: widget.title);
  late int perDay = widget.perDay;

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.editing ? 'تعديل الكتاب' : 'كتاب جديد'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'اسم الكتاب')),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Text('صفحات كل يوم')),
          IconButton(onPressed: perDay > 1 ? () => setState(() => perDay--) : null, icon: const Icon(Icons.remove)),
          Text('$perDay', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          IconButton(onPressed: () => setState(() => perDay++), icon: const Icon(Icons.add)),
        ]),
        Wrap(spacing: 6, children: [
          for (final n in const [5, 10, 20, 30])
            ChoiceChip(label: Text('$n'), selected: perDay == n, onSelected: (_) => setState(() => perDay = n)),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            final t = title.text.trim();
            if (t.isEmpty) return;
            Navigator.pop(context, (t, perDay));
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

/// بطاقة كتاب: ورد اليوم والتقدم الكلي وموعد الختم.
class BookCard extends StatelessWidget {
  final Book book;
  final bool compact;
  const BookCard({super.key, required this.book, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final lib = s.library;
    final b = lib.byId(book.id) ?? book;
    final pal = Palette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = lib.todayOf(b.id);
    final exists = b.fileExists;

    if (b.finished) {
      return SectionCard(
        color: pal.soft,
        child: Row(children: [
          const Icon(Icons.check_circle, color: AppColors.sage),
          const SizedBox(width: 12),
          Expanded(
            child: Text('أتممت «${b.title}» · ${b.pages} صفحة', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ),
          if (!compact) _menu(context, b),
        ]),
      );
    }

    final target = t?.target ?? b.perDay;
    final read = (t?.readCount ?? 0).clamp(0, target);
    final done = t?.done ?? false;
    final finish = lib.finishDate(b);
    final streak = lib.streakOf(b.id);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(compact ? 'ورد «${b.title}»' : b.title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          if (done) const Icon(Icons.check_circle, color: AppColors.sage),
          if (!compact) _menu(context, b),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              t == null ? 'ورد اليوم $target صفحات' : 'ورد اليوم: ص ${t.fromPos}–${t.toPos} · قرأت $read من $target',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: target == 0 ? 1 : read / target, minHeight: 7, borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 8),
            Text(
              [
                'وصلت ص ${b.position - 1} من ${b.pages} (${(b.progress * 100).round()}٪)',
                if (finish != null) 'الختم ${gregorianFull(finish)}',
                if (streak > 1) 'خطك ${daysWord(streak)}',
              ].join(' · '),
              style: TextStyle(color: pal.muted, fontSize: 13),
            ),
            if (!exists) ...[
              const SizedBox(height: 8),
              Text('ملف الكتاب غير موجود على هذا الهاتف (ربما بعد استعادة نسخة). اختره من جديد ليبقى تقدمك.',
                  style: TextStyle(color: scheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: exists
                    ? FilledButton(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookReader(book: b))),
                        child: Text(done ? 'زد إن شئت' : read == 0 ? 'ابدأ ورد اليوم' : 'أكمل القراءة'),
                      )
                    : FilledButton.tonal(onPressed: () => _relink(context, b), child: const Text('اختر ملف الكتاب')),
              ),
              if (!done && t != null) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: () => lib.markTodayDone(b), child: const Text('قرأته من نسخة ورقية')),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }

  Future<void> _relink(BuildContext context, Book b) async {
    final lib = context.read<AppState>().library;
    final path = await _pickPdf();
    if (path == null) return;
    try {
      await lib.relink(b, path);
    } catch (_) {
      if (context.mounted) toast(context, 'تعذر فتح الملف.');
    }
  }

  Widget _menu(BuildContext context, Book b) {
    final lib = context.read<AppState>().library;
    return PopupMenuButton<String>(
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            final res = await showDialog<(String, int)>(
              context: context,
              builder: (c) => _BookDialog(title: b.title, perDay: b.perDay, editing: true),
            );
            if (res != null) await lib.update(b, title: res.$1, perDay: res.$2);
          case 'pos':
            if (!context.mounted) return;
            final ctl = TextEditingController(text: '${b.position}');
            final n = await showDialog<int>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('من أي صفحة تكمل؟'),
                content: TextField(
                  controller: ctl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(hintText: 'من 1 إلى ${b.pages}'),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
                  FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(ctl.text)), child: const Text('حفظ')),
                ],
              ),
            );
            if (n != null) await lib.update(b, position: n.clamp(1, b.pages + 1));
          case 'benefits':
            if (context.mounted) openBenefitsPage(context, source: b.title);
          case 'relink':
            if (context.mounted) await _relink(context, b);
          case 'del':
            if (!context.mounted) return;
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('حذف الكتاب'),
                content: Text('يُحذف «${b.title}» وسجل ورده من التطبيق. الفوائد التي حفظتها منه تبقى في الدفتر.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('احذف')),
                ],
              ),
            );
            if (ok == true) await lib.remove(b);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'benefits', child: Text('فوائد هذا الكتاب')),
        PopupMenuItem(value: 'edit', child: Text('الاسم وصفحات كل يوم')),
        PopupMenuItem(value: 'pos', child: Text('غيّر موضع القراءة')),
        PopupMenuItem(value: 'relink', child: Text('اختر الملف من جديد')),
        PopupMenuItem(value: 'del', child: Text('حذف')),
      ],
    );
  }
}
