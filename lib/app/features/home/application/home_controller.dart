import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:transla_screen/app/services/native_bridge.dart';
import 'package:transla_screen/app/services/ocr_service.dart'; // Should be LocalOcrService
import 'package:transla_screen/app/services/openai_ocr_service.dart';
import 'package:transla_screen/app/services/openai_translation_service.dart';
import 'package:transla_screen/app/services/settings_service.dart';
import 'package:transla_screen/app/core/models/ocr_result.dart';
import 'package:transla_screen/app/core/constants/enums.dart';
import 'package:transla_screen/app/services/command_server_service.dart';

class HomeController {
  final VoidCallback updateUi; // Callback to trigger UI update (setState)
  final BuildContext Function()
      getContext; // Callback to get BuildContext when needed

  // Fields migrated from _MyHomePageState
  bool _isOverlayVisible = false;
  String statusMessage = "正在初始化..."; // Initial status
  Uint8List? capturedImageBytes;
  List<OcrResult> ocrResults = [];

  late LocalOcrService _localOcrService;
  OpenAiOcrService? _openAiOcrService;
  late SettingsService _settingsService;
  OcrEngineType _selectedOcrEngine = OcrEngineType.local;
  bool isInitializing = true;

  OpenAiTranslationService? _translationService;
  final TextEditingController targetLanguageController =
      TextEditingController(text: '中文');
  String translatedText = ""; // For potential in-app display

  CommandServerService? _commandServerService;

  // Getter for UI
  bool get isOverlayVisible => _isOverlayVisible;
  bool get isTranslationServiceAvailable => _translationService != null;

  HomeController({required this.updateUi, required this.getContext});

  Future<void> initialize() async {
    isInitializing = true;
    _updateStatusMessageUI(); // updateUi() might be better here

    _settingsService = SettingsService();
    _localOcrService = LocalOcrService();
    await loadAndInitializeServices(); // This will also call _checkInitialPermissions

    _commandServerService = CommandServerService(
        onCommandReceived: _handleOverlayCommand,
        updateStatusMessage: (msg) {
          // This callback is for the command server's own status messages
          // We might want to log these or display them differently if needed.
          // For now, let's log them and not overwrite the main statusMessage directly here.
          log("[CommandServer] $msg");
          // statusMessage = msg;
          // _updateStatusMessageUI();
        });
    await _commandServerService!.startServer();
    statusMessage = "服务已启动。" +
        (statusMessage.contains("http://localhost:10080")
            ? ""
            : " 命令服务器: http://localhost:10080");

    isInitializing = false;
    _updateStatusMessageUI();
  }

  void dispose() {
    _localOcrService.dispose();
    _openAiOcrService?.dispose();
    _translationService?.dispose();
    targetLanguageController.dispose();
    _commandServerService?.stopServer();
  }

  Future<void> loadAndInitializeServices() async {
    isInitializing = true;
    translatedText = "";
    _updateStatusMessageUI();

    _selectedOcrEngine = await _settingsService.getSelectedOcrEngine();
    String ocrStatus = "OCR引擎: ${_selectedOcrEngine.name}. ";

    if (_selectedOcrEngine == OcrEngineType.openai) {
      final openAIConfig = await _settingsService.getOpenAiConfig();
      if (openAIConfig['apiKey'] != null &&
          openAIConfig['apiKey']!.isNotEmpty &&
          openAIConfig['apiKey'] != 'YOUR_OPENAI_API_KEY') {
        _openAiOcrService = OpenAiOcrService(
          apiKey: openAIConfig['apiKey']!,
          apiEndpoint: openAIConfig['apiEndpoint']!,
          model: openAIConfig['modelName']!,
        );
        ocrStatus += "OpenAI OCR 配置成功.";
      } else {
        _selectedOcrEngine = OcrEngineType.local;
        _openAiOcrService = null;
        log("OpenAI OCR API key not configured or invalid. Falling back to Local OCR.");
        ocrStatus += "OpenAI OCR 配置无效，已切换回本地 OCR.";
      }
    } else {
      _openAiOcrService = null;
      ocrStatus += "本地 OCR 已就绪.";
    }

    String translationStatus = "";
    final translationConfig =
        await _settingsService.getOpenAiTranslationConfig();
    if (translationConfig['apiKey'] != null &&
        translationConfig['apiKey']!.isNotEmpty &&
        translationConfig['apiKey'] != 'YOUR_OPENAI_API_KEY') {
      _translationService = OpenAiTranslationService(
        apiKey: translationConfig['apiKey']!,
        apiEndpoint: translationConfig['apiEndpoint']!,
        model: translationConfig['modelName']!,
      );
      translationStatus = "OpenAI 翻译服务已配置.";
    } else {
      _translationService = null;
      log("OpenAI Translation API key not configured or invalid. Translation will be unavailable.");
      translationStatus = "OpenAI 翻译服务未配置，翻译功能不可用.";
    }
    statusMessage = ocrStatus + "\n" + translationStatus;
    await _checkInitialPermissions(); // This calls _updateStatusMessageUI internally
    isInitializing = false;
    // _updateStatusMessageUI(); // Already called by _checkInitialPermissions
  }

