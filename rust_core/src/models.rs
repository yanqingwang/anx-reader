//! 跨 FFI 边界的数据结构。
//!
//! flutter_rust_bridge 要求这些结构体满足类型约束（字段必须是基础类型或 Vec/Tuple）。
//! 这里用纯 Rust struct + #[derive(Clone, Debug, Default)]，不加 Serialize ——
//! frb 会自己生成 FFI 适配层。

#[derive(Clone, Debug, Default)]
pub struct EpubMetadata {
    pub title: String,
    pub author: String,
    pub description: String,
    pub language: String,
    /// cover image 在 zip 中的内部路径（可以用来解压出来）
    pub cover_path: Option<String>,
    pub opf_path: String,
}

#[derive(Clone, Debug)]
pub struct SpineItem {
    /// OPF manifest 里的 id
    pub idref: String,
    /// zip 内部 href，相对 OPF 所在目录
    pub href: String,
    /// 线性阅读顺序（linear="yes"/"no"）
    pub linear: bool,
}

#[derive(Clone, Debug)]
pub struct SearchHit {
    pub section_href: String,
    /// 命中字符在该 section 内的偏移
    pub offset: usize,
    pub snippet: String,
}

// ===== TTS 阶段 2 =====

#[derive(Clone, Debug, Default)]
pub struct WavData {
    pub sample_rate: u32,
    /// 单声道 16-bit PCM（i16 LE）字节序列
    pub pcm_i16_le: Vec<i16>,
    pub duration_ms: u32,
}

#[derive(Clone, Debug)]
pub struct TtsModelSpec {
    pub model_dir: String,
    pub dict_dir: Option<String>,
    pub tokens_path: String,
    pub lexicon_path: Option<String>,
    pub num_threads: u32,
}
