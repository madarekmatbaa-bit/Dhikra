import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/quran_db.dart';
import '../services/notifications.dart';
import '../state/app_state.dart';
import '../state/quran_review.dart';
import '../theme.dart';
import '../util/arabic.dart';
import '../widgets/brand.dart';
import '../widgets/ornaments.dart';
import 'quran_notes.dart';
import 'quran_reader.dart';
import 'quran_setup.dart';

class QuranTab extends StatefulWidget {
  const QuranTab({super.key});

  @override
  State<QuranTab> createState() => _QuranTabState();
}

class _QuranTabState extends State<QuranTab> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Aya>? hits;

  @override
  void dispose() {
    _q.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (v.trim().length < 2) {
        if (mounted) setState(() => hits = null);
        return;
      }
      final r = await context.read<AppState>().quranDb.search(v, limit: 100);
      if (mounted && _q.text == v) setState(() => hits = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final q = s.quran;
    final pal = Palette.of(context);
    return SafeArea(
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverList.list(children: [
            Headpiece(
              title: 'المصحف',
              actions: [
                HeadAction(Icons.sticky_note_2_outlined, 'الغلطات والمتشابهات',
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuranNotesScreen()))),
                if (q.enabled) HeadAction(Icons.tune, 'إعدادات الورد', () => openQuranSetup(context)),
              ],
            ),
            const SizedBox(height: 6),
            const SizedBox(height: 10),
            if (!q.enabled) const _Intro() else const QuranTodayCard(),
            const SizedBox(height: 12),
            // حيث توقفت والتسميع في لوح واحد بنصفين.
            Card(
              clipBehavior: Clip.antiAlias,
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: _HalfTile(
                      icon: Icons.bookmark_outline,
                      title: 'حيث توقفت',
                      detail: 'ص ${q.lastPage} · ${s.quranDb.suraOfPage(q.lastPage).name}',
                      onTap: () => openMushaf(context, q.lastPage),
                    ),
                  ),
                  VerticalDivider(width: 1, indent: 12, endIndent: 12, color: pal.line),
                  Expanded(
                    child: _HalfTile(
                      icon: Icons.mic_none,
                      title: 'سمّع من حفظك',
                      detail: 'يتبعك وينبّهك على الخطأ',
                      onTap: () => openMushaf(context, q.lastPage, listen: true),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _q,
              onChanged: (v) {
                setState(() {});
                _onChanged(v);
              },
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'ابحث في القرآن بكلمة أو أكثر',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _q.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _q.clear();
                          setState(() => hits = null);
                        },
                      ),
              ),
            ),
            const SizedBox(height: 18),
            SectionHead(hits == null ? 'فهرس السور' : hits!.length >= 100 ? 'أول 100 آية' : '${hits!.length} آية'),
          ]),
        ),
        if (hits != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.separated(
              itemCount: hits!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (c, i) {
                final a = hits![i];
                return SectionCard(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  onTap: () => openMushaf(context, a.page, sura: a.sura, aya: a.aya),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('سورة ${s.quranDb.suras[a.sura - 1].name} · الآية ${a.aya} · ص ${a.page}',
                        style: TextStyle(color: pal.muted, fontSize: 12.5)),
                    Text(QuranDb.stripNumber(a.text),
                        style: const TextStyle(fontFamily: quranFont, fontSize: 20, height: 1.9)),
                  ]),
                );
              },
            ),
          )
        else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverToBoxAdapter(
            child: Card(
              child: Column(children: [
                for (final sura in s.quranDb.suras) ...[
                  if (sura.id > 1) Divider(height: 1, indent: 16, endIndent: 16, color: pal.line),
                  InkWell(
                    onTap: () => openMushaf(context, sura.firstPage),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Row(children: [
                        Rosette('${sura.id}', size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('سورة ${sura.name}',
                              style: const TextStyle(fontFamily: readingFont, fontSize: 17, fontWeight: FontWeight.w700, height: 1.4)),
                        ),
                        Text('${sura.ayat} آية · ص ${sura.firstPage}', style: TextStyle(color: pal.muted, fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()])),
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
        {List<int>? portion,
        String? title,
        int? sura,
        int? aya,
        Future<void> Function()? onFinish,
        bool listen = false}) =>
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
          listenAnywhere: listen,
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

class _HalfTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  const _HalfTile({required this.icon, required this.title, required this.detail, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.wheat, size: 22),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontFamily: readingFont, fontSize: 17, fontWeight: FontWeight.w700, height: 1.4)),
          Text(detail, maxLines: 2, style: TextStyle(color: pal.muted, fontSize: 12.5, height: 1.5)),
        ]),
      ),
    );
  }
}
