import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'package:speech_to_text/speech_to_text.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../util/recitation.dart';

/// يستمع إلى التلاوة بخدمة التعرّف على الكلام في الهاتف، ويرسل كلمات كل عبارة.
/// الخدمة تتوقف بعد كل سكتة، فنعيد تشغيلها ما دام المستخدم لم يوقف المتابعة.
class RecitationListener {
  final _stt = SpeechToText();
  bool active = false;
  bool _ready = false;
  Timer? _restart;

  /// بدائل العبارة الحالية كاملة (أرجحها أولاً)، وهل هي عبارة جديدة، وهل النتيجة نهائية.
  void Function(List<List<String>> alternatives, bool newPhrase, bool isFinal)? onWords;
  void Function(String message)? onFatal;
  void Function(double level)? onLevel;

  bool _newPhrase = true;

  /// يعيد رسالة خطأ إن تعذّر البدء، أو null إن بدأ.
  Future<String?> start() async {
    if (!_ready) {
      _ready = await _stt.initialize(onError: (e) => _onError(e.errorMsg, e.permanent), onStatus: _onStatus);
      if (!_ready) return 'خدمة التعرّف على الكلام غير متاحة في هذا الهاتف، أو لم تأذن بالميكروفون.';
    }
    final locales = await _stt.locales();
    final hasArabic = locales.any((l) => l.localeId.toLowerCase().startsWith('ar'));
    if (locales.isNotEmpty && !hasArabic) {
      return 'لا تدعم خدمة التعرّف في هاتفك العربية. ثبّت تطبيق Google وأضف العربية من إعدادات الكتابة الصوتية.';
    }
    active = true;
    await WakelockPlus.enable();
    await _listen();
    return null;
  }

  Future<void> stop() async {
    active = false;
    _restart?.cancel();
    await WakelockPlus.disable();
    if (_ready) await _stt.cancel();
  }

  Future<void> _listen() async {
    if (!active || _stt.isListening) return;
    _newPhrase = true;
    try {
      await _stt.listen(
        onResult: (r) {
          final alts = [
            for (final a in r.alternates)
              if (recitationWords(a.recognizedWords).isNotEmpty) recitationWords(a.recognizedWords),
          ];
          if (alts.isEmpty) return;
          onWords?.call(alts, _newPhrase, r.finalResult);
          _newPhrase = false;
          if (r.finalResult) _newPhrase = true;
        },
        onSoundLevelChange: (l) => onLevel?.call(l),
        listenOptions: SpeechListenOptions(
          localeId: 'ar_SA',
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
          listenFor: const Duration(minutes: 10),
          pauseFor: const Duration(seconds: 8),
        ),
      );
    } catch (_) {
      _scheduleRestart();
    }
  }

  void _scheduleRestart([Duration d = const Duration(milliseconds: 400)]) {
    if (!active) return;
    _restart?.cancel();
    _restart = Timer(d, _listen);
  }

  void _onStatus(String s) {
    if (s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) _scheduleRestart();
  }

  void _onError(String msg, bool permanent) {
    if (!active) return;
    const fatal = {
      'error_permission',
      'error_insufficient_permissions',
      'error_language_not_supported',
      'error_language_unavailable',
    };
    if (fatal.contains(msg)) {
      stop();
      onFatal?.call(
        msg.contains('permission')
            ? 'يحتاج التطبيق إذن الميكروفون ليتابع التلاوة.'
            : 'العربية غير متاحة في خدمة التعرّف على الكلام في هاتفك.',
      );
      return;
    }
    // انقطاع الشبكة أو سكتة طويلة أو انشغال الخدمة: نعيد المحاولة بعد قليل.
    _scheduleRestart(
      msg == 'error_busy' || msg == 'error_network' ? const Duration(seconds: 2) : const Duration(milliseconds: 400),
    );
  }
}

/// نغمة قصيرة واهتزاز عند الخطأ في التلاوة. لا تطلب تركيز الصوت، فلا توقف تلاوة
/// قارئ يعمل من تطبيق آخر.
class MistakeAlert {
  AudioPlayer? _player;
  DateTime _last = DateTime(2000);

  Future<void> play({bool sound = true}) async {
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(milliseconds: 700)) return;
    _last = now;
    HapticFeedback.heavyImpact();
    if (!sound) return;
    try {
      var p = _player;
      if (p == null) {
        p = _player = AudioPlayer();
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              audioFocus: AndroidAudioFocus.none,
              usageType: AndroidUsageType.assistanceSonification,
              contentType: AndroidContentType.sonification,
            ),
          ),
        );
        await p.setReleaseMode(ReleaseMode.stop);
      }
      await p.stop();
      await p.play(AssetSource('sounds/mistake.wav'), volume: 0.8);
    } catch (_) {}
  }

  void dispose() => _player?.dispose();
}
