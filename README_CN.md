<p align="right">
<img src="https://flagicons.lipis.dev/flags/4x3/cn.svg" width="30" height="24">
</p>

# TranslaScreen

<p align="center">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT">
  </a>
  <img src="https://img.shields.io/badge/version-1.0.0-blue" alt="Version">
  <img src="https://img.shields.io/badge/Flutter-%3E=3.0.0-blue?logo=flutter" alt="Flutter version">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Android-Supported-green?logo=android" alt="Android">
  <img src="https://img.shields.io/badge/iOS-Supported-green?logo=apple" alt="iOS">
  <img src="https://img.shields.io/badge/Linux-Supported-blue?logo=linux" alt="Linux">
  <img src="https://img.shields.io/badge/macOS-Supported-blue?logo=apple" alt="macOS">
  <img src="https://img.shields.io/badge/Windows-Supported-blue?logo=windows" alt="Windows">
  <img src="https://img.shields.io/badge/Web-Supported-blue?logo=googlechrome" alt="Web">
</p>

TranslaScreen 是一款基于 Flutter 的屏幕翻译应用，可以让你轻松地直接翻译屏幕上的文本。捕获屏幕的任何部分，应用会自动识别文本并提供翻译。

<p align="center">
<a href="README_CN.md">
<img src="https://flagicons.lipis.dev/flags/4x3/gb.svg" width="30" height="24">
</a>
</p>

## ✨ 功能

- **屏幕文本识别**：即时识别来自任何图像或屏幕截图的文本。
- **快速翻译**：将识别出的文本翻译成你想要的语言。
- **简洁界面**：易于使用和直观的用户界面。

## 🚀 开始使用

### 环境要求

- Flutter SDK: 请确保你已经安装了 Flutter SDK。更多信息，请参阅 [Flutter 文档](https://flutter.dev/docs/get-started/install)。

### 安装

1.  克隆仓库：
    ```sh
    git clone https://github.com/Mcayear/TranslaScreen.git
    ```
2.  进入项目目录：
    ```sh
    cd transla_screen
    ```
3.  安装依赖：
    ```sh
    flutter pub get
    ```
4.  运行应用：
    ```sh
    flutter run
    ```

## 🛠️ 技术栈

- [Flutter](https://flutter.dev/) - 用于从单个代码库为移动、Web 和桌面构建本地编译应用的 UI 工具包。
- [google_mlkit_text_recognition](https://pub.dev/packages/google_mlkit_text_recognition) - 用于从图像中识别文本。
- [http](https://pub.dev/packages/http) - 用于向翻译 API 发出 HTTP 请求。
- [permission_handler](https://pub.dev/packages/permission_handler) - 用于请求和检查权限。
- [shared_preferences](https://pub.dev/packages/shared_preferences) - 用于存储简单数据。

## 🤝 贡献

欢迎各种贡献！请随时提交拉取请求。