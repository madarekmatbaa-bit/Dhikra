import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/quran_db.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/ranges.dart';
import '../widgets/brand.dart';
import 'quran_tab.dart';

/// تحديد المحفوظ وإعدادات ورد المراجعة.
class QuranSetupScreen extends StatefulWidget {
  const QuranSetupScreen({super.key});

  @override
  State<QuranSetupScreen> createState() => _QuranSetupScreenState();
}

class _QuranSetupScreenState extends State<QuranSetupScreen> {
  late Set<int> memorized;
  late int newPerDay;
  late bool descending;
  late int recentCount;
  late int cycleDays;
  final custom = TextEditingController();

  @override
  void initState() {
    super.initState();
    final c = context.read<AppState>().quran.config;
    memorized = c.memorized.toSet();
    newPerDay = c.newPerDay;
    descending = c.descending;
    recentCount = c.recentCount;
    cycleDays = c.cycleDays;
    custom.text = formatRanges(memorized);
  }

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  void _toggleJuz(QuranDb db, int j) {
    final pages = db.juzPages(j);
    setState(() {
      if (pages.every(memorized.contains)) {
        memorized.removeAll(pages);
      } else {
        memorized.addAll(pages);
      }
      custom.text = formatRanges(memorized);
    });
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    await s.quran.setup(
      memorized: memorized.toList()..sort(),
      newPerDay: newPerDay,
      descending: descending,
      recentCount: recentCount,
      cycleDays: cycleDays,
    );
    if (!mounted) return;
    toast(context, 'حُفظ ورد القرآن');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final db = s.quranDb;
    final pal = Palette.of(context);
    final recentN = min(recentCount, memorized.length);
    final oldN = memorized.length - recentN;
    final oldPerDay = oldN == 0 ? 0 : (oldN / cycleDays).ceil();

    return Scaffold(
      appBar: AppBar(title: const Text('ورد القرآن')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
        children: [
          const _Head('ما تحفظه الآن'),
          Text('اختر الأجزاء التي تحفظها كاملة، أو اكتب الصفحات بالأرقام.',
              style: TextStyle(color: pal.muted, fontSize: 14)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var j = 1; j <= 30; j++)
              FilterChip(
                label: Text('$j'),
                selected: db.juzPages(j).every(memorized.contains),
                showCheckmark: false,
                onSelected: (_) => _toggleJuz(db, j),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: custom,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'الصفحات المحفوظة',
              hintText: 'مثال: 1-21, 582-604',
            ),
            onChanged: (v) => setState(() => memorized = parseRanges(v).toSet()),
          ),
          const SizedBox(height: 6),
          Text(
            memorized.isEmpty
                ? 'لم تحدد شيئاً بعد. لا بأس إن كنت تبدأ الحفظ من الصفر.'
                : '${memorized.length} صفحة · ${juzCount(db, memorized.toList())} جزءاً كاملاً',
            style: TextStyle(color: pal.muted, fontSize: 13),
          ),
          const _Head('الحفظ الجديد كل يوم'),
          Card(
            child: Column(children: [
              ListTile(
                title: Text(newPerDay == 0 ? 'لا حفظ جديد، مراجعة فقط' : '$newPerDay ${newPerDay == 1 ? 'صفحة' : 'صفحات'} في اليوم'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: newPerDay > 0 ? () => setState(() => newPerDay--) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: newPerDay < 10 ? () => setState(() => newPerDay++) : null,
                  ),
                ]),
              ),
              if (newPerDay > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('من أول المصحف')),
                      ButtonSegment(value: true, label: Text('من آخره (جزء عمّ)')),
                    ],
                    selected: {descending},
                    onSelectionChanged: (v) => setState(() => descending = v.first),
                  ),
                ),
            ]),
          ),
          const _Head('مراجعة القريب'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('آخر ما حفظته يُقرأ كل يوم. كم صفحة؟'),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  for (final n in const [5, 10, 20, 30])
                    ChoiceChip(label: Text('$n'), selected: recentCount == n, onSelected: (_) => setState(() => recentCount = n)),
                ]),
              ]),
            ),
          ),
          const _Head('مراجعة البعيد'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('يمرّ عليك كل محفوظك القديم مرة كل:'),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final d in const [7, 10, 14, 21, 30])
                    ChoiceChip(label: Text('$d يوماً'), selected: cycleDays == d, onSelected: (_) => setState(() => cycleDays = d)),
                ]),
                const SizedBox(height: 10),
                Text(
                  oldN == 0
                      ? 'لا يوجد محفوظ بعيد بعد؛ كل ما تحفظه الآن في «القريب».'
                      : 'يعني نحو $oldPerDay ${oldPerDay == 1 ? 'صفحة' : 'صفحات'} في اليوم من $oldN صفحة.',
                  style: TextStyle(color: pal.muted, fontSize: 13),
                ),
              ]),
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
          FilledButton(onPressed: _save, child: const Text('حفظ')),
          const SizedBox(height: 12),
          Text(
            'تقسيم «الجديد والقريب والبعيد» طريقة معروفة عند معلّمي التحفيظ. غيّر الأرقام بما يناسب وقتك، والمهم الدوام.',
            style: TextStyle(color: pal.muted, fontSize: 13, height: 1.7),
          ),
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

