// ignore_for_file: non_constant_identifier_names, prefer_const_constructors

/// anx-reader Rust backend 工厂入口。
///
/// 生产默认走 Dart 原实现（archive + html 解析），用户可在设置里开启 Rust backend。
/// 鸿蒙 / Web 平台自动降级（sherpa_onnx pub 包 + frb 均无鸿蒙原生库）。
///
/// 接入 flutter_rust_bridge 的步骤（需 Flutter SDK）：
///   1. flutter pub get
///   2. dart run flutter_rust_bridge_codegen generate rust_core/rust.yaml
///   3. 取消下面 _RustEpubMetadata 里的 stub throw，接 anx_rust_core.epubMetadata()
///   4. 加 Prefs().useRustBackend 开关（默认 false）
///   5. 在 epub_metadata.dart 的公共入口处把调用换成本工厂
///   6. flutter analyze && flutter test

import 'dart:io' as io;

import 'package:anx_reader/utils/book_metadata/epub_metadata.dart'
    as dart_impl;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:anx_reader/utils/platform_utils.dart';

/// EPUB 元数据服务工厂。
///
/// [useRust] 仅在支持平台 + Rust backend 已 codegen 且实现就绪时生效，
/// 否则自动回退 Dart 原实现。鸿蒙/Web 永远走 Dart。
class EpubMetadataService {
  static Future<EpubMetadataResult> open({
    required String path,
    bool useRust = false,
  }) async {
    if (useRust && _isRustSupported) {
      try {
        return await _RustEpubMetadata.open(path);
      } on UnsupportedError {
        // frb 还没接或平台不支持，自动回退
        return _DartEpubMetadata.open(path);
      } catch (_) {
        return _DartEpubMetadata.open(path);
      }
    }
    return _DartEpubMetadata.open(path);
  }

  /// A/B 对比接口：强制指定 backend
  static Future<EpubMetadataResult> openWithDart(String path) =>
      _DartEpubMetadata.open(path);
  static Future<EpubMetadataResult> openWithRust(String path) =>
      _RustEpubMetadata.open(path);
}

bool get _isRustSupported {
  if (kIsWeb) return false;
  if (AnxPlatform.isOhos) return false;
  return true;
}

// ========================================================================
// 结果结构
// ========================================================================

/// 跨 Dart / Rust 的同语义元数据（比原 dart_impl.EpubMetadata 多了 spine）。
class EpubMetadataResult {
  final String title;
  final String author;
  final String description;
  final String language;
  final String? coverDataUri; // dart 实现返回的 data:URI 字符串
  final String? coverPath; // Rust 实现返回的 zip 内部路径
  final List<SpineItemResult> spine;

  const EpubMetadataResult({
    required this.title,
    required this.author,
    required this.description,
    required this.language,
    required this.coverDataUri,
    required this.coverPath,
    required this.spine,
  });

  factory EpubMetadataResult.fromDart(dart_impl.EpubMetadata src) {
    return EpubMetadataResult(
      title: src.title,
      author: src.author,
      description: src.description,
      language: 'zh', // dart 实现当前没暴露 language 字段，默认 zh
      coverDataUri: src.cover.isEmpty ? null : src.cover,
      coverPath: null,
      spine: const [], // dart 实现没暴露 spine，Rust 有
    );
  }
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

/// Dart 原实现（archive + html）。真实调用 [dart_impl.readEpubMetadata]。
class _DartEpubMetadata {
  static Future<EpubMetadataResult> open(String path) async {
    if (!await io.File(path).exists()) {
      throw Exception('EPUB not found: $path');
    }
    final meta = await dart_impl.readEpubMetadata(io.File(path));
    return EpubMetadataResult.fromDart(meta);
  }
}

/// Rust backend —— 当前是 stub（需 frb codegen）。
///
/// 有 Flutter SDK 的机器上跑：
///   dart run flutter_rust_bridge_codegen generate rust_core/rust.yaml
/// 之后会生成 anx_rust_core.dart，提供：
///   Future<EpubMetadata> epubMetadata(String path)
///   Future<List<SpineItem>> epubSpine(String path)
/// 那时把下面 throw 替换为真实调用。
class _RustEpubMetadata {
  static Future<EpubMetadataResult> open(String path) async {
    // TODO: frb codegen 后接真实调用
    // final meta = await anx_rust_core.epubMetadata(path);
    // final spine = await anx_rust_core.epubSpine(path);
    throw UnsupportedError(
      'Rust EPUB backend not yet wired. '
      'Run `dart run flutter_rust_bridge_codegen generate rust_core/rust.yaml` '
      'in a machine with Flutter SDK, then wire into rust_backend.dart.',
    );
  }
}
