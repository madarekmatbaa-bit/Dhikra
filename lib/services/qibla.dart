import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

const kaabaLat = 21.422487, kaabaLng = 39.826206;

double _rad(double d) => d * pi / 180;
double _deg(double r) => r * 180 / pi;

/// اتجاه القبلة من موضع ما، بالدرجات من الشمال الجغرافي باتجاه عقارب الساعة.
double qiblaBearing(double lat, double lng) {
  final p1 = _rad(lat), p2 = _rad(kaabaLat), dl = _rad(kaabaLng - lng);
  final y = sin(dl) * cos(p2);
  final x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl);
  return (_deg(atan2(y, x)) + 360) % 360;
}

/// المسافة إلى الكعبة بالكيلومتر.
double distanceToKaaba(double lat, double lng) {
  final p1 = _rad(lat), p2 = _rad(kaabaLat);
  final dp = p2 - p1, dl = _rad(kaabaLng - lng);
  final a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2);
  return 6371 * 2 * atan2(sqrt(a), sqrt(1 - a));
}

/// اتجاه أعلى الهاتف من الشمال المغناطيسي، من مقياسي التسارع والمغناطيس،
/// مع تعويض الميل (كطريقة getRotationMatrix في أندرويد) وتنعيم يسير.
class Compass {
  final _out = StreamController<double>.broadcast();
  StreamSubscription<AccelerometerEvent>? _a;
  StreamSubscription<MagnetometerEvent>? _m;
  List<double>? _g, _mag;
  double? _heading;

  /// تشويش مغناطيسي قوي (قرب حديد أو مغناطيس): القراءة غير موثوقة.
  bool disturbed = false;

  Stream<double> get headings => _out.stream;

  void start() {
    if (_a != null) return;
    const period = Duration(milliseconds: 40);
    _a = accelerometerEventStream(samplingPeriod: period).listen((e) {
      _g = _lowPass([e.x, e.y, e.z], _g, 0.15);
      _update();
    }, onError: (_) {});
    _m = magnetometerEventStream(samplingPeriod: period).listen((e) {
      _mag = _lowPass([e.x, e.y, e.z], _mag, 0.2);
      _update();
    }, onError: (_) {});
  }

  static List<double> _lowPass(List<double> v, List<double>? prev, double k) =>
      prev == null ? v : [for (var i = 0; i < 3; i++) prev[i] + k * (v[i] - prev[i])];

  void _update() {
    final g = _g, m = _mag;
    if (g == null || m == null) return;
    final ax = g[0], ay = g[1], az = g[2];
    final ex = m[0], ey = m[1], ez = m[2];
    var hx = ey * az - ez * ay, hy = ez * ax - ex * az, hz = ex * ay - ey * ax;
    final normH = sqrt(hx * hx + hy * hy + hz * hz);
    if (normH < 0.1) return; // الهاتف عمودي تماماً أو حرّ السقوط
    hx /= normH;
    hy /= normH;
    hz /= normH;
    final normA = sqrt(ax * ax + ay * ay + az * az);
    final nx = ax / normA, nz = az / normA;
    final my = nz * hx - nx * hz;
    final h = (_deg(atan2(hy, my)) + 360) % 360;
    final field = sqrt(ex * ex + ey * ey + ez * ez);
    disturbed = field < 20 || field > 75; // المجال الأرضي بين 25 و65 ميكروتسلا تقريباً
    // تنعيم الزاوية مع مراعاة الالتفاف عند 360.
    final prev = _heading;
    if (prev == null) {
      _heading = h;
    } else {
      final d = ((h - prev + 540) % 360) - 180;
      _heading = (prev + d * 0.25 + 360) % 360;
    }
    _out.add(_heading!);
  }

  void stop() {
    _a?.cancel();
    _m?.cancel();
    _a = _m = null;
  }

  void dispose() {
    stop();
    _out.close();
  }
}
