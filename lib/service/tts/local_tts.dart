import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/local/local_tts_engine.dart';
import 'package:anx_reader/service/tts/local/local_tts_engine_spec.dart';
import 'package:anx_reader/service/tts/local/local_tts_model_catalog.dart';
import 'package:anx_reader/service/tts/local/local_tts_model_manager.dart';
import 'package:anx_reader/service/tts/local/wav_encoder.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Offline TTS powered by sherpa-onnx models downloaded on demand.
class LocalTts extends BaseTts {
  static final LocalTts _instance = LocalTts._internal();

  factory LocalTts() {
    return _instance;
  }

  LocalTts._internal();

  static bool get isPlatformSupported => !kIsWeb && !AnxPlatform.isOhos;

  AudioPlayer? _player;
  StreamSubscription<void>? _playerCompleteSubscription;
  Completer<void>? _playbackCompleter;

  String? _currentVoiceText;
  late Function getHereFunction;
  late Function getNextTextFunction;
  late Function getPrevTextFunction;
  bool isInit = false;
  bool _shouldStop = false;
  bool _restarting = false;
  int _wavFileIndex = 0;

  @override
  final ValueNotifier<TtsStateEnum> ttsStateNotifier =
      ValueNotifier<TtsStateEnum>(TtsStateEnum.stopped);

  @override
  void updateTtsState(TtsStateEnum newState) {
    ttsStateNotifier.value = newState;
  }

  @override
  double get volume => Prefs().ttsVolume;

  @override
  set volume(double volume) {
    Prefs().ttsVolume = volume;
    _player?.setVolume(volume);
  }

  @override
  double get pitch => Prefs().ttsPitch;

  @override
  set pitch(double pitch) {
    // Local models cannot adjust pitch; stored for consistency and applied
    // from the next sentence onward (no-op for synthesis).
    Prefs().ttsPitch = pitch;
  }

  @override
  double get rate => Prefs().ttsRate;

  @override
  set rate(double rate) {
    Prefs().ttsRate = rate;
  }

  @override
  bool get isPlaying => ttsStateNotifier.value == TtsStateEnum.playing;

  @override
  String? get currentVoiceText => _currentVoiceText;

  @override
  Future<void> init(Function getCurrentText, Function getNextText,
      Function getPrevText) async {
    getHereFunction = getCurrentText;
    getNextTextFunction = getNextText;
    getPrevTextFunction = getPrevText;
    isInit = true;
  }

  // ============ Voices ============

  /// Voices of every installed model, encoded as `<modelId>#<speakerId>`.
  @override
  Future<List<TtsVoice>> getVoices() async {
    final voices = <TtsVoice>[];
    if (!isPlatformSupported) return voices;

    for (final entry in kLocalTtsModelCatalog) {
      final dirPath = await localTtsModelDirPath(entry.id);
      if (!isLocalTtsModelInstalledAt(dirPath)) continue;
      for (var sid = 0; sid < entry.numSpeakers; sid++) {
        final speakerName = entry.speakerName(sid);
        voices.add(TtsVoice(
          shortName: localTtsVoiceId(entry.id, sid),
          name: speakerName ?? 'Speaker $sid',
          locale: entry.locale,
          gender: _guessGender(entry, sid),
          description: '${entry.displayName} · ${entry.languages}',
          rawData: {'modelId': entry.id, 'speakerId': sid},
        ));
      }
    }
    return voices;
  }

  String _guessGender(LocalTtsModelCatalogEntry entry, int sid) {
    final name = entry.speakerName(sid);
    if (name == null) return '';
    if (name.startsWith('zm') || name.contains('男')) return 'male';
    if (name.startsWith('zf') ||
        name.startsWith('af') ||
        name.contains('女')) {
      return 'female';
    }
    return '';
  }

  // ============ Model resolution ============

  Future<LocalTtsEngineSpec?> _resolveSpec(String? voiceOverride) async {
    final voiceId = (voiceOverride?.isNotEmpty ?? false)
        ? voiceOverride!
        : Prefs().getTtsVoiceModel(LocalTtsProvider().serviceId);

    String? modelId;
    int speakerId = 0;
    final parsed = parseLocalTtsVoiceId(voiceId);
    if (parsed != null) {
      modelId = parsed.modelId;
      speakerId = parsed.speakerId;
    }

    // Fall back to the first installed model, then the default catalog model.
    if (modelId == null) {
      for (final entry in kLocalTtsModelCatalog) {
        final dirPath = await localTtsModelDirPath(entry.id);
        if (isLocalTtsModelInstalledAt(dirPath)) {
          modelId = entry.id;
          break;
        }
      }
      modelId ??= defaultLocalTtsModel.id;
    }

    final dirPath = await localTtsModelDirPath(modelId);
    final files = discoverLocalTtsModelFiles(dirPath);
    if (files == null) {
      AnxLog.severe('LocalTts model not installed or incomplete: $modelId');
      return null;
    }

    return LocalTtsEngineSpec(
      modelId: modelId,
      modelPath: files.modelOnnx,
      tokensPath: files.tokensTxt,
      lexiconPaths: files.lexicon,
      dataDirPath: files.dataDir,
      dictDirPath: files.dictDir,
      ruleFsts: files.ruleFsts,
      numThreads: 2,
    );
  }

  // ============ Playback helpers ============

  Future<AudioPlayer> _ensurePlayer() async {
    if (_player != null) return _player!;

    _player = AudioPlayer();
    await _player!.setReleaseMode(ReleaseMode.stop);
    await _player!.setPlayerMode(PlayerMode.mediaPlayer);
    await _player!.setVolume(volume);

    _playerCompleteSubscription = _player!.onPlayerComplete.listen((_) {
      _playbackCompleter?.complete();
    });

    return _player!;
  }

