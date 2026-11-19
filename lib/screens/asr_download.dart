import 'package:flutter/material.dart';

import '../services/quran_asr.dart';
import '../theme.dart';

/// يعرض تنزيل نموذج التلاوة. يعيد true إن نُزّل، وfalse إن اختار خدمة Google، وnull إن أغلق.
Future<bool?> downloadQuranModel(BuildContext context) => showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (c) => const _DownloadSheet(),
    );

class _DownloadSheet extends StatefulWidget {
  const _DownloadSheet();

  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  double? progress;
  String? error;
  bool cancelled = false;
  final int total = QuranAsrModel.sizeBytes;

  Future<void> _start() async {
    setState(() {
      progress = 0;
      error = null;
      cancelled = false;
    });
    final err = await QuranAsrModel.downloadAll(
      (p) {
        if (mounted) setState(() => progress = p);
      },
      cancelled: () => cancelled,
    );
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        progress = null;
        error = cancelled ? null : err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final busy = progress != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('نموذج التسميع',
              style: TextStyle(fontFamily: readingFont, fontSize: 21, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 6),
          Text(
            'نموذج يسمع التلاوة حرفاً حرفاً، مدرَّب على قراءة الناس بهواتفهم لا على قرّاء الاستوديو وحدهم. '
            'يعمل على هاتفك بلا إنترنت، ويتبعك أثناء القراءة، ولا يخرج صوتك من الهاتف.\n'
            'يُنزَّل مرة واحدة، نحو ${(total / 1048576).round()} ميغابايت، ويُفضَّل على شبكة Wi-Fi.\n'
            'تنبيهه آلي قد يخطئ، ولا يغني عن القراءة على شيخ.',
            style: TextStyle(color: pal.muted, fontSize: 14.5, height: 1.6),
          ),
          const SizedBox(height: 16),
          if (busy) ...[
            LinearProgressIndicator(value: progress == 0 ? null : progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            const SizedBox(height: 8),
            Text(
              '${((progress ?? 0) * total / 1048576).round()} من ${(total / 1048576).round()} ميغابايت'
              '${(progress ?? 0) >= 1 ? ' · نتحقق من سلامة الملف…' : ''}',
              style: TextStyle(color: pal.muted, fontSize: 13),
            ),
            Text('إن انقطع الاتصال أكمل التنزيل وحده من حيث وقف.', style: TextStyle(color: pal.muted, fontSize: 12.5)),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: () => setState(() => cancelled = true), child: const Text('إلغاء')),
            ),
          ] else ...[
            if (error != null) ...[
              Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 14)),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.download),
                label: Text(error == null ? 'نزّل النموذج' : 'حاول مرة أخرى'),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('استعمل خدمة Google')),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('لاحقاً')),
            ]),
          ],
        ]),
      ),
    );
  }
}
