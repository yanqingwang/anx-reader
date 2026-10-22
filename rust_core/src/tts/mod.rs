//! sherpa_onnx 本地离线 TTS Rust 封装。
//!
//! 使用 crates.io 的 `sherpa-onnx = "1.13.8"` safe wrapper。
//! 生命周期：init(handle) → generate → free
//! OfflineTts 内部持有 ONNX runtime session，构造重，不可 Clone。本模块用
//! Box<OfflineTts> 存入 Mutex<HashMap<u64, Box<OfflineTts>>>，generate 通过
//! &OfflineTts 借用共享。

use crate::models::{TtsModelSpec, WavData};
use std::collections::HashMap;
use std::sync::Mutex;

static ENGINE_POOL: Mutex<Option<HashMap<u64, Box<sherpa_onnx::OfflineTts>>>> = Mutex::new(None);

fn ensure_pool(
) -> std::sync::MutexGuard<'static, Option<HashMap<u64, Box<sherpa_onnx::OfflineTts>>>> {
    let mut guard = ENGINE_POOL.lock().unwrap();
    if guard.is_none() {
        *guard = Some(HashMap::new());
    }
    guard
}

pub fn tts_engine_init(spec: TtsModelSpec) -> Result<u64, String> {
    let mut pool = ensure_pool();
    let map = pool.as_mut().unwrap();
    let handle = compute_handle(&spec.model_dir);
    if map.contains_key(&handle) {
        return Ok(handle); // 已存在
    }

    let config = build_config(&spec)?;
    let tts = sherpa_onnx::OfflineTts::create(&config)
        .ok_or_else(|| "sherpa_onnx OfflineTts::create returned None".to_string())?;

    map.insert(handle, Box::new(tts));
    Ok(handle)
}

fn compute_handle(s: &str) -> u64 {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    let mut h = DefaultHasher::new();
    s.hash(&mut h);
    h.finish()
}

fn build_config(spec: &TtsModelSpec) -> Result<sherpa_onnx::OfflineTtsConfig, String> {
    // 找到 .onnx 文件（Piper 模型名是 en_US-lessac-low.onnx，不一定叫 model.onnx）
    let onnx_path = std::fs::read_dir(&spec.model_dir)
        .map_err(|e| format!("model_dir not found {}: {}", spec.model_dir, e))?
        .flatten()
        .map(|e| e.path())
        .find(|p| {
            p.extension()
                .map(|e| e == "onnx")
                .unwrap_or(false)
        })
        .ok_or_else(|| format!("no .onnx in {}", spec.model_dir))?;

    let tokens = resolve(&spec.tokens_path, Some("tokens.txt"), &spec.model_dir)?;
    let data_dir = spec.data_dir.clone().or_else(|| {
        // Piper 模型用 espeak-ng-data
        let espeak = format!("{}/espeak-ng-data", spec.model_dir);
        if std::path::Path::new(&espeak).exists() {
            Some(espeak)
        } else {
            None
        }
    });
    let dict_dir = spec.dict_dir.clone();
    let lexicon = spec.lexicon_path.clone();

    let vits = sherpa_onnx::OfflineTtsVitsModelConfig {
        model: Some(onnx_path.to_string_lossy().to_string()),
        tokens: Some(tokens),
        data_dir,
        dict_dir,
        lexicon,
        ..Default::default()
    };

    let model_config = sherpa_onnx::OfflineTtsModelConfig {
        vits,
        num_threads: spec.num_threads.max(1) as i32,
        debug: false,
        provider: None,
        ..Default::default()
    };

    Ok(sherpa_onnx::OfflineTtsConfig {
        model: model_config,
        rule_fsts: None,
        rule_fars: None,
        max_num_sentences: 2,
        silence_scale: 0.2,
    })
}

fn resolve(
    explicit: &str,
    fallback_name: Option<&str>,
    model_dir: &str,
) -> Result<String, String> {
    if std::path::Path::new(explicit).exists() {
        return Ok(explicit.to_string());
    }
    if let Some(name) = fallback_name {
        let candidate = format!("{}/{}", model_dir, name);
        if std::path::Path::new(&candidate).exists() {
            return Ok(candidate);
        }
    }
    Err(format!(
        "file not found: explicit={:?} fallback={:?} dir={}",
        explicit, fallback_name, model_dir
    ))
}

