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

class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

/// قيم خاصة لمرشّح الرفوف.
const _all = '\u0000all', _none = '\u0000none', _read = '\u0000read';

class _LibraryTabState extends State<LibraryTab> {
  String filter = _all;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final lib = s.library;
    final pal = Palette.of(context);
    final shelves = lib.shelves;
    final reading = lib.books.where((b) => !b.finished).toList();
    final read = lib.books.where((b) => b.finished).toList();
    final unshelved = lib.books.where((b) => b.shelf == null).toList();
    if (filter != _all && filter != _none && filter != _read && !shelves.contains(filter)) filter = _all;

    Widget chip(String value, String label, int count, {IconData? icon}) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 16),
        label: Text(count > 0 ? '$label · $count' : label),
        selected: filter == value,
        onSelected: (_) => setState(() => filter = value),
      ),
    );

    List<Widget> section(String title, List<Book> list, {String? shelf}) => [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Row(
          children: [
            Icon(shelf == null ? Icons.inbox_outlined : Icons.shelves, size: 18, color: AppColors.wheat),
            const SizedBox(width: 6),
            Expanded(child: Label('$title · ${list.length}')),
          ],
        ),
      ),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Text('لا كتب على هذا الرف بعد.', style: TextStyle(color: pal.muted, fontSize: 13)),
        ),
      for (final b in list) ...[BookCard(book: b), const SizedBox(height: 10)],
    ];

    final body = <Widget>[];
    if (filter == _all) {
      for (final sh in shelves) {
        body.addAll(section(sh, lib.books.where((b) => b.shelf == sh && !b.finished).toList(), shelf: sh));
      }
      final rest = unshelved.where((b) => !b.finished).toList();
      if (rest.isNotEmpty || shelves.isEmpty) {
        body.addAll(section(shelves.isEmpty ? 'كتبي' : 'بلا رف', rest));
      }
      if (read.isNotEmpty) body.addAll(section('قرأتها', read));
    } else if (filter == _read) {
      body.addAll(section('قرأتها', read));
    } else if (filter == _none) {
      body.addAll(section('بلا رف', unshelved));
    } else {
      body.addAll(section(filter, lib.books.where((b) => b.shelf == filter).toList(), shelf: filter));
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => addBookFlow(context, shelf: shelves.contains(filter) ? filter : null),
        icon: const Icon(Icons.add),
        label: const Text('أضف كتاباً'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 96),
          children: [
            Row(
              children: [
                Expanded(child: Text('المكتبة', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                  tooltip: 'الرفوف',
                  icon: const Icon(Icons.shelves),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShelvesScreen())),
                ),
                IconButton(
                  tooltip: 'تذكير ورد الكتب',
                  icon: Icon(lib.reminder == null ? Icons.notifications_none : Icons.notifications_active_outlined),
                  onPressed: () => _reminder(context),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (lib.books.isEmpty && shelves.isEmpty)
              SectionCard(
                color: pal.soft,
                onTap: () => addBookFlow(context),
                child: const Row(
                  children: [
                    Icon(Icons.local_library_outlined, color: AppColors.olive),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'أضف كتاباً بصيغة PDF من هاتفك، وحدد كم صفحة تقرأ منه كل يوم. يتذكر التطبيق أين وصلت ويحسب لك موعد الختم. ورتّب كتبك على رفوف من زر الرفوف في الأعلى.',
                        style: TextStyle(fontSize: 15, height: 1.6),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    chip(_all, 'الكل', 0),
                    for (final sh in shelves)
                      chip(sh, sh, lib.books.where((b) => b.shelf == sh).length, icon: Icons.shelves),
                    if (shelves.isNotEmpty && unshelved.isNotEmpty) chip(_none, 'بلا رف', unshelved.length),
                    if (read.isNotEmpty) chip(_read, 'قرأتها', read.length, icon: Icons.done_all),
                  ],
                ),
              ),
              if (reading.isEmpty && filter == _all && read.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('أتممت كل كتبك. أضف كتاباً جديداً لتبدأ ورده.', style: TextStyle(color: pal.muted)),
                ),
              ...body,
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

Future<void> addBookFlow(BuildContext context, {String? shelf}) async {
  final lib = context.read<AppState>().library;
  final path = await _pickPdf();
  if (path == null || !context.mounted) return;
  final res = await showDialog<_BookResult>(
    context: context,
    builder: (c) => _BookDialog(title: p.basenameWithoutExtension(path), perDay: 10, shelf: shelf),
  );
  if (res == null || !context.mounted) return;
  try {
    if (res.shelf != null) await lib.addShelf(res.shelf!);
    final b = await lib.addBook(path, res.title, perDay: res.perDay, shelf: res.shelf, alreadyRead: res.alreadyRead);
    if (context.mounted) toast(context, 'أُضيف «${b.title}» · ${b.pages} صفحة');
  } catch (_) {
    if (context.mounted) toast(context, 'تعذر فتح الملف. تأكد أنه PDF سليم.');
  }
}

class _BookResult {
  final String title;
  final int perDay;
  final String? shelf;
  final bool alreadyRead;
  const _BookResult(this.title, this.perDay, this.shelf, this.alreadyRead);
}

class _BookDialog extends StatefulWidget {
  final String title;
  final int perDay;
  final String? shelf;
  final bool editing;
  const _BookDialog({required this.title, required this.perDay, this.shelf, this.editing = false});

  @override
  State<_BookDialog> createState() => _BookDialogState();
}

class _BookDialogState extends State<_BookDialog> {
  late final TextEditingController title = TextEditingController(text: widget.title);
  late int perDay = widget.perDay;
  late String? shelf = widget.shelf;
  bool alreadyRead = false;

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> _newShelf() async {
    final n = await askShelfName(context);
    if (n != null) setState(() => shelf = n);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.editing ? 'تعديل الكتاب' : 'كتاب جديد'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'اسم الكتاب'),
            ),
            if (!widget.editing) ...[
              const SizedBox(height: 16),
              const Text('الرف'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('بلا رف'),
                    selected: shelf == null,
                    onSelected: (_) => setState(() => shelf = null),
                  ),
                  for (final sh in {...context.read<AppState>().library.shelves, ?shelf})
                    ChoiceChip(label: Text(sh), selected: shelf == sh, onSelected: (_) => setState(() => shelf = sh)),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('رف جديد'),
                    onPressed: _newShelf,
                  ),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: alreadyRead,
                onChanged: (v) => setState(() => alreadyRead = v ?? false),
                title: const Text('قرأته من قبل'),
                subtitle: const Text('يُحفظ في «قرأتها» بلا ورد يومي'),
              ),
            ],
            if (!alreadyRead) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('صفحات كل يوم')),
                  IconButton(
                    onPressed: perDay > 1 ? () => setState(() => perDay--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$perDay', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  IconButton(onPressed: () => setState(() => perDay++), icon: const Icon(Icons.add)),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final n in const [5, 10, 20, 30])
                    ChoiceChip(label: Text('$n'), selected: perDay == n, onSelected: (_) => setState(() => perDay = n)),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            final t = title.text.trim();
            if (t.isEmpty) return;
            Navigator.pop(context, _BookResult(t, perDay, shelf, alreadyRead));
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
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.sage),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'أتممت «${b.title}» · ${b.pages} صفحة',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
            if (!compact) _menu(context, b),
          ],
        ),
      );
    }

    final target = t?.target ?? b.perDay;
    final read = (t?.readCount ?? 0).clamp(0, target);
    final done = t?.done ?? false;
    final finish = lib.finishDate(b);
    final streak = lib.streakOf(b.id);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  compact ? 'ورد «${b.title}»' : b.title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (done) const Icon(Icons.check_circle, color: AppColors.sage),
              if (!compact) _menu(context, b),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t == null
                      ? 'ورد اليوم $target صفحات'
                      : 'ورد اليوم: ص ${t.fromPos}–${t.toPos} · قرأت $read من $target',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: target == 0 ? 1 : read / target,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(6),
                ),
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
                  Text(
                    'ملف الكتاب غير موجود على هذا الهاتف (ربما بعد استعادة نسخة). اختره من جديد ليبقى تقدمك.',
                    style: TextStyle(color: scheme.error, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: exists
                          ? FilledButton(
                              onPressed: () =>
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => BookReader(book: b))),
                              child: Text(
                                done
                                    ? 'زد إن شئت'
                                    : read == 0
                                    ? 'ابدأ ورد اليوم'
                                    : 'أكمل القراءة',
                              ),
                            )
                          : FilledButton.tonal(
                              onPressed: () => _relink(context, b),
                              child: const Text('اختر ملف الكتاب'),
                            ),
                    ),
                    if (!done && t != null) ...[
                      const SizedBox(width: 8),
                      TextButton(onPressed: () => lib.markTodayDone(b), child: const Text('قرأته من نسخة ورقية')),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
            final res = await showDialog<_BookResult>(
              context: context,
              builder: (c) => _BookDialog(title: b.title, perDay: b.perDay, editing: true),
            );
            if (res != null) await lib.update(b, title: res.title, perDay: res.perDay);
          case 'shelf':
            if (!context.mounted) return;
            await pickShelfFor(context, b);
          case 'finish':
            await lib.markFinished(b);
            if (context.mounted) toast(context, 'بارك الله لك، أُضيف «${b.title}» إلى ما قرأته');
          case 'restart':
            await lib.restart(b);
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
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'benefits', child: Text('فوائد هذا الكتاب')),
        const PopupMenuItem(value: 'shelf', child: Text('انقله إلى رف')),
        if (b.finished)
          const PopupMenuItem(value: 'restart', child: Text('أعد قراءته من أوله'))
        else
          const PopupMenuItem(value: 'finish', child: Text('قرأته كله')),
        const PopupMenuItem(value: 'edit', child: Text('الاسم وصفحات كل يوم')),
        const PopupMenuItem(value: 'pos', child: Text('غيّر موضع القراءة')),
        const PopupMenuItem(value: 'relink', child: Text('اختر الملف من جديد')),
        const PopupMenuItem(value: 'del', child: Text('حذف')),
      ],
    );
  }
}

