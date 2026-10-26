import 'dart:convert';
import 'dart:io';

import 'package:dhikra/services/prayer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('مواقيت دمشق مرتبة ومعقولة', () {
    const cfg = PrayerConfig(lat: 33.5138, lng: 36.2765, place: 'دمشق', method: 'muslim_world_league', hanafi: false);
    final t = cfg.timesFor(DateTime(2026, 10, 27));
    final order = Salah.values.map((s) => t[s]!).toList();
    for (var i = 1; i < order.length; i++) {
      expect(order[i].isAfter(order[i - 1]), isTrue);
    }
    // فرق الظهر عن الفجر بين 6 و8 ساعات في الخريف
    final h = t[Salah.dhuhr]!.difference(t[Salah.fajr]!).inMinutes / 60;
    expect(h, inInclusiveRange(6, 8));
  });

  test('ملف الأذكار سليم', () {
    final m = jsonDecode(File('assets/data/adhkar.json').readAsStringSync()) as Map<String, dynamic>;
    for (final k in ['morning', 'evening', 'prayer', 'sleep']) {
      final list = m[k] as List;
      expect(list, isNotEmpty);
      for (final e in list) {
        expect((e['text'] as String).trim(), isNotEmpty);
        expect(e['count'] as int, greaterThan(0));
      }
    }
  });
}
