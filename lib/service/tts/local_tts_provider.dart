import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:flutter/widgets.dart';

/// Provider for the local (offline) TTS service.
///
/// The service needs no connection config; the selected voice is stored as
/// `<modelId>#<speakerId>` via the standard per-service voice preference.
class LocalTtsProvider extends TtsServiceProvider {
  static final LocalTtsProvider _instance = LocalTtsProvider._internal();

  factory LocalTtsProvider() {
    return _instance;
  }

  LocalTtsProvider._internal();

  @override
  TtsService get service => TtsService.local;

  @override
  String getLabel(BuildContext context) =>
      L10n.of(context).settingsNarrateLocalTts;
}