Future<String?> askShelfName(BuildContext context, {String initial = '', String title = 'رف جديد'}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'مثلاً: العقيدة، الفقه، العمل'),
        onSubmitted: (v) => Navigator.pop(c, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctl.text.trim().isEmpty ? null : ctl.text.trim()),
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
}

Future<void> pickShelfFor(BuildContext context, Book b) async {
  final lib = context.read<AppState>().library;
  const none = '\u0000none', add = '\u0000add';
  final v = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('رف «${b.title}»', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          for (final sh in lib.shelves)
            ListTile(
              leading: const Icon(Icons.shelves),
              title: Text(sh),
              trailing: b.shelf == sh ? const Icon(Icons.check, color: AppColors.sage) : null,
              onTap: () => Navigator.pop(c, sh),
            ),
          ListTile(
            leading: const Icon(Icons.inbox_outlined),
            title: const Text('بلا رف'),
            trailing: b.shelf == null ? const Icon(Icons.check, color: AppColors.sage) : null,
            onTap: () => Navigator.pop(c, none),
          ),
          ListTile(leading: const Icon(Icons.add), title: const Text('رف جديد'), onTap: () => Navigator.pop(c, add)),
        ],
      ),
    ),
  );
  if (v == null || !context.mounted) return;
  if (v == add) {
    final n = await askShelfName(context);
    if (n != null) await lib.setShelf(b, n);
  } else {
    await lib.setShelf(b, v == none ? null : v);
  }
}

