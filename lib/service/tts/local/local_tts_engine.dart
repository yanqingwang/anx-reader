/// Conditional export of the local TTS engine.
///
/// `dart.library.io` is true on every native target (android/ios/macos/
/// windows/linux) and false on web, where the native sherpa-onnx bindings are
/// unavailable. The stub keeps web compilation working; ohos has no sherpa
/// plugin either but `io` is available there, so LocalTts additionally checks
/// the platform at runtime.
export 'local_tts_engine_stub.dart'
    if (dart.library.io) 'local_tts_engine_native.dart';
