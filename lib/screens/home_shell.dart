import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'adhkar_tab.dart';
import 'benefits.dart';
import 'bukhari_index.dart';
import 'stats.dart';
import 'today.dart';

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
      s.ensureToday();
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
          const BukhariIndexScreen(),
          const AdhkarTab(),
          const BenefitsScreen(),
          const StatsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), selectedIcon: Icon(Icons.wb_sunny), label: 'اليوم'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'البخاري'),
          NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'الأذكار'),
          NavigationDestination(
              icon: Icon(Icons.bookmark_border), selectedIcon: Icon(Icons.bookmark), label: 'الفوائد'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'الإحصاءات'),
        ],
      ),
    );
  }
}