/// إدارة الرفوف: إضافة، إعادة تسمية، ترتيب، حذف.
class ShelvesScreen extends StatelessWidget {
  const ShelvesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<AppState>().library;
    final pal = Palette.of(context);
    final shelves = lib.shelves;
    return Scaffold(
      appBar: AppBar(title: const Text('الرفوف')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final n = await askShelfName(context);
          if (n != null) await lib.addShelf(n);
        },
        icon: const Icon(Icons.add),
        label: const Text('رف جديد'),
      ),
      body: shelves.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'لا رفوف بعد. أضف رفاً لكل باب: العقيدة، الفقه، الحديث، العمل…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: pal.muted, fontSize: 15, height: 1.7),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                for (final (i, sh) in shelves.indexed)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.shelves, color: AppColors.wheat),
                      title: Text(sh),
                      subtitle: Text('${lib.books.where((b) => b.shelf == sh).length} كتاب'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          switch (v) {
                            case 'up':
                              await lib.moveShelf(sh, -1);
                            case 'down':
                              await lib.moveShelf(sh, 1);
                            case 'rename':
                              final n = await askShelfName(context, initial: sh, title: 'إعادة تسمية الرف');
                              if (n != null) await lib.renameShelf(sh, n);
                            case 'del':
                              if (!context.mounted) return;
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: Text('حذف رف «$sh»'),
                                  content: const Text('يُحذف الرف فقط، وتبقى كتبه في المكتبة بلا رف.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('احذف')),
                                  ],
                                ),
                              );
                              if (ok == true) await lib.deleteShelf(sh);
                          }
                        },
                        itemBuilder: (_) => [
                          if (i > 0) const PopupMenuItem(value: 'up', child: Text('انقله للأعلى')),
                          if (i < shelves.length - 1) const PopupMenuItem(value: 'down', child: Text('انقله للأسفل')),
                          const PopupMenuItem(value: 'rename', child: Text('إعادة تسمية')),
                          const PopupMenuItem(value: 'del', child: Text('حذف')),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
