import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/adhkar_data.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/arabic.dart';
import '../widgets/brand.dart';
import '../widgets/ornaments.dart';
import 'adhkar_list.dart';
import 'book_reader.dart';
import 'prayer_tab.dart';
import 'benefit_edit.dart';
import 'home_shell.dart';
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
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          // التاريخ في سرلوح الصفحة، كعنوان صفحة في مصحف أو كتاب مطبوع.
          Headpiece(
            title: hijriLong(now),
            subtitle: gregorianLong(now),
            actions: [
              HeadAction(Icons.bookmark_border, 'دفتر الفوائد', () => openBenefitsPage(context)),
              HeadAction(Icons.settings_outlined, 'الإعدادات',
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
            ],
          ),
          const SizedBox(height: 18),
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
            const SizedBox(height: 16),
          ],
          SectionHead('وِرد اليوم', trailing: _doneSummary(s)),
          const _Ledger(),
          const SizedBox(height: 22),
          SectionHead('الصلاة', onMore: () => onOpenTab(3), more: 'المواقيت والقبلة'),
          PrayerTimesCard(onTap: () => onOpenTab(3)),
          const SizedBox(height: 22),
          const SectionHead('الأذكار'),
          const _AdhkarRow(),
          const SizedBox(height: 22),
          _BenefitOfDay(onOpenTab: onOpenTab),
        ],
      ),
    );
  }

  static String? _doneSummary(AppState s) {
    var total = 0, done = 0;
    if (s.quran.enabled && s.quran.today != null && !s.quran.today!.isEmpty) {
      total++;
      if (s.quran.today!.done) done++;
    }
    if (!s.finished) {
      total++;
      if (s.todayLog?.done ?? false) done++;
    }
    for (final b in s.library.books.where((b) => !b.finished)) {
      total++;
      if (s.library.todayOf(b.id)?.done ?? false) done++;
    }
    if (total == 0) return null;
    return done == total ? 'تمّ كله، تقبّل الله' : '$done من $total';
  }
}

/// أوراد اليوم سطوراً في ورقة واحدة: القرآن، ثم الحديث، ثم كتب المكتبة.
class _Ledger extends StatelessWidget {
  const _Ledger();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final rows = <Widget>[];

    // القرآن
    final q = s.quran;
    final qt = q.today;
    if (!q.enabled || qt == null || qt.isEmpty) {
      rows.add(_LedgerRow(
        title: 'القرآن',
        detail: 'حدّد ورداً يومياً: 10 أو 20 أو 30 صفحة',
        read: 0,
        total: 0,
        done: false,
        onTap: () => openQuranSetup(context),
        action: 'حدّد',
      ));
    } else {
      final a = s.quranDb.suraOfPage(qt.pages.first).name, b = s.quranDb.suraOfPage(qt.pages.last).name;
      rows.add(_LedgerRow(
        title: 'القرآن',
        detail: 'ص ${qt.pages.first}–${qt.pages.last} · ${a == b ? a : '$a إلى $b'}',
        read: qt.readCount,
        total: qt.pages.length,
        done: qt.done,
        onTap: () => openQuranWird(context),
        onCheck: () => q.markDone(!qt.done),
      ));
    }

    // الحديث
    final title = s.hadith.current.title;
    if (s.finished) {
      final next = s.nextCollection;
      rows.add(_LedgerRow(
        title: title,
        detail: next == null ? 'ختمت الكتب الستة، الحمد لله' : 'ختمته، الحمد لله. التالي: ${next.title}',
        read: 1,
        total: 1,
        done: true,
        action: next == null ? 'من جديد' : 'ابدأ',
        onTap: () => next == null ? s.newKhatma() : s.switchCollection(next.id, carryOver: true),
      ));
    } else {
      final log = s.todayLog;
      final target = log?.target ?? s.plan!.perDay;
      final read = (log?.readCount ?? 0).clamp(0, target);
      final from = log?.fromPos ?? s.position;
      final to = log?.toPos ?? s.position + target - 1;
      rows.add(_LedgerRow(
        title: title,
        detail: 'الحديث $from–$to · كتاب ${s.hadith.bookOf(s.position).title}',
        read: read,
        total: target,
        done: log?.done ?? false,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderScreen(start: s.position, wirdMode: true))),
      ));
    }

    // الكتب
    for (final b in s.library.books.where((b) => !b.finished)) {
      final t = s.library.todayOf(b.id);
      final target = t?.target ?? b.perDay;
      rows.add(_LedgerRow(
        title: b.title,
        detail: t == null ? '$target صفحات' : 'ص ${t.fromPos}–${t.toPos}',
        read: (t?.readCount ?? 0).clamp(0, target),
        total: target,
        done: t?.done ?? false,
        onTap: b.fileExists
            ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookReader(book: b)))
            : () => onOpenLibrary(context),
      ));
    }

    return Card(
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 62, endIndent: 14, color: pal.line),
          rows[i],
        ],
      ]),
    );
  }

  static void onOpenLibrary(BuildContext context) => HomeShellTabs.open?.call(4);
}

