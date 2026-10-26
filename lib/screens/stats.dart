import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/user_db.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/arabic.dart';
import '../widgets/brand.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late DateTime month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final progress = s.plan == null ? 0.0 : ((s.position - 1) / s.plan!.endPos).clamp(0.0, 1.0);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          Text('الإحصاءات', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          SectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Label('التقدم في صحيح البخاري'),
              const SizedBox(height: 8),
              Text('${(progress * 100).toStringAsFixed(1)}٪',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(6)),
              const SizedBox(height: 8),
              Text('وصلت إلى الحديث ${s.position.clamp(1, 7563)} من 7563${s.khatmas > 0 ? ' · ختمات: ${s.khatmas}' : ''}',
                  style: TextStyle(color: pal.muted, fontSize: 14)),
            ]),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.9,
            children: [
              _Num(daysWord(s.currentStreak), 'الخط الحالي'),
              _Num(daysWord(s.longestStreak), 'أطول خط'),
              _Num(hadithWord(s.totalRead), 'مجموع ما قرأت'),
              _Num(daysWord(s.daysCompleted), 'أيام أتممت فيها الورد'),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(children: [
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
                ),
                Expanded(
                  child: Text('${monthNames[month.month - 1]} ${month.year}',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)),
                ),
              ]),
              const SizedBox(height: 6),
              _MonthGrid(month: month, logs: s.logs, today: dateOnly(s.clock())),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _Legend(color: AppColors.sage, text: 'أتممت الورد'),
                const SizedBox(width: 14),
                _Legend(color: AppColors.wheat, text: 'يوم عذر'),
                const SizedBox(width: 14),
                _Legend(color: pal.soft, text: 'قرأت بعضه'),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Num extends StatelessWidget {
  final String value;
  final String label;
  const _Num(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        FittedBox(child: Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
        Text(label, style: TextStyle(color: Palette.of(context).muted, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend({required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12)),
      ]);
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final List<WirdLog> logs;
  final DateTime today;
  const _MonthGrid({required this.month, required this.logs, required this.today});

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final byDate = {for (final l in logs) l.date: l};
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    // الأسبوع يبدأ من السبت.
    final lead = (DateTime(month.year, month.month, 1).weekday - DateTime.saturday) % 7;
    const heads = ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'];
    final cells = <Widget>[
      for (final h in heads)
        Center(child: Text(h, style: TextStyle(color: pal.muted, fontSize: 13, fontWeight: FontWeight.w500))),
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var d = 1; d <= days; d++) _day(context, DateTime(month.year, month.month, d), byDate),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: cells,
    );
  }

  Widget _day(BuildContext context, DateTime d, Map<String, WirdLog> byDate) {
    final pal = Palette.of(context);
    final l = byDate[dateKey(d)];
    Color? bg;
    Color fg = Theme.of(context).colorScheme.onSurface;
    if (l != null && l.done) {
      bg = AppColors.sage;
      fg = Colors.white;
    } else if (l != null && l.excused) {
      bg = AppColors.wheat;
      fg = AppColors.ink;
    } else if (l != null && l.readCount > 0) {
      bg = pal.soft;
    }
    final isToday = d == today;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: isToday ? Border.all(color: AppColors.wheat, width: 2) : null,
      ),
      child: Center(child: Text('${d.day}', style: TextStyle(color: fg, fontSize: 14))),
    );
  }
}
