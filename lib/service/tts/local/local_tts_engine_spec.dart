import 'dart:typed_data';

/// Plain-data spec describing a local TTS model for the engine isolate.
///
/// Kept free of any sherpa-onnx imports so the stub implementation (web/ohos)
/// can share the same interface without pulling in native bindings.
class LocalTtsEngineSpec {
  /// Id of the model, used to detect engine reloads.
  final String modelId;

  /// Absolute path to the `.onnx` model file.
  final String modelPath;

  /// Absolute path to `tokens.txt`.
  final String tokensPath;

  /// Comma-joined lexicon file paths, or null.
  final String? lexiconPaths;

  /// espeak-ng-data directory, or null.
  final String? dataDirPath;

  /// jieba dict directory, or null.
  final String? dictDirPath;

  /// Comma-joined rule fst paths, or null.
  final String? ruleFsts;

  final int numThreads;

  const LocalTtsEngineSpec({
    required this.modelId,
    required this.modelPath,
    required this.tokensPath,
    this.lexiconPaths,
    this.dataDirPath,
    this.dictDirPath,
    this.ruleFsts,
    this.numThreads = 2,
  });
}

/// Synthesis output of the engine.
class LocalTtsSynthesisResult {
  final Float32List samples;
  final int sampleRate;

  const LocalTtsSynthesisResult({
    required this.samples,
    required this.sampleRate,
  });
}
