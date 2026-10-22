// ignore_for_file: non_constant_identifier_names, prefer_const_constructors

/// anx-reader Rust backend 工厂入口。
///
/// 生产默认走 Dart 原实现（archive + html 解析），用户可在设置里开启 Rust backend。
/// 鸿蒙 / Web 平台自动降级（sherpa_onnx pub 包 + frb 均无鸿蒙原生库）。

import 'dart:io' as io;

import 'package:anx_reader/utils/book_metadata/epub_metadata.dart'
    as dart_impl;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:anx_reader/rust/api.dart' as rust_api;
import 'package:anx_reader/rust/frb_generated.dart';
import 'package:anx_reader/rust/models.dart' as rust_models;
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
      } catch (_) {
        // frb 未初始化、动态库缺失、解析异常 —— 自动回退 Dart
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

  factory EpubMetadataResult.fromRust({
    required rust_models.EpubMetadata meta,
    required List<rust_models.SpineItem> spine,
  }) {
    return EpubMetadataResult(
      title: meta.title,
      author: meta.author,
      description: meta.description,
      language: meta.language,
      coverDataUri: null,
      coverPath: meta.coverPath,
      spine: spine
          .map((s) => SpineItemResult(
                idref: s.idref,
                href: s.href,
                linear: s.linear,
              ))
          .toList(),
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

/// Rust backend —— 通过 flutter_rust_bridge 调用 anx_rust_core。
class _RustEpubMetadata {
  static Future<EpubMetadataResult> open(String path) async {
    await _ensureRustInit();
    final meta = await rust_api.epubMetadata(path: path);
    final spine = await rust_api.epubSpine(path: path);
    return EpubMetadataResult.fromRust(meta: meta, spine: spine);
  }

  static Future<void>? _initFuture;
  static bool _initialized = false;

  /// 确保 RustLib 只初始化一次。
  static Future<void> _ensureRustInit() async {
    if (_initialized) return;
    _initFuture ??= RustLib.init();
    await _initFuture;
    _initialized = true;
  }
}
