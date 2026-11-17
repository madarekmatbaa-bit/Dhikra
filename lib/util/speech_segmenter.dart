import 'dart:math' as math;
import 'dart:typed_data';

/// يقطّع صوت الميكروفون (16 كيلوهرتز، أحادي) إلى عبارات عند وقفات القارئ.
///
/// يقيس طاقة كل 20 جزءاً من الثانية، ويتعلّم مستوى الضجيج في الغرفة، فيعدّ ما
/// فوقه بوضوح كلاماً. المدّ صوت متصل فلا يقطع العبارة، والوقف عند رؤوس الآي
/// أو لأخذ النَّفَس يُنهيها. وإن طالت العبارة قُطعت عند أهدأ لحظة في آخرها.
///
/// [onPhrase] يُستدعى بالعبارة كلها حين تنتهي (نهائية)، أو بما سُمع منها حتى
/// الآن كل [interimEvery] (جزئية)، ليتبع التطبيق القارئ قبل أن يقف.
class SpeechSegmenter {
  static const rate = 16000;
  static const _frame = 320; // 20ms

  final void Function(Float32List samples, bool isFinal) onPhrase;
  void Function(double level)? onLevel;

  final Duration endSilence;
  final Duration maxPhrase;
  final Duration interimEvery;

  SpeechSegmenter({
    required this.onPhrase,
    this.onLevel,
    this.endSilence = const Duration(milliseconds: 420),
    this.maxPhrase = const Duration(seconds: 20),
    this.interimEvery = const Duration(milliseconds: 1000),
  });

  final _pending = <double>[];
  final _phrase = <double>[];
  final _frameEnergy = <double>[];
  final _preRoll = <double>[];

  double _noise = 0.004;
  double _peak = 0;
  bool _inSpeech = false;
  int _speechFrames = 0;
  int _silentFrames = 0;
  int _sinceInterim = 0;
  int _frames = 0;

  bool get inSpeech => _inSpeech;

  int get _endSilenceFrames => endSilence.inMilliseconds ~/ 20;
  int get _maxFrames => maxPhrase.inMilliseconds ~/ 20;
  int get _interimFrames => interimEvery.inMilliseconds ~/ 20;

