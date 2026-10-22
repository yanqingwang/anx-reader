//! anx-reader 的 Rust 内核
//!
//! 通过 flutter_rust_bridge 暴露给 Flutter。阶段 1 完成 EPUB 解析内核，
//! 阶段 2 追加 sherpa_onnx 本地离线 TTS 封装。Dart 侧默认使用原实现，
//! 用户可在设置里开启 Rust backend 替换。
//!
//! flutter_rust_bridge setup（在有 Flutter SDK 的机器上执行）：
//! ```bash
//! # 1. 首次生成 Dart 桥接代码 + Rust build 脚本
//! cd code/anx-reader
//! dart run flutter_rust_bridge_codegen generate rust_core/rust.yaml
//!
//! # 2. 后续只改 Rust API 后重新生成
//! dart run flutter_rust_bridge_codegen generate rust_core/rust.yaml
//! ```
//! 生成的 Dart 代码位于 `lib/rust/`，Rust CMake 配置位于 `rust_core/native/`。

use flutter_rust_bridge::frb;
use std::path::Path;
use zip::ZipArchive;

pub mod epub;
pub mod models;
pub mod tts;

pub use models::*;

/// 打开 EPUB 文件做快速验证（主要给 Dart 侧确认路径存在且可解压）
#[frb]
pub fn epub_open(path: &str) -> Result<bool, String> {
    let p = Path::new(path);
    if !p.exists() {
        return Err(format!("EPUB file not found: {}", path));
    }
    let file = std::fs::File::open(p).map_err(|e| e.to_string())?;
    let archive = ZipArchive::new(file).map_err(|e| e.to_string())?;
    let _ = archive; // 验证通过
    Ok(true)
}

/// 从 EPUB 文件提取元数据（title / author / cover / description / language）
#[frb]
pub fn epub_metadata(path: &str) -> Result<EpubMetadata, String> {
    let doc = epub::EpubDoc::open(path)?;
    Ok(doc.metadata.clone())
}

/// 返回 spine 顺序的章节列表
#[frb]
pub fn epub_spine(path: &str) -> Result<Vec<SpineItem>, String> {
    let doc = epub::EpubDoc::open(path)?;
    Ok(doc.spine.clone())
}

/// 提取指定章节（href）的所有段落文本
#[frb]
pub fn epub_section_paragraphs(path: &str, section_href: &str) -> Result<Vec<String>, String> {
    let doc = epub::EpubDoc::open(path)?;
    let paragraphs = doc.section_paragraphs(section_href)?;
    Ok(paragraphs)
}

/// 全文搜索，返回匹配片段（用于 EPUB 书内搜索）
#[frb]
pub fn epub_search(path: &str, query: &str) -> Result<Vec<SearchHit>, String> {
    let doc = epub::EpubDoc::open(path)?;
    let hits = doc.search(query)?;
    Ok(hits)
}

// ===== TTS 阶段 2 =====

/// 初始化本地 TTS 引擎（阶段 2：占位实现，后续接 sherpa_onnx）
#[frb]
pub fn tts_engine_init(spec: TtsModelSpec) -> Result<u64, String> {
    tts::tts_engine_init(spec)
}

#[frb]
pub fn tts_engine_free(handle: u64) {
    tts::tts_engine_free(handle)
}

#[frb]
pub fn tts_generate(
    handle: u64,
    text: &str,
    speaker_id: u32,
    speed: f32,
) -> Result<WavData, String> {
    tts::tts_generate(handle, text, speaker_id, speed)
}
