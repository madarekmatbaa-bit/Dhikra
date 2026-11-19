import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/prayer.dart';
import '../services/qibla.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/ornaments.dart';
import 'prayer_settings.dart';

void openPrayerSettings(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PrayerSettingsScreen()));

/// تبويب الصلاة: مواقيت اليوم كاملة، ورابط صفحة القبلة.
class PrayerTab extends StatelessWidget {
  const PrayerTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cfg = s.prayerConfig;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Headpiece(
            title: 'الصلاة',
            actions: [
              HeadAction(Icons.tune, 'المدينة وطريقة الحساب والتنبيهات', () => openPrayerSettings(context)),
            ],
          ),
          const SizedBox(height: 14),
          if (cfg == null) const PrayerTimesCard() else ...[
            _TimesTable(cfg: cfg),
            const SizedBox(height: 16),
            _QiblaLink(cfg: cfg),
          ],
        ],
      ),
    );
  }
}

/// مواقيت اليوم مختصرة، للصفحة الرئيسية: الصلاة القادمة ثم صف المواقيت.
class PrayerTimesCard extends StatefulWidget {
  final VoidCallback? onTap;
  const PrayerTimesCard({super.key, this.onTap});

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
            child: Text('حدد مدينتك لتظهر مواقيت الصلاة والقبلة ويصلك التذكير بها، دون إنترنت.',
                style: TextStyle(fontSize: 15)),
          ),
          Icon(Icons.chevron_left),
        ]),
      );
    }
    final now = DateTime.now();
    final times = cfg.timesFor(now);
    final (nextS, nextT) = cfg.next(now);
    return SectionCard(
      onTap: widget.onTap,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(salahNames[nextS]!,
              style: const TextStyle(fontFamily: readingFont, fontSize: 20, fontWeight: FontWeight.w700, height: 1.3)),
          const SizedBox(width: 8),
          Text(clock12(nextT), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(untilText(nextT.difference(now)), style: TextStyle(color: pal.muted, fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        Divider(height: 1, color: pal.line),
        const SizedBox(height: 8),
        Row(children: [
          for (final p in Salah.values)
            Expanded(
              child: Column(children: [
                Text(salahNames[p]!,
                    style: TextStyle(fontSize: 11.5, color: p == nextS ? AppColors.olive : pal.muted,
                        fontWeight: p == nextS ? FontWeight.w700 : FontWeight.w400)),
                FittedBox(
                  child: Text(clock12(times[p]!).replaceAll(' ص', '').replaceAll(' م', ''),
                      style: TextStyle(fontSize: 14, fontWeight: p == nextS ? FontWeight.w700 : FontWeight.w500,
                          color: p == Salah.sunrise ? pal.muted : null)),
                ),
              ]),
            ),
        ]),
      ]),
    );
  }
}

class _TimesTable extends StatefulWidget {
  final PrayerConfig cfg;
  const _TimesTable({required this.cfg});

  @override
  State<_TimesTable> createState() => _TimesTableState();
}

class _TimesTableState extends State<_TimesTable> {
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
    final cfg = widget.cfg;
    final now = DateTime.now();
    final times = cfg.timesFor(now);
    final (nextS, nextT) = cfg.next(now);
    final alerts = s.prayerAlerts;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // الصلاة القادمة داخل محراب: قوس مدبّب بإطارين.
      CustomPaint(
        painter: MihrabPainter(
          line: AppColors.wheat,
          fill: Theme.of(context).colorScheme.surface,
          pattern: AppColors.wheat.withValues(alpha: 0.32),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 70, 28, 26),
          child: Column(children: [
            Text('الصلاة القادمة', style: TextStyle(color: pal.muted, fontSize: 13)),
            Text(salahNames[nextS]!,
                style: const TextStyle(fontFamily: readingFont, fontSize: 38, fontWeight: FontWeight.w700, height: 1.35)),
            Text(clock12(nextT), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, height: 1.3)),
            const SizedBox(height: 10),
            const SizedBox(width: 120, child: DoubleRule()),
            const SizedBox(height: 8),
            Text('${untilText(nextT.difference(now))} · ${cfg.place}', style: TextStyle(color: pal.muted, fontSize: 14)),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      SectionCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (final p in Salah.values) ...[
            if (p != Salah.fajr) Divider(height: 1, indent: 16, endIndent: 16, color: pal.line),
            Container(
              decoration: p == nextS
                  ? BoxDecoration(
                      color: pal.highlight.withValues(alpha: 0.6),
                      border: const BorderDirectional(start: BorderSide(color: AppColors.wheat, width: 3)),
                    )
                  : null,
              padding: const EdgeInsets.fromLTRB(16, 11, 8, 11),
              child: Row(children: [
                Expanded(
                  child: Text(salahNames[p]!,
                      style: TextStyle(
                          fontFamily: readingFont,
                          fontSize: 18,
                          fontWeight: p == nextS ? FontWeight.w700 : FontWeight.w400,
                          color: p == Salah.sunrise ? pal.muted : null)),
                ),
                Text(clock12(times[p]!),
                    style: TextStyle(fontSize: 16, fontWeight: p == nextS ? FontWeight.w700 : FontWeight.w500)),
                SizedBox(
                  width: 44,
                  child: p == Salah.sunrise
                      ? null
                      : IconButton(
                          tooltip: alerts.contains(p) ? 'إيقاف التنبيه' : 'تشغيل التنبيه',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(alerts.contains(p) ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                              size: 20, color: alerts.contains(p) ? AppColors.sage : pal.muted),
                          onPressed: () => s.setPrayerAlert(p, !alerts.contains(p)),
                        ),
                ),
              ]),
            ),
          ],
        ]),
      ),
    ]);
  }
}

