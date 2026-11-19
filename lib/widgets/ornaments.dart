import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// زخارف ذِكرى المرسومة باليد بالكود: مستوحاة من سرلوحات المصاحف وإطارات الكتب المطبوعة،
/// بخطوط ذهبية رفيعة على ورق عاجي، بلا صور ولا ظلال.

/// نجمة ثمانية من مربعين متراكبين، كعلامة الحزب ۞ في المصاحف.
Path rubStar(Offset c, double r) {
  final p = Path();
  for (final rot in [0.0, math.pi / 4]) {
    for (var i = 0; i < 4; i++) {
      final a = rot + i * math.pi / 2 - math.pi / 4;
      final q = c + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
    }
    p.close();
  }
  return p;
}

/// محيط النجمة الثمانية (شكل واحد مغلق) للتعبئة.
Path starOutline(Offset c, double r, {int points = 8, double inner = 0.76}) {
  final p = Path();
  for (var i = 0; i < points * 2; i++) {
    final a = i * math.pi / points - math.pi / 2;
    final rad = i.isEven ? r : r * inner;
    final q = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
    i == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
  }
  return p..close();
}

Path diamond(Offset c, double r) => Path()
  ..moveTo(c.dx, c.dy - r)
  ..lineTo(c.dx + r, c.dy)
  ..lineTo(c.dx, c.dy + r)
  ..lineTo(c.dx - r, c.dy)
  ..close();

/// لوحة مستطيلة طرفاها مقوّسان للداخل، كلوحات أسماء السور.
Path tabletPath(Rect r, {double cut = 0.32}) {
  final c = r.height * cut;
  return Path()
    ..moveTo(r.left + c, r.top)
    ..lineTo(r.right - c, r.top)
    ..quadraticBezierTo(r.right - c * 0.15, r.center.dy, r.right - c, r.bottom)
    ..lineTo(r.left + c, r.bottom)
    ..quadraticBezierTo(r.left + c * 0.15, r.center.dy, r.left + c, r.top)
    ..close();
}

/// نقش هندسي متكرر (نجوم ثمانية وصلبان بينها) يملأ مساحة، بلون خافت.
void paintLattice(Canvas canvas, Rect area, Color color, {double cell = 18, double stroke = 0.7}) {
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke;
  canvas.save();
  canvas.clipRect(area);
  final cols = (area.width / cell).ceil() + 2;
  final rows = (area.height / cell).ceil() + 2;
  final ox = area.center.dx - (cols / 2).floor() * cell;
  final oy = area.center.dy - (rows / 2).floor() * cell;
  for (var i = 0; i < cols; i++) {
    for (var j = 0; j < rows; j++) {
      final c = Offset(ox + i * cell, oy + j * cell);
      canvas.drawPath(rubStar(c, cell * 0.36), paint);
      canvas.drawPath(diamond(c + Offset(cell / 2, cell / 2), cell * 0.16), paint);
    }
  }
  canvas.restore();
}

/// نجمة صغيرة تسبق العناوين، كعلامات الفصول في الكتب.
class Fleuron extends StatelessWidget {
  final double size;
  final Color? color;
  final bool filled;
  const Fleuron({super.key, this.size = 11, this.color, this.filled = true});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _FleuronPainter(color ?? AppColors.wheat, filled)),
      );
}

class _FleuronPainter extends CustomPainter {
  final Color color;
  final bool filled;
  _FleuronPainter(this.color, this.filled);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    if (filled) {
      canvas.drawPath(starOutline(c, r, inner: 0.72), Paint()..color = color);
    } else {
      canvas.drawPath(
          rubStar(c, r * 0.92),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, size.width / 18));
    }
  }

  @override
  bool shouldRepaint(covariant _FleuronPainter o) => o.color != color || o.filled != filled;
}

