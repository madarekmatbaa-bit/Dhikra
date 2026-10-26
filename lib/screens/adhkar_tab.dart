import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/adhkar_data.dart';
import '../services/prayer.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import 'adhkar_reader.dart';
import 'prayer_settings.dart';

class AdhkarTab extends StatelessWidget {
  const AdhkarTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          Row(children: [
            Expanded(child: Text('الأذكار والصلاة', style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
              tooltip: 'إعدادات الصلاة والتذكير',
              icon: const Icon(Icons.tune),
              onPressed: () => openPrayerSettings(context),
            ),
          ]),
          const SizedBox(height: 14),
          const PrayerTimesCard(),
          const SizedBox(height: 16),
          for (final set in AdhkarSet.values) ...[
            _SetTile(set: set, done: set != AdhkarSet.prayer && s.adhkarDone(set)),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

void openPrayerSettings(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PrayerSettingsScreen()));

Future<void> openAdhkar(BuildContext context, AdhkarSet set) async {
  Salah? after;
  if (set == AdhkarSet.prayer) {
    after = await showModalBottomSheet<Salah>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('بعد أي صلاة؟', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          for (final p in fivePrayers)
            ListTile(title: Text('صلاة ${salahNames[p]}'), onTap: () => Navigator.pop(c, p)),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (after == null) return;
  }
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => AdhkarReader(set: set, afterPrayer: after)));
}

class _SetTile extends StatelessWidget {
  final AdhkarSet set;
  final bool done;
  const _SetTile({required this.set, required this.done});

  static const _icons = {
    AdhkarSet.morning: Icons.wb_twilight,
    AdhkarSet.evening: Icons.nights_stay_outlined,
    AdhkarSet.prayer: Icons.mosque_outlined,
    AdhkarSet.sleep: Icons.bedtime_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final pal = Palette.of(context);
    final n = s.adhkar.sets[set]!.length;
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: done ? pal.soft : null,
      onTap: () => openAdhkar(context, set),
      child: Row(children: [
        CircleAvatar(
          backgroundColor: done ? AppColors.sage : pal.soft,
          child: Icon(_icons[set], color: done ? Colors.white : Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(adhkarTitles[set]!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(done ? 'أتممتها اليوم' : '$n ذكراً', style: TextStyle(color: pal.muted, fontSize: 13)),
          ]),
        ),
        Icon(done ? Icons.check_circle : Icons.chevron_left, color: done ? AppColors.sage : pal.muted),
      ]),
    );
  }
}

/// مواقيت اليوم مع الصلاة القادمة.
class PrayerTimesCard extends StatefulWidget {
  final bool compact;
  const PrayerTimesCard({super.key, this.compact = false});

  @override
  State<PrayerTimesCard> createState() => _PrayerTimesCardState();
}

class _PrayerTimesCardState extends State<PrayerTimesCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final cfg = s.prayerConfig;
    if (cfg == null) {
      return SectionCard(
        color: pal.soft,
        onTap: () => openPrayerSettings(context),
        child: const Row(children: [
          Icon(Icons.location_on_outlined, color: AppColors.olive),
          SizedBox(width: 12),
          Expanded(
            child: Text('حدد مدينتك لتظهر مواقيت الصلاة ويصلك التذكير بها، دون إنترنت.',
                style: TextStyle(fontSize: 15)),
          ),
          Icon(Icons.chevron_left),
        ]),
      );
    }
    final now = DateTime.now();
    final times = cfg.timesFor(now);
    final (nextS, nextT) = cfg.next(now);
    final primary = Theme.of(context).colorScheme.primary;
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('الصلاة القادمة: ${salahNames[nextS]}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text('${clock12(nextT)} · ${untilText(nextT.difference(now))}',
                  style: TextStyle(color: pal.muted, fontSize: 14)),
            ]),
          ),
          Row(children: [
            Icon(Icons.location_on_outlined, size: 16, color: pal.muted),
            Text(cfg.place, style: TextStyle(color: pal.muted, fontSize: 13)),
          ]),
        ]),
        if (!widget.compact) ...[
          const SizedBox(height: 14),
          Row(children: [
            for (final p in Salah.values)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: p == nextS ? pal.highlight : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(children: [
                    Text(salahNames[p]!,
                        style: TextStyle(
                            fontSize: 12, color: p == Salah.sunrise ? pal.muted : null, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    FittedBox(
                      child: Text(clock12(times[p]!).replaceAll(' ص', '').replaceAll(' م', ''),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p == nextS ? primary : null)),
                    ),
                  ]),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// ينقل إلى تبويب الأذكار في الشاشة الرئيسية.
void openAdhkarTab(BuildContext context) => HomeShellTabs.open?.call(2);

class HomeShellTabs {
  static void Function(int)? open;
}
