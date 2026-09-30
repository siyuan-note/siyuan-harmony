[English](README.md)

## 概述

* 报告问题/咨询讨论请到 [SiYuan issues](https://github.com/siyuan-note/siyuan/issues)
* 欢迎参与代码贡献

## 搭建步骤

1. 参考[思源笔记开发指南](https://github.com/siyuan-note/siyuan/blob/master/.github/CONTRIBUTING.zh-CN.md)编译内核
2. 使用官方 ONNX Runtime v1.24.3 检出目录构建原生 OCR 运行库：`python3 ../siyuan/scripts/build-ocr-harmony.py --source <onnxruntime-checkout> --ndk <sdk-native-directory> --protoc <host-protoc-3.21.12> --output entry/libs --arch arm64-v8a`。脚本在临时副本中适配鸿蒙 Clang 15，保留 FP32/INT8 NEON 推理，关闭不受支持的 BF16/FP16 向量路径。模拟器使用 `--arch x86_64`。缺少运行库时，CMake 会明确拒绝打包
3. 执行 `python3 ../siyuan/scripts/prepare-ocr.py` 准备内置模型，将 `stage/ocr/models` 和许可证文件随前端资源打包。移动端资源包需排除 `stage/ocr/runtime` 中的 Android 和桌面运行库目录
4. 拷贝资源文件并打包 entry/src/main/resources/rawfile/app.zip
   * appearance
   * guide
   * stage
   * changelogs

目录结构参考：

![project-tree](project-tree.png)

![app.zip](app-zip.png)
