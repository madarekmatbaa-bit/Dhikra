import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../db/adhkar_data.dart';
import '../services/prayer.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// قارئ الأذكار: ذكر في كل صفحة، والضغط على البطاقة يعدّ، وعند تمام العدد ينتقل لما بعده.
class AdhkarReader extends StatefulWidget {
  final AdhkarSet set;
  final Salah? afterPrayer;
  const AdhkarReader({super.key, required this.set, this.afterPrayer});

  @override
  State<AdhkarReader> createState() => _AdhkarReaderState();
}

class _AdhkarReaderState extends State<AdhkarReader> {
  final _pages = PageController();
  late final List<Dhikr> items;
  late final List<int> counts;
  int index = 0;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    final all = context.read<AppState>().adhkar.sets[widget.set]!;
    final p = widget.afterPrayer;
    items = [for (final d in all) if (d.only == null || (p != null && d.only!.contains(p.name))) d];
    counts = List.filled(items.length, 0);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _tap() {
    final i = index;
    if (counts[i] >= items[i].count) {
      _next();
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => counts[i]++);
    if (counts[i] >= items[i].count) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && index == i) _next();
      });
    }
  }

  void _next() {
    if (index < items.length - 1) {
      _pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    if (widget.set != AdhkarSet.prayer) await context.read<AppState>().markAdhkarDone(widget.set);
    setState(() => finished = true);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Palette.of(context);
    final title = widget.afterPrayer == null
        ? adhkarTitles[widget.set]!
        : 'أذكار ما بعد صلاة ${salahNames[widget.afterPrayer]}';
    final done = counts.where((c) => c > 0).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(value: finished ? 1 : (index + (counts[index] >= items[index].count ? 1 : 0)) / items.length, minHeight: 4),
        ),
      ),
      body: finished
          ? _Finished(title: title, count: done)
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(children: [
                  Text('${index + 1} من ${items.length}', style: TextStyle(color: pal.muted, fontSize: 14)),
                  const Spacer(),
                  if (counts[index] > 0)
                    TextButton.icon(
                      onPressed: () => setState(() => counts[index] = 0),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('إعادة العد'),
                    ),
                ]),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: items.length,
                  onPageChanged: (i) => setState(() => index = i),
                  itemBuilder: (context, i) => _DhikrPage(dhikr: items[i], count: counts[i], onTap: _tap),
                ),
              ),
            ]),
      bottomNavigationBar: finished
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Row(children: [
                  IconButton.outlined(
                    tooltip: 'السابق',
                    onPressed: index > 0
                        ? () => _pages.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut)
                        : null,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _Counter(dhikr: items[index], count: counts[index], onTap: _tap)),
                  const SizedBox(width: 12),
                  IconButton.outlined(
                    tooltip: 'التالي',
                    onPressed: _next,
                    icon: const Icon(Icons.arrow_back),
                  ),
                ]),
              ),
            ),
    );
  }
}

class _DhikrPage extends StatelessWidget {
  final Dhikr dhikr;
  final int count;
  final VoidCallback onTap;
  const _DhikrPage({required this.dhikr, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final complete = count >= dhikr.count;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: complete ? pal.soft : pal.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: complete ? AppColors.sage : pal.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                dhikr.text,
                textAlign: TextAlign.justify,
                style: TextStyle(fontFamily: readingFont, fontSize: s.fontSize, height: 1.95),
              ),
              if (dhikr.virtue.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: pal.highlight, borderRadius: BorderRadius.circular(12)),
                  child: Text(dhikr.virtue, style: const TextStyle(fontSize: 14, height: 1.7)),
                ),
              ],
              if (dhikr.ref.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(dhikr.ref, style: TextStyle(color: pal.muted, fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          Center(child: Text('اضغط على الذكر أو على العدّاد للعدّ', style: TextStyle(color: pal.muted, fontSize: 13))),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  final Dhikr dhikr;
  final int count;
  final VoidCallback onTap;
  const _Counter({required this.dhikr, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final complete = count >= dhikr.count;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 60,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(backgroundColor: complete ? AppColors.sage : scheme.primary),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(complete ? 'تم · التالي' : '$count / ${dhikr.count}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _Finished extends StatelessWidget {
  final String title;
  final int count;
  const _Finished({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, size: 72, color: AppColors.sage),
          const SizedBox(height: 16),
          Text('أتممت $title', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('تقبّل الله منك', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 28),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع')),
        ]),
      ),
    );
  }
}