  Future<void> _checkInitialPermissions() async {
    await checkOverlayPermissionStatus(); // This updates statusMessage and calls UI update
    capturedImageBytes = null;
    ocrResults = [];
    // statusMessage is handled by checkOverlayPermissionStatus, no need to overwrite here
    // unless adding more info.
    _updateStatusMessageUI();
  }

  Future<void> checkOverlayPermissionStatus() async {
    final bool granted = await FlutterOverlayWindow.isPermissionGranted();
    String permStatus = "悬浮窗权限: ${granted ? '已授予' : '未授予'}.";
    if (!granted && !statusMessage.contains("请通过按钮请求权限")) {
      statusMessage = permStatus + " 请通过按钮请求权限.";
    } else if (granted && statusMessage.contains("悬浮窗权限未授予")) {
      statusMessage = permStatus;
    } else if (!statusMessage.startsWith("悬浮窗权限")) {
      statusMessage = permStatus + "\n" + statusMessage;
    }
    // else keep existing detailed status message if it's not about permission specifically
    _updateStatusMessageUI();
  }

  Future<void> requestOverlayPermission() async {
    statusMessage = '正在请求悬浮窗权限...';
    capturedImageBytes = null;
    ocrResults = [];
    _updateStatusMessageUI();

    bool? granted = await FlutterOverlayWindow.isPermissionGranted();

    if (granted == false) {
      granted = await FlutterOverlayWindow.requestPermission();
    }
    if (granted == true) {
      statusMessage = '悬浮窗权限已授予。';
    } else {
      statusMessage = '悬浮窗权限请求被拒绝或失败。';
    }
    _updateStatusMessageUI();
  }

