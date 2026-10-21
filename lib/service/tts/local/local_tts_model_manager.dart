import 'dart:io';

import 'package:anx_reader/service/tts/local/local_tts_model_catalog.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Root directory holding downloaded local TTS models.
///
/// Lives under the application support directory so it is excluded from
/// document sync/backup but still removed on uninstall.
Future<Directory> localTtsModelsRootDir() async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'tts-models'));
}

Future<String> localTtsModelDirPath(String modelId) async {
  final root = await localTtsModelsRootDir();
  return p.join(root.path, modelId);
}

/// Cheap check whether `<dir>/tokens.txt` and at least one `.onnx` file exist.
bool isLocalTtsModelInstalledAt(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return false;
  if (!File(p.join(dirPath, 'tokens.txt')).existsSync()) return false;
  try {
    return dir
        .listSync()
        .any((e) => e is File && e.path.toLowerCase().endsWith('.onnx'));
  } catch (_) {
    return false;
  }
}

/// Scan a downloaded model directory for the files required by sherpa-onnx.
LocalTtsModelFiles? discoverLocalTtsModelFiles(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return null;
  return _scanRoot(dirPath) ?? _scanRoot(_singleNestedRoot(dirPath));
}

String? _singleNestedRoot(String dirPath) {
  final entries = Directory(dirPath).listSync();
  final dirs = entries.whereType<Directory>().toList();
  final files = entries.whereType<File>().toList();
  if (dirs.length == 1 && files.isEmpty) return dirs.first.path;
  return null;
}

LocalTtsModelFiles? _scanRoot(String root) {
  if (!File(p.join(root, 'tokens.txt')).existsSync()) return null;

  final entries = Directory(root).listSync();

  String? modelOnnx;
  String? lexicon;
  String? dataDir;
  String? dictDir;
  final ruleFsts = <String>[];

  for (final entity in entries) {
    final name = p.basename(entity.path);
    final lower = name.toLowerCase();
    if (entity is File) {
      if (lower.endsWith('.onnx')) {
        // Prefer `model.onnx`, skip vocoders, otherwise take the first one.
        if (modelOnnx == null ||
            (lower == 'model.onnx') ||
            (_isVocoder(modelOnnx) && !_isVocoder(entity.path))) {
          modelOnnx = entity.path;
        }
      } else if (lower.startsWith('lexicon') && lower.endsWith('.txt')) {
        lexicon = lexicon == null ? entity.path : '$lexicon,${entity.path}';
      } else if (lower.endsWith('.fst')) {
        ruleFsts.add(entity.path);
      }
    } else if (entity is Directory) {
      if (lower == 'espeak-ng-data') {
        dataDir = entity.path;
      } else if (lower == 'dict') {
        dictDir = entity.path;
      }
    }
  }

  if (modelOnnx == null) return null;

  return LocalTtsModelFiles(
    modelOnnx: modelOnnx,
    tokensTxt: p.join(root, 'tokens.txt'),
    lexicon: (lexicon?.isEmpty ?? true) ? null : lexicon,
    dataDir: dataDir,
    dictDir: dictDir,
    ruleFsts: ruleFsts.isEmpty ? null : ruleFsts.join(','),
  );
}

bool _isVocoder(String path) {
  final lower = path.toLowerCase();
  return lower.contains('vocoder') ||
      lower.contains('hifigan') ||
      lower.contains('vocos');
}

// ============ Download & extract ============

final Dio _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 20),
  // Model archives are large; do not time out the whole transfer.
  receiveTimeout: null,
));

/// Download and install [modelId] into the models root directory.
///
/// Tries direct GitHub first, then the configured mirrors. Extracts the
/// tar.bz2 archive and normalizes the directory layout so that
/// `<modelsRoot>/<modelId>/` contains the model files directly.
Future<void> downloadAndInstallLocalTtsModel(
  String modelId, {
  void Function(double progress)? onProgress,
  CancelToken? cancelToken,
}) async {
  final entry = findLocalTtsModel(modelId);
  if (entry == null) {
    throw ArgumentError('Unknown local TTS model: $modelId');
  }

  final root = await localTtsModelsRootDir();
  await root.create(recursive: true);

  final archivePath = p.join(root.path, '$modelId.tar.bz2');
  final extractDir = Directory(p.join(root.path, '.tmp-$modelId'));
  final targetDir = Directory(p.join(root.path, modelId));

  if (targetDir.existsSync()) {
    throw StateError('Model already installed: $modelId');
  }

  Object? lastError;
  var downloaded = false;
  for (final url in downloadUrlsFor(entry)) {
    try {
      AnxLog.info('Downloading local TTS model from $url');
      await _dio.download(
        url,
        archivePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (onProgress == null || total <= 0) return;
          onProgress((received / total).clamp(0.0, 1.0));
        },
      );
      downloaded = true;
      break;
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) rethrow;
      lastError = e;
      AnxLog.warning('Download failed for $url: $e');
    }
  }

  if (!downloaded) {
    throw Exception('Failed to download local TTS model $modelId: $lastError');
  }

  try {
    if (extractDir.existsSync()) {
      extractDir.deleteSync(recursive: true);
    }
    extractDir.createSync(recursive: true);

    await extractTarBz2(archivePath, extractDir.path);

    final modelRoot = _singleNestedRoot(extractDir.path) ?? extractDir.path;
    _moveDirectory(Directory(modelRoot), targetDir);

    if (!isLocalTtsModelInstalledAt(targetDir.path)) {
      throw Exception('Model archive is missing required files');
    }
    AnxLog.info('Installed local TTS model to ${targetDir.path}');
  } finally {
    if (extractDir.existsSync()) {
      try {
        extractDir.deleteSync(recursive: true);
      } catch (_) {}
    }
    final archiveFile = File(archivePath);
    if (archiveFile.existsSync()) {
      try {
        archiveFile.deleteSync();
      } catch (_) {}
    }
  }
}

