import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/bukhari_db.dart';
import '../services/notifications.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/arabic.dart';
import '../widgets/brand.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final plan = s.plan!;
    final reminder = parseTime(plan.reminder);

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
        children: [
          const _Head('الورد'),
          _Group(children: [
            ListTile(
              title: const Text('أحاديث كل يوم'),
              subtitle: Text('الختم بعد ${roughDuration((totalHadiths / plan.perDay).ceil())} تقريباً'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: plan.perDay > 1 ? () => s.setPerDay(plan.perDay - 1) : null,
                ),
                Text('${plan.perDay}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: plan.perDay < 200 ? () => s.setPerDay(plan.perDay + 1) : null,
                ),
              ]),
            ),
            const Divider(),
            ListTile(
              title: const Text('موضعك الحالي'),
              subtitle: Text('الحديث ${s.position.clamp(1, totalHadiths)} · كتاب ${s.bukhari.bookOf(s.position).title}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _changePosition(context, s),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('إذا فاتك يوم', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'postpone', label: Text('أؤجل الختم')),
                    ButtonSegment(value: 'compensate', label: Text('أعوّضه مع الغد')),
                  ],
                  selected: {s.catchUp},
                  onSelectionChanged: (v) => s.setCatchUp(v.first),
                ),
                const SizedBox(height: 6),
                Text(
                  s.catchUp == 'postpone'
                      ? 'تكمل من حيث توقفت بنفس العدد اليومي، ويتأخر موعد الختم.'
                      : 'يضاف ما فاتك إلى ورد اليوم التالي (حتى ضعفي الورد).',
                  style: TextStyle(color: pal.muted, fontSize: 13),
                ),
              ]),
            ),
          ]),
          const _Head('التذكير'),
          _Group(children: [
            SwitchListTile(
              title: const Text('تذكير يومي'),
              value: reminder != null,
              onChanged: (v) => s.setReminder(v ? const TimeOfDay(hour: 20, minute: 0) : null),
            ),
            if (reminder != null) ...[
              const Divider(),
              ListTile(
                title: const Text('الوقت'),
                trailing: Text(formatTime(reminder), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: reminder);
                  if (t != null) await s.setReminder(t);
                },
              ),
            ],
          ]),
          const _Head('القراءة والمظهر'),
          _Group(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('حجم خط الحديث: ${s.fontSize.round()}', style: const TextStyle(fontSize: 16)),
                Slider(
                  value: s.fontSize,
                  min: 15,
                  max: 34,
                  divisions: 19,
                  onChanged: s.setFontSize,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: pal.soft, borderRadius: BorderRadius.circular(12)),
                  child: Text('إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ، وَإِنَّمَا لِكُلِّ امْرِئٍ مَا نَوَى',
                      style: TextStyle(fontFamily: readingFont, fontSize: s.fontSize, height: 1.9)),
                ),
                const SizedBox(height: 12),
              ]),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('الوضع الليلي'),
              value: s.themeMode == ThemeMode.dark,
              onChanged: (v) => s.setThemeMode(v ? ThemeMode.dark : ThemeMode.light),
            ),
          ]),
          const _Head('النسخ الاحتياطي'),
          _Group(children: [
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('حفظ نسخة احتياطية'),
              subtitle: const Text('ملف فيه وردك وسجلك وفوائدك، احفظه أو أرسله لنفسك'),
              onTap: () => _export(context, s),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('استعادة من نسخة'),
              subtitle: const Text('تستبدل البيانات الحالية بما في الملف'),
              onTap: () => _import(context, s),
            ),
          ]),
          const _Head('عن التطبيق'),
          _Group(children: [
            ListTile(
              leading: const BrandMark(size: 34),
              title: const Text('ذِكرى · الإصدار 0.1'),
              subtitle: const Text(
                  'نص صحيح البخاري من مجموعة بيانات مفتوحة (hadith-api) مأخوذة عن موقع sunnah.com، بترقيم فتح الباري. '
                  'يعمل التطبيق دون إنترنت، وكل بياناتك على جهازك.'),
              isThreeLine: true,
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _changePosition(BuildContext context, AppState s) async {
    final ctrl = TextEditingController(text: '${s.position.clamp(1, totalHadiths)}');
    final n = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('الانتقال بالورد إلى حديث'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'من 1 إلى 7563'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(ctrl.text)), child: const Text('حفظ')),
        ],
      ),
    );
    if (n != null) await s.setPosition(n);
  }

  Future<void> _export(BuildContext context, AppState s) async {
    final json = await s.exportJson();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/dhikra-backup-${dateKey(DateTime.now())}.json');
    await file.writeAsString(json);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: 'نسخة احتياطية من ذِكرى',
    ));
  }

  Future<void> _import(BuildContext context, AppState s) async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('استعادة النسخة؟'),
        content: const Text('ستُستبدل بياناتك الحالية بما في الملف.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('استعادة')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final raw = await files.first.xFile.readAsString();
      await s.importJson(raw);
      if (context.mounted) toast(context, 'تمت الاستعادة');
    } catch (e) {
      if (context.mounted) toast(context, 'تعذرت قراءة الملف. تأكد أنه نسخة احتياطية من ذِكرى.');
    }
  }
}

class _Head extends StatelessWidget {
  final String text;
  const _Head(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
        child: Label(text),
      );
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) => Card(child: Column(children: children));
}
