import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/user_db.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/arabic.dart';
import '../widgets/share_card.dart';
import 'benefit_edit.dart';

class BenefitsScreen extends StatefulWidget {
  const BenefitsScreen({super.key});

  @override
  State<BenefitsScreen> createState() => _BenefitsScreenState();
}

class _BenefitsScreenState extends State<BenefitsScreen> {
  String? tag;
  String query = '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final q = normalizeArabic(query);
    final list = s.benefits.where((b) {
      if (tag != null && !b.tags.contains(tag)) return false;
      if (q.isEmpty) return true;
      return normalizeArabic('${b.title} ${b.body} ${b.tags.join(' ')}').contains(q);
    }).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BenefitEditScreen())),
        icon: const Icon(Icons.add),
        label: const Text('فائدة جديدة'),
      ),
      body: SafeArea(
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('دفتر الفوائد · ${s.benefits.length}', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: const InputDecoration(hintText: 'ابحث في فوائدك', prefixIcon: Icon(Icons.search)),
                ),
                if (s.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      ChoiceChip(label: const Text('الكل'), selected: tag == null, onSelected: (_) => setState(() => tag = null)),
                      for (final t in s.tags) ...[
                        const SizedBox(width: 8),
                        ChoiceChip(label: Text(t), selected: tag == t, onSelected: (_) => setState(() => tag = t)),
                      ],
                    ]),
                  ),
                ],
              ]),
            ),
          ),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    s.benefits.isEmpty
                        ? 'لا فوائد بعد.\nحدد جملة أثناء قراءة الحديث واختر «احفظ فائدة»، أو اكتب فائدة حرة من درس أو مجلس.'
                        : 'لا نتائج',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: pal.muted, fontSize: 15, height: 1.8),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 96),
              sliver: SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _BenefitTile(benefit: list[i]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _BenefitTile extends StatelessWidget {
  final Benefit benefit;
  const _BenefitTile({required this.benefit});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final pal = Palette.of(context);
    final b = benefit;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BenefitEditScreen(benefit: b))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (b.pinned) const Padding(
                padding: EdgeInsetsDirectional.only(end: 6),
                child: Icon(Icons.push_pin, size: 18, color: AppColors.wheat),
              ),
              Expanded(
                child: Text(b.title.isEmpty ? 'فائدة' : b.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: pal.muted),
                onSelected: (v) async {
                  switch (v) {
                    case 'pin':
                      await s.togglePin(b);
                    case 'text':
                      await shareBenefitText(b);
                    case 'image':
                      if (context.mounted) await showShareCard(context, b);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'pin', child: Text(b.pinned ? 'إلغاء التثبيت' : 'تثبيت')),
                  const PopupMenuItem(value: 'text', child: Text('مشاركة نصاً')),
                  const PopupMenuItem(value: 'image', child: Text('مشاركة صورة')),
                ],
              ),
            ]),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: Text(b.body, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(b.sourceLabel, style: TextStyle(color: pal.muted, fontSize: 13)),
              for (final t in b.tags)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: pal.soft, borderRadius: BorderRadius.circular(8)),
                  child: Text(t, style: const TextStyle(fontSize: 12)),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
