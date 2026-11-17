import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/adhkar_data.dart';
import '../services/prayer.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import 'adhkar_reader.dart';

Future<void> openAdhkar(BuildContext context, AdhkarSet set) async {
  Salah? after;
  if (set == AdhkarSet.prayer) {
    after = await showModalBottomSheet<Salah>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('بعد أي صلاة؟', style: TextStyle(fontFamily: readingFont, fontSize: 18, fontWeight: FontWeight.w700, height: 1.45)),
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

/// سطر مجموعة أذكار، مع علامة الإتمام اليوم.
class AdhkarSetTile extends StatelessWidget {
  final AdhkarSet set;
  final bool done;
  const AdhkarSetTile({super.key, required this.set, required this.done});

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
        SizedBox(width: 30, child: Icon(_icons[set], color: done ? AppColors.sage : AppColors.wheat)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(adhkarTitles[set]!, style: const TextStyle(fontFamily: readingFont, fontSize: 17, fontWeight: FontWeight.w700, height: 1.45)),
            Text(done ? 'أتممتها اليوم' : '$n ذكراً', style: TextStyle(color: pal.muted, fontSize: 13)),
          ]),
        ),
        Icon(done ? Icons.check_circle : Icons.chevron_left, color: done ? AppColors.sage : pal.muted),
      ]),
    );
  }
}

/// ينقل إلى تبويب الصلاة في الشاشة الرئيسية.
void openPrayerTab(BuildContext context) => HomeShellTabs.open?.call(3);

class HomeShellTabs {
  static void Function(int)? open;
}
