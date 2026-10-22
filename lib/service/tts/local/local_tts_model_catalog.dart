/// Catalog of curated offline TTS models for the local (on-device) TTS engine.
///
/// Models are hosted on the k2-fsa/sherpa-onnx `tts-models` GitHub release and
/// downloaded at runtime. This file is pure Dart (no Flutter, no dart:io) so it
/// can be unit-tested and imported from any layer.
library;

class LocalTtsModelCatalogEntry {
  /// Model id, also used as the archive name on the release page
  /// (e.g. `vits-melo-tts-zh_en.tar.bz2`) and as the on-disk folder name.
  final String id;

  final String displayName;

  /// Human readable languages, e.g. `中文/English`.
  final String languages;

  /// Primary locale used when building voice entries, e.g. `zh-CN`.
  final String locale;

  /// Approximate archive size in MB, for display only.
  final int approxSizeMb;

  /// Number of speakers reported by the model.
  final int numSpeakers;

  /// Optional speaker id -> display name mapping. Missing ids fall back to
  /// a generic `Speaker <id>` label.
  final Map<int, String> speakerNames;

  /// Whether this model should be suggested as the first download.
  final bool isDefault;

  final String description;

  const LocalTtsModelCatalogEntry({
    required this.id,
    required this.displayName,
    required this.languages,
    required this.locale,
    required this.approxSizeMb,
    required this.numSpeakers,
    this.speakerNames = const {},
    this.isDefault = false,
    this.description = '',
  });

  String? speakerName(int speakerId) => speakerNames[speakerId];
}

/// Curated model catalog, ordered by recommendation.
const List<LocalTtsModelCatalogEntry> kLocalTtsModelCatalog = [
  LocalTtsModelCatalogEntry(
    id: 'vits-melo-tts-zh_en',
    displayName: 'MeloTTS 中英双语',
    languages: '中文/English',
    locale: 'zh-CN',
    approxSizeMb: 170,
    numSpeakers: 1,
    speakerNames: {0: 'Melo 中文女声'},
    isDefault: true,
    description: '中英混合朗读，效果自然，适合中文书籍',
  ),
  LocalTtsModelCatalogEntry(
    id: 'vits-zh-hf-fanchen-C',
    displayName: 'Fanchen 中文多音色',
    languages: '中文',
    locale: 'zh-CN',
    approxSizeMb: 70,
    numSpeakers: 187,
    description: '轻量中文模型，提供多种音色可选',
  ),
  LocalTtsModelCatalogEntry(
    id: 'vits-piper-en_US-amy-medium',
    displayName: 'Piper English (Amy)',
    languages: 'English',
    locale: 'en-US',
    approxSizeMb: 63,
    numSpeakers: 1,
    speakerNames: {0: 'Amy'},
    description: '轻量英文模型，合成速度快',
  ),
];

LocalTtsModelCatalogEntry? findLocalTtsModel(String id) {
  for (final entry in kLocalTtsModelCatalog) {
    if (entry.id == id) return entry;
  }
  return null;
}

LocalTtsModelCatalogEntry get defaultLocalTtsModel =>
    kLocalTtsModelCatalog.firstWhere((e) => e.isDefault,
        orElse: () => kLocalTtsModelCatalog.first);

/// Mirror prefixes tried in order when downloading models. Empty prefix means
/// the direct GitHub URL.
const List<String> kLocalTtsModelMirrorPrefixes = [
  '',
  'https://ghfast.top/',
  'https://gh-proxy.com/',
];

const String _kModelBaseUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

/// All candidate download URLs for a model, in try order.
List<String> downloadUrlsFor(LocalTtsModelCatalogEntry entry) =>
    kLocalTtsModelMirrorPrefixes
        .map((prefix) => '$prefix$_kModelBaseUrl/${entry.id}.tar.bz2')
        .toList();

/// Voice ids encode both the model and the speaker:
/// `<modelId>#<speakerId>`, e.g. `vits-melo-tts-zh_en#0`.
String localTtsVoiceId(String modelId, int speakerId) =>
    '$modelId#$speakerId';

({String modelId, int speakerId})? parseLocalTtsVoiceId(String voiceId) {
  // Use lastIndexOf so model ids that themselves contain '#' are handled
  // correctly (voiceId format: <modelId>#<speakerId>, speakerId is always
  // the last segment).
  final index = voiceId.lastIndexOf('#');
  if (index <= 0 || index == voiceId.length - 1) return null;
  final speakerId = int.tryParse(voiceId.substring(index + 1));
  if (speakerId == null || speakerId < 0) return null;
  return (modelId: voiceId.substring(0, index), speakerId: speakerId);
}