/// Decompress a .tar.bz2 archive into [destDir].
Future<void> extractTarBz2(String archivePath, String destDir) async {
  final input = InputFileStream(archivePath);
  final tarBytes = BZip2Decoder().decodeBuffer(input);
  input.close();

  final tar = TarDecoder().decodeBytes(tarBytes);
  for (final entry in tar.files) {
    if (!entry.isFile) continue;
    final name = entry.name.replaceAll('\\', '/');
    if (name.contains('..')) continue; // path traversal guard
    final outPath = p.join(destDir, name);
    final outFile = File(outPath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(entry.content as List<int>, flush: true);
  }
}

void _moveDirectory(Directory source, Directory target) {
  if (target.existsSync()) {
    target.deleteSync(recursive: true);
  }
  try {
    source.renameSync(target.path);
  } catch (_) {
    _copyDirectory(source, target);
    source.deleteSync(recursive: true);
  }
}

void _copyDirectory(Directory source, Directory target) {
  target.createSync(recursive: true);
  for (final entity in source.listSync()) {
    final newPath = p.join(target.path, p.basename(entity.path));
    if (entity is Directory) {
      _copyDirectory(entity, Directory(newPath));
    } else if (entity is File) {
      entity.copySync(newPath);
    }
  }
}

/// Delete an installed model directory.
Future<void> deleteLocalTtsModel(String modelId) async {
  final root = await localTtsModelsRootDir();
  final dir = Directory(p.join(root.path, modelId));
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
}

// ============ Riverpod state ============

enum LocalTtsModelPhase { notInstalled, downloading, extracting, installed, failed }

class LocalTtsModelStatus {
  final LocalTtsModelPhase phase;
  final double progress;
  final String? error;

  const LocalTtsModelStatus({
    required this.phase,
    this.progress = 0,
    this.error,
  });
}

/// Tracks install/download state for every catalog model.
class LocalTtsModelsNotifier
    extends StateNotifier<Map<String, LocalTtsModelStatus>> {
  LocalTtsModelsNotifier() : super(const {}) {
    refreshInstalled();
  }

  final Map<String, CancelToken> _cancelTokens = {};

  bool isDownloading(String modelId) =>
      state[modelId]?.phase == LocalTtsModelPhase.downloading;

  /// Rescan every catalog model and update install state. In-flight
  /// downloads/extracts are never overwritten.
  Future<void> refreshInstalled() async {
    for (final entry in kLocalTtsModelCatalog) {
      final current = state[entry.id];
      if (current != null &&
          (current.phase == LocalTtsModelPhase.downloading ||
              current.phase == LocalTtsModelPhase.extracting)) {
        continue;
      }
      final dirPath = await localTtsModelDirPath(entry.id);
      final installed = isLocalTtsModelInstalledAt(dirPath);
      final phase = installed
          ? LocalTtsModelPhase.installed
          : LocalTtsModelPhase.notInstalled;
      if (state[entry.id]?.phase != phase) {
        _setStatus(entry.id, LocalTtsModelStatus(phase: phase));
      }
    }
  }

  Future<void> download(String modelId) async {
    if (isDownloading(modelId)) return;
    final cancelToken = CancelToken();
    _cancelTokens[modelId] = cancelToken;
    _setStatus(modelId, const LocalTtsModelStatus(
      phase: LocalTtsModelPhase.downloading,
    ));

    try {
      await downloadAndInstallLocalTtsModel(
        modelId,
        cancelToken: cancelToken,
        onProgress: (progress) {
          if (state[modelId]?.phase == LocalTtsModelPhase.downloading) {
            _setStatus(modelId,
                LocalTtsModelStatus(phase: LocalTtsModelPhase.downloading, progress: progress));
          }
        },
      );
      await refreshInstalled();
    } catch (e) {
      if (cancelToken.isCancelled) {
        await refreshInstalled();
        return;
      }
      AnxLog.severe('Local TTS model download failed: $e');
      _setStatus(modelId, LocalTtsModelStatus(
        phase: LocalTtsModelPhase.failed,
        error: e.toString(),
      ));
    } finally {
      _cancelTokens.remove(modelId);
    }
  }

  void cancelDownload(String modelId) {
    _cancelTokens[modelId]?.cancel();
  }

  Future<void> delete(String modelId) async {
    if (isDownloading(modelId)) return;
    await deleteLocalTtsModel(modelId);
    _setStatus(modelId, const LocalTtsModelStatus(
      phase: LocalTtsModelPhase.notInstalled,
    ));
  }

  void _setStatus(String modelId, LocalTtsModelStatus status) {
    state = {...state, modelId: status};
  }
}

final localTtsModelsProvider =
    StateNotifierProvider<LocalTtsModelsNotifier, Map<String, LocalTtsModelStatus>>(
        (ref) {
  return LocalTtsModelsNotifier();
});
