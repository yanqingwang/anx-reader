//! sherpa_onnx 本地离线 TTS Rust 封装。
//!
//! **重要：阶段 2 先做骨架和生命周期测试，暂不真调 sherpa_onnx C API。**
//! 等 flutter_rust_bridge 脚手架在有 Flutter SDK 的机器上通了之后，
//! 再把 sherpa_onnx-ffi crate 接进来；如果 crates.io 的 ffi crate 在 iOS/Android
//! 质量不够，就手动写 extern "C" 调 Dart pub 包里已经打好的静态库。
//!
//! 这里先定义 handle 协议 + 假实现（返回 fixture 数据），让 Dart 侧可以先接上
//! factory 而不需要等 iOS/Android 链接问题解决。

use crate::models::{TtsModelSpec, WavData};
use std::collections::HashMap;
use std::sync::Mutex;

// ---- handle 池 ---------------------------------------------------------

struct EngineSlot {
    spec: TtsModelSpec,
}

static ENGINE_POOL: Mutex<Option<HashMap<u64, EngineSlot>>> = Mutex::new(None);

fn ensure_pool() -> std::sync::MutexGuard<'static, Option<HashMap<u64, EngineSlot>>> {
    let mut guard = ENGINE_POOL.lock().unwrap();
    if guard.is_none() {
        *guard = Some(HashMap::new());
    }
    guard
}

/// 初始化本地 TTS 引擎（占位实现：只存 spec，不真调 sherpa_onnx）
///
/// 阶段 2 完成后这里会：
/// 1. 加载 sherpa_onnx 的 OnlineTtsConfig（model + lexicon + tokens + dict + rule_fsts）
/// 2. 创建 OfflineTts 实例并塞进 pool
pub fn tts_engine_init(spec: TtsModelSpec) -> Result<u64, String> {
    let mut pool = ensure_pool();
    let map = pool.as_mut().unwrap();
    // 用 model_dir + 当前 map.len() 做 hash 基，保证每次新 init 都生成不同 handle
    let seed = (spec.model_dir.len() as u64).wrapping_mul(0x9E3779B1).wrapping_add(map.len() as u64);
    let handle = simple_hash(&spec.model_dir, seed);
    // 如果碰撞了，递归重试（极小概率，但安全起见）
    if map.contains_key(&handle) {
        return Err(format!("handle collision for {}", spec.model_dir));
    }
    map.insert(handle, EngineSlot { spec });
    Ok(handle)
}

fn simple_hash(s: &str, salt: u64) -> u64 {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    let mut h = DefaultHasher::new();
    (salt, s).hash(&mut h);
    h.finish()
}

pub fn tts_engine_free(handle: u64) {
    let mut pool = ensure_pool();
    if let Some(map) = pool.as_mut() {
        map.remove(&handle);
    }
}

pub fn tts_generate(
    handle: u64,
    _text: &str,
    _speaker_id: u32,
    _speed: f32,
) -> Result<WavData, String> {
    let pool = ensure_pool();
    let exists = pool.as_ref().map(|m| m.contains_key(&handle)).unwrap_or(false);
    if !exists {
        return Err(format!("handle {} not initialized", handle));
    }
    // 占位：返回一段 1ms 的静音 16kHz PCM，让 Dart 侧能完整走通 WavData → 播放 的协议
    Ok(WavData {
        sample_rate: 16_000,
        pcm_i16_le: vec![0i16; 16], // 1ms
        duration_ms: 1,
    })
}

/// 清空所有引擎（测试/退出时用）
pub fn tts_pool_clear() {
    let mut pool = ensure_pool();
    if let Some(map) = pool.as_mut() {
        map.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_spec() -> TtsModelSpec {
        TtsModelSpec {
            model_dir: "/tmp/fake-model".to_string(),
            dict_dir: None,
            tokens_path: "/tmp/fake-model/tokens.txt".to_string(),
            lexicon_path: None,
            num_threads: 2,
        }
    }

    #[test]
    fn lifecycle_init_generate_free() {
        tts_pool_clear();
        let h = tts_engine_init(default_spec()).unwrap();
        let wav = tts_generate(h, "你好世界", 0, 1.0).unwrap();
        assert_eq!(wav.sample_rate, 16_000);
        assert!(!wav.pcm_i16_le.is_empty());
        tts_engine_free(h);
        // 再次生成应失败
        assert!(tts_generate(h, "again", 0, 1.0).is_err());
    }

    #[test]
    fn init_twice_gives_different_handles() {
        tts_pool_clear();
        let a = tts_engine_init(TtsModelSpec {
            model_dir: "/tmp/a".into(),
            ..default_spec()
        }).unwrap();
        let b = tts_engine_init(TtsModelSpec {
            model_dir: "/tmp/b".into(),
            ..default_spec()
        }).unwrap();
        assert_ne!(a, b);
        tts_pool_clear();
    }
}
