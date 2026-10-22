// anx-reader Rust 内核对外 API
//
// 所有 flutter_rust_bridge 暴露的函数集中在这里，通过 `#[frb]` 标注。
// dart 侧通过 anx_rust_core crate 调用。

use flutter_rust_bridge::frb;
use std::path::Path;
use zip::ZipArchive;

use crate::models::*;

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
    let doc = crate::epub::EpubDoc::open(path)?;
    Ok(doc.metadata.clone())
}

/// 返回 spine 顺序的章节列表
#[frb]
pub fn epub_spine(path: &str) -> Result<Vec<SpineItem>, String> {
    let doc = crate::epub::EpubDoc::open(path)?;
    Ok(doc.spine.clone())
}

/// 提取指定章节（href）的所有段落文本
#[frb]
pub fn epub_section_paragraphs(path: &str, section_href: &str) -> Result<Vec<String>, String> {
    let doc = crate::epub::EpubDoc::open(path)?;
    let paragraphs = doc.section_paragraphs(section_href)?;
    Ok(paragraphs)
}

/// 全文搜索，返回匹配片段（用于 EPUB 书内搜索）
#[frb]
pub fn epub_search(path: &str, query: &str) -> Result<Vec<SearchHit>, String> {
    let doc = crate::epub::EpubDoc::open(path)?;
    let hits = doc.search(query)?;
    Ok(hits)
}

// ===== TTS =====

/// 初始化本地 TTS 引擎
#[frb]
pub fn tts_engine_init(spec: TtsModelSpec) -> Result<u64, String> {
    crate::tts::tts_engine_init(spec)
}

#[frb]
pub fn tts_engine_free(handle: u64) {
    crate::tts::tts_engine_free(handle)
}

#[frb]
pub fn tts_generate(
    handle: u64,
    text: &str,
    speaker_id: u32,
    speed: f32,
) -> Result<WavData, String> {
    crate::tts::tts_generate(handle, text, speaker_id, speed)
}
