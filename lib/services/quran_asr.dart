import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../util/speech_segmenter.dart';
import 'recitation_listener.dart';

/// نموذج سماع التلاوة: Zipformer متدفق (Quran-Lab، رخصة NPL-1.2) يُخرج أصوات القراءة
/// حرفاً حرفاً مع حركاتها، لا كلمات. درّبه أصحابه على تسجيلات قرّاء عاديين بهواتفهم،
/// فيسمع القارئ العادي كما يسمع المجوّد. يُنزَّل مرة واحدة ثم يعمل على الهاتف بلا إنترنت.
class QuranAsrModel {
  static const file = 'quran-zipformer-a.int8.onnx';
  static const url = 'https://github.com/madarekmatbaa-bit/Dhikra/releases/download/asr-3/$file';
  static const sizeBytes = 72705392;
  static const sha256Hex = '6a5ddafa9c5e5c01260d30264031b341785bdc152e9ef1d569b41c8c278508eb';
  static const approxMb = 69;

  /// ملفات النموذج السابق (Whisper): تُحذف من الهاتف، فلم تعد تُستعمل.
  static const _old = ['quran-base-q5_1.bin', 'quran-tiny-q5_1.bin'];

  static Future<String> path([String name = file]) async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'asr', name);
  }

  static Future<bool> installed() async {
    for (final o in _old) {
      for (final f in [File(await path(o)), File('${await path(o)}.part')]) {
        if (f.existsSync()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }
    return File(await path()).existsSync();
  }

  static Future<String?> downloadAll(void Function(double progress) onProgress, {bool Function()? cancelled}) =>
      download(onProgress, cancelled: cancelled);

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
    for (final f in [File(await path()), File('${await path()}.part')]) {
      if (f.existsSync()) await f.delete();
    }
  }
}

// ---------- الربط مع المكتبة الأصلية (dhikra_stream.cpp) ----------

typedef _InitC = Pointer<Void> Function(Pointer<Utf8>, Int32);
typedef _InitD = Pointer<Void> Function(Pointer<Utf8>, int);
typedef _ErrC = Pointer<Utf8> Function();
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);
typedef _ResetC = Int32 Function(Pointer<Void>);
typedef _ResetD = int Function(Pointer<Void>);
typedef _AcceptC = Int32 Function(Pointer<Void>, Pointer<Float>, Int32, Pointer<Float>, Int32);
typedef _AcceptD = int Function(Pointer<Void>, Pointer<Float>, int, Pointer<Float>, int);

String _hostLib = '';

/// للاختبار على الحاسوب: مسار المكتبة المبنية محلياً.
void setAsrLibraryPath(String path) => _hostLib = path;

/// عدد رموز النموذج (آخرها الفراغ).
const _vocab = 251;

