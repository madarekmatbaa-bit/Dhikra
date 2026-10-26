import 'dart:convert';

import 'package:flutter/services.dart';

class Dhikr {
  final String text;
  final int count;
  final String virtue;
  final String ref;
  final List<String>? only; // صلوات بعينها (مثل الفجر والمغرب)
  const Dhikr(this.text, this.count, this.virtue, this.ref, this.only);
}

enum AdhkarSet { morning, evening, prayer, sleep }

const adhkarTitles = {
  AdhkarSet.morning: 'أذكار الصباح',
  AdhkarSet.evening: 'أذكار المساء',
  AdhkarSet.prayer: 'أذكار ما بعد الصلاة',
  AdhkarSet.sleep: 'أذكار النوم',
};

/// نص الأذكار من حصن المسلم، يُبنى بـ tools/build_adhkar.py.
class AdhkarData {
  late final String source;
  late final Map<AdhkarSet, List<Dhikr>> sets;

  Future<void> load() async {
    final m = jsonDecode(await rootBundle.loadString('assets/data/adhkar.json')) as Map<String, dynamic>;
    source = m['source'] as String;
    List<Dhikr> parse(String k) => [
          for (final e in (m[k] as List).cast<Map<String, dynamic>>())
            Dhikr(e['text'] as String, e['count'] as int, e['virtue'] as String, e['ref'] as String,
                (e['only'] as List?)?.cast<String>()),
        ];
    sets = {
      AdhkarSet.morning: parse('morning'),
      AdhkarSet.evening: parse('evening'),
      AdhkarSet.prayer: parse('prayer'),
      AdhkarSet.sleep: parse('sleep'),
    };
  }
}