/// رقم داخل نجمة ثمانية مزخرفة، كأرقام الفهارس في المصاحف.
class Rosette extends StatelessWidget {
  final String text;
  final double size;
  final bool active;
  const Rosette(this.text, {super.key, this.size = 34, this.active = false});

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RosettePainter(
          line: AppColors.wheat,
          fill: active ? pal.highlight : scheme.surface,
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: size * (text.length > 2 ? 0.27 : 0.33),
              fontWeight: FontWeight.w700,
              height: 1,
              color: active ? scheme.primary : pal.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _RosettePainter extends CustomPainter {
  final Color line;
  final Color fill;
  _RosettePainter({required this.line, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 1;
    final star = rubStar(c, r);
    canvas.drawPath(starOutline(c, r, inner: 0.924), Paint()..color = fill);
    canvas.drawPath(
        star,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..strokeJoin = StrokeJoin.miter);
    canvas.drawCircle(
        c,
        r * 0.7,
        Paint()
          ..color = line.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7);
  }

  @override
  bool shouldRepaint(covariant _RosettePainter o) => o.line != line || o.fill != fill;
}

/// سرلوح الصفحة: شريط مزخرف بنقش هندسي، في وسطه لوحة فيها العنوان،
/// وعلى طرفيه جامتان تحملان أزرار الصفحة. يُستعمل رأساً لكل تبويب.
class Headpiece extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<HeadAction> actions;
  final VoidCallback? onTitleTap;
  final bool titleDropdown;
  const Headpiece({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onTitleTap,
    this.titleDropdown = false,
  });

  static const height = 76.0;

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final start = actions.isNotEmpty ? actions.first : null;
    final end = actions.length > 1 ? actions[1] : null;
    Widget medal(HeadAction? a) => SizedBox.square(
          dimension: 48,
          child: a == null
              ? const Center(child: Fleuron(size: 12))
              : IconButton(
                  tooltip: a.tooltip,
                  onPressed: a.onTap,
                  icon: Icon(a.icon, size: 21, color: scheme.primary),
                ),
        );
    final titleText = Text(
      title,
      maxLines: 1,
      style: TextStyle(fontFamily: readingFont, fontSize: 23, fontWeight: FontWeight.w700, height: 1.25, color: scheme.onSurface),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: height,
        child: CustomPaint(
          painter: HeadpiecePainter(
            line: AppColors.wheat,
            fill: scheme.surface,
            band: pal.soft,
            pattern: AppColors.wheat.withValues(alpha: 0.38),
          ),
          child: Row(children: [
            const SizedBox(width: 6),
            medal(start),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: InkWell(
                  onTap: onTitleTap,
                  borderRadius: BorderRadius.circular(20),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        titleText,
                        if (titleDropdown) Icon(Icons.expand_more, size: 20, color: pal.muted),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            medal(end),
            const SizedBox(width: 6),
          ]),
        ),
      ),
      if (subtitle != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: pal.muted, fontSize: 13.5)),
        ),
    ]);
  }
}

class HeadAction {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const HeadAction(this.icon, this.tooltip, this.onTap);
}

class HeadpiecePainter extends CustomPainter {
  final Color line;
  final Color fill;
  final Color band;
  final Color pattern;
  HeadpiecePainter({required this.line, required this.fill, required this.band, required this.pattern});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final thick = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final thin = Paint()
      ..color = line.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;

    // الشريط: إطار مزدوج يملؤه نقش هندسي خافت.
    final outer = Rect.fromLTWH(0.7, 0.7, w - 1.4, h - 1.4);
    final inner = outer.deflate(4);
    canvas.drawRect(outer, Paint()..color = band);
    paintLattice(canvas, inner, pattern, cell: 17);
    canvas.drawRect(outer, thick);
    canvas.drawRect(inner, thin);

    // جامتان على الطرفين.
    final mr = 24.0;
    for (final cx in [6 + mr, w - 6 - mr]) {
      final c = Offset(cx, h / 2);
      final star = starOutline(c, mr, points: 8, inner: 0.84);
      canvas.drawPath(star, Paint()..color = fill);
      canvas.drawPath(star, thick);
      canvas.drawCircle(c, mr * 0.74, thin);
    }

    // اللوحة الوسطى للعنوان، بإطارين.
    final tab = Rect.fromLTRB(6 + mr * 2 + 10, h * 0.17, w - 6 - mr * 2 - 10, h * 0.83);
    if (tab.width > 40) {
      final path = tabletPath(tab, cut: 0.42);
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(path, thick);
      canvas.drawPath(tabletPath(tab.deflate(3.2), cut: 0.42), thin);
      // نقطتان ذهبيتان عند طرفي اللوحة.
      final dot = Paint()..color = line;
      canvas.drawPath(diamond(Offset(tab.left - 5, h / 2), 3), dot);
      canvas.drawPath(diamond(Offset(tab.right + 5, h / 2), 3), dot);
    }
  }

  @override
  bool shouldRepaint(covariant HeadpiecePainter o) =>
      o.line != line || o.fill != fill || o.band != band || o.pattern != pattern;
}

