import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notifications.dart';
import '../state/app_state.dart';
import '../state/quran_review.dart';
import '../theme.dart';
import '../util/arabic.dart';
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
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          sliver: SliverList.list(children: [
            Row(children: [
              Expanded(child: Text('المصحف', style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                tooltip: 'الغلطات والمتشابهات',
                icon: const Icon(Icons.sticky_note_2_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuranNotesScreen())),
              ),
              if (q.enabled)
                IconButton(
                  tooltip: 'إعدادات الورد',
                  icon: const Icon(Icons.tune),
                  onPressed: () => openQuranSetup(context),
                ),
            ]),
            const SizedBox(height: 10),
            if (!q.enabled) const _Intro() else const QuranTodayCard(),
            const SizedBox(height: 12),
            SectionCard(
              onTap: () => openMushaf(context, q.lastPage),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                const SizedBox(width: 30, child: Icon(Icons.bookmark_outline, color: AppColors.wheat)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('حيث توقفت', style: TextStyle(fontFamily: readingFont, fontSize: 17, fontWeight: FontWeight.w700, height: 1.45)),
                    Text('صفحة ${q.lastPage} · سورة ${s.quranDb.suraOfPage(q.lastPage).name}',
                        style: TextStyle(color: pal.muted, fontSize: 13)),
                  ]),
                ),
                Icon(Icons.chevron_left, color: pal.muted),
              ]),
            ),
            const SizedBox(height: 22),
            const Label('فهرس السور'),
            const SizedBox(height: 8),
          ]),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          sliver: SliverToBoxAdapter(
            child: Card(
              child: Column(children: [
                for (final sura in s.quranDb.suras) ...[
                  if (sura.id > 1) Divider(height: 1, indent: 16, endIndent: 16, color: pal.line),
                  InkWell(
                    onTap: () => openMushaf(context, sura.firstPage),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      child: Row(children: [
                        SizedBox(
                          width: 34,
                          child: Text('${sura.id}', style: TextStyle(fontFamily: readingFont, fontSize: 15, color: pal.muted)),
                        ),
                        Expanded(
                          child: Text('سورة ${sura.name}',
                              style: const TextStyle(fontFamily: readingFont, fontSize: 17, fontWeight: FontWeight.w700, height: 1.4)),
                        ),
                        Text('${sura.ayat} آية · ص ${sura.firstPage}', style: TextStyle(color: pal.muted, fontSize: 12.5)),
                      ]),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

void openMushaf(BuildContext context, int page,
        {List<int>? portion, String? title, int? sura, int? aya, Future<void> Function()? onFinish}) =>
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuranReader(
          page: page,
          portion: portion,
          portionTitle: title,
          highlightSura: sura,
          highlightAya: aya,
          onFinishPortion: onFinish,
        ),
      ),
    );

/// يفتح ورد اليوم في المصحف من حيث وقف فيه.
void openQuranWird(BuildContext context) {
  final q = context.read<AppState>().quran;
  final t = q.today;
  if (t == null || t.isEmpty) return;
  final start = t.done || t.reached < t.pages.first ? t.pages.first : t.reached.clamp(t.pages.first, t.pages.last);
  openMushaf(context, start, portion: t.pages, title: 'ورد اليوم', onFinish: t.done ? null : () => q.markDone(true));
}

void openQuranSetup(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const QuranSetupScreen()));

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ورد يومي من المصحف', style: TextStyle(fontFamily: readingFont, fontSize: 19, fontWeight: FontWeight.w700, height: 1.45)),
        const SizedBox(height: 6),
        Text('تختار عدد الصفحات كل يوم، 10 أو 20 أو 30، ويمضي بك الورد في المصحف بالترتيب حتى تختم ثم يبدأ من جديد.',
            style: TextStyle(color: pal.muted, fontSize: 14, height: 1.6)),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: () => openQuranSetup(context), child: const Text('حدّد وردك')),
        ),
      ]),
    );
  }
}

/// بطاقة ورد القرآن لليوم، تُستعمل هنا وفي الصفحة الرئيسية.
class QuranTodayCard extends StatelessWidget {
  const QuranTodayCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final q = s.quran;
    final pal = Palette.of(context);
    final t = q.today;
    if (!q.enabled) {
      return SectionCard(
        color: pal.soft,
        onTap: () => openQuranSetup(context),
        child: const Row(children: [
          Icon(Icons.auto_stories_outlined, color: AppColors.olive),
          SizedBox(width: 12),
          Expanded(child: Text('حدّد ورداً يومياً من المصحف: 10 أو 20 أو 30 صفحة.', style: TextStyle(fontSize: 15))),
          Icon(Icons.chevron_left),
        ]),
      );
    }
    if (t == null || t.isEmpty) return const SizedBox.shrink();
    final read = t.readCount;
    final total = t.pages.length;
    final first = s.quranDb.suraOfPage(t.pages.first).name;
    final last = s.quranDb.suraOfPage(t.pages.last).name;
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('ورد القرآن', style: TextStyle(fontFamily: readingFont, fontSize: 18, fontWeight: FontWeight.w700, height: 1.45)),
          ),
          Text(t.done ? 'تمّ' : '$read من $total', style: TextStyle(color: t.done ? AppColors.sage : pal.muted, fontSize: 14, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 2),
        Text(
          'الصفحات ${t.pages.first}–${t.pages.last} · ${first == last ? 'سورة $first' : 'من $first إلى $last'}',
          style: TextStyle(color: pal.muted, fontSize: 13.5),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: total == 0 ? 0 : read / total, minHeight: 5, borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: () => openQuranWird(context),
              child: Text(t.done ? 'اقرأ مرة أخرى' : read == 0 ? 'ابدأ الورد' : 'أكمل من صفحة ${t.reached}'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: t.done ? 'إلغاء الإتمام' : 'قرأته',
            onPressed: () => q.markDone(!t.done),
            icon: Icon(t.done ? Icons.check_circle : Icons.check, color: t.done ? AppColors.sage : null),
          ),
        ]),
        if (q.khatmas > 0 || t.done)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              [
                if (q.khatmas > 0) 'ختماتك: ${q.khatmas}',
                'الختم بعد ${daysWord(q.daysToKhatma)}',
              ].join(' · '),
              style: TextStyle(color: pal.muted, fontSize: 12.5),
            ),
          ),
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
