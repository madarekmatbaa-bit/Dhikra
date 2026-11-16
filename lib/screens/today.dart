import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/adhkar_data.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/arabic.dart';
import '../widgets/brand.dart';
import 'adhkar_tab.dart';
import 'benefit_edit.dart';
import 'home_shell.dart';
import 'library_tab.dart';
import 'quran_tab.dart';
import 'reader.dart';
import 'settings.dart';

class TodayScreen extends StatelessWidget {
  final ValueChanged<int> onOpenTab;
  const TodayScreen({super.key, required this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final now = s.clock();
    final yesterday = dateOnly(now).subtract(const Duration(days: 1));
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          Row(children: [
            const BrandMark(size: 30),
            const SizedBox(width: 10),
            const Text('ذِكرى',
                style: TextStyle(fontFamily: readingFont, fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.olive)),
            const Spacer(),
            IconButton(
              tooltip: 'دفتر الفوائد',
              icon: const Icon(Icons.bookmark_border),
              onPressed: () => openBenefitsPage(context),
            ),
            IconButton(
              tooltip: 'الإحصاءات',
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () => openStatsPage(context),
            ),
            IconButton(
              tooltip: 'الإعدادات',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ]),
          const SizedBox(height: 18),
          // التاريخ كرأس صفحة: الهجري بخط النسخ، والميلادي تحته.
          Text(hijriLong(now), style: const TextStyle(fontFamily: readingFont, fontSize: 27, fontWeight: FontWeight.w700, height: 1.35)),
          Text(gregorianLong(now), style: TextStyle(color: pal.muted, fontSize: 14)),
          const SizedBox(height: 14),
          const Ornament(),
          const SizedBox(height: 20),
          if (s.update != null) ...[
            SectionCard(
              color: pal.highlight,
              onTap: () => checkUpdateInteractive(context),
              child: Row(children: [
                const Icon(Icons.system_update_outlined, color: AppColors.olive),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('نسخة جديدة من ذِكرى متاحة (${s.update!.build}). اضغط لتنزيلها.',
                      style: const TextStyle(fontSize: 15)),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          if (s.quran.enabled) ...[
            const QuranTodayCard(compact: true),
            const SizedBox(height: 12),
          ],
          const _WirdCard(),
          if (s.canExcuseYesterday) ...[
            const SizedBox(height: 12),
            SectionCard(
              color: pal.highlight,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('فاتك ورد أمس', style: TextStyle(fontFamily: readingFont, fontSize: 17, fontWeight: FontWeight.w700, height: 1.45)),
                const SizedBox(height: 4),
                const Text('لك يوم عذر واحد في الأسبوع لا ينقطع به خطك.', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton(
                    onPressed: () => s.excuse(yesterday),
                    child: const Text('احسب أمس يوم عذر'),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          _StatsStrip(state: s),
          for (final b in s.library.books.where((b) => !b.finished)) ...[
            const SizedBox(height: 12),
            BookCard(book: b, compact: true),
          ],
          if (!s.quran.enabled) ...[
            const SizedBox(height: 12),
            SectionCard(
              color: pal.soft,
              onTap: () => onOpenTab(1),
              child: Row(children: [
                const Icon(Icons.auto_stories_outlined, color: AppColors.olive),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('أضف ورد حفظ القرآن ومراجعته: الجديد والقريب والبعيد.', style: TextStyle(fontSize: 15)),
                ),
                Icon(Icons.chevron_left, color: pal.muted),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          const PrayerTimesCard(compact: true),
          const SizedBox(height: 12),
          const _AdhkarRow(),
          const SizedBox(height: 12),
          _BenefitOfDay(onOpenTab: onOpenTab),
        ],
      ),
    );
  }
}

class _WirdCard extends StatelessWidget {
  const _WirdCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final scheme = Theme.of(context).colorScheme;

    if (s.finished) {
      return SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ختمت صحيح البخاري', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('الحمد لله الذي بنعمته تتم الصالحات. عدد ختماتك: ${s.khatmas}.', style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 14),
          FilledButton(onPressed: s.newKhatma, child: const Text('ابدأ ختمة جديدة')),
        ]),
      );
    }

    final log = s.todayLog;
    final target = log?.target ?? s.plan!.perDay;
    final read = (log?.readCount ?? 0).clamp(0, target);
    final done = log?.done ?? false;
    final from = log?.fromPos ?? s.position;
    final to = log?.toPos ?? s.position + target - 1;
    final book = s.bukhari.bookOf(s.position);

    return SectionCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('ورد البخاري اليوم', style: TextStyle(fontFamily: readingFont, fontSize: 18, fontWeight: FontWeight.w700, height: 1.45))),
          if (log?.excused == true && !done)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: pal.highlight, borderRadius: BorderRadius.circular(10)),
              child: const Text('يوم عذر', style: TextStyle(fontSize: 13)),
            ),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$read', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: scheme.primary, height: 1)),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(' / $target', style: TextStyle(fontSize: 20, color: pal.muted)),
          ),
          const Spacer(),
          if (done) const Icon(Icons.check_circle, color: AppColors.sage, size: 30),
        ]),
        const SizedBox(height: 12),
        LinearProgressIndicator(
            value: target == 0 ? 1 : read / target, minHeight: 8, borderRadius: BorderRadius.circular(6)),
        const SizedBox(height: 12),
        Text('من الحديث $from إلى $to · كتاب ${book.title}', style: TextStyle(color: pal.muted, fontSize: 14)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ReaderScreen(start: s.position, wirdMode: true))),
            child: Text(done ? 'أتممت ورد اليوم · زد إن شئت' : read == 0 ? 'ابدأ ورد اليوم' : 'أكمل القراءة'),
          ),
        ),
        if (!done && log?.excused != true && s.excuseAvailable(s.clock()))
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('يوم عذر'),
                    content: const Text('تحسب اليوم يوم عذر فلا ينقطع خطك. لك يوم واحد في الأسبوع.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('نعم')),
                    ],
                  ),
                );
                if (ok == true) await s.excuse(s.clock());
              },
              child: const Text('عندي عذر اليوم'),
            ),
          ),
      ]),
    );
  }
}