/// عنوان قسم: نجمة صغيرة، ثم العنوان بخط النسخ، ثم خطان رفيعان كفواصل الكتب.
class SectionHead extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onMore;
  final String? more;
  const SectionHead(this.title, {super.key, this.trailing, this.onMore, this.more});

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        const Fleuron(size: 11),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontFamily: readingFont, fontSize: 19, fontWeight: FontWeight.w700, height: 1.3)),
        const SizedBox(width: 10),
        const Expanded(child: DoubleRule()),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Text(trailing!, style: TextStyle(color: pal.muted, fontSize: 13)),
        ],
        if (onMore != null)
          InkWell(
            onTap: onMore,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 10, top: 4, bottom: 4),
              child: Text(more ?? 'المزيد',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ),
      ]),
    );
  }
}

/// خطان رفيعان متوازيان: الأعلى ذهبي، والأسفل بلون الخطوط.
class DoubleRule extends StatelessWidget {
  const DoubleRule({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(height: 1, color: AppColors.wheat.withValues(alpha: 0.7)),
      const SizedBox(height: 2),
      Container(height: 1, color: pal.line),
    ]);
  }
}

/// حدّ البطاقات: خط خارجي، وخط ذهبي داخلي رفيع، ومعيّنات صغيرة في الزوايا،
/// كإطار صفحة في كتاب مطبوع.
class BookFrameBorder extends OutlinedBorder {
  final Color line;
  final Color accent;
  final double radius;
  const BookFrameBorder({required this.line, required this.accent, this.radius = 3, super.side});

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(1);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect.deflate(1), Radius.circular(radius)));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius)),
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    final inner = rect.deflate(3.5);
    if (inner.width < 20 || inner.height < 20) return;
    canvas.drawRect(
        inner,
        Paint()
          ..color = accent.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6);
    final dot = Paint()..color = accent;
    for (final c in [inner.topLeft, inner.topRight, inner.bottomLeft, inner.bottomRight]) {
      canvas.drawPath(diamond(c, 2.6), dot);
    }
  }

  @override
  ShapeBorder scale(double t) => this;

  @override
  BookFrameBorder copyWith({BorderSide? side}) =>
      BookFrameBorder(line: line, accent: accent, radius: radius, side: side ?? this.side);

  @override
  bool operator ==(Object other) =>
      other is BookFrameBorder && other.line == line && other.accent == accent && other.radius == radius;

  @override
  int get hashCode => Object.hash(line, accent, radius);
}

/// إطار المحراب: قوس مدبّب فوق لوحة، بخطين رفيعين، للصلاة القادمة.
class MihrabPainter extends CustomPainter {
  final Color line;
  final Color fill;
  final Color pattern;
  MihrabPainter({required this.line, required this.fill, required this.pattern});

  static Path arch(Rect r, double archH) {
    final top = r.top, cx = r.center.dx;
    final shoulder = top + archH;
    return Path()
      ..moveTo(r.left, r.bottom)
      ..lineTo(r.left, shoulder)
      ..cubicTo(r.left, top + archH * 0.35, cx - r.width * 0.12, top + archH * 0.18, cx, top)
      ..cubicTo(cx + r.width * 0.12, top + archH * 0.18, r.right, top + archH * 0.35, r.right, shoulder)
      ..lineTo(r.right, r.bottom)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // لوحة مستطيلة بإطار مزدوج، في داخلها قوس مدبّب، وكوشتا القوس منقوشتان كبلاط المحاريب.
    final frame = (Offset.zero & size).deflate(0.7);
    final innerFrame = frame.deflate(4);
    final archRect = innerFrame.deflate(9);
    final archH = math.min(archRect.width * 0.26, 80.0);
    canvas.drawRect(frame, Paint()..color = fill);
    final a = arch(archRect, archH);
    final spandrel = Path.combine(PathOperation.difference, Path()..addRect(innerFrame), a);
    canvas.save();
    canvas.clipPath(spandrel);
    paintLattice(canvas, innerFrame, pattern, cell: 16);
    canvas.restore();
    final thick = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final thin = Paint()
      ..color = line.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    canvas.drawRect(frame, thick);
    canvas.drawRect(innerFrame, thin);
    canvas.drawPath(a, thick);
    canvas.drawPath(arch(archRect.deflate(3.5), archH - 2.5), thin);
    // تاج صغير فوق رأس القوس، ومعيّنات في زوايا الإطار.
    canvas.drawPath(starOutline(Offset(archRect.center.dx, archRect.top - 1), 5.5, inner: 0.55), Paint()..color = line);
    final dot = Paint()..color = line;
    for (final c in [innerFrame.topLeft, innerFrame.topRight, innerFrame.bottomLeft, innerFrame.bottomRight]) {
      canvas.drawPath(diamond(c, 3), dot);
    }
  }

