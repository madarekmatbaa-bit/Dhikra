import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/user_db.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/share_card.dart';
import 'reader.dart';

class BenefitEditScreen extends StatefulWidget {
  final Benefit? benefit;
  final String initialBody;
  final String sourceType;
  final String? sourceRef;
  const BenefitEditScreen({
    super.key,
    this.benefit,
    this.initialBody = '',
    this.sourceType = 'free',
    this.sourceRef,
  });

  @override
  State<BenefitEditScreen> createState() => _BenefitEditScreenState();
}

class _BenefitEditScreenState extends State<BenefitEditScreen> {
  late final TextEditingController title;
  late final TextEditingController body;
  final tagCtrl = TextEditingController();
  late List<String> tags;
  late bool pinned;
  late String sourceType;
  String? sourceRef;

  @override
  void initState() {
    super.initState();
    final b = widget.benefit;
    title = TextEditingController(text: b?.title ?? '');
    body = TextEditingController(text: b?.body ?? widget.initialBody);
    tags = [...?b?.tags];
    pinned = b?.pinned ?? false;
    sourceType = b?.sourceType ?? widget.sourceType;
    sourceRef = b?.sourceRef ?? widget.sourceRef;
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    tagCtrl.dispose();
    super.dispose();
  }

  Benefit get _current => Benefit(
        id: widget.benefit?.id,
        title: title.text.trim(),
        body: body.text.trim(),
        sourceType: sourceType,
        sourceRef: sourceRef,
        pinned: pinned,
        createdAt: widget.benefit?.createdAt ?? DateTime.now().toIso8601String(),
        tags: tags,
      );

  Future<void> _save() async {
    if (body.text.trim().isEmpty && title.text.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }
    _addTag();
    await context.read<AppState>().saveBenefit(_current);
    if (mounted) Navigator.pop(context);
  }

  void _addTag() {
    final t = tagCtrl.text.trim();
    if (t.isNotEmpty && !tags.contains(t)) setState(() => tags.add(t));
    tagCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final existing = widget.benefit;
    final suggestions = s.tags.where((t) => !tags.contains(t)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(existing == null ? 'فائدة جديدة' : 'الفائدة'),
        actions: [
          IconButton(
            tooltip: pinned ? 'إلغاء التثبيت' : 'تثبيت',
            icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined, color: pinned ? AppColors.wheat : null),
            onPressed: () => setState(() => pinned = !pinned),
          ),
          if (existing != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'text':
                    await shareBenefitText(_current);
                  case 'image':
                    await showShareCard(context, _current);
                  case 'delete':
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('حذف الفائدة؟'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) {
                      await s.deleteBenefit(existing);
                      if (context.mounted) Navigator.pop(context);
                    }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'text', child: Text('مشاركة نصاً')),
                PopupMenuItem(value: 'image', child: Text('مشاركة صورة')),
                PopupMenuItem(value: 'delete', child: Text('حذف')),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          if (sourceType == 'hadith')
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ActionChip(
                avatar: const Icon(Icons.menu_book_outlined, size: 18),
                label: Text('البخاري · حديث $sourceRef'),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ReaderScreen(start: int.tryParse(sourceRef ?? '') ?? 1))),
              ),
            ),
          TextField(
            controller: title,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            decoration: const InputDecoration(hintText: 'العنوان (اختياري)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: body,
            minLines: 6,
            maxLines: null,
            style: const TextStyle(fontSize: 16, height: 1.7),
            decoration: const InputDecoration(hintText: 'اكتب الفائدة بكلماتك'),
          ),
          const SizedBox(height: 18),
          const Text('الوسوم', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in tags)
              InputChip(
                label: Text(t),
                selected: true,
                showCheckmark: false,
                onDeleted: () => setState(() => tags.remove(t)),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: tagCtrl,
            onSubmitted: (_) => _addTag(),
            decoration: InputDecoration(
              hintText: 'أضف وسماً، مثل: عقيدة، أخلاق، فقه',
              suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _addTag),
            ),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in suggestions)
                ActionChip(
                  label: Text(t, style: TextStyle(color: pal.muted)),
                  onPressed: () => setState(() => tags.add(t)),
                ),
            ]),
          ],
          const SizedBox(height: 28),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
        ],
      ),
    );
  }
}
