[English](README.md)

## 概述

* 报告问题/咨询讨论请到 [SiYuan issues](https://github.com/siyuan-note/siyuan/issues)
* 欢迎参与代码贡献

## 搭建步骤

1. 参考[思源笔记开发指南](https://github.com/siyuan-note/siyuan/blob/master/.github/CONTRIBUTING.zh-CN.md)编译内核
2. 使用官方 ONNX Runtime v1.24.3 检出目录构建原生 OCR 运行库：`python3 ../siyuan/scripts/build-ocr-harmony.py --source <onnxruntime-checkout> --ndk <sdk-native-directory> --protoc <host-protoc-3.21.12> --output entry/libs --arch arm64-v8a --work-dir <build-directory>`。脚本在独立副本中适配鸿蒙 Clang 15，保留 FP32/INT8 NEON 推理，关闭 BF16/FP16 向量路径和 I8MM 优化。工作目录保留源码、依赖和编译产物，失败后可使用相同命令继续；更换架构、SDK 或源码适配后需使用新的工作目录。模拟器使用 `--arch x86_64`。缺少运行库时，CMake 会明确拒绝打包
3. 执行 `python3 ../siyuan/scripts/prepare-ocr.py` 准备内置模型，将 `stage/ocr/models` 和许可证文件随前端资源打包。移动端资源包需排除 `stage/ocr/runtime` 中的 Android 和桌面运行库目录
4. 拷贝资源文件并打包 entry/src/main/resources/rawfile/app.zip
   * appearance
   * guide
   * stage
   * changelogs

网络不稳定时，可通过 `--deps-mirror <mirror-directory>` 使用上游 CMake 支持的本地依赖镜像。镜像内按原始下载 URL 的域名和路径保存压缩包，例如 `<mirror-directory>/github.com/onnx/onnx/archive/refs/tags/v1.20.1.zip`；版本和校验值以固定源码中的 `cmake/deps.txt` 为准，CMake 仍会校验文件。未缓存的依赖会从上游下载。

目录结构参考：

![project-tree](project-tree.png)

![app.zip](app-zip.png)