  Future<void> toggleScreenCaptureAndOcr({bool sendToOverlay = false}) async {
    capturedImageBytes = null;
    ocrResults = [];
    statusMessage = '正在准备开始屏幕捕获...';
    _updateStatusMessageUI();

    final bool overlayPermGranted =
        await FlutterOverlayWindow.isPermissionGranted();
    if (!overlayPermGranted && sendToOverlay) {
      statusMessage = 'OCR结果需发送到悬浮窗，但悬浮窗权限未授予。请先授权。';
      _updateStatusMessageUI();
      return;
    }
    if (!overlayPermGranted && !sendToOverlay) {
      statusMessage = '提示：悬浮窗权限未授予，OCR结果将仅在主界面显示。';
      // Allow proceeding, but warn
    }

    statusMessage = '正在请求屏幕捕获权限和截图...';
    _updateStatusMessageUI();

    final Uint8List? imageBytes = await NativeBridge.startScreenCapture();

    if (imageBytes != null) {
      capturedImageBytes = imageBytes;
      statusMessage =
          '截图成功！正在进行OCR识别 (${_selectedOcrEngine == OcrEngineType.openai && _openAiOcrService != null ? "OpenAI" : "本地"})...';
      _updateStatusMessageUI();

      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final int imageWidth = frame.image.width;
      final int imageHeight = frame.image.height;
      frame.image.dispose();

      List<OcrResult> currentResultsList = [];
      try {
        if (_selectedOcrEngine == OcrEngineType.openai &&
            _openAiOcrService != null) {
          if (_openAiOcrService!.apiKey.isEmpty ||
              _openAiOcrService!.apiKey == 'YOUR_OPENAI_API_KEY') {
            statusMessage = 'OpenAI API Key 未配置，转用本地OCR。';
            _updateStatusMessageUI();
            currentResultsList =
                await _localOcrService.processImageBytes(imageBytes);
          } else {
            currentResultsList = await _openAiOcrService!
                .processImageBytes(imageBytes, imageWidth, imageHeight);
          }
        } else {
          currentResultsList =
              await _localOcrService.processImageBytes(imageBytes);
        }
      } catch (e) {
        log("Error during OCR processing: $e");
        statusMessage = "OCR 处理出错: $e";
        _updateStatusMessageUI();
        return;
      }

      ocrResults = currentResultsList;
      if (ocrResults.isNotEmpty &&
          !(ocrResults.length == 1 &&
              ocrResults.first.text.contains("API Key not configured"))) {
        statusMessage =
            'OCR完成 (${_selectedOcrEngine == OcrEngineType.openai && _openAiOcrService != null ? "OpenAI" : "本地"})！识别到 ${ocrResults.length} 个文本块。';
      } else if (ocrResults.isNotEmpty &&
          ocrResults.first.text.contains("API Key not configured")) {
        // statusMessage is already set for this case
      } else {
        statusMessage =
            'OCR完成 (${_selectedOcrEngine == OcrEngineType.openai && _openAiOcrService != null ? "OpenAI" : "本地"})，但未识别到文本。';
      }
      _updateStatusMessageUI();

      if (sendToOverlay) {
        if (ocrResults.isNotEmpty) {
          statusMessage = '正在准备数据并发送到悬浮窗...';
          _updateStatusMessageUI();
          await _sendDataToOverlay(
              translateIfPossible: _translationService != null);
        } else {
          statusMessage = '未识别到文本，无法发送到悬浮窗。';
          _updateStatusMessageUI();
        }
      } else {
        // Not sending to overlay, results are in ocrResults for main UI display if desired.
        // If translation is desired for main UI, call translateOcrResults() separately.
      }
    } else {
      capturedImageBytes = null;
      statusMessage = '屏幕捕获失败或未返回图像数据。';
      _updateStatusMessageUI();
    }
  }

