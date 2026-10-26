import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';

import 'db/adhkar_data.dart';
import 'screens/adhkar_reader.dart';
import 'screens/adhkar_tab.dart';
import 'screens/home_shell.dart';
import 'screens/reader.dart';
import 'services/notifications.dart';
import 'screens/onboarding.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/brand.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  runApp(ChangeNotifierProvider.value(value: state, child: const DhikraApp()));
  Reminders.onOpen = (p) => _openFromNotification(state, p);
  state.load().then((_) async {
    final p = await Reminders.launchPayload();
    if (p != null) _openFromNotification(state, p);
    final w = await HomeWidget.initiallyLaunchedFromHomeWidget();
    if (w != null) _openFromNotification(state, w.host);
  });
  HomeWidget.widgetClicked.listen((uri) {
    if (uri != null) _openFromNotification(state, uri.host);
  });
}

final navigatorKey = GlobalKey<NavigatorState>();

/// يفتح الشاشة المناسبة عند الضغط على إشعار.
void _openFromNotification(AppState state, String payload) {
  final nav = navigatorKey.currentState;
  if (nav == null || !state.ready || state.plan == null) return;
  final set = switch (payload) {
    'morning' => AdhkarSet.morning,
    'evening' => AdhkarSet.evening,
    'sleep' => AdhkarSet.sleep,
    _ => null,
  };
  if (set != null) {
    nav.push(MaterialPageRoute(builder: (_) => AdhkarReader(set: set)));
  } else if (payload == 'wird') {
    nav.push(MaterialPageRoute(builder: (_) => ReaderScreen(start: state.position, wirdMode: true)));
  } else if (payload == 'benefits') {
    nav.popUntil((r) => r.isFirst);
    HomeShellTabs.open?.call(3);
  } else if (payload == 'prayer') {
    final ctx = navigatorKey.currentContext;
    if (ctx != null) openAdhkarTab(ctx);
  }
}

class DhikraApp extends StatelessWidget {
  const DhikraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final dark = s.themeMode == ThemeMode.dark;
    SystemChrome.setSystemUIOverlayStyle(dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);
    return MaterialApp(
      title: 'ذِكرى',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: s.themeMode,
      home: !s.ready
          ? const _Splash()
          : s.plan == null
              ? const OnboardingScreen()
              : const HomeShell(),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: BrandMark(size: 72)));
  }
}
