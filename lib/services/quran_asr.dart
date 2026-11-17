import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../util/recitation.dart';
import '../util/speech_segmenter.dart';
import 'recitation_listener.dart';

/// نموذج التعرّف على التلاوة: Whisper معدّل على تلاوة القرآن (Tarteel)، بصيغة whisper.cpp.
/// يُنزَّل مرة واحدة من إصدارات المستودع، ثم يعمل على الهاتف بلا إنترنت.
class QuranAsrModel {
  static const file = 'quran-base-q5_1.bin';
  static const url = 'https://github.com/madarekmatbaa-bit/Dhikra/releases/download/asr-2/$file';
  static const sha256Hex = 'acc1f03c8b1468b674b4fab50e0b2312cff982ba0001cd16fe36ca23862b6536';
  static const approxMb = 60;

  static Future<String> path() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'asr', file);
  }

  static Future<bool> installed() async => File(await path()).existsSync();

  static const sizeBytes = 59707625;

  /// ينزّل النموذج مع تقدّم من 0 إلى 1. يعيد رسالة خطأ أو null.
  ///
  /// إن انقطع الاتصال (وهو كثير على الشبكة الخلوية) أكمل من حيث وقف بطلب جزئي،
  /// ويعيد المحاولة وحده مرات قبل أن يعرض خطأً. وما نُزّل يبقى، فالمحاولة التالية تكمل منه.
  static Future<String?> download(void Function(double progress) onProgress,
      {bool Function()? cancelled,
      String? from,
      String? to,
      int expectedSize = sizeBytes,
      String expectedSha = sha256Hex,
      Duration retryDelay = const Duration(seconds: 2)}) async {
    final dest = to ?? await path();
    await Directory(p.dirname(dest)).create(recursive: true);
    final part = File('$dest.part');
    var failures = 0;
    var sawNetwork = false;
    while (true) {
      if (cancelled?.call() ?? false) return 'أُلغي التنزيل، وما نُزّل محفوظ يكمل منه لاحقاً.';
      var have = part.existsSync() ? part.lengthSync() : 0;
      if (have > expectedSize) {
        await part.delete();
        have = 0;
      }
      if (have < expectedSize) {
        final r = await _fetch(from ?? url, part, have, expectedSize, onProgress, cancelled);
        if (r == _Fetch.cancelled) return 'أُلغي التنزيل، وما نُزّل محفوظ يكمل منه لاحقاً.';
        if (r == _Fetch.progressed) failures = 0;
        if (r == _Fetch.offline) sawNetwork = false;
        if (r == _Fetch.online) sawNetwork = true;
        if (r != _Fetch.done) {
          failures++;
          if (failures > 6) {
            return sawNetwork || part.existsSync() && part.lengthSync() > 0
                ? 'انقطع التنزيل أكثر من مرة. ما نُزّل محفوظ، فاضغط «حاول مرة أخرى» ليكمل من حيث وقف.'
                : 'لا يوجد اتصال بالإنترنت. يلزم الاتصال مرة واحدة لتنزيل النموذج.';
          }
          await Future.delayed(retryDelay * failures);
          continue;
        }
      }
      // اكتمل: نتحقق من سلامة الملف قبل اعتماده.
      if (expectedSha.isNotEmpty) {
        final path = part.path;
        final digest = await Isolate.run(() => sha256.convert(File(path).readAsBytesSync()).toString());
        if (digest != expectedSha) {
          await part.delete();
          return 'وصل الملف تالفاً فحُذف. حاول مرة أخرى.';
        }
      }
      await part.rename(dest);
      onProgress(1);
      return null;
    }
  }

  static Future<_Fetch> _fetch(String url, File part, int have, int total, void Function(double) onProgress,
      bool Function()? cancelled) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 20);
    IOSink? sink;
    var got = have;
    try {
      final req = await client.getUrl(Uri.parse(url));
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (have > 0 && res.statusCode == 200) {
        // الخادم لم يقبل الإكمال: نبدأ من أول الملف.
        got = 0;
        sink = part.openWrite();
      } else if (res.statusCode == 206 || res.statusCode == 200) {
        sink = part.openWrite(mode: FileMode.append);
      } else if (res.statusCode == 416) {
        await part.delete();
        return _Fetch.online;
      } else {
        return _Fetch.online;
      }
      onProgress(got / total);
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        if (cancelled?.call() ?? false) return _Fetch.cancelled;
        sink.add(chunk);
        got += chunk.length;
        onProgress((got / total).clamp(0, 1));
      }
      return got >= total ? _Fetch.done : (got > have ? _Fetch.progressed : _Fetch.online);
    } on SocketException {
      return got > have ? _Fetch.progressed : _Fetch.offline;
    } catch (_) {
      // انقطاع أثناء الاستلام أو مهلة: ما وصل محفوظ، ونكمل في المحاولة التالية.
      return got > have ? _Fetch.progressed : _Fetch.online;
    } finally {
      await sink?.flush();
      await sink?.close();
      client.close(force: true);
    }
  }

  static Future<void> remove() async {
    final f = File(await path());
    if (f.existsSync()) await f.delete();
  }
}