  @override
  bool shouldRepaint(covariant MihrabPainter o) => o.line != line || o.fill != fill || o.pattern != pattern;
}

/// شريط زخرفي رفيع: خطان بينهما سلسلة معيّنات، كحواشي الكتب القديمة.
class BorderBandPainter extends CustomPainter {
  final Color color;
  BorderBandPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(0, 0.5), Offset(size.width, 0.5), p);
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), p);
    final cy = size.height / 2;
    final d = size.height / 2 - 1.5;
    final step = d * 2 + 4;
    final fill = Paint()..color = color.withValues(alpha: 0.75);
    for (var x = step / 2; x < size.width; x += step) {
      canvas.drawPath(diamond(Offset(x, cy), d), fill);
    }
  }

  @override
  bool shouldRepaint(covariant BorderBandPainter o) => o.color != color;
}

/// إطار صفحة المصحف: خط خارجي غليظ، ثم حاشية فيها سلسلة معيّنات ونقاط، ثم خط داخلي رفيع،
/// وفي الزوايا مربعات فيها نجوم ثمانية، وفي منتصف الأضلاع جامات صغيرة.
void paintPageFrame(Canvas canvas, Size size, Color color) {
  final outerR = (Offset.zero & size).deflate(0.9);
  final innerR = outerR.deflate(6);
  final mid = outerR.deflate(3);
  final thick = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8;
  final thin = Paint()
    ..color = color.withValues(alpha: 0.8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;
  final fill = Paint()..color = color.withValues(alpha: 0.7);
  canvas.drawRect(outerR, thick);
  canvas.drawRect(innerR, thin);

  // سلسلة الحاشية: معيّن ونقطة بالتناوب على طول الأضلاع.
  void chain(Offset a, Offset b) {
    final len = (b - a).distance;
    final dir = (b - a) / len;
    const step = 9.0;
    final n = (len / step).floor();
    final start = (len - n * step) / 2;
    for (var i = 0; i <= n; i++) {
      final p = a + dir * (start + i * step);
      if (i.isEven) {
        canvas.drawPath(diamond(p, 1.9), fill);
      } else {
        canvas.drawCircle(p, 0.9, fill);
      }
    }
  }

  const k = 14.0; // حجم مربعات الزوايا
  chain(Offset(mid.left + k, mid.top), Offset(mid.right - k, mid.top));
  chain(Offset(mid.left + k, mid.bottom), Offset(mid.right - k, mid.bottom));
  chain(Offset(mid.left, mid.top + k), Offset(mid.left, mid.bottom - k));
  chain(Offset(mid.right, mid.top + k), Offset(mid.right, mid.bottom - k));

  for (final c in [outerR.topLeft, outerR.topRight, outerR.bottomLeft, outerR.bottomRight]) {
    final sx = c.dx == outerR.left ? 1.0 : -1.0;
    final sy = c.dy == outerR.top ? 1.0 : -1.0;
    final sq = Rect.fromPoints(c, c + Offset(sx * k, sy * k));
    canvas.drawRect(sq, thin);
    canvas.drawPath(starOutline(sq.center, k * 0.36, inner: 0.5), Paint()..color = color);
  }

  // جامات صغيرة في منتصف الأضلاع.
  for (final c in [
    Offset(size.width / 2, mid.top),
    Offset(size.width / 2, mid.bottom),
    Offset(mid.left, size.height / 2),
    Offset(mid.right, size.height / 2),
  ]) {
    canvas.drawPath(rubStar(c, 5.5), Paint()..color = color);
  }
}

/// حدّ سفلي لشريط العنوان في الصفحات الداخلية: خط ذهبي رفيع فوق خط بلون الخطوط.
class RuledBottomBorder extends ShapeBorder {
  final Color accent;
  final Color line;
  const RuledBottomBorder({required this.accent, required this.line});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path()..addRect(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRect(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final y = rect.bottom;
    canvas.drawLine(Offset(rect.left, y - 3.5), Offset(rect.right, y - 3.5), Paint()
      ..color = accent.withValues(alpha: 0.6)
      ..strokeWidth = 0.8);
    canvas.drawLine(Offset(rect.left, y - 0.5), Offset(rect.right, y - 0.5), Paint()
      ..color = line
      ..strokeWidth = 1);
  }

  @override
  ShapeBorder scale(double t) => this;

  @override
  bool operator ==(Object other) => other is RuledBottomBorder && other.accent == accent && other.line == line;

  @override
  int get hashCode => Object.hash(accent, line);
}
