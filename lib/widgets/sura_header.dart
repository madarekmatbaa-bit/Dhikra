import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// ترويسة السورة كما في المصاحف المطبوعة: لوحة بإطار مزدوج، في وسطها اسم السورة،
/// وعلى جانبيها جامتان مزخرفتان فيهما رقم السورة وعدد آياتها.
class SuraHeader extends StatelessWidget {
  final int number;
  final String name;
  final int ayat;
  final double height;
  final double fontSize;
  const SuraHeader({
    super.key,
    required this.number,
    required this.name,
    required this.ayat,
    this.height = 48,
    this.fontSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final ink = Theme.of(context).colorScheme.onSurface;
    final h = math.max(34.0, height);
    final medal = h * 0.86;
    Widget side(String top, String value) => SizedBox(
      width: medal,
      height: medal,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            top,
            style: TextStyle(fontSize: medal * 0.17, height: 1.1, color: pal.muted),
          ),
          Text(
            value,
            style: TextStyle(fontSize: medal * 0.27, height: 1.1, fontWeight: FontWeight.w700, color: ink),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: SizedBox(
        height: h,
        child: CustomPaint(
          painter: SuraHeaderPainter(fill: pal.soft, line: AppColors.wheat, medal: medal),
          child: Row(
            children: [
              SizedBox(width: h * 0.07),
              side('سورة', '$number'),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'سُورَةُ $name',
                      style: TextStyle(fontFamily: quranFont, fontSize: fontSize, height: 1.3, color: ink),
                    ),
                  ),
                ),
              ),
              side('آياتها', '$ayat'),
              SizedBox(width: h * 0.07),
            ],
          ),
        ),
      ),
    );
  }
}

class SuraHeaderPainter extends CustomPainter {
  final Color fill;
  final Color line;
  final double medal;
  SuraHeaderPainter({required this.fill, required this.line, required this.medal});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final thin = Paint()
      ..color = line.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final solid = Paint()..color = line;

    // اللوحة: مستطيل نهايتاه مقوّستان للداخل كلوحات أسماء السور.
    final band = Rect.fromLTWH(h * 0.5, h * 0.12, w - h, h * 0.76);
    Path tablet(Rect r) {
      final c = r.height * 0.32;
      return Path()
        ..moveTo(r.left + c, r.top)
        ..lineTo(r.right - c, r.top)
        ..quadraticBezierTo(r.right - c * 0.2, r.center.dy, r.right - c, r.bottom)
        ..lineTo(r.left + c, r.bottom)
        ..quadraticBezierTo(r.left + c * 0.2, r.center.dy, r.left + c, r.top)
        ..close();
    }

    canvas.drawPath(tablet(band), Paint()..color = fill);
    canvas.drawPath(tablet(band), stroke);
    canvas.drawPath(tablet(band.deflate(3.5)), thin);

    // جامتان على الطرفين: دائرة يحيط بها نجم ثماني.
    final cy = h / 2;
    final r = medal / 2;
    for (final cx in [h * 0.07 + r, w - h * 0.07 - r]) {
      final c = Offset(cx, cy);
      final star = Path();
      for (var i = 0; i < 16; i++) {
        final a = i * math.pi / 8 - math.pi / 2;
        final rad = i.isEven ? r : r * 0.82;
        final p = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
        i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
      }
      star.close();
      canvas.drawPath(star, Paint()..color = fill);
      canvas.drawPath(star, stroke);
      canvas.drawCircle(c, r * 0.68, thin);
    }

    // نقاط زخرفية بين الجامتين واسم السورة
    for (final x in [h * 0.07 + medal + h * 0.32, w - h * 0.07 - medal - h * 0.32]) {
      final p = Path()
        ..moveTo(x, cy - 4)
        ..lineTo(x + 4, cy)
        ..lineTo(x, cy + 4)
        ..lineTo(x - 4, cy)
        ..close();
      canvas.drawPath(p, solid);
    }
  }

  @override
  bool shouldRepaint(covariant SuraHeaderPainter old) => old.fill != fill || old.line != line || old.medal != medal;
}
