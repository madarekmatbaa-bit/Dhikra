import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/ornaments.dart';
import 'adhkar_list.dart';
import 'hadith_tab.dart';
import 'library_tab.dart';
import 'prayer_tab.dart';
import 'quran_tab.dart';
import 'today.dart';
import 'benefits.dart';
import 'stats.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int tab = 0;

  /// يُستعمل لفتح تبويب من خارج الشاشة (مثل الضغط على إشعار).
  static _HomeShellState? current;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    current = this;
    HomeShellTabs.open = openTab;
  }

  void openTab(int i) => setState(() => tab = i);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (current == this) current = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // يوم جديد أثناء بقاء التطبيق مفتوحاً في الخلفية.
    if (state == AppLifecycleState.resumed) {
      final s = context.read<AppState>();
      s.newDayCheck();
      s.reschedule().catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: tab,
        children: [
          TodayScreen(onOpenTab: (i) => setState(() => tab = i)),
          const QuranTab(),
          const HadithTab(),
          const PrayerTab(),
          const LibraryTab(),
        ],
      ),
      bottomNavigationBar: _BookNavBar(
        selected: tab,
        onSelect: (i) => setState(() => tab = i),
        items: const [
          (Icons.wb_sunny_outlined, Icons.wb_sunny, 'اليوم'),
          (Icons.auto_stories_outlined, Icons.auto_stories, 'المصحف'),
          (Icons.menu_book_outlined, Icons.menu_book, 'الحديث'),
          (Icons.mosque_outlined, Icons.mosque, 'الصلاة'),
          (Icons.local_library_outlined, Icons.local_library, 'المكتبة'),
        ],
      ),
    );
  }
}

/// تفتح الفوائد والإحصاءات صفحةً مستقلة بعد أن خرجتا من الشريط السفلي.
void openBenefitsPage(BuildContext context, {String? source}) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(), body: BenefitsScreen(source: source))));

void openStatsPage(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(), body: const StatsScreen())));

/// الشريط السفلي: حاشية زخرفية رفيعة في أعلاه، والتبويب المختار تحته نجمة ذهبية صغيرة.
class _BookNavBar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  final List<(IconData, IconData, String)> items;
  const _BookNavBar({required this.selected, required this.onSelect, required this.items});

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 7,
            width: double.infinity,
            child: CustomPaint(painter: BorderBandPainter(AppColors.wheat.withValues(alpha: 0.55))),
          ),
          SizedBox(
            height: 62,
            child: Row(children: [
              for (final (i, (icon, on, label)) in items.indexed)
                Expanded(
                  child: Semantics(
                    selected: i == selected,
                    button: true,
                    child: InkResponse(
                      onTap: () => onSelect(i),
                      radius: 36,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(i == selected ? on : icon, size: 23, color: i == selected ? scheme.primary : pal.muted),
                        const SizedBox(height: 3),
                        Text(label,
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.2,
                                fontWeight: i == selected ? FontWeight.w700 : FontWeight.w400,
                                color: i == selected ? scheme.primary : pal.muted)),
                        const SizedBox(height: 3),
                        Opacity(opacity: i == selected ? 1 : 0, child: const Fleuron(size: 7)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
