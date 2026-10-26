import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/user_db.dart';
import '../theme.dart';
import 'brand.dart';

String benefitAsText(Benefit b) {
  final parts = [
    if (b.title.isNotEmpty) b.title,
    b.body,
    '— ${b.sourceLabel}',
    'من دفتر فوائدي في تطبيق ذِكرى',
  ];
  return parts.join('\n\n');
}

Future<void> shareBenefitText(Benefit b) => SharePlus.instance.share(ShareParams(text: benefitAsText(b)));

/// يعرض بطاقة الفائدة بهوية التطبيق، ويشاركها صورة.
Future<void> showShareCard(BuildContext context, Benefit b) {
  final key = GlobalKey();
  return showDialog(
    context: context,
    builder: (c) => Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SingleChildScrollView(
              child: RepaintBoundary(key: key, child: _Card(b)),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق'))),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('مشاركة الصورة'),
                onPressed: () async {
                  final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
                  final image = await boundary.toImage(pixelRatio: 3);
                  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
                  final dir = await getTemporaryDirectory();
                  final file = File('${dir.path}/dhikra-faida-${DateTime.now().millisecondsSinceEpoch}.png');
                  await file.writeAsBytes(bytes!.buffer.asUint8List());
                  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')]));
                },
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  final Benefit b;
  const _Card(this.b);

  @override
  Widget build(BuildContext context) {
    // البطاقة فاتحة دائماً، حتى في الوضع الليلي، لتبدو واحدة عند من تصله.
    return Container(
      width: 340,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: uiFont, color: AppColors.ink),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, color: AppColors.wheat),
          const SizedBox(height: 16),
          if (b.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(b.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.4)),
            ),
          Text(b.body, style: const TextStyle(fontFamily: readingFont, fontSize: 19, height: 1.9)),
          const SizedBox(height: 16),
          Text(b.sourceLabel, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 20),
          const Divider(color: AppColors.line),
          const SizedBox(height: 12),
          const Row(children: [
            BrandMark(size: 26),
            SizedBox(width: 8),
            Text('ذِكرى', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.olive)),
          ]),
        ]),
      ),
    );
  }
}