pub fn tts_engine_free(handle: u64) {
    let mut pool = ensure_pool();
    if let Some(map) = pool.as_mut() {
        map.remove(&handle); // Box<OfflineTts> drop → 内部 raw ptr 自动清理
    }
}

pub fn tts_generate(
    handle: u64,
    text: &str,
    speaker_id: u32,
    speed: f32,
) -> Result<WavData, String> {
    let audio = {
        let mut pool = ensure_pool();
        let map = pool.as_mut().unwrap();
        let tts = map
            .get(&handle)
            .ok_or_else(|| format!("handle {} not initialized", handle))?;
        let gen_config = sherpa_onnx::GenerationConfig {
            speed,
            sid: speaker_id as i32,
            ..Default::default()
        };
        // 第三个参数是流式回调（每产生一批 chunk 时调用），我们不需要流式播放，
        // 传一个始终返回 true 的空闭包让 sherpa-onnx 一次性完整生成。
        (&**tts)
            .generate_with_config(text, &gen_config, Some(|_: &[f32], _: f32| true))
            .ok_or_else(|| format!("generate returned None for text: {}", text))?
    };

    let samples = audio.samples();
    let sample_rate = audio.sample_rate();
    let duration_ms = if sample_rate > 0 && !samples.is_empty() {
        (samples.len() as u32 * 1000 / sample_rate as u32)
    } else {
        0
    };

    let pcm: Vec<i16> = samples
        .iter()
        .map(|s| (s.clamp(-1.0, 1.0) * 32767.0) as i16)
        .collect();

    Ok(WavData {
        sample_rate: sample_rate as u32,
        pcm_i16_le: pcm,
        duration_ms,
    })
}

pub fn tts_pool_clear() {
    let mut pool = ensure_pool();
    if let Some(map) = pool.as_mut() {
        map.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec() -> TtsModelSpec {
        let dir = format!(
            "{}/test_data/models/vits-piper-en_US-lessac-low",
            env!("CARGO_MANIFEST_DIR")
        );
        TtsModelSpec {
            model_dir: dir,
            dict_dir: None,
            tokens_path: format!(
                "{}/test_data/models/vits-piper-en_US-lessac-low/tokens.txt",
                env!("CARGO_MANIFEST_DIR")
            ),
            lexicon_path: None,
            data_dir: None,
            num_threads: 2,
        }
    }

    #[test]
    fn init_generate_free_real_piper() {
        tts_pool_clear();
        let h = tts_engine_init(spec()).expect("init");
        let wav = tts_generate(h, "Hello world. Rust + sherpa_onnx works.", 0, 1.0)
            .expect("generate");
        eprintln!(
            "  sample_rate={}, frames={}, duration_ms={}, max_amp={}",
            wav.sample_rate,
            wav.pcm_i16_le.len(),
            wav.duration_ms,
            wav.pcm_i16_le.iter().max().copied().unwrap_or(0)
        );

        assert!(wav.sample_rate > 0);
        assert!(!wav.pcm_i16_le.is_empty());
        assert!(
            wav.duration_ms > 50,
            "duration={} should be real speech",
            wav.duration_ms
        );
        // 振幅不应该全 0（全 0 = 静音 = 没真生成）
        let max_amp = wav.pcm_i16_le.iter().map(|x| x.unsigned_abs()).max().unwrap_or(0);
        assert!(max_amp > 500, "max amplitude too low: {}", max_amp);

        tts_engine_free(h);
    }

    #[test]
    fn bad_path_init_fails() {
        tts_pool_clear();
        let mut s = spec();
        s.model_dir = "/tmp/nonexistent".to_string();
        assert!(tts_engine_init(s).is_err());
    }

    #[test]
    fn unknown_handle_is_err() {
        tts_pool_clear();
        assert!(tts_generate(0xDEADBEEF, "x", 0, 1.0).is_err());
    }
}
