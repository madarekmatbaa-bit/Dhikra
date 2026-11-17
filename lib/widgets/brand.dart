import 'package:flutter/material.dart';

import '../theme.dart';
import 'ornaments.dart';

/// علامة ذِكرى: شريط علامة كتاب قمحي على مربع زيتوني، فيه نقطة الذال وكسرتها.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size, child: CustomPaint(painter: _MarkPainter()));
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final bg = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.24));
    canvas.drawRRect(bg, Paint()..color = AppColors.olive);
    final ribbon = Path()
      ..moveTo(s * 0.34, s * 0.16)
      ..lineTo(s * 0.66, s * 0.16)
      ..lineTo(s * 0.66, s * 0.84)
      ..lineTo(s * 0.50, s * 0.70)
      ..lineTo(s * 0.34, s * 0.84)
      ..close();
    canvas.drawPath(ribbon, Paint()..color = AppColors.wheat);
    canvas.drawCircle(Offset(s * 0.5, s * 0.36), s * 0.055, Paint()..color = AppColors.olive);
    final kasra = Paint()
      ..color = AppColors.olive
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(s * 0.57, s * 0.47), Offset(s * 0.43, s * 0.53), kasra);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// بطاقة بعنوان صغير، تُستعمل في الشاشات كلها.
class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class Label extends StatelessWidget {
  final String text;
  const Label(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        const Fleuron(size: 8),
        const SizedBox(width: 7),
        Flexible(
          child: Text(text, style: TextStyle(fontSize: 14, color: Palette.of(context).muted, fontWeight: FontWeight.w500)),
        ),
      ]);
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontFamily: uiFont))));
}

/// فاصل رفيع في وسطه معيّن صغير، كفواصل الأبواب في الكتب المطبوعة.
class Ornament extends StatelessWidget {
  final double width;
  const Ornament({super.key, this.width = double.infinity});

  @override
  Widget build(BuildContext context) {
    final line = Palette.of(context).line;
    return SizedBox(
      width: width,
      height: 12,
      child: Row(children: [
        Expanded(child: Container(height: 1, color: line)),
        const SizedBox(width: 8),
        Transform.rotate(
          angle: 0.785398,
          child: Container(width: 6, height: 6, color: AppColors.wheat),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: line)),
      ]),
    );
  }
}

/// عنوان قسم بخط النسخ يتبعه خط رفيع.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Row(children: [
        Text(text, style: const TextStyle(fontFamily: readingFont, fontSize: 19, fontWeight: FontWeight.w700, height: 1.3)),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: pal.line)),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}
