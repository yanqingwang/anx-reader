# anx_rust_core — Rust 内核

anx-reader 渐进式 Rust 重构的 Rust crate。通过 `flutter_rust_bridge v2` 暴露给 Flutter。

## 目录结构

```
rust_core/
  Cargo.toml
  rust.yaml                      # flutter_rust_bridge 配置
  src/
    lib.rs                       # #[frb] 入口
    models.rs                    # 跨 FFI 数据结构
    epub/                        # EPUB 解析内核
      mod.rs                     # EpubDoc 主入口
      container.rs                # META-INF/container.xml 解析
      opf.rs                     # OPF manifest/spine/metadata 解析
      sections.rs                # XHTML 段落抽取
    tts/
      mod.rs                     # sherpa_onnx 封装（阶段 2）
  test_data/                     # cargo test fixture（当前用临时文件动态生成）
```

## Rust 侧测试（本机能跑）

```bash
cd rust_core
cargo test                       # 所有测试，当前 9 个全绿
cargo build --release            # release 构建，strip + LTO
cargo clippy --all-targets       # 可选 lint
```

## Flutter ↔ Rust 桥接生成

**需要有 Flutter SDK**。在 `code/anx-reader/` 根目录执行：

```bash
# 1. pubspec 加依赖（已写入，只需要 pub get）
flutter pub get

# 2. 生成 Dart 桥接代码
dart run flutter_rust_bridge_codegen generate rust_core/rust.yaml
```

生成后会有：
- `lib/rust/anx_rust_core.dart` — Dart 端 API（从 Rust 自动生成）
- `rust_core/native/` — frb 自动生成的 CMake build 脚本

Flutter 打包时会自动编译这个 Rust crate（iOS/Android/macOS/Windows/Linux 全平台，
鸿蒙 frb 暂不支持 → Rust backend 自动降级 Dart 原实现）。

## Dart 侧使用模式

所有 Rust 功能通过 Dart 工厂切换，默认走原实现：

```dart
// lib/utils/rust_backend.dart（待创建）
class EpubMetadataService {
  static Future<EpubMetadata> open({required String path, bool useRust = false}) {
    if (useRust && kIsWeb == false && !AnxPlatform.isOhos) {
      return _RustEpubMetadata.open(path);  // 调用 frb 生成的桥接 API
    }
    return _DartEpubMetadata.open(path);    // 现有 archive + xml 实现
  }
}
```

生产默认 `useRust: false`，用户可在设置里开启 Rust backend 回滚。

## 阶段划分

| 阶段 | 内容 | 状态 |
|---|---|---|
| 脚手架 | Cargo crate + flutter_rust_bridge 集成 + 目录结构 | ✅ 完成 |
| 阶段 1 | EPUB 解析内核（container/opf/sections）+ cargo test | ✅ 完成，9/9 绿 |
| 阶段 2 | sherpa_onnx 本地离线 TTS 封装 + 生命周期测试 | 🟡 骨架完成，待接 C API |
| 阶段 3 | Dart 侧 factory wrapper + epub_metadata 开关 | 🔜 在有 Flutter SDK 的机器上接 |

## 鸿蒙兼容

sherpa_onnx pub 包本身在鸿蒙无原生库，frb 也不支持鸿蒙；Rust backend
在鸿蒙自动降级到 Dart 原实现。Dart 侧工厂需要显式判断 `AnxPlatform.isOhos`。
