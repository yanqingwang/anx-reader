import 'dart:async';

import 'package:anx_reader/service/tts/local/local_tts_engine_spec.dart';

/// Stub engine for platforms without sherpa-onnx support (web, ohos).
class LocalTtsEngine {
  static final LocalTtsEngine instance = LocalTtsEngine._();

  LocalTtsEngine._();

  int get sampleRate => 0;

  int get numSpeakers => 0;

  String? get activeModelId => null;

  bool get isReady => false;

  Future<void> ensureReady(LocalTtsEngineSpec spec) {
    throw UnsupportedError(
        'Local TTS is not supported on this platform (web/ohos)');
  }

  Future<LocalTtsSynthesisResult> generate(
    String text, {
    required int speakerId,
    required double speed,
  }) {
    throw UnsupportedError(
        'Local TTS is not supported on this platform (web/ohos)');
  }

  Future<void> dispose() async {}
}