/// الخط والختم المتوقع في بطاقة واحدة يفصل بينهما خط رفيع.
class _StatsStrip extends StatelessWidget {
  final AppState state;
  const _StatsStrip({required this.state});

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final f = state.forecast;
    Widget cell(String value, String label, String? sub) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: pal.muted, fontSize: 13)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontFamily: readingFont, fontSize: 20, fontWeight: FontWeight.w700, height: 1.4)),
              if (sub != null) Text(sub, style: TextStyle(color: pal.muted, fontSize: 12)),
            ]),
          ),
        );
    return SectionCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          cell(daysWord(state.currentStreak), 'خطك الحالي', null),
          VerticalDivider(width: 1, color: pal.line),
          f == null
              ? cell('تم الختم', 'الختم', null)
              : cell(gregorianFull(f.date), 'الختم المتوقع', 'بعد ${daysWord(f.days)}${f.fromActualRate ? ' بمعدلك الفعلي' : ''}'),
        ]),
      ),
    );
  }
}

class _BenefitOfDay extends StatelessWidget {
  final ValueChanged<int> onOpenTab;
  const _BenefitOfDay({required this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final b = s.benefitOfTheDay;
    if (b == null) {
      return SectionCard(
        color: pal.soft,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BenefitEditScreen())),
        child: Row(children: [
          const Icon(Icons.edit_note, color: AppColors.olive),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('دفتر الفوائد فارغ. ما يستوقفك أثناء القراءة احفظه هنا.', style: TextStyle(fontSize: 15)),
          ),
          Icon(Icons.chevron_left, color: pal.muted),
        ]),
      );
    }
    return SectionCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BenefitEditScreen(benefit: b))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Label('من دفترك'),
          const Spacer(),
          TextButton(onPressed: () => openBenefitsPage(context), child: const Text('كل الفوائد')),
        ]),
        if (b.title.isNotEmpty) Text(b.title, style: const TextStyle(fontFamily: readingFont, fontSize: 18, fontWeight: FontWeight.w700, height: 1.45)),
        const SizedBox(height: 4),
        Text(b.body, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 8),
        Text(b.sourceLabel, style: TextStyle(color: pal.muted, fontSize: 13)),
      ]),
    );
  }
}

class _AdhkarRow extends StatelessWidget {
  const _AdhkarRow();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    Widget cell(AdhkarSet set, String label) {
      final done = s.adhkarDone(set);
      return Expanded(
        child: InkWell(
          onTap: () => openAdhkar(context, set),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(children: [
              Icon(done ? Icons.check_circle : Icons.circle_outlined, color: done ? AppColors.sage : pal.line, size: 20),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: done ? pal.muted : null)),
            ]),
          ),
        ),
      );
    }

    return SectionCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          cell(AdhkarSet.morning, 'أذكار الصباح'),
          VerticalDivider(width: 1, color: pal.line),
          cell(AdhkarSet.evening, 'أذكار المساء'),
          VerticalDivider(width: 1, color: pal.line),
          cell(AdhkarSet.sleep, 'أذكار النوم'),
        ]),
      ),
    );
  }
}
