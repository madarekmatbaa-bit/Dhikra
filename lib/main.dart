import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'screens/onboarding.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/brand.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  runApp(ChangeNotifierProvider.value(value: state, child: const DhikraApp()));
  state.load();
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