// ---------- الربط مع whisper.cpp ----------

typedef _InitC = Pointer<Void> Function(Pointer<Utf8>);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeStrC = Void Function(Pointer<Utf8>);
typedef _TranscribeC = Pointer<Utf8> Function(Pointer<Void>, Pointer<Float>, Int32, Pointer<Utf8>, Int32, Int32);
typedef _TranscribeD = Pointer<Utf8> Function(Pointer<Void>, Pointer<Float>, int, Pointer<Utf8>, int, int);

DynamicLibrary _lib() => DynamicLibrary.open(Platform.isAndroid ? 'libdhikra_asr.so' : _hostLib);
String _hostLib = 'libdhikra_asr.so';

/// للاختبار على الحاسوب: مسار المكتبة المبنية محلياً.
void setAsrLibraryPath(String path) => _hostLib = path;

int _initIn(String model, String libPath) {
  _hostLib = libPath;
  final f = _lib().lookupFunction<_InitC, Pointer<Void> Function(Pointer<Utf8>)>('dq_init');
  final m = model.toNativeUtf8();
  try {
    return f(m).address;
  } finally {
    malloc.free(m);
  }
}

String? _transcribeIn(int ctx, Float32List pcm, String prompt, int audioCtx, int threads, String libPath) {
  _hostLib = libPath;
  final lib = _lib();
  final f = lib.lookupFunction<_TranscribeC, _TranscribeD>('dq_transcribe');
  final freeStr = lib.lookupFunction<_FreeStrC, void Function(Pointer<Utf8>)>('dq_free_str');
  final buf = malloc<Float>(pcm.length);
  buf.asTypedList(pcm.length).setAll(0, pcm);
  final pr = prompt.toNativeUtf8();
  try {
    final r = f(Pointer.fromAddress(ctx), buf, pcm.length, pr, audioCtx, threads);
    if (r.address == 0) return null;
    final s = r.toDartString();
    freeStr(r);
    return s;
  } finally {
    malloc.free(buf);
    malloc.free(pr);
  }
}

/// محرّك Whisper: يحمّل النموذج مرة، وينسخ كل عبارة في خيط منفصل حتى لا تتجمد الواجهة.
class WhisperEngine {
  int _ctx = 0;
  bool get ready => _ctx != 0;

  static int get threads => (Platform.numberOfProcessors >= 8 ? 4 : Platform.numberOfProcessors.clamp(2, 4));

  Future<bool> load(String modelPath) async {
    if (_ctx != 0) return true;
    final lib = _hostLib;
    _ctx = await Isolate.run(() => _initIn(modelPath, lib));
    return _ctx != 0;
  }

  /// نافذة الترميز بقدر طول المقطع (50 إطاراً في الثانية) مع هامش، وهي أسرع بكثير
  /// من نافذة الثلاثين ثانية الكاملة لعبارة من بضع ثوانٍ.
  static int audioCtxFor(int samples) {
    final secs = samples / SpeechSegmenter.rate;
    final frames = ((secs + 2.5) * 50).ceil();
    final rounded = ((frames + 63) ~/ 64) * 64;
    return rounded >= 1500 ? 0 : rounded.clamp(384, 1500);
  }

  Future<String?> transcribe(Float32List pcm, {String prompt = '', bool fullWindow = false}) async {
    if (_ctx == 0) return null;
    // هامش صامت قبل العبارة وبعدها: بدونه يُسقط النموذج أحياناً آخر كلمة.
    const lead = 3200, tail = 9600;
    final padded = Float32List(pcm.length + lead + tail)..setAll(lead, pcm);
    final ctx = _ctx, lib = _hostLib, th = threads;
    final ac = fullWindow ? 0 : audioCtxFor(padded.length);
    final text = await Isolate.run(() => _transcribeIn(ctx, padded, prompt, ac, th, lib));
    if (text == null || fullWindow) return text;
    // دوران في التكرار (كلمات أكثر مما يتسع له الصوت): نعيد بالنافذة الكاملة.
    final words = text.trim().split(RegExp(r'\s+')).length;
    final secs = pcm.length / SpeechSegmenter.rate;
    if (words > secs * 3.2 + 3 || hasLoop(text)) {
      final again = await Isolate.run(() => _transcribeIn(ctx, padded, prompt, 0, th, lib));
      if (again != null) return hasLoop(again) ? cutLoop(again) : again;
    }
    return text;
  }

