mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */

// anx-reader 的 Rust 内核
//
// 通过 flutter_rust_bridge 暴露给 Flutter。阶段 1 完成 EPUB 解析内核，
// 阶段 2 追加 sherpa_onnx 本地离线 TTS 封装。Dart 侧默认使用原实现，
// 用户可在设置里开启 Rust backend 替换。
//
// flutter_rust_bridge setup（在有 Flutter SDK 的机器上执行）：
// ```bash
// cd code/anx-reader
// flutter_rust_bridge_codegen generate \
//   --rust-input crate::api \
//   --rust-root rust_core \
//   --rust-output rust_core/src/frb_generated.rs \
//   --dart-output lib/rust \
//   --c-output rust_core/native/frb_generated.h
// ```
// 生成的 Dart 代码位于 `lib/rust/`，Rust CMake 配置位于 `rust_core/native/`。

pub mod api;
pub mod epub;
pub mod models;
pub mod tts;

pub use models::*;
