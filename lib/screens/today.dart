import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../util/arabic.dart';
import '../widgets/brand.dart';
import 'benefit_edit.dart';
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
            const BrandMark(size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ذِكرى', style: Theme.of(context).textTheme.titleLarge),
                Text('${gregorianLong(now)} · ${hijriLong(now)}', style: TextStyle(color: pal.muted, fontSize: 13)),
              ]),
            ),
            IconButton(
              tooltip: 'الإعدادات',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ]),
          const SizedBox(height: 20),
          const _WirdCard(),
          if (s.canExcuseYesterday) ...[
            const SizedBox(height: 12),
            SectionCard(
              color: pal.highlight,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('فاتك ورد أمس', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
          Row(children: [
            Expanded(
              child: _StatTile(
                icon: Icons.local_fire_department_outlined,
                value: daysWord(s.currentStreak),
                label: 'خطك الحالي',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _ForecastTile(state: s)),
          ]),
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
          const Expanded(child: Text('ورد البخاري اليوم', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
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

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String? sub;
  const _StatTile({required this.icon, required this.value, required this.label, this.sub});

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

class _ForecastTile extends StatelessWidget {
  final AppState state;
  const _ForecastTile({required this.state});

  @override
  Widget build(BuildContext context) {
    final f = state.forecast;
    if (f == null) {
      return const _StatTile(icon: Icons.flag_outlined, value: 'تم الختم', label: 'الختم');
    }
    return _StatTile(
      icon: Icons.flag_outlined,
      value: gregorianFull(f.date),
      label: 'الختم المتوقع',
      sub: 'بعد ${daysWord(f.days)}${f.fromActualRate ? ' بمعدلك الفعلي' : ''}',
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
          TextButton(onPressed: () => onOpenTab(2), child: const Text('كل الفوائد')),
        ]),
        if (b.title.isNotEmpty) Text(b.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(b.body, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 8),
        Text(b.sourceLabel, style: TextStyle(color: pal.muted, fontSize: 13)),
      ]),
    );
  }
}
