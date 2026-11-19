import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'ornaments.dart';

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
          painter: SuraHeaderPainter(
            fill: pal.soft,
            paper: Theme.of(context).colorScheme.surface,
            line: AppColors.wheat,
            medal: medal,
          ),
          child: Row(
            children: [
              SizedBox(width: h * 0.07),
              side('سورة', '$number'),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: h * 0.62),
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
  final Color paper;
  final Color line;
  final double medal;
  SuraHeaderPainter({required this.fill, required this.paper, required this.line, required this.medal});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final thin = Paint()
      ..color = line.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    final solid = Paint()..color = line;
    final cy = h / 2;
    final r = medal / 2;
    final edge = h * 0.07;

    // الشريط الكامل: لوحة طرفاها مقوّسان، يملؤها نقش هندسي خافت كترويسات المصاحف.
    final band = Rect.fromLTWH(edge + r, h * 0.1, w - 2 * (edge + r), h * 0.8);
    final bandPath = tabletPath(band, cut: 0.3);
    canvas.drawPath(bandPath, Paint()..color = fill);
    canvas.save();
    canvas.clipPath(bandPath);
    paintLattice(canvas, band, line.withValues(alpha: 0.4), cell: math.max(12, h * 0.36), stroke: 0.6);
    canvas.restore();
    canvas.drawPath(bandPath, stroke);
    canvas.drawPath(tabletPath(band.deflate(3), cut: 0.3), thin);

    // لوحة الاسم في الوسط على ورق صاف.
    final name = Rect.fromLTRB(edge + medal + h * 0.42, h * 0.2, w - edge - medal - h * 0.42, h * 0.8);
    if (name.width > 30) {
      final np = tabletPath(name, cut: 0.45);
      canvas.drawPath(np, Paint()..color = paper);
      canvas.drawPath(np, stroke);
      canvas.drawPath(tabletPath(name.deflate(2.6), cut: 0.45), thin);
      canvas.drawPath(diamond(Offset(name.left - 4, cy), 2.6), solid);
      canvas.drawPath(diamond(Offset(name.right + 4, cy), 2.6), solid);
    }

    // جامتان على الطرفين: نجمة ثمانية من مربعين متراكبين، وفي وسطها دائرة.
    for (final cx in [edge + r, w - edge - r]) {
      final c = Offset(cx, cy);
      canvas.drawPath(starOutline(c, r, inner: 0.924), Paint()..color = paper);
      canvas.drawPath(rubStar(c, r), stroke);
      canvas.drawCircle(c, r * 0.7, thin);
    }
  }

  @override
  bool shouldRepaint(covariant SuraHeaderPainter old) =>
      old.fill != fill || old.paper != paper || old.line != line || old.medal != medal;
}
