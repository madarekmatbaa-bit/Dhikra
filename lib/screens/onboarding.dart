import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/bukhari_db.dart';
import '../services/notifications.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/arabic.dart';
import '../widgets/brand.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  int perDay = 10;
  String startMode = 'begin'; // begin | book | number
  int bookId = 1;
  final numberCtrl = TextEditingController();
  bool remind = true;
  TimeOfDay time = const TimeOfDay(hour: 20, minute: 0);
  bool saving = false;

  @override
  void dispose() {
    numberCtrl.dispose();
    super.dispose();
  }

  int get startPos {
    final s = context.read<AppState>();
    return switch (startMode) {
      'book' => s.bukhari.bookById(bookId).first,
      'number' => (int.tryParse(numberCtrl.text) ?? 1).clamp(1, totalHadiths),
      _ => 1,
    };
  }

  Future<void> _finish() async {
    setState(() => saving = true);
    await context.read<AppState>().startPlan(perDay: perDay, startPos: startPos, reminder: remind ? time : null);
  }

  @override
  Widget build(BuildContext context) {
    final steps = [_perDayStep(), _startStep(), _reminderStep()];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const BrandMark(size: 44),
                const SizedBox(width: 12),
                Text('ذِكرى', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                Text('${step + 1} من 3', style: TextStyle(color: Palette.of(context).muted)),
              ]),
              const SizedBox(height: 14),
              LinearProgressIndicator(value: (step + 1) / 3, minHeight: 5, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 26),
              Expanded(child: SingleChildScrollView(child: steps[step])),
              Row(children: [
                if (step > 0)
                  Expanded(
                    child: OutlinedButton(onPressed: () => setState(() => step--), child: const Text('رجوع')),
                  ),
                if (step > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: saving ? null : () => step < 2 ? setState(() => step++) : _finish(),
                    child: Text(step < 2 ? 'التالي' : 'ابدأ الورد'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(String t, String sub) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(sub, style: TextStyle(color: Palette.of(context).muted, fontSize: 15)),
        const SizedBox(height: 22),
      ]);

  Widget _perDayStep() {
    final days = (totalHadiths / perDay).ceil();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('كم حديثاً تقرأ كل يوم؟', 'القليل الدائم خير من الكثير المنقطع. تستطيع تغييره لاحقاً.'),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final n in [3, 5, 10, 20, 30])
          ChoiceChip(
            label: Text('$n', style: const TextStyle(fontSize: 17)),
            selected: perDay == n,
            onSelected: (_) => setState(() => perDay = n),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
      ]),
      const SizedBox(height: 18),
      Row(children: [
        const Text('عدد آخر:', style: TextStyle(fontSize: 15)),
        const SizedBox(width: 8),
        IconButton.outlined(
            onPressed: perDay > 1 ? () => setState(() => perDay--) : null, icon: const Icon(Icons.remove)),
        SizedBox(
            width: 56,
            child: Text('$perDay',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
        IconButton.outlined(
            onPressed: perDay < 200 ? () => setState(() => perDay++) : null, icon: const Icon(Icons.add)),
      ]),
      const SizedBox(height: 24),
      SectionCard(
        color: Palette.of(context).soft,
        child: Row(children: [
          const Icon(Icons.flag_outlined, color: AppColors.sage),
          const SizedBox(width: 12),
          Expanded(
            child: Text('تختم الصحيح (7563 حديثاً) خلال ${daysWord(days)}، ${roughDuration(days)}.',
                style: const TextStyle(fontSize: 15)),
          ),
        ]),
      ),
    ]);
  }

  Widget _startStep() {
    final s = context.read<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('من أين تبدأ؟', 'الترقيم المعتمد هو ترقيم فتح الباري الشائع.'),
      _option('begin', 'من أول الصحيح', 'كتاب بدء الوحي، الحديث 1'),
      _option('book', 'من كتاب معين', 'تختار الكتاب من الفهرس'),
      if (startMode == 'book')
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<int>(
            initialValue: bookId,
            isExpanded: true,
            items: [
              for (final b in s.bukhari.books)
                DropdownMenuItem(value: b.id, child: Text('${b.id}. ${b.title}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => bookId = v ?? 1),
          ),
        ),
      _option('number', 'من رقم حديث', 'إن كنت بدأت القراءة من قبل'),
      if (startMode == 'number')
        TextField(
          controller: numberCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'رقم الحديث من 1 إلى 7563'),
          onChanged: (_) => setState(() {}),
        ),
    ]);
  }

  Widget _option(String value, String title, String sub) {
    final selected = startMode == value;
    final pal = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        color: selected ? pal.soft : null,
        onTap: () => setState(() => startMode = value),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? Theme.of(context).colorScheme.primary : pal.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              Text(sub, style: TextStyle(color: pal.muted, fontSize: 13)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _reminderStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('تذكير يومي', 'تذكير واحد فقط في الوقت الذي تختاره، دون إزعاج.'),
      SectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('ذكّرني بالورد'),
            value: remind,
            onChanged: (v) => setState(() => remind = v),
          ),
          if (remind) const Divider(),
          if (remind)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('الوقت'),
              trailing: Text(formatTime(time), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: time);
                if (t != null) setState(() => time = t);
              },
            ),
        ]),
      ),
      const SizedBox(height: 18),
      Text('خلاصة: ${hadithWord(perDay)} كل يوم، تبدأ من الحديث $startPos.',
          style: TextStyle(color: Palette.of(context).muted, fontSize: 15)),
    ]);
  }
}