  Future<File> _writeWavFile(LocalTtsSynthesisResult result) async {
    final tempDir = await getAnxTempDir();
    final dir = Directory(p.join(tempDir.path, 'local-tts'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _wavFileIndex = (_wavFileIndex + 1) % 2;
    final file = File(p.join(dir.path, 'utterance-$_wavFileIndex.wav'));
    await file.writeAsBytes(
        encodeWavPcm16(result.samples, result.sampleRate),
        flush: true);
    return file;
  }

  /// Synthesize one sentence and play it. Returns false when interrupted.
  Future<bool> _synthesizeAndPlay(String text, int speakerId,
      {String? voiceOverride}) async {
    final spec = await _resolveSpec(voiceOverride);
    if (spec == null || _shouldStop) return false;

    await LocalTtsEngine.instance.ensureReady(spec);

    final result = await LocalTtsEngine.instance
        .generate(text, speakerId: speakerId, speed: rate);
    if (_shouldStop || result.samples.isEmpty) {
      return !_shouldStop;
    }

    final wavFile = await _writeWavFile(result);
    if (_shouldStop) return false;

    final player = await _ensurePlayer();
    _playbackCompleter = Completer<void>();
    try {
      await player.play(DeviceFileSource(wavFile.path));
      await _playbackCompleter!.future;
    } catch (e) {
      AnxLog.severe('LocalTts playback error: $e');
    }
    _playbackCompleter = null;
    return !_shouldStop;
  }

  Future<TtsSentence?> _collectSentence() async {
    final state = epubPlayerKey.currentState;
    if (state == null) return null;
    try {
      final sentences =
          await state.ttsCollectDetails(count: 1, includeCurrent: true);
      if (sentences.isEmpty) return null;
      return sentences.first;
    } catch (e) {
      AnxLog.severe('LocalTts collect sentence error: $e');
      return null;
    }
  }

  Future<void> _highlightSentence(TtsSentence sentence) async {
    final cfi = sentence.cfi;
    if (cfi == null || cfi.isEmpty) return;
    final state = epubPlayerKey.currentState;
    if (state == null) return;
    try {
      await state.ttsHighlightByCfi(cfi);
    } catch (_) {}
  }

  // ============ BaseTts API ============

  @override
  Future<void> speak({String? content}) async {
    if (!isPlatformSupported) {
      AnxLog.warning('LocalTts is not supported on this platform');
      return;
    }

    _shouldStop = false;
    updateTtsState(TtsStateEnum.playing);

    if (content != null) {
      // One-off utterance (e.g. test from settings).
      final parsed =
          parseLocalTtsVoiceId(Prefs().getTtsVoiceModel('local'));
      await _synthesizeAndPlay(content, parsed?.speakerId ?? 0);
      updateTtsState(TtsStateEnum.stopped);
      return;
    }

    // Sync to current location first.
    try {
      await getHereFunction();
    } catch (_) {}

    while (!_shouldStop) {
      final sentence = await _collectSentence();
      if (_shouldStop) break;
      if (sentence == null || sentence.text.trim().isEmpty) break;

      _currentVoiceText = sentence.text;
      await _highlightSentence(sentence);

      final parsed = parseLocalTtsVoiceId(
          Prefs().getTtsVoiceModel(LocalTtsProvider().serviceId));
      final ok = await _synthesizeAndPlay(
        sentence.text,
        parsed?.speakerId ?? 0,
      );
      if (!ok || _shouldStop) break;

      // Advance the reader position before the next sentence.
      try {
        await getNextTextFunction();
      } catch (e) {
        AnxLog.severe('LocalTts advance error: $e');
        break;
      }
    }

    if (!_shouldStop) {
      updateTtsState(TtsStateEnum.stopped);
    }
  }

  /// Test a specific voice from settings without touching the reader.
  Future<void> speakWithVoice(String content, String voiceShortName) async {
    if (!isPlatformSupported) return;
    await stop();
    final parsed = parseLocalTtsVoiceId(voiceShortName);
    await _synthesizeAndPlay(
      content,
      parsed?.speakerId ?? 0,
      voiceOverride: voiceShortName,
    );
  }

  @override
  Future<void> stop() async {
    _shouldStop = true;
    updateTtsState(TtsStateEnum.stopped);
    _playbackCompleter?.complete();
    _playbackCompleter = null;
    try {
      await _player?.stop();
    } catch (_) {}
    _currentVoiceText = null;
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
    updateTtsState(TtsStateEnum.paused);
  }

  @override
  Future<void> resume() async {
    await _player?.resume();
    updateTtsState(TtsStateEnum.playing);
  }

  @override
  Future<void> prev() async {
    if (_restarting) return;
    _restarting = true;
    await stop();
    try {
      await getPrevTextFunction();
    } catch (e) {
      AnxLog.severe('LocalTts prev error: $e');
    }
    await speak();
    _restarting = false;
  }

  @override
  Future<void> next() async {
    if (_restarting) return;
    _restarting = true;
    await stop();
    try {
      await getNextTextFunction();
    } catch (e) {
      AnxLog.severe('LocalTts next error: $e');
    }
    await speak();
    _restarting = false;
  }

  @override
  Future<void> restart() async {
    if (_restarting) return;
    _restarting = true;
    await stop();
    await speak();
    _restarting = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _playerCompleteSubscription?.cancel();
    _playerCompleteSubscription = null;
    await _player?.dispose();
    _player = null;
    await LocalTtsEngine.instance.dispose();
    isInit = false;
  }
}