  /// عبارة من أربع كلمات فأكثر تتكرر ثلاث مرات متتالية: النموذج يدور.
  static bool hasLoop(String text) => cutLoop(text) != text;

  /// يقطع النص عند بدء التكرار الثالث لعبارة متكررة.
  static String cutLoop(String text) {
    final w = text.trim().split(RegExp(r'\s+'));
    for (var n = 2; n <= 10; n++) {
      for (var i = 0; i + 3 * n <= w.length; i++) {
        var rep = true;
        for (var k = 0; k < n && rep; k++) {
          if (w[i + k] != w[i + n + k] || w[i + k] != w[i + 2 * n + k]) rep = false;
        }
        if (rep && n * 3 >= 6) return w.sublist(0, i + 2 * n).join(' ');
      }
    }
    return text;
  }

  void dispose() {
    if (_ctx == 0) return;
    final f = _lib().lookupFunction<_FreeC, void Function(Pointer<Void>)>('dq_free');
    f(Pointer.fromAddress(_ctx));
    _ctx = 0;
  }
}

/// يستمع بالميكروفون مباشرة ويحوّل كل عبارة بنموذج التلاوة على الهاتف.
/// يرسل نتائج جزئية أثناء العبارة ليتبع القارئ، ونهائية بعد كل وقفة ليحكم على الأخطاء.
class QuranAsrListener implements ReciteListener {
  final _rec = AudioRecorder();
  // يبقى النموذج محمّلاً بين فتحات المصحف، فتحميله يأخذ ثانية أو اثنتين.
  static final _engine = WhisperEngine();
  StreamSubscription<Uint8List>? _sub;
  late final SpeechSegmenter _seg = SpeechSegmenter(onPhrase: _onPhrase, onLevel: (l) => onLevel?.call(l * 10));

  @override
  bool active = false;
  @override
  void Function(List<List<String>> alternatives, bool newPhrase, bool isFinal)? onWords;
  @override
  void Function(String message)? onFatal;
  @override
  void Function(double level)? onLevel;

  /// نص المصحف الذي قرأه القارئ قبل العبارة، يُعطى للنموذج ليتّبع إملاءه.
  String Function()? context;

  bool _busy = false;
  bool _phraseOpen = false;
  final _finals = <Float32List>[];

  @override
  Future<String?> start() async {
    if (!await _rec.hasPermission()) return 'يحتاج التطبيق إذن الميكروفون ليتابع التلاوة.';
    if (!_engine.ready) {
      final ok = await _engine.load(await QuranAsrModel.path());
      if (!ok) return 'تعذّر تحميل نموذج التلاوة. احذفه من الإعدادات ونزّله من جديد.';
    }
    try {
      final stream = await _rec.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: SpeechSegmenter.rate,
        numChannels: 1,
        autoGain: true,
        noiseSuppress: true,
        androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
      ));
      active = true;
      _phraseOpen = false;
      _sub = stream.listen(_seg.addPcm16, onError: (_) {});
    } catch (_) {
      return 'تعذّر فتح الميكروفون. أغلق أي تطبيق آخر يستعمله وحاول مجدداً.';
    }
    await WakelockPlus.enable();
    return null;
  }

  @override
  Future<void> stop() async {
    if (!active) return;
    active = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _rec.stop();
    } catch (_) {}
    _seg.flush();
    await WakelockPlus.disable();
    // ننتظر نسخ العبارة الأخيرة لتُحسب أخطاؤها في الملخص.
    for (var i = 0; i < 60 && (_busy || _finals.isNotEmpty); i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _onPhrase(Float32List pcm, bool isFinal) {
    if (isFinal) {
      _finals.add(pcm);
      _pump();
    } else if (!_busy && _finals.isEmpty) {
      _run(pcm, false);
    }
  }

  void _pump() {
    if (_busy || _finals.isEmpty) return;
    _run(_finals.removeAt(0), true);
  }

  Future<void> _run(Float32List pcm, bool isFinal) async {
    _busy = true;
    try {
      final text = await _engine.transcribe(pcm, prompt: context?.call() ?? '');
      final words = text == null ? const <String>[] : recitationWords(text);
      if (words.isNotEmpty) {
        final newPhrase = !_phraseOpen;
        _phraseOpen = !isFinal;
        onWords?.call([words], newPhrase, isFinal);
      } else if (isFinal && _phraseOpen) {
        // لم يُفهم شيء في آخر العبارة: نغلقها بما سُمع جزئياً.
        _phraseOpen = false;
      }
    } catch (_) {
    } finally {
      _busy = false;
      _pump();
    }
  }

  void dispose() {
    stop().whenComplete(_rec.dispose);
  }

  /// يحرّر النموذج من الذاكرة (عند حذفه من الإعدادات).
  static void unload() => _engine.dispose();
}

enum _Fetch { done, progressed, online, offline, cancelled }