  /// صوت PCM بعرض 16 بت (little-endian) كما يصل من الميكروفون.
  void addPcm16(Uint8List bytes) {
    final n = bytes.lengthInBytes ~/ 2;
    final data = ByteData.sublistView(bytes);
    final f = Float32List(n);
    for (var i = 0; i < n; i++) {
      f[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    addSamples(f);
  }

  void addSamples(Float32List s) {
    _pending.addAll(s);
    var off = 0;
    while (_pending.length - off >= _frame) {
      _processFrame(_pending.sublist(off, off + _frame));
      off += _frame;
    }
    _pending.removeRange(0, off);
  }

  void _processFrame(List<double> fr) {
    _frames++;
    var sum = 0.0;
    for (final v in fr) {
      sum += v * v;
    }
    final rms = math.sqrt(sum / fr.length);
    // الضجيج: ينزل سريعاً إلى أهدأ ما سُمع، ويرتفع ببطء بإطارات قريبة منه فقط،
    // فلا يرفعه صوت القارئ نفسه مهما طالت قراءته.
    if (rms < _noise) {
      _noise = _noise * 0.85 + rms * 0.15;
    } else if (rms < _noise * 2.5) {
      _noise = _noise * 0.98 + rms * 0.02;
    } else {
      _noise *= 1.0005; // ضجيج ارتفع فجأة واستمر: يلحقه ببطء شديد
    }
    _noise = _noise.clamp(0.0008, 0.05);
    // ذروة العبارة: ما دون جزء صغير منها صدى أو نَفَس، لا قراءة.
    _peak = math.max(rms, _peak * 0.998);
    final threshold = math.max(math.max(_noise * 3.2, 0.006), _inSpeech ? _peak * 0.1 : 0);
    final loud = rms > threshold;
    onLevel?.call((rms / (threshold * 4)).clamp(0.0, 1.0));

    if (!_inSpeech) {
      _preRoll.addAll(fr);
      // نُبقي ربع ثانية قبل بدء الكلام، فلا يضيع أول حرف.
      if (_preRoll.length > rate ~/ 4) _preRoll.removeRange(0, _preRoll.length - rate ~/ 4);
      if (loud) {
        _speechFrames++;
        if (_speechFrames >= 3) {
          _inSpeech = true;
          _phrase
            ..clear()
            ..addAll(_preRoll);
          _frameEnergy
            ..clear()
            ..addAll(List.filled(_preRoll.length ~/ _frame, 0.0));
          _preRoll.clear();
          _silentFrames = 0;
          _sinceInterim = 0;
        }
      } else {
        _speechFrames = 0;
      }
      return;
    }

    _phrase.addAll(fr);
    _frameEnergy.add(rms);
    _sinceInterim++;
    if (loud) {
      _speechFrames++;
      _silentFrames = 0;
    } else {
      _silentFrames++;
    }

    // النموذج أدق في عبارة قصيرة (آية أو بعضها)، فبعد ثماني ثوانٍ تكفي وقفة أقصر.
    final longPhrase = _frameEnergy.length > 400;
    if (_silentFrames >= _endSilenceFrames || longPhrase && _silentFrames >= 16) {
      // ننهي العبارة بعد السكتة، ونحذف معظمها من آخرها.
      final keep = _phrase.length - (_silentFrames - 8).clamp(0, _silentFrames) * _frame;
      _emitFinal(keep);
      return;
    }
    if (_frameEnergy.length >= _maxFrames) {
      // عبارة طويلة بلا وقف: نقطع في وسط أطول فترة هادئة في آخر خمس ثوانٍ،
      // لا عند أهدأ إطار منفرد قد يكون سكون حرف في وسط كلمة.
      final from = _frameEnergy.length - 250;
      final quiet = threshold * 1.6;
      var best = _frameEnergy.length - 1, bestLen = 0, runStart = -1;
      for (var i = from; i <= _frameEnergy.length; i++) {
        final q = i < _frameEnergy.length && _frameEnergy[i] < quiet;
        if (q && runStart < 0) runStart = i;
        if (!q && runStart >= 0) {
          if (i - runStart >= bestLen) {
            bestLen = i - runStart;
            best = runStart + (i - runStart) ~/ 2;
          }
          runStart = -1;
        }
      }
      if (bestLen == 0) {
        for (var i = from; i < _frameEnergy.length; i++) {
          if (_frameEnergy[i] < _frameEnergy[best]) best = i;
        }
      }
      final cut = (best + 1) * _frame;
      final rest = _phrase.sublist(cut.clamp(0, _phrase.length));
      final restE = _frameEnergy.sublist((best + 1).clamp(0, _frameEnergy.length));
      _emitFinal(cut);
      _inSpeech = true;
      _phrase.addAll(rest);
      _frameEnergy.addAll(restE);
      return;
    }
    if (_sinceInterim >= _interimFrames && _speechFrames > 15) {
      _sinceInterim = 0;
      onPhrase(Float32List.fromList(_phrase), false);
    }
  }

  void _emitFinal(int keep) {
    final n = keep.clamp(0, _phrase.length);
    final voiced = _speechFrames;
    final out = Float32List.fromList(_phrase.sublist(0, n));
    _phrase.clear();
    _frameEnergy.clear();
    _inSpeech = false;
    _speechFrames = 0;
    _silentFrames = 0;
    _sinceInterim = 0;
    // نقرة أو سعلة قصيرة ليست عبارة.
    if (voiced >= 15) onPhrase(out, true);
  }

  /// ينهي العبارة الجارية (عند إيقاف المتابعة).
  void flush() {
    if (_inSpeech) _emitFinal(_phrase.length);
    _pending.clear();
    _preRoll.clear();
  }

  int get framesSeen => _frames;
}