/// رابط القبلة في تبويب الصلاة. البوصلة لا تعمل إلا في صفحتها، فلا تستهلك البطارية.
class _QiblaLink extends StatelessWidget {
  final PrayerConfig cfg;
  const _QiblaLink({required this.cfg});

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final b = qiblaBearing(cfg.lat, cfg.lng);
    final km = distanceToKaaba(cfg.lat, cfg.lng);
    return SectionCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QiblaScreen(cfg: cfg))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        const SizedBox(width: 30, child: Icon(Icons.explore_outlined, color: AppColors.wheat)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('القبلة', style: TextStyle(fontFamily: readingFont, fontSize: 17, fontWeight: FontWeight.w700, height: 1.45)),
            Text('${b.round()}° من الشمال · ${km.round()} كم إلى مكة', style: TextStyle(color: pal.muted, fontSize: 13)),
          ]),
        ),
        Icon(Icons.chevron_left, color: pal.muted),
      ]),
    );
  }
}

/// صفحة القبلة: تشغّل البوصلة حين تُفتح، وتوقفها حين تُغلق أو يذهب التطبيق إلى الخلفية.
class QiblaScreen extends StatelessWidget {
  final PrayerConfig cfg;
  const QiblaScreen({super.key, required this.cfg});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('القبلة')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [_QiblaCard(cfg: cfg)],
        ),
      );
}

class _QiblaCard extends StatefulWidget {
  final PrayerConfig cfg;
  const _QiblaCard({required this.cfg});

  @override
  State<_QiblaCard> createState() => _QiblaCardState();
}

class _QiblaCardState extends State<_QiblaCard> with WidgetsBindingObserver {
  final _compass = Compass();
  StreamSubscription<double>? _sub;
  double? heading;
  bool _aligned = false;
  bool _noSensor = false;
  Timer? _sensorCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _compass.start();
    _sub = _compass.headings.listen((h) {
      if (!mounted) return;
      final diff = _diff(h);
      final aligned = diff.abs() < 4;
      if (aligned && !_aligned) HapticFeedback.mediumImpact();
      setState(() {
        heading = h;
        _aligned = aligned;
      });
    });
    _sensorCheck = Timer(const Duration(seconds: 3), () {
      if (mounted && heading == null) setState(() => _noSensor = true);
    });
  }

  double get bearing => qiblaBearing(widget.cfg.lat, widget.cfg.lng);

  /// كم يلزم أن يدور الهاتف ليتجه أعلاه إلى القبلة (موجب = يميناً).
  double _diff(double h) => ((bearing - h + 540) % 360) - 180;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _compass.start();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _compass.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sensorCheck?.cancel();
    _sub?.cancel();
    _compass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final b = bearing;
    final km = distanceToKaaba(widget.cfg.lat, widget.cfg.lng);
    final h = heading;
    String hint;
    if (h == null) {
      hint = _noSensor ? 'لا توجد بوصلة في هذا الهاتف. القبلة ${b.round()}° من الشمال.' : 'ضع الهاتف مسطحاً…';
    } else if (_aligned) {
      hint = 'أنت متجه إلى القبلة';
    } else {
      final d = _diff(h);
      hint = d > 0 ? 'استدر يميناً ${d.abs().round()}°' : 'استدر يساراً ${d.abs().round()}°';
    }
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('القبلة', style: TextStyle(fontFamily: readingFont, fontSize: 20, fontWeight: FontWeight.w700, height: 1.4)),
          ),
          Text('${b.round()}° من الشمال · ${km.round()} كم', style: TextStyle(color: pal.muted, fontSize: 13)),
        ]),
        const SizedBox(height: 12),
        Center(
          child: SizedBox.square(
            dimension: 250,
            child: CustomPaint(
              painter: _DialPainter(
                heading: h ?? 0,
                qibla: b,
                live: h != null,
                aligned: _aligned,
                ink: Theme.of(context).colorScheme.onSurface,
                muted: pal.muted,
                line: pal.line,
                face: pal.soft,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(hint,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: _aligned ? AppColors.olive : null)),
        ),
        const SizedBox(height: 6),
        Text(
          _compass.disturbed
              ? 'القراءة مضطربة: ابتعد عن الحديد والمغناطيس والشاحن، وحرّك الهاتف على شكل الرقم 8.'
              : 'أمسك الهاتف مسطحاً بعيداً عن الحديد. إن اضطربت البوصلة فحرّك الهاتف على شكل الرقم 8.',
          style: TextStyle(color: _compass.disturbed ? mistakeTint : pal.muted, fontSize: 12.5, height: 1.5),
        ),
      ]),
    );
  }
}

