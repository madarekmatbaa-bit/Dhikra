import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/quran_db.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/arabic.dart';
import '../widgets/brand.dart';
import 'quran_tab.dart';

/// إعداد ورد القرآن اليومي: كم صفحة كل يوم، ومن أين يبدأ.
class QuranSetupScreen extends StatefulWidget {
  const QuranSetupScreen({super.key});

  @override
  State<QuranSetupScreen> createState() => _QuranSetupScreenState();
}

class _QuranSetupScreenState extends State<QuranSetupScreen> {
  late int perDay;
  late int start;
  bool startChanged = false;

  @override
  void initState() {
    super.initState();
    final q = context.read<AppState>().quran;
    perDay = q.enabled ? q.perDay : 20;
    final t = q.today;
    start = t != null && !t.done && t.pages.isNotEmpty ? t.pages.first : q.next;
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final first = !s.quran.enabled;
    await s.quran.setup(perDay: perDay, start: first || startChanged ? start : null);
    if (!mounted) return;
    toast(context, 'حُفظ ورد القرآن');
    Navigator.pop(context);
  }

  Future<void> _pickStart(QuranDb db) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (c, ctrl) => ListView(
          controller: ctrl,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('ابدأ من أول جزء…', style: TextStyle(fontFamily: readingFont, fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (var j = 1; j <= 30; j++)
              ListTile(
                leading: SizedBox(width: 28, child: Text('$j', style: const TextStyle(fontFamily: readingFont, fontSize: 17))),
                title: Text('الجزء $j'),
                subtitle: Text('صفحة ${db.juzPages(j).first} · سورة ${db.suraOfPage(db.juzPages(j).first).name}'),
                onTap: () => Navigator.pop(c, db.juzPages(j).first),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        start = picked;
        startChanged = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final db = s.quranDb;
    final pal = Palette.of(context);
    final days = ((quranPages - start + 1) / perDay).ceil();
    final fullDays = (quranPages / perDay).ceil();
    return Scaffold(
      appBar: AppBar(title: const Text('ورد القرآن')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
        children: [
          const _Head('كم صفحة تقرأ كل يوم؟'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final n in const [5, 10, 20, 30, 40])
              ChoiceChip(
                label: Text('$n صفحة', style: const TextStyle(fontSize: 16)),
                selected: perDay == n,
                onSelected: (_) => setState(() => perDay = n),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Text('عدد آخر:', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            IconButton.outlined(onPressed: perDay > 1 ? () => setState(() => perDay--) : null, icon: const Icon(Icons.remove)),
            SizedBox(
              width: 52,
              child: Text('$perDay', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            IconButton.outlined(onPressed: perDay < 100 ? () => setState(() => perDay++) : null, icon: const Icon(Icons.add)),
          ]),
          const SizedBox(height: 8),
          Text(
            perDay == 20
                ? 'عشرون صفحة: جزء كل يوم، فتختم في شهر.'
                : 'تختم المصحف كاملاً في ${daysWord(fullDays)}، ${roughDuration(fullDays)} تقريباً.',
            style: TextStyle(color: pal.muted, fontSize: 14),
          ),
          const _Head('من أين تبدأ؟'),
          Card(
            child: ListTile(
              title: Text('صفحة $start · سورة ${db.suraOfPage(start).name}'),
              subtitle: Text(start == 1 ? 'من أول المصحف' : 'يبقى ${daysWord(days)} على الختم'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _pickStart(db),
            ),
          ),
          const _Head('التذكير'),
          Card(
            child: SwitchListTile(
              title: const Text('ذكّرني بورد القرآن'),
              subtitle: Text(quranReminderLabel(s.quran)),
              value: s.quran.reminder != null,
              onChanged: (v) => v ? pickQuranReminder(context) : s.quran.setReminder(null),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(onPressed: _save, child: Text(s.quran.enabled ? 'حفظ' : 'ابدأ الورد')),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  final String text;
  const _Head(this.text);

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(4, 22, 4, 8), child: Label(text));
}
