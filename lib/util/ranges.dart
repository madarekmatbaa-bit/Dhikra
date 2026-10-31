// أدوات لتمثيل مجموعة صفحات بنص مختصر مثل "1-20,582-604".

/// يقرأ نصاً مثل "1-5,9" أو "٥-١٠ ، ٢٠" ويعيد الصفحات مرتبة دون تكرار.
/// يتجاهل ما يقع خارج [min]..[max].
List<int> parseRanges(String? raw, {int min = 1, int max = 604}) {
  if (raw == null) return const [];
  final s = _latinDigits(raw).replaceAll('،', ',').replaceAll('–', '-').replaceAll('—', '-');
  final out = <int>{};
  for (final part in s.split(RegExp(r'[,\s]+'))) {
    if (part.isEmpty) continue;
    final m = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(part);
    if (m == null) continue;
    var a = int.parse(m.group(1)!);
    var b = m.group(2) == null ? a : int.parse(m.group(2)!);
    if (a > b) (a, b) = (b, a);
    for (var i = a; i <= b; i++) {
      if (i >= min && i <= max) out.add(i);
    }
  }
  return out.toList()..sort();
}

/// يحوّل قائمة صفحات إلى نص مختصر "1-5,9".
String formatRanges(Iterable<int> pages) {
  final l = pages.toSet().toList()..sort();
  final parts = <String>[];
  var i = 0;
  while (i < l.length) {
    var j = i;
    while (j + 1 < l.length && l[j + 1] == l[j] + 1) {
      j++;
    }
    parts.add(i == j ? '${l[i]}' : '${l[i]}-${l[j]}');
    i = j + 1;
  }
  return parts.join(',');
}

/// صياغة للعرض: «ص 5–9، 12».
String describeRanges(Iterable<int> pages) {
  if (pages.isEmpty) return '';
  final f = formatRanges(pages).replaceAll('-', '–').replaceAll(',', '، ');
  return pages.length == 1 ? 'صفحة $f' : 'الصفحات $f';
}

String _latinDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final c in s.split('')) {
    final i = ar.indexOf(c);
    final j = fa.indexOf(c);
    b.write(i >= 0 ? '$i' : j >= 0 ? '$j' : c);
  }
  return b.toString();
}
