import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'adhkar_tab.dart';
import 'bukhari_index.dart';
import 'library_tab.dart';
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
          const BukhariIndexScreen(),
          const AdhkarTab(),
          const LibraryTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), selectedIcon: Icon(Icons.wb_sunny), label: 'اليوم'),
          NavigationDestination(
              icon: Icon(Icons.auto_stories_outlined), selectedIcon: Icon(Icons.auto_stories), label: 'القرآن'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'البخاري'),
          NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'الأذكار'),
          NavigationDestination(
              icon: Icon(Icons.local_library_outlined), selectedIcon: Icon(Icons.local_library), label: 'المكتبة'),
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
