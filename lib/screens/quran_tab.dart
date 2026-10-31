import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/quran_db.dart';
import '../services/notifications.dart';
import '../state/app_state.dart';
import '../state/quran_review.dart';
import '../theme.dart';
import '../util/arabic.dart';
import '../util/ranges.dart';
import '../widgets/brand.dart';
import 'quran_notes.dart';
import 'quran_reader.dart';
import 'quran_setup.dart';

class QuranTab extends StatelessWidget {
  const QuranTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final q = s.quran;
    final pal = Palette.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          Row(children: [
            Expanded(child: Text('القرآن الكريم', style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
              tooltip: 'الغلطات والمتشابهات',
              icon: const Icon(Icons.sticky_note_2_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuranNotesScreen())),
            ),
            if (q.enabled)
              IconButton(
                tooltip: 'إعدادات المراجعة',
                icon: const Icon(Icons.tune),
                onPressed: () => openQuranSetup(context),
              ),
          ]),
          const SizedBox(height: 14),
          if (!q.enabled) const _Intro() else const QuranTodayCard(),
          const SizedBox(height: 12),
          SectionCard(
            onTap: () => openMushaf(context, q.lastPage),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: pal.soft,
                child: Icon(Icons.auto_stories_outlined, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('المصحف', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('تابع من الصفحة ${q.lastPage} · سورة ${s.quranDb.suraOfPage(q.lastPage).name}',
                      style: TextStyle(color: pal.muted, fontSize: 13)),
                ]),
              ),
              Icon(Icons.chevron_left, color: pal.muted),
            ]),
          ),
          if (q.enabled) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _Tile(
                  icon: Icons.local_fire_department_outlined,
                  value: daysWord(q.currentStreak),
                  label: 'خط المراجعة',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Tile(
                  icon: Icons.menu_book_outlined,
                  value: '${q.config.memorized.length} صفحة',
                  label: 'محفوظك من 604',
                  sub: q.daysToFinish == null ? null : 'الختم حفظاً بعد ${roughDuration(q.daysToFinish!)} تقريباً',
                ),
              ),
            ]),
          ],
          const SizedBox(height: 18),
          Text(
            'نص المصحف وخطه من ${s.quranDb.source}. اضغط على أي آية لتسجّل غلطة أو متشابهاً أو فائدة.',
            style: TextStyle(color: pal.muted, fontSize: 13, height: 1.7),
          ),
        ],
      ),
    );
  }
}

void openMushaf(BuildContext context, int page, {List<int>? portion, String? title, int? sura, int? aya}) =>
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuranReader(page: page, portion: portion, portionTitle: title, highlightSura: sura, highlightAya: aya),
      ),
    );

void openQuranSetup(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const QuranSetupScreen()));

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    Widget row(IconData i, String t, String d) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, color: AppColors.wheat, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$t: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: d),
              ]), style: const TextStyle(fontSize: 14, height: 1.6)),
            ),
          ]),
        );
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ورد الحفظ والمراجعة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('كل يوم ثلاثة أجزاء صغيرة، يحسبها التطبيق لك:', style: TextStyle(color: pal.muted, fontSize: 14)),
        const SizedBox(height: 12),
        row(Icons.add_circle_outline, 'الجديد', 'ما تحفظه اليوم، صفحة أو أكثر، أو لا شيء إن كنت تراجع فقط.'),
        row(Icons.history, 'القريب', 'آخر ما حفظته (20 صفحة مثلاً) يُقرأ كل يوم حتى يثبت.'),
        row(Icons.autorenew, 'البعيد', 'باقي محفوظك مقسوم على دورة تختارها، فيمرّ كله عليك كل أسبوعين مثلاً.'),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: () => openQuranSetup(context), child: const Text('حدّد محفوظك وابدأ')),
        ),
      ]),
    );
  }
}

/// بطاقة ورد القرآن لليوم، تُستعمل هنا وفي شاشة «اليوم».
class QuranTodayCard extends StatelessWidget {
  final bool compact;
  const QuranTodayCard({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final q = s.quran;
    final pal = Palette.of(context);
    final t = q.today;
    if (t == null || t.isEmpty) {
      return SectionCard(
        color: pal.soft,
        onTap: () => openQuranSetup(context),
        child: const Text('لا شيء في ورد القرآن اليوم. حدّد محفوظك أو صفحات الحفظ الجديد من الإعدادات.',
            style: TextStyle(fontSize: 15)),
      );
    }
    Widget part(String title, IconData icon, List<int> pages, bool done, Future<void> Function(bool) mark) {
      if (pages.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          color: done ? pal.soft : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => openMushaf(context, pages.first, portion: pages, title: title),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(children: [
                Icon(icon, color: done ? AppColors.sage : AppColors.wheat),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    Text(_where(s, pages), style: TextStyle(color: pal.muted, fontSize: 13)),
                  ]),
                ),
                Checkbox(value: done, onChanged: (v) => mark(v ?? false)),
              ]),
            ),
          ),
        ),
      );
    }

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('ورد القرآن اليوم', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          Text('${t.partsDone} / ${t.partsTotal}', style: TextStyle(color: pal.muted, fontSize: 15)),
          const SizedBox(width: 6),
          if (t.complete) const Icon(Icons.check_circle, color: AppColors.sage),
        ]),
        part('الحفظ الجديد', Icons.add_circle_outline, t.newPages, t.newDone, q.markNew),
        part('مراجعة القريب', Icons.history, t.recent, t.recentDone, q.markRecent),
        part('مراجعة البعيد', Icons.autorenew, t.old, t.oldDone, q.markOld),
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('اضغط على الجزء لتفتحه في المصحف، وعلّم عليه حين تتمّه.',
                style: TextStyle(color: pal.muted, fontSize: 12)),
          ),
      ]),
    );
  }

  static String _where(AppState s, List<int> pages) {
    final first = s.quranDb.suraOfPage(pages.first).name;
    final last = s.quranDb.suraOfPage(pages.last).name;
    final suras = first == last ? 'سورة $first' : 'من $first إلى $last';
    return '${describeRanges(pages)} · $suras';
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String? sub;
  const _Tile({required this.icon, required this.value, required this.label, this.sub});

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppColors.wheat),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(color: pal.muted, fontSize: 13)),
        if (sub != null) Text(sub!, style: TextStyle(color: pal.muted, fontSize: 12)),
      ]),
    );
  }
}

/// تذكير ورد القرآن، يُستعمل في شاشة الإعدادات.
Future<void> pickQuranReminder(BuildContext context) async {
  final q = context.read<AppState>().quran;
  final t = await showTimePicker(context: context, initialTime: q.reminder ?? const TimeOfDay(hour: 5, minute: 30));
  if (t != null) await q.setReminder(t);
}

String quranReminderLabel(QuranReview q) => q.reminder == null ? 'مطفأ' : formatTime(q.reminder!);

int juzCount(QuranDb db, List<int> memorized) {
  final m = memorized.toSet();
  var n = 0;
  for (var j = 1; j <= 30; j++) {
    if (db.juzPages(j).every(m.contains)) n++;
  }
  return n;
}
