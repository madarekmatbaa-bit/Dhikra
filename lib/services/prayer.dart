import 'package:adhan/adhan.dart';

/// الصلوات الخمس بالترتيب، مع الشروق للعرض فقط.
enum Salah { fajr, sunrise, dhuhr, asr, maghrib, isha }

const salahNames = {
  Salah.fajr: 'الفجر',
  Salah.sunrise: 'الشروق',
  Salah.dhuhr: 'الظهر',
  Salah.asr: 'العصر',
  Salah.maghrib: 'المغرب',
  Salah.isha: 'العشاء',
};

const fivePrayers = [Salah.fajr, Salah.dhuhr, Salah.asr, Salah.maghrib, Salah.isha];

class City {
  final String name;
  final double lat;
  final double lng;
  const City(this.name, this.lat, this.lng);
}

/// مدن جاهزة لمن لا يريد تشغيل الموقع.
const cities = [
  City('دمشق', 33.5138, 36.2765),
  City('حلب', 36.2021, 37.1343),
  City('حمص', 34.7324, 36.7137),
  City('حماة', 35.1318, 36.7578),
  City('اللاذقية', 35.5317, 35.7915),
  City('إدلب', 35.9306, 36.6339),
  City('دير الزور', 35.3359, 40.1408),
  City('عمّان', 31.9454, 35.9284),
  City('إربد', 32.5556, 35.85),
  City('بيروت', 33.8938, 35.5018),
  City('طرابلس (لبنان)', 34.4367, 35.8497),
  City('القدس', 31.7683, 35.2137),
  City('غزة', 31.5017, 34.4668),
  City('مكة المكرمة', 21.3891, 39.8579),
  City('المدينة المنورة', 24.5247, 39.5692),
  City('الرياض', 24.7136, 46.6753),
  City('جدة', 21.4858, 39.1925),
  City('الدمام', 26.4207, 50.0888),
  City('الكويت', 29.3759, 47.9774),
  City('الدوحة', 25.2854, 51.531),
  City('دبي', 25.2048, 55.2708),
  City('أبوظبي', 24.4539, 54.3773),
  City('المنامة', 26.2285, 50.586),
  City('مسقط', 23.588, 58.3829),
  City('بغداد', 33.3152, 44.3661),
  City('الموصل', 36.34, 43.13),
  City('القاهرة', 30.0444, 31.2357),
  City('الإسكندرية', 31.2001, 29.9187),
  City('إسطنبول', 41.0082, 28.9784),
  City('غازي عنتاب', 37.0662, 37.3833),
  City('برلين', 52.52, 13.405),
];

const methodNames = {
  'muslim_world_league': 'رابطة العالم الإسلامي',
  'umm_al_qura': 'أم القرى (مكة)',
  'egyptian': 'الهيئة المصرية العامة للمساحة',
  'karachi': 'جامعة العلوم الإسلامية بكراتشي',
  'dubai': 'دبي',
  'kuwait': 'الكويت',
  'qatar': 'قطر',
  'turkey': 'رئاسة الشؤون الدينية التركية',
  'north_america': 'أمريكا الشمالية (ISNA)',
  'singapore': 'سنغافورة',
  'tehran': 'طهران',
};

class PrayerConfig {
  final double lat;
  final double lng;
  final String place;
  final String method;
  final bool hanafi;
  const PrayerConfig({required this.lat, required this.lng, required this.place, required this.method, required this.hanafi});

  CalculationParameters get _params {
    final m = CalculationMethod.values.firstWhere((e) => e.name == method,
        orElse: () => CalculationMethod.muslim_world_league);
    final p = m.getParameters();
    p.madhab = hanafi ? Madhab.hanafi : Madhab.shafi;
    return p;
  }

  /// أوقات يوم واحد بالتوقيت المحلي للجهاز.
  Map<Salah, DateTime> timesFor(DateTime day) {
    final t = PrayerTimes(Coordinates(lat, lng), DateComponents(day.year, day.month, day.day), _params);
    return {
      Salah.fajr: t.fajr.toLocal(),
      Salah.sunrise: t.sunrise.toLocal(),
      Salah.dhuhr: t.dhuhr.toLocal(),
      Salah.asr: t.asr.toLocal(),
      Salah.maghrib: t.maghrib.toLocal(),
      Salah.isha: t.isha.toLocal(),
    };
  }

  /// الصلاة القادمة من الآن (قد تكون فجر الغد).
  (Salah, DateTime) next(DateTime now) {
    final today = timesFor(now);
    for (final s in fivePrayers) {
      if (today[s]!.isAfter(now)) return (s, today[s]!);
    }
    final tomorrow = timesFor(now.add(const Duration(days: 1)));
    return (Salah.fajr, tomorrow[Salah.fajr]!);
  }
}

String clock12(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'ص' : 'م'}';
}

String untilText(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return 'بعد $m دقيقة';
  return 'بعد $h س و$m د';
}
