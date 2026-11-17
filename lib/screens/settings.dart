import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/notifications.dart';
import '../services/updates.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/arabic.dart';
import '../widgets/brand.dart';
import 'home_shell.dart';
import 'quran_tab.dart';

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
          _Head('ورد الحديث · ${s.hadith.current.title}'),
          _Group(children: [
            ListTile(
              title: const Text('أحاديث كل يوم'),
              subtitle: Text('الختم بعد ${roughDuration((s.hadith.total / plan.perDay).ceil())} تقريباً'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: plan.perDay > 1 ? () => s.setPerDay(plan.perDay - 1) : null,
                ),
                Text('${plan.perDay}', style: const TextStyle(fontFamily: readingFont, fontSize: 19, fontWeight: FontWeight.w700, height: 1.45)),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: plan.perDay < 200 ? () => s.setPerDay(plan.perDay + 1) : null,
                ),
              ]),
            ),
            const Divider(),
            ListTile(
              title: const Text('موضعك الحالي'),
              subtitle: Text('الحديث ${s.position.clamp(1, s.hadith.total)} · كتاب ${s.hadith.bookOf(s.position).title}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _changePosition(context, s),
            ),
            const Divider(),
            ListTile(
              title: const Text('سجل الأيام'),
              subtitle: const Text('التقويم والخط وتقدمك في الكتاب'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => openStatsPage(context),
            ),
          ]),
          const _Head('ورد القرآن'),
          _Group(children: [
            ListTile(
              title: Text(s.quran.enabled ? '${s.quran.perDay} صفحة كل يوم' : 'لم تحدّد ورداً بعد'),
              subtitle: Text('التذكير: ${quranReminderLabel(s.quran)}'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => openQuranSetup(context),
            ),
          ]),
          const _Head('تذكير ورد الحديث'),
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
              title: Text('ذِكرى · الإصدار 0.8${appBuild > 0 ? ' · نسخة $appBuild' : ''}'),
              subtitle: const Text(
                  'نص القرآن وخطه من مجمع الملك فهد لطباعة المصحف الشريف. '
                  'نصوص الكتب الستة من مجموعات بيانات مفتوحة مأخوذة عن موقع sunnah.com (hadith-api وhadith-json)، والبخاري بترقيم فتح الباري. '
                  'يعمل التطبيق دون إنترنت، وكل بياناتك على جهازك.'),
              isThreeLine: true,
            ),
            if (!playStore) const Divider(),
            if (!playStore) ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: const Text('تحقق من تحديث'),
              subtitle: const Text('يحتاج إنترنت. التحديث يُثبَّت فوق النسخة الحالية ولا تضيع بياناتك.'),
              onTap: () => checkUpdateInteractive(context),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _changePosition(BuildContext context, AppState s) async {
    final ctrl = TextEditingController(text: '${s.position.clamp(1, s.hadith.total)}');
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

/// فحص التحديث من الإعدادات أو من بطاقة «اليوم»، مع رسالة للمستخدم.
Future<void> checkUpdateInteractive(BuildContext context) async {
  final s = context.read<AppState>();
  toast(context, 'جارٍ الفحص…');
  final u = await s.checkUpdate(force: true);
  if (!context.mounted) return;
  if (u == null) {
    final l = s.update;
    toast(context, l == null ? 'عندك أحدث نسخة، أو لا يوجد اتصال بالإنترنت' : 'عندك أحدث نسخة');
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('نسخة جديدة: ${u.build}'),
      content: const Text(
          'تنزل النسخة من المتصفح، ثم افتح الملف من التنزيلات واضغط «تحديث». تُثبَّت فوق الحالية وتبقى بياناتك كما هي.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لاحقاً')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('نزّلها')),
      ],
    ),
  );
  if (ok == true) await Updates.download(u);
}