/// الخيط الذي يشغّل النموذج: يستقبل الصوت قطعاً، ويرسل لكل إطار (40 جزءاً من ألف من الثانية)
/// أرجح ثلاثة رموز واحتمالاتها. يبقى حياً ما بقي النموذج محمّلاً.
void _worker((SendPort, String, String, int) args) {
  final (out, model, libPath, threads) = args;
  final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open(libPath.isEmpty ? 'libdhikra_asr.so' : libPath);
  } catch (e) {
    out.send('تعذّر فتح مكتبة النموذج');
    return;
  }
  final init = lib.lookupFunction<_InitC, _InitD>('zq_init');
  final err = lib.lookupFunction<_ErrC, _ErrC>('zq_error');
  final free = lib.lookupFunction<_FreeC, _FreeD>('zq_free');
  final reset = lib.lookupFunction<_ResetC, _ResetD>('zq_reset');
  final accept = lib.lookupFunction<_AcceptC, _AcceptD>('zq_accept');

  final m = model.toNativeUtf8();
  final ctx = init(m, threads);
  malloc.free(m);
  if (ctx == nullptr) {
    final e = err();
    out.send(e == nullptr ? 'تعذّر تحميل النموذج' : e.toDartString());
    return;
  }
  const cap = 96;
  var inCap = 16000;
  var inBuf = malloc<Float>(inCap);
  final outBuf = malloc<Float>(cap * _vocab);
  final lp = outBuf.asTypedList(cap * _vocab);
  final inbox = ReceivePort();

  void emit(int frames) {
    final ids = Uint8List(frames * 3);
    final probs = Float32List(frames * 3);
    for (var f = 0; f < frames; f++) {
      final o = f * _vocab;
      var b0 = 0, b1 = 0, b2 = 0;
      var p0 = -1e30, p1 = -1e30, p2 = -1e30;
      for (var i = 0; i < _vocab; i++) {
        final x = lp[o + i];
        if (x > p0) {
          p2 = p1;
          b2 = b1;
          p1 = p0;
          b1 = b0;
          p0 = x;
          b0 = i;
        } else if (x > p1) {
          p2 = p1;
          b2 = b1;
          p1 = x;
          b1 = i;
        } else if (x > p2) {
          p2 = x;
          b2 = i;
        }
      }
      ids[f * 3] = b0;
      ids[f * 3 + 1] = b1;
      ids[f * 3 + 2] = b2;
      probs[f * 3] = math.exp(p0);
      probs[f * 3 + 1] = math.exp(p1);
      probs[f * 3 + 2] = math.exp(p2);
    }
    out.send((ids, probs, frames));
  }

  inbox.listen((msg) {
    if (msg is Float32List) {
      if (msg.length > inCap) {
        malloc.free(inBuf);
        inCap = msg.length;
        inBuf = malloc<Float>(inCap);
      }
      inBuf.asTypedList(msg.length).setAll(0, msg);
      var n = msg.length;
      while (true) {
        final frames = accept(ctx, inBuf, n, outBuf, cap);
        if (frames < 0) {
          final e = err();
          out.send(e == nullptr ? 'توقّف النموذج' : e.toDartString());
          return;
        }
        if (frames > 0) emit(frames);
        // امتلأ المخرج وبقي صوت لم يُعالج: نكمل دون صوت جديد.
        if (frames + 16 <= cap) break;
        n = 0;
      }
    } else if (msg is int) {
      if (msg < 0) reset(ctx);
      out.send(msg); // علامة: كل ما سبقها عولج
    } else {
      free(ctx);
      malloc.free(inBuf);
      malloc.free(outBuf);
      inbox.close();
    }
  });
  out.send(inbox.sendPort);
}

/// محرّك السماع: يحمّل النموذج مرة في خيط خاص ويبقيه بين فتحات المصحف.
class StreamEngine {
  Isolate? _iso;
  SendPort? _to;
  ReceivePort? _from;
  String? error;
  int _mark = 0;
  final _marks = <int, Completer<void>>{};

  /// إطارات جاهزة: أرجح ثلاثة رموز لكل إطار واحتمالاتها.
  void Function(Uint8List ids, Float32List probs, int n)? onFrames;
  void Function(String message)? onError;

  bool get ready => _to != null;

  static int get threads => Platform.numberOfProcessors >= 8 ? 4 : Platform.numberOfProcessors.clamp(1, 2);

  Future<bool> load(String modelPath) async {
    if (_to != null) return true;
    final from = ReceivePort();
    final first = Completer<Object?>();
    from.listen((msg) {
      if (!first.isCompleted) {
        first.complete(msg);
      } else if (msg is (Uint8List, Float32List, int)) {
        onFrames?.call(msg.$1, msg.$2, msg.$3);
      } else if (msg is int) {
        _marks.remove(msg)?.complete();
      } else if (msg is String) {
        onError?.call(msg);
      }
    });
    try {
      _iso = await Isolate.spawn(_worker, (from.sendPort, modelPath, _hostLib, threads));
    } catch (e) {
      from.close();
      error = '$e';
      return false;
    }
    final r = await first.future;
    if (r is SendPort) {
      _to = r;
      _from = from;
      return true;
    }
    error = '$r';
    from.close();
    _iso?.kill();
    _iso = null;
    return false;
  }

  void feed(Float32List pcm) => _to?.send(pcm);

  /// ينتظر حتى يُعالج كل ما أُرسل. [reset]: يبدأ النموذج بعدها من جديد (قراءة جديدة).
  Future<void> drain({bool reset = false, Duration timeout = const Duration(seconds: 8)}) {
    final to = _to;
    if (to == null) return Future.value();
    final id = reset ? -(++_mark) : ++_mark;
    final c = Completer<void>();
    _marks[id] = c;
    to.send(id);
    return c.future.timeout(timeout, onTimeout: () {
      _marks.remove(id);
    });
  }

  void dispose() {
    _to?.send('close');
    _to = null;
    _from?.close();
    _from = null;
    _iso = null;
    for (final c in _marks.values) {
      c.complete();
    }
    _marks.clear();
  }
}

