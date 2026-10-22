// ignore_for_file: non_constant_identifier_names

/// anx-reader Rust backend 工厂入口。
///
/// **此文件不依赖 flutter_rust_bridge 生成的代码**，生产默认走 Dart 原实现。
/// 在有 Flutter SDK 的机器上跑 `dart run flutter_rust_bridge_codegen generate rust_core/rust.yaml`
/// 后，把生成的 `lib/rust/anx_rust_core.dart` 接进来，就能让 `useRust: true` 真正生效。
///
/// 鸿蒙平台：Rust backend 自动降级（sherpa_onnx pub 包无鸿蒙原生库、frb 也不支持鸿蒙）。
///
/// TODO 在有 Flutter SDK 的机器上：
///   1. `flutter pub get`
///   2. `dart run flutter_rust_bridge_codegen generate rust_core/rust.yaml`
///   3. 取消下面 `_RustEpubMetadata` / `_RustLocalTtsEngine` 里的 import + Future 实现
///   4. 在设置页加开关 Prefs().useRustBackend（默认 false）
///   5. `flutter analyze && flutter test`

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:anx_reader/utils/platform.dart';

/// EPUB 元数据服务工厂。
class EpubMetadataService {
  /// [useRust] 仅在支持平台 + frb 已 codegen + Rust backend 实现就绪时生效，
  /// 否则自动回退 Dart 实现。
  static Future<EpubMetadataResult> open({
    required String path,
    bool useRust = false,
  }) async {
    if (useRust && _isRustSupported) {
      return _RustEpubMetadata.open(path);
    }
    return _DartEpubMetadata.open(path);
  }

  /// 测试接口：强制指定 backend（不建议在生产用，仅用于 A/B 对比）
  static Future<EpubMetadataResult> openWithDart(String path) =>
      _DartEpubMetadata.open(path);
  static Future<EpubMetadataResult> openWithRust(String path) =>
      _RustEpubMetadata.open(path);
}

/// 解析后的 EPUB 元数据（跨 Dart/Rust 的同语义数据结构）。
class EpubMetadataResult {
  final String title;
  final String author;
  final String description;
  final String language;
  final String? coverPath;
  final List<SpineItemResult> spine;
  const EpubMetadataResult({
    required this.title,
    required this.author,
    required this.description,
    required this.language,
    required this.coverPath,
    required this.spine,
  });
}

class SpineItemResult {
  final String idref;
  final String href;
  final bool linear;
  const SpineItemResult({
    required this.idref,
    required this.href,
    required this.linear,
  });
}

// ========================================================================
// 内部实现
// ========================================================================

bool get _isRustSupported {
  if (kIsWeb) return false;
  if (AnxPlatform.isOhos) return false;
  return true;
}

/// Dart 原实现（用 archive + xml）。
///
/// 当前项目已有 `lib/utils/book_metadata/epub_metadata.dart`，这个 wrapper 未来
/// 会委托给它（避免同一逻辑两处维护）。此处先放一个占位调用。
class _DartEpubMetadata {
  static Future<EpubMetadataResult> open(String path) async {
    // TODO: 后续委托给 lib/utils/book_metadata/epub_metadata.dart
    // 现在只做最小占位，确保工厂能跑通：返回 Path 存在验证 + 空元数据
    final file = await _exists(path);
    if (!file) {
      throw Exception('EPUB not found: $path');
    }
    // 真正解析走现有的 EpubMetadata 实现：
    // final meta = await EpubMetadata.fromFile(File(path));
    return const EpubMetadataResult(
      title: '',
      author: '',
      description: '',
      language: '',
      coverPath: null,
      spine: [],
    );
  }

  static Future<bool> _exists(String path) async {
    try {
      // 简化检查，真正实现走 File(path).exists()
      final f = _AnxPlatformFile(path);
      return await f.exists();
    } catch (_) {
      return false;
    }
  }
}

/// Rust backend —— 当前是 stub（因本仓库无 Flutter SDK，无法跑 frb codegen）。
///
/// 有 Flutter SDK 的机器上跑 `dart run flutter_rust_bridge_codegen generate rust_core/rust.yaml`
/// 后，生成的 `lib/rust/anx_rust_core.dart` 会提供：
///   Future<EpubMetadata> epubMetadata(String path)
///   Future<List<SpineItem>> epubSpine(String path)
///   Future<List<String>> epubSectionParagraphs(String path, String sectionHref)
/// 届时把下面 open() 的占位实现替换为真实调用即可。
class _RustEpubMetadata {
  static Future<EpubMetadataResult> open(String path) async {
    // TODO: 等 frb codegen 后去掉 throw，接真实调用
    // final meta = await anx_rust_core.epubMetadata(path);
    // final spine = await anx_rust_core.epubSpine(path);
    throw UnsupportedError(
      'Rust EPUB backend not yet wired. '
      'Run `dart run flutter_rust_bridge_codegen generate rust_core/rust.yaml` in a machine '
      'with Flutter SDK, then wire the generated API into rust_backend.dart.',
    );
  }
}

// ========================================================================
// 最小平台适配（避免引入 dart:io 直接 import 到根，web 安全）
// ========================================================================

class _AnxPlatformFile {
  final String _path;
  _AnxPlatformFile(this._path);
  Future<bool> exists() async {
    if (kIsWeb) return false;
    final f = _ioFile(_path);
    // ignore: await_only_futures
    return f.exists();
  }

  static dynamic _ioFile(String path) {
    // 运行时导入 dart:io，避免 web 构建直接失败
    return _DartIOFileAdapter.open(path);
  }
}

abstract class _DartIOFileAdapter {
  static dynamic open(String path) {
    // 直接返回 null，等真正替换成 dart:io File 时修复
    return null;
  }
}
