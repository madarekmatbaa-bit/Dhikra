import 'package:hijri/hijri_calendar.dart';

/// يطابق تطبيع النص المستعمل عند بناء قاعدة البيانات (tools/build_db.py):
/// حذف الحركات والتطويل، وتوحيد الهمزات والألف المقصورة والتاء المربوطة.
String normalizeArabic(String s) {
  var t = s.replaceAll(RegExp('[ً-ْٰـ‏‎]'), '');
  t = t
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _weekdays = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];
const hijriMonths = [
  'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة',
  'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة',
];
const monthNames = _months;
const weekdayShort = ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];
String gregorianLong(DateTime d) => '${weekdayName(d)} ${d.day} ${_months[d.month - 1]}';
String gregorianFull(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String hijriLong(DateTime d) {
  final h = HijriCalendar.fromDate(d);
  return '${h.hDay} ${hijriMonths[h.hMonth - 1]} ${h.hYear} هـ';
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseKey(String k) {
  final p = k.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// "يوم" بصيغة العدد الصحيحة.
String daysWord(int n) {
  if (n == 1) return 'يوم واحد';
  if (n == 2) return 'يومان';
  if (n >= 3 && n <= 10) return '$n أيام';
  return '$n يوماً';
}

String hadithWord(int n) {
  if (n == 1) return 'حديث واحد';
  if (n == 2) return 'حديثان';
  if (n >= 3 && n <= 10) return '$n أحاديث';
  return '$n حديثاً';
}

/// مدة تقريبية بالسنوات والأشهر.
String roughDuration(int days) {
  if (days < 45) return daysWord(days);
  final months = (days / 30.4).round();
  if (months < 12) return 'حوالي ${months == 1 ? 'شهر' : months == 2 ? 'شهرين' : months <= 10 ? '$months أشهر' : '$months شهراً'}';
  final y = months ~/ 12, m = months % 12;
  final ys = y == 1 ? 'سنة' : y == 2 ? 'سنتين' : y <= 10 ? '$y سنوات' : '$y سنة';
  if (m == 0) return 'حوالي $ys';
  final ms = m == 1 ? 'شهر' : m == 2 ? 'شهرين' : m <= 10 ? '$m أشهر' : '$m شهراً';
  return 'حوالي $ys و$ms';
}
