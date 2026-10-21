import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:anx_reader/service/tts/local/local_tts_engine_spec.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Background-isolate wrapper around the sherpa-onnx offline TTS engine.
///
/// Model loading and synthesis are CPU-heavy and block the calling thread, so
/// both run inside a dedicated isolate. The engine holds at most one loaded
/// model; calling [ensureReady] with a different model id reloads it.
class LocalTtsEngine {
  static final LocalTtsEngine instance = LocalTtsEngine._();

  LocalTtsEngine._();

  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _replyPort;
  StreamSubscription<dynamic>? _replySubscription;

  Completer<void>? _initCompleter;
  Completer<LocalTtsSynthesisResult>? _generateCompleter;
  int? _pendingSequence;
  int _nextSequence = 0;

  String? _activeModelId;
  int _numSpeakers = 0;
  int _sampleRate = 0;

  int get sampleRate => _sampleRate;
  int get numSpeakers => _numSpeakers;
  String? get activeModelId => _activeModelId;
  bool get isReady => _activeModelId != null && _initCompleter != null;

  /// Ensure the given model is loaded. Safe to call repeatedly; only reloads
  /// when the model id differs from the active one.
  Future<void> ensureReady(LocalTtsEngineSpec spec) async {
    if (_activeModelId == spec.modelId && isReady) {
      return _initCompleter!.future;
    }
    await _shutdown();
    _initCompleter = Completer<void>();

    try {
      _replyPort = ReceivePort();
      _isolate = await Isolate.spawn(_engineWorker, _replyPort!.sendPort);

      final readyForCommands = Completer<SendPort>();
      _replySubscription = _replyPort!.listen((message) {
        if (message is SendPort) {
          if (!readyForCommands.isCompleted) {
            readyForCommands.complete(message);
          }
          return;
        }
        _handleWorkerMessage(message);
      });

      _commandPort = await readyForCommands.future;
      _commandPort!.send(spec);

      await _initCompleter!.future;
      _activeModelId = spec.modelId;
      AnxLog.info(
          'LocalTts engine ready: ${spec.modelId} (sampleRate: $_sampleRate, speakers: $_numSpeakers)');
    } catch (e) {
      _initCompleter = null;
      await _shutdown();
      rethrow;
    }
  }

  void _handleWorkerMessage(dynamic message) {
    if (message is _EngineReady) {
      _numSpeakers = message.numSpeakers;
      _sampleRate = message.sampleRate;
      _initCompleter?.complete();
    } else if (message is _EngineError) {
      if (_pendingSequence == null &&
          _initCompleter != null &&
          !_initCompleter!.isCompleted) {
        _initCompleter!.completeError(Exception(message.message));
      } else if (_generateCompleter != null) {
        _generateCompleter!.completeError(Exception(message.message));
      }
      AnxLog.severe('LocalTts engine error: ${message.message}');
    } else if (message is _EngineDone) {
      if (message.sequence != _pendingSequence) {
        // Stale result from a discarded generation (stop/restart race).
        return;
      }
      _pendingSequence = null;
      _generateCompleter?.complete(LocalTtsSynthesisResult(
        samples: message.samples,
        sampleRate: message.sampleRate,
      ));
      _generateCompleter = null;
    }
  }

  /// Synthesize [text] with the loaded model. Must be called after a
  /// successful [ensureReady].
  Future<LocalTtsSynthesisResult> generate(
    String text, {
    required int speakerId,
    required double speed,
  }) async {
    final commandPort = _commandPort;
    if (commandPort == null || _activeModelId == null) {
      throw StateError('LocalTts engine is not ready');
    }
    // Drop any in-flight generation; its late result is ignored via the
    // sequence check in _handleWorkerMessage.
    _generateCompleter = null;
    _pendingSequence = _nextSequence++;
    final completer = Completer<LocalTtsSynthesisResult>();
    _generateCompleter = completer;
    commandPort.send(_GenerateRequest(_pendingSequence!, text, speakerId, speed));
    return completer.future;
  }

  /// Release the native engine and kill the isolate.
  Future<void> dispose() => _shutdown();

  Future<void> _shutdown() async {
    _activeModelId = null;
    _initCompleter = null;
    _generateCompleter = null;
    _pendingSequence = null;
    _numSpeakers = 0;
    _sampleRate = 0;
    try {
      _commandPort?.send(const _DisposeRequest());
    } catch (_) {}
    _commandPort = null;
    await _replySubscription?.cancel();
    _replySubscription = null;
    _replyPort?.close();
    _replyPort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    // Give the isolate a tick to free the native engine.
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

// ============ Isolate entry ============

void _engineWorker(SendPort mainPort) {
  final port = ReceivePort();
  mainPort.send(port.sendPort);

  try {
    sherpa_onnx.initBindings();
  } catch (e) {
    AnxLog.warning('sherpa_onnx initBindings: $e');
  }

  sherpa_onnx.OfflineTts? tts;

  port.listen((message) {
    if (message is LocalTtsEngineSpec) {
      try {
        tts?.free();
        tts = null;
        final config = _buildSherpaConfig(message);
        tts = sherpa_onnx.OfflineTts(config);
        mainPort.send(_EngineReady(tts!.numSpeakers, tts!.sampleRate));
      } catch (e) {
        mainPort.send(const _EngineError('Failed to load local TTS model'));
        AnxLog.severe('LocalTts load failed: $e');
      }
    } else if (message is _GenerateRequest) {
      if (tts == null) {
        mainPort.send(const _EngineError('LocalTts engine not loaded'));
        return;
      }
      try {
        final audio = tts!.generate(
          text: message.text,
          sid: message.speakerId,
          speed: message.speed,
        );
        mainPort.send(_EngineDone(
          message.sequence,
          Float32List.fromList(audio.samples),
          audio.sampleRate,
        ));
      } catch (e) {
        mainPort.send(const _EngineError('Local TTS synthesis failed'));
        AnxLog.severe('LocalTts generate failed: $e');
      }
    } else if (message is _DisposeRequest) {
      tts?.free();
      tts = null;
      port.close();
    }
  });
}

sherpa_onnx.OfflineTtsConfig _buildSherpaConfig(LocalTtsEngineSpec spec) {
  return sherpa_onnx.OfflineTtsConfig(
    model: sherpa_onnx.OfflineTtsModelConfig(
      vits: sherpa_onnx.OfflineTtsVitsModelConfig(
        model: spec.modelPath,
        lexicon: spec.lexiconPaths ?? '',
        tokens: spec.tokensPath,
        dataDir: spec.dataDirPath ?? '',
        dictDir: spec.dictDirPath ?? '',
      ),
      numThreads: spec.numThreads,
      debug: false,
      provider: 'cpu',
    ),
    ruleFsts: spec.ruleFsts ?? '',
  );
}

// ============ Messages ============
// All message fields are primitives or TypedData, which are safely sendable
// between isolates.

class _GenerateRequest {
  final int sequence;
  final String text;
  final int speakerId;
  final double speed;

  const _GenerateRequest(this.sequence, this.text, this.speakerId, this.speed);
}

class _DisposeRequest {
  const _DisposeRequest();
}

class _EngineReady {
  final int numSpeakers;
  final int sampleRate;

  const _EngineReady(this.numSpeakers, this.sampleRate);
}

class _EngineDone {
  final int sequence;
  final Float32List samples;
  final int sampleRate;

  const _EngineDone(this.sequence, this.samples, this.sampleRate);
}

class _EngineError {
  final String message;

  const _EngineError(this.message);
}