  Future<void> toggleOverlay() async {
    if (_isOverlayVisible) {
      await FlutterOverlayWindow.closeOverlay();
      _isOverlayVisible = false;
      statusMessage = "悬浮窗已关闭。";
    } else {
      final bool permGranted = await FlutterOverlayWindow.isPermissionGranted();
      if (!permGranted) {
        statusMessage = "无法显示悬浮窗：权限未授予。请先通过主界面按钮请求权限。";
        _updateStatusMessageUI();
        return;
      }

      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: "TranslaScreen 悬浮窗",
        overlayContent: "悬浮窗正在运行",
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        height: 56 * 4,
        width: 56 * 4,
        startPosition: const OverlayPosition(0, -259),
      );
      _isOverlayVisible = true;
      statusMessage = "悬浮窗已显示。";
    }
    _updateStatusMessageUI();
  }

  Future<void> _sendDataToOverlay({bool translateIfPossible = true}) async {
    if (!_isOverlayVisible) {
      statusMessage = "悬浮窗未激活，无法发送数据。";
      _updateStatusMessageUI();
      return;
    }
    if (ocrResults.isEmpty) {
      statusMessage = "无 OCR 结果可发送。";
      _updateStatusMessageUI();
      return;
    }

    final List<Map<String, dynamic>> maskItems = [];
    if (translateIfPossible && _translationService != null) {
      statusMessage = "正在翻译结果并发送到悬浮窗...";
      _updateStatusMessageUI();
      try {
        for (final ocrResult in ocrResults) {
          final String translated = await _translationService!.translate(
            ocrResult.text,
            targetLanguageController.text.trim().isEmpty
                ? '中文'
                : targetLanguageController.text.trim(),
          );
          maskItems.add({
            'bbox': {
              'l': ocrResult.boundingBox.left,
              't': ocrResult.boundingBox.top,
              'w': ocrResult.boundingBox.width,
              'h': ocrResult.boundingBox.height,
            },
            'translatedText': translated,
            'originalText': ocrResult.text,
          });
        }
        statusMessage = "已将翻译结果发送到悬浮窗显示。";
      } catch (e) {
        log("翻译时出错: $e");
        statusMessage = "翻译出错: $e - 将发送原文。";
        // Fallback to sending original text if translation fails
        maskItems.clear(); // Clear partially translated items
        for (final ocrResult in ocrResults) {
          maskItems.add({
            'bbox': {
              'l': ocrResult.boundingBox.left,
              't': ocrResult.boundingBox.top,
              'w': ocrResult.boundingBox.width,
              'h': ocrResult.boundingBox.height
            },
            'translatedText': ocrResult.text,
            'originalText': ocrResult.text,
          });
        }
      }
    } else {
      statusMessage = "翻译服务不可用或未请求翻译，正在发送原文到悬浮窗。";
      for (final ocrResult in ocrResults) {
        maskItems.add({
          'bbox': {
            'l': ocrResult.boundingBox.left,
            't': ocrResult.boundingBox.top,
            'w': ocrResult.boundingBox.width,
            'h': ocrResult.boundingBox.height
          },
          'translatedText': ocrResult.text,
          'originalText': ocrResult.text,
        });
      }
    }

    final data = {'type': 'display_translation_mask', 'items': maskItems};
    await FlutterOverlayWindow.shareData(jsonEncode(data));
    _updateStatusMessageUI();
  }

  void _updateStatusMessageUI() {
    updateUi();
  }

  Future<void> translateOcrResultsForAppDisplay() async {
    if (ocrResults.isEmpty) {
      translatedText = "没有文本可供翻译。";
      _updateStatusMessageUI();
      return;
    }
    if (_translationService == null) {
      translatedText = "翻译服务未配置或API密钥无效。";
      _updateStatusMessageUI();
      return;
    }
    translatedText = "正在翻译...";
    _updateStatusMessageUI();
    String textToTranslateCombined = ocrResults.map((r) => r.text).join("\n");
    try {
      final String translationResult = await _translationService!.translate(
        textToTranslateCombined,
        targetLanguageController.text.trim().isEmpty
            ? '中文'
            : targetLanguageController.text.trim(),
      );
      translatedText = translationResult;
    } catch (e) {
      log("Error during in-app translation: $e");
      translatedText = "翻译时发生错误: $e";
    } finally {
      _updateStatusMessageUI();
    }
  }

  void _handleOverlayCommand(String? action) {
    log("[HomeController] Handling overlay command: $action");
    if (action == null) return;

    String commandStatus = "收到命令: $action. ";
    switch (action) {
      case "start_fullscreen_translation":
        _startFullscreenTranslation();
        commandStatus += "开始全屏翻译流程。";
        break;
      case "start_area_selection":
        _startAreaSelection();
        commandStatus += "开始选区翻译流程 (暂用全屏替代)。";
        break;
      case "reset_overlay_ui":
        log("[HomeController] Received reset_overlay_ui command.");
        ocrResults = [];
        capturedImageBytes = null;
        commandStatus += "悬浮窗已重置。";
        break;
      default:
        log("[HomeController] Unknown overlay command: $action");
        commandStatus += "未知命令。";
    }
    statusMessage = commandStatus;
    _updateStatusMessageUI();
  }

  Future<void> _startFullscreenTranslation() async {
    await toggleScreenCaptureAndOcr(sendToOverlay: true);
  }

  Future<void> _startAreaSelection() async {
    statusMessage = "选区翻译功能尚未实现，暂时使用全屏翻译代替";
    _updateStatusMessageUI();
    log("选区翻译功能尚未实现，暂时使用全屏翻译代替");
    await _startFullscreenTranslation();
  }
}