const mistakeTint = Color(0xFFB3261E);

/// قرص البوصلة: يدور مع الهاتف فيبقى الشمال شمالاً، وعليه علامة الكعبة.
/// السهم الثابت أعلى القرص هو اتجاه الهاتف.
class _DialPainter extends CustomPainter {
  final double heading, qibla;
  final bool live, aligned;
  final Color ink, muted, line, face;
  _DialPainter({
    required this.heading,
    required this.qibla,
    required this.live,
    required this.aligned,
    required this.ink,
    required this.muted,
    required this.line,
    required this.face,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 14;
    canvas.drawCircle(c, r, Paint()..color = face);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = line);

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-heading * pi / 180);
    // تدريجات كل 10 درجات، وأطول كل 30.
    for (var d = 0; d < 360; d += 10) {
      final a = d * pi / 180;
      final long = d % 30 == 0;
      final p1 = Offset(sin(a), -cos(a)) * (r - (long ? 12 : 7));
      final p2 = Offset(sin(a), -cos(a)) * (r - 2);
      canvas.drawLine(p1, p2, Paint()
        ..color = long ? muted : line
        ..strokeWidth = long ? 1.6 : 1);
    }
    const labels = {0: 'ش', 90: 'شر', 180: 'ج', 270: 'غ'};
    for (final e in labels.entries) {
      final a = e.key * pi / 180;
      final tp = TextPainter(
        text: TextSpan(
            text: e.value,
            style: TextStyle(
                fontFamily: 'Readex', fontSize: 13, fontWeight: FontWeight.w700, color: e.key == 0 ? mistakeTint : muted)),
        textDirection: TextDirection.rtl,
      )..layout();
      final pos = Offset(sin(a), -cos(a)) * (r - 26);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(heading * pi / 180); // تبقى الحروف قائمة
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    // خط القبلة وعلامة الكعبة.
    final qa = qibla * pi / 180;
    final dir = Offset(sin(qa), -cos(qa));
    final color = aligned ? AppColors.olive : AppColors.wheat;
    canvas.drawLine(Offset.zero, dir * (r - 44), Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
    final k = dir * (r - 44);
    canvas.save();
    canvas.translate(k.dx, k.dy);
    canvas.rotate(heading * pi / 180);
    final cube = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 22, height: 22), const Radius.circular(3));
    canvas.drawRRect(cube, Paint()..color = const Color(0xFF1F1E1A));
    canvas.drawRect(Rect.fromLTWH(-11, -5, 22, 3.5), Paint()..color = AppColors.wheat);
    canvas.restore();
    canvas.restore();

    canvas.drawCircle(c, 5, Paint()..color = live ? ink : muted);
    // مؤشر اتجاه الهاتف (ثابت في الأعلى).
    final tri = Path()
      ..moveTo(c.dx, c.dy - r - 12)
      ..lineTo(c.dx - 9, c.dy - r + 4)
      ..lineTo(c.dx + 9, c.dy - r + 4)
      ..close();
    canvas.drawPath(tri, Paint()..color = aligned ? AppColors.olive : ink);
  }

  @override
  bool shouldRepaint(covariant _DialPainter o) =>
      o.heading != heading || o.qibla != qibla || o.aligned != aligned || o.live != live || o.face != face;
}