/// سطر ورد: حلقة تمتلئ بقدر ما قرأ، والعنوان بخط النسخ، والتفصيل تحته.
class _LedgerRow extends StatelessWidget {
  final String title;
  final String detail;
  final int read;
  final int total;
  final bool done;
  final VoidCallback onTap;
  final VoidCallback? onCheck;
  final String? action;
  const _LedgerRow({
    required this.title,
    required this.detail,
    required this.read,
    required this.total,
    required this.done,
    required this.onTap,
    this.onCheck,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final ring = GestureDetector(
      onTap: onCheck,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox.square(
          dimension: 30,
          child: CustomPaint(
            painter: _RingPainter(
              value: done ? 1 : (total == 0 ? 0 : read / total),
              done: done,
              track: pal.line,
              empty: total == 0,
            ),
          ),
        ),
      ),
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        child: Row(children: [
          ring,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: readingFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: done ? pal.muted : null,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: pal.muted)),
              Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 8),
          if (action != null)
            Text(action!, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 14, fontWeight: FontWeight.w700))
          else if (!done)
            Text('$read/$total', style: TextStyle(color: pal.muted, fontSize: 14, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final bool done;
  final bool empty;
  final Color track;
  _RingPainter({required this.value, required this.done, required this.track, required this.empty});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2;
    if (done) {
      canvas.drawCircle(c, r + 1, Paint()..color = AppColors.sage);
      final p = Path()
        ..moveTo(c.dx - r * 0.42, c.dy + r * 0.02)
        ..lineTo(c.dx - r * 0.1, c.dy + r * 0.34)
        ..lineTo(c.dx + r * 0.45, c.dy - r * 0.32);
      canvas.drawPath(p, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
      return;
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = track;
    canvas.drawCircle(c, r, stroke);
    if (empty) {
      final plus = Paint()
        ..color = AppColors.wheat
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(c.dx - r * 0.4, c.dy), Offset(c.dx + r * 0.4, c.dy), plus);
      canvas.drawLine(Offset(c.dx, c.dy - r * 0.4), Offset(c.dx, c.dy + r * 0.4), plus);
      return;
    }
    if (value > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -pi / 2, 2 * pi * value.clamp(0, 1), false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..color = AppColors.wheat);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.value != value || o.done != done || o.track != track || o.empty != empty;
}

class _BenefitOfDay extends StatelessWidget {
  final ValueChanged<int> onOpenTab;
  const _BenefitOfDay({required this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final b = s.benefitOfTheDay;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHead('من دفترك', onMore: () => openBenefitsPage(context), more: 'كل الفوائد'),
      InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => b == null ? const BenefitEditScreen() : BenefitEditScreen(benefit: b))),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
          decoration: const BoxDecoration(border: BorderDirectional(start: BorderSide(color: AppColors.wheat, width: 3))),
          child: b == null
              ? Text('ما يستوقفك أثناء القراءة احفظه هنا: حدّد الجملة واضغط «فائدة».',
                  style: TextStyle(color: pal.muted, fontSize: 15, height: 1.7))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (b.title.isNotEmpty)
                    Text(b.title, style: const TextStyle(fontFamily: readingFont, fontSize: 17, fontWeight: FontWeight.w700, height: 1.5)),
                  Text(b.body,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: readingFont, fontSize: 17, height: 1.8)),
                  const SizedBox(height: 4),
                  Text(b.sourceLabel, style: TextStyle(color: pal.muted, fontSize: 12.5)),
                ]),
        ),
      ),
    ]);
  }
}

class _AdhkarRow extends StatelessWidget {
  const _AdhkarRow();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    Widget cell(AdhkarSet set, String label) {
      final done = set != AdhkarSet.prayer && s.adhkarDone(set);
      return Expanded(
        child: InkWell(
          onTap: () => openAdhkar(context, set),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(children: [
              _DoneStar(done: done),
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
          cell(AdhkarSet.morning, 'الصباح'),
          VerticalDivider(width: 1, color: pal.line),
          cell(AdhkarSet.evening, 'المساء'),
          VerticalDivider(width: 1, color: pal.line),
          cell(AdhkarSet.prayer, 'بعد الصلاة'),
          VerticalDivider(width: 1, color: pal.line),
          cell(AdhkarSet.sleep, 'النوم'),
        ]),
      ),
    );
  }
}

/// نجمة ثمانية: مفرغة قبل الذكر، وممتلئة بعلامة صح بعده.
class _DoneStar extends StatelessWidget {
  final bool done;
  const _DoneStar({required this.done});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 24,
      child: Stack(alignment: Alignment.center, children: [
        Fleuron(size: 24, filled: done, color: done ? AppColors.sage : AppColors.wheat),
        if (done) const Icon(Icons.check, size: 13, color: Colors.white),
      ]),
    );
  }
}
