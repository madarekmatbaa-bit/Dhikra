import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../services/notifications.dart';
import '../services/prayer.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/brand.dart';

class PrayerSettingsScreen extends StatefulWidget {
  const PrayerSettingsScreen({super.key});

  @override
  State<PrayerSettingsScreen> createState() => _PrayerSettingsScreenState();
}

class _PrayerSettingsScreenState extends State<PrayerSettingsScreen> {
  bool locating = false;

  Future<void> _useGps() async {
    final s = context.read<AppState>();
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) toast(context, 'شغّل خدمة الموقع في الهاتف ثم أعد المحاولة');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) toast(context, 'لم يُسمح بالوصول للموقع. اختر مدينتك من القائمة.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 30)),
      );
      await s.setLocation(pos.latitude, pos.longitude, _nearestName(pos.latitude, pos.longitude));
      if (mounted) toast(context, 'تم تحديد موقعك');
    } catch (_) {
      if (mounted) toast(context, 'تعذر تحديد الموقع. اختر مدينتك من القائمة.');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  /// اسم أقرب مدينة من القائمة إن كانت قريبة، وإلا «موقعي».
  String _nearestName(double lat, double lng) {
    City? best;
    var bestD = double.infinity;
    for (final c in cities) {
      final d = Geolocator.distanceBetween(lat, lng, c.lat, c.lng);
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return bestD < 40000 ? best!.name : 'موقعي';
  }

  Future<void> _pickCity() async {
    final s = context.read<AppState>();
    final c = await showModalBottomSheet<City>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, sc) => ListView(controller: sc, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('اختر مدينتك', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          for (final c in cities) ListTile(title: Text(c.name), onTap: () => Navigator.pop(ctx, c)),
        ]),
      ),
    );
    if (c != null) await s.setLocation(c.lat, c.lng, c.name);
  }

  Future<void> _pickTime(TimeOfDay initial, Future<void> Function(TimeOfDay) save) async {
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t != null) await save(t);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = Palette.of(context);
    final cfg = s.prayerConfig;
    final alerts = s.prayerAlerts;
    const offsets = [0, 15, 30, 45, 60];

    Widget offsetChips(int? value, Future<void> Function(int?) save) => Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(label: const Text('مطفأ'), selected: value == null, onSelected: (_) => save(null)),
          for (final o in offsets)
            ChoiceChip(
              label: Text(o == 0 ? 'مع الأذان' : 'بعد $o د'),
              selected: value == o,
              onSelected: (_) => save(o),
            ),
        ]);

    return Scaffold(
      appBar: AppBar(title: const Text('الصلاة والأذكار')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
        children: [
          const _Head('الموقع'),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(cfg == null ? 'لم يُحدَّد بعد' : cfg.place),
                subtitle: cfg == null
                    ? const Text('تُحسب المواقيت على الهاتف دون إنترنت')
                    : Text('${cfg.lat.toStringAsFixed(3)}، ${cfg.lng.toStringAsFixed(3)}'),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: locating ? null : _useGps,
                      icon: locating
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location),
                      label: const Text('موقعي الحالي'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton(onPressed: _pickCity, child: const Text('اختر مدينة'))),
                ]),
              ),
            ]),
          ),
          if (cfg != null) ...[
            const _Head('طريقة الحساب'),
            Card(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: DropdownButtonFormField<String>(
                    initialValue: cfg.method,
                    isExpanded: true,
                    items: [
                      for (final e in methodNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => v == null ? null : s.setMethod(v),
                  ),
                ),
                SwitchListTile(
                  title: const Text('العصر على المذهب الحنفي'),
                  subtitle: const Text('يتأخر وقت العصر قليلاً'),
                  value: cfg.hanafi,
                  onChanged: s.setHanafi,
                ),
              ]),
            ),
            const _Head('التذكير بالصلاة'),
            Card(
              child: Column(children: [
                for (final p in fivePrayers)
                  SwitchListTile(
                    title: Text('صلاة ${salahNames[p]}'),
                    value: alerts.contains(p),
                    onChanged: (v) => s.setPrayerAlert(p, v),
                  ),
              ]),
            ),
            const _Head('تذكير أذكار الصباح (بعد الفجر)'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: offsetChips(s.morningAfterFajr, s.setMorningAfterFajr),
              ),
            ),
            const _Head('تذكير أذكار المساء (بعد العصر)'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: offsetChips(s.eveningAfterAsr, s.setEveningAfterAsr),
              ),
            ),
          ],
          const _Head('تذكير أذكار النوم'),
          Card(
            child: Column(children: [
              SwitchListTile(
                title: const Text('ذكّرني قبل النوم'),
                value: s.sleepReminder != null,
                onChanged: (v) => s.setSleepReminder(v ? const TimeOfDay(hour: 22, minute: 30) : null),
              ),
              if (s.sleepReminder != null) ...[
                const Divider(),
                ListTile(
                  title: const Text('الوقت'),
                  trailing: Text(formatTime(s.sleepReminder!),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  onTap: () => _pickTime(s.sleepReminder!, s.setSleepReminder),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 18),
          Text(
            'التذكيرات تُجدول لأسبوعين وتتجدد كلما فتحت التطبيق. نص الأذكار من «${s.adhkar.source.split('،').first}».',
            style: TextStyle(color: pal.muted, fontSize: 13, height: 1.7),
          ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  final String text;
  const _Head(this.text);

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(4, 22, 4, 8), child: Label(text));
}
