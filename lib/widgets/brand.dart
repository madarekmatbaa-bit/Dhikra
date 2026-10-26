import 'package:flutter/material.dart';

import '../theme.dart';

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
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 14, color: Palette.of(context).muted, fontWeight: FontWeight.w500));
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontFamily: uiFont))));
}