/// يستمع بالميكروفون ويمرّر الصوت إلى النموذج قطعة قطعة، فيخرج أصوات القراءة أثناءها
/// (لا بعد الوقفة)، ويتابعها [PhonemeTracker] في شاشة المصحف.
class QuranStreamListener implements ReciteListener {
  final _rec = AudioRecorder();
  static final _engine = StreamEngine();
  StreamSubscription<Uint8List>? _sub;
  // يُستعمل لقياس مستوى الصوت ومعرفة السكوت فقط، لا لتقطيع العبارات.
  late final SpeechSegmenter _seg = SpeechSegmenter(
    onPhrase: (_, _) {},
    onLevel: (l) => onLevel?.call(l * 10),
    interimEvery: const Duration(days: 1),
  );

  @override
  bool active = false;
  @override
  void Function(List<List<String>> alternatives, bool newPhrase, bool isFinal)? onWords;
  @override
  void Function(String message)? onFatal;
  @override
  void Function(double level)? onLevel;

  /// إطارات النموذج، وهل في الصوت قراءة الآن.
  void Function(Uint8List ids, Float32List probs, int n, bool speech)? onFrames;

  /// الهاتف يعالج الصوت أبطأ مما يُقرأ (مرة واحدة في الجلسة).
  void Function()? onSlow;

  int _sent = 0, _got = 0;
  bool _toldSlow = false;

  /// ثوانٍ من الصوت لم تُعالج بعد.
  double get lag => (_sent / SpeechSegmenter.rate - _got * 0.04).clamp(0, 1e9);

  @override
  Future<String?> start() async {
    if (!await _rec.hasPermission()) return 'يحتاج التطبيق إذن الميكروفون ليتابع التلاوة.';
    if (!_engine.ready) {
      final ok = await _engine.load(await QuranAsrModel.path());
      if (!ok) return 'تعذّر تحميل نموذج التلاوة. احذفه من الإعدادات ونزّله من جديد.';
    }
    await _engine.drain(reset: true);
    _engine
      ..onFrames = _frames
      ..onError = (m) {
        if (!active) return;
        stop();
        onFatal?.call('توقّف نموذج التلاوة. أعد تشغيل المتابعة.');
      };
    _sent = 0;
    _got = 0;
    _toldSlow = false;
    try {
      final stream = await _rec.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: SpeechSegmenter.rate,
        numChannels: 1,
        autoGain: true,
        androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
      ));
      active = true;
      _sub = stream.listen(_pcm, onError: (_) {});
    } catch (_) {
      return 'تعذّر فتح الميكروفون. أغلق أي تطبيق آخر يستعمله وحاول مجدداً.';
    }
    await WakelockPlus.enable();
    return null;
  }

  Uint8List? _odd;

  void _pcm(Uint8List bytes) {
    // قد تصل القطعة بعدد فردي من البايتات: نضمّ الباقي إلى التالية.
    var b = bytes;
    final odd = _odd;
    if (odd != null) {
      b = Uint8List(odd.length + bytes.length)
        ..setAll(0, odd)
        ..setAll(odd.length, bytes);
      _odd = null;
    }
    if (b.length.isOdd) {
      _odd = Uint8List.fromList([b.last]);
      b = Uint8List.sublistView(b, 0, b.length - 1);
    }
    final n = b.length ~/ 2;
    if (n == 0) return;
    final data = ByteData.sublistView(b);
    final f = Float32List(n);
    for (var i = 0; i < n; i++) {
      f[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    _seg.addSamples(f);
    _sent += n;
    _engine.feed(f);
  }

  void _frames(Uint8List ids, Float32List probs, int n) {
    _got += n;
    if (!active && !_stopping) return;
    onFrames?.call(ids, probs, n, _seg.inSpeech);
    if (!_toldSlow && lag > 4) {
      _toldSlow = true;
      onSlow?.call();
    }
  }

  bool _stopping = false;

  @override
  Future<void> stop() async {
    if (!active) return;
    active = false;
    _stopping = true;
    await _sub?.cancel();
    _sub = null;
    try {
      await _rec.stop();
    } catch (_) {}
    _seg.flush();
    // صمت قصير يُخرج آخر ما بقي في النموذج من القراءة، ثم ننتظر معالجته.
    _engine.feed(Float32List(SpeechSegmenter.rate));
    await _engine.drain();
    _stopping = false;
    await WakelockPlus.disable();
  }

  void dispose() {
    stop().whenComplete(_rec.dispose);
  }

  /// يحرّر النموذج من الذاكرة (عند حذفه من الإعدادات).
  static void unload() => _engine.dispose();
}

enum _Fetch { done, progressed, online, offline, cancelled }
