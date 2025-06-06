import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:transla_screen/app/services/native_bridge.dart';
import 'package:transla_screen/app/services/ocr_service.dart';
import 'package:transla_screen/app/services/openai_ocr_service.dart';
import 'package:transla_screen/app/services/openai_translation_service.dart';
import 'package:transla_screen/app/services/settings_service.dart';
import 'package:transla_screen/app/core/models/ocr_result.dart';
import 'package:transla_screen/app/core/constants/enums.dart';
import 'package:transla_screen/app/services/logger_service.dart';
import 'package:transla_screen/app/services/native_overlay_service.dart';
// import 'package:transla_screen/app/features/settings/presentation/settings_dialog.dart'; // Commented out for now

// 定义命令处理回调类型
typedef CommandHandlerCallback = void Function(
    String action, Map<String, dynamic>? params);

class HomeController {
  final VoidCallback updateUi;
  final BuildContext Function() getContext;
  StreamSubscription<dynamic>? _overlayMessageSubscription;

  // 使用新的原生悬浮窗服务
  final NativeOverlayService _nativeOverlayService = NativeOverlayService();

  bool _isOverlayPermissionGranted = false; // 是否授予了悬浮窗权限
  bool _isScreenCapturePermissionGranted = false; // 新增：是否授予了截屏权限
  bool _isControlOverlayActive = false; // 悬浮球是否激活
  String statusMessage = "正在初始化...";
  Uint8List? capturedImageBytes;
  List<OcrResult> ocrResults = [];

  late LocalOcrService _localOcrService;
  OpenAiOcrService? _openAiOcrService;
  late SettingsService _settingsService;
  OcrEngineType _selectedOcrEngine = OcrEngineType.local;
  bool isInitializing = true;

  OpenAiTranslationService? _translationService;
  final TextEditingController targetLanguageController =
      TextEditingController(text: '中文'); // Default to Chinese
  String translatedText = "";

  bool get isOverlayEffectivelyVisible => _isControlOverlayActive;
  bool get isTranslationServiceAvailable => _translationService != null;

  HomeController({required this.updateUi, required this.getContext}) {
    // 设置原生悬浮窗服务的回调
    _nativeOverlayService.onBubbleActionReceived = _handleBubbleAction;
    _nativeOverlayService.onOverlayError = _handleOverlayError;
  }

  void _handleBubbleAction(String action) {
    log.i("[HomeController] 收到悬浮球命令: $action");
    switch (action) {
      case 'translate_fullscreen':
        toggleScreenCaptureAndOcr(sendToTranslationMask: true);
        break;
      case 'start_area_selection':
        _updateStatusMessageUI('区域选择功能尚未实现。');
        break;
      case 'mask_closed':
        _updateStatusMessageUI('翻译蒙版已关闭');
        break;
      default:
        log.w("[HomeController] Unknown command: $action");
    }
  }

  void _handleOverlayError(String error) {
    log.e("[HomeController] 悬浮窗错误: $error");
    _updateStatusMessageUI('悬浮窗错误: $error');
    _isControlOverlayActive = false;
  }

  Future<void> initialize() async {
    isInitializing = true;
    log.i("[HomeController] 正在初始化服务...");
    _updateStatusMessageUI("正在初始化服务...");

    _settingsService = SettingsService();
    _localOcrService = LocalOcrService();

    // Load target language first as it might be part of the initial status
    targetLanguageController.text = await _settingsService.getTargetLanguage();

    await loadAndInitializeServices(); // This also calls _checkInitialPermissions

    // 检查当前overlay权限状态
    await _checkInitialPermissions();

    isInitializing = false;
    _updateStatusMessageUI(); // Update with the final status
  }

  void dispose() {
    _localOcrService.dispose();
    _openAiOcrService?.dispose();
    _translationService?.dispose();
    targetLanguageController.dispose();
    _overlayMessageSubscription?.cancel();
  }

  Future<void> loadAndInitializeServices() async {
    isInitializing = true; // Mark as initializing
    translatedText = "";
    _updateStatusMessageUI("加载OCR和翻译配置...");

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
        _selectedOcrEngine = OcrEngineType.local; // Fallback
        await _settingsService
            .setSelectedOcrEngine(OcrEngineType.local); // Persist fallback
        _openAiOcrService = null;
        log.w(
            "OpenAI OCR API key not configured or invalid. Falling back to Local OCR.");
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
      translationStatus =
          "OpenAI 翻译服务已配置 (目标语言: ${targetLanguageController.text}).";
    } else {
      _translationService = null;
      log.w(
          "OpenAI Translation API key not configured or invalid. Translation will be unavailable.");
      translationStatus = "OpenAI 翻译服务未配置，翻译功能不可用.";
    }
    statusMessage = ocrStatus + "\n" + translationStatus;
    await _checkInitialPermissions(); // This updates status message further with permission info
    isInitializing = false; // Done with this part
    _updateStatusMessageUI(); // Update UI with new status
  }

  Future<void> _checkInitialPermissions() async {
    await _updatePermissionsStatus(); // This updates _isOverlayPermissionGranted, _isControlOverlayActive and statusMessage
    capturedImageBytes = null;
    ocrResults = [];
    // statusMessage is handled by _updatePermissionsStatus
    _updateStatusMessageUI();
  }

  Future<void> _updatePermissionsStatus({String? baseMessage}) async {
    String permStatus = "悬浮窗权限: ${_isOverlayPermissionGranted ? "已授予" : "未授予"}";
    String capturePermStatus =
        "截屏权限: ${_isScreenCapturePermissionGranted ? "已授予" : "未授予"}";
    String activeStatus =
        _isControlOverlayActive ? "悬浮控制球: 活动中." : "悬浮控制球: 未活动.";

    List<String> statusParts = [];
    if (baseMessage != null && baseMessage.isNotEmpty) {
      statusParts.add(baseMessage);
    }
    statusParts.add(permStatus);
    statusParts.add(capturePermStatus);
    statusParts.add(activeStatus);

    statusMessage = statusParts.join("\n");
    _updateStatusMessageUI();
  }

  Future<void> requestPermission() async {
    if (Platform.isAndroid) {
      // 1. 请求悬浮窗权限
      _updateStatusMessageUI('正在请求悬浮窗权限...');
      PermissionStatus overlayStatus =
          await Permission.systemAlertWindow.request();
      if (overlayStatus.isGranted) {
        _isOverlayPermissionGranted = true;
        _updateStatusMessageUI('悬浮窗权限已授予。');
      } else {
        _isOverlayPermissionGranted = false;
        _updateStatusMessageUI('悬浮窗权限被拒绝。');
      }

      // 2. 请求截屏权限
      if (_isOverlayPermissionGranted) {
        _updateStatusMessageUI('请求截屏权限中...');
        final Uint8List? captureGranted =
            await NativeBridge.startScreenCapture();
        if (captureGranted != null) {
          _isScreenCapturePermissionGranted = true;
          _updateStatusMessageUI('截屏权限已授予。');
        } else {
          _isScreenCapturePermissionGranted = false;
          _updateStatusMessageUI('截屏权限被拒绝或取消。');
        }
      }
    } else {
      _updateStatusMessageUI('此平台无需特殊权限。');
      _isOverlayPermissionGranted = true;
      _isScreenCapturePermissionGranted = true;
    }
    await _updatePermissionsStatus(); // Refresh full status
  }

  Future<void> toggleScreenCaptureAndOcr(
      {bool sendToTranslationMask = true}) async {
    capturedImageBytes = null;
    ocrResults = [];
    translatedText = "";
    _updateStatusMessageUI('准备捕获屏幕...');

    _updateStatusMessageUI('正在请求屏幕捕获权限和截图...');
    final Uint8List? imageBytes = await NativeBridge.startScreenCapture();

    if (imageBytes != null) {
      capturedImageBytes = imageBytes;
      _updateStatusMessageUI('截图成功！正在进行OCR (${_selectedOcrEngine.name})...');

      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final int imageWidth = frame.image.width;
      final int imageHeight = frame.image.height;
      frame.image.dispose(); // Dispose codec and frame image

      List<OcrResult> currentResultsList = [];
      try {
        if (_selectedOcrEngine == OcrEngineType.openai &&
            _openAiOcrService != null) {
          currentResultsList = await _openAiOcrService!
              .processImageBytes(imageBytes, imageWidth, imageHeight);
        } else {
          currentResultsList =
              await _localOcrService.processImageBytes(imageBytes);
        }

        ocrResults = currentResultsList;

        if (ocrResults.isEmpty) {
          _updateStatusMessageUI('OCR未能识别任何文本。');
        } else {
          if (_translationService != null) {
            _updateStatusMessageUI(
                'OCR识别完成。正在翻译到${targetLanguageController.text}...');

            // 使用结构化翻译API
            Map<String, String> translations = await _translationService!
                .translateStructured(ocrResults, targetLanguageController.text);

            // 检查是否有错误
            if (translations.containsKey('error')) {
              _updateStatusMessageUI('翻译过程中发生错误: ${translations['error']}');
              translatedText = ocrResults.map((e) => e.text).join("\n");
            } else {
              // 根据翻译结果处理每个OCR项
              for (var result in ocrResults) {
                if (translations.containsKey(result.text)) {
                  // 保存原始OCR文本，用于显示
                  String originalText = result.text;
                  // 将译文与原文关联
                  translatedText += "${translations[originalText]}\n";
                }
              }

              translatedText = translatedText.trim();
              _updateStatusMessageUI('翻译完成。');

              // 如果需要发送到overlay，则展示译文遮罩
              if (sendToTranslationMask) {
                await _displayTranslationMask(ocrResults, translations);
              }
            }
          } else {
            translatedText = ocrResults.map((e) => e.text).join("\n");
            _updateStatusMessageUI('OCR识别完成。未配置翻译服务。');
          }
        }
      } catch (e, stacktrace) {
        log.e('[HomeController] OCR或翻译错误: $e',
            error: e, stackTrace: stacktrace);
        _updateStatusMessageUI('OCR或翻译过程中发生错误: $e');
      }
    } else {
      _updateStatusMessageUI('屏幕捕获失败或被取消。');
    }

    updateUi();
  }

  Future<void> _displayTranslationMask(
      List<OcrResult> ocrResults, Map<String, String> translations) async {
    if (ocrResults.isEmpty) return;

    log.i('[HomeController] 准备显示翻译遮罩，OCR结果: ${ocrResults.length}个');

    // 准备用于遮罩显示的数据
    List<Map<String, dynamic>> maskItems = [];
    for (int i = 0; i < ocrResults.length; i++) {
      var result = ocrResults[i];
      // 从翻译Map中获取对应的译文
      String translatedText = translations[result.text] ?? result.text;

      log.i(
          '[HomeController] 添加翻译项 #$i: 位置=${result.boundingBox}, 原文=${result.text}, 译文=${translatedText}');

      maskItems.add({
        'bbox': {
          'l': result.boundingBox.left,
          't': result.boundingBox.top,
          'w': result.boundingBox.width,
          'h': result.boundingBox.height,
        },
        'originalText': result.text,
        'translatedText': translatedText,
      });
    }

    // 使用原生实现显示译文蒙版
    await _nativeOverlayService.showTranslationOverlay(maskItems);
    _updateStatusMessageUI('已显示译文遮罩');
  }

  Future<void> toggleOverlay() async {
    if (_isControlOverlayActive) {
      await hideOverlay();
    } else {
      await showOverlay();
    }
  }

  Future<void> showOverlay() async {
    _updateStatusMessageUI('正在显示悬浮控制球...');

    try {
      // 使用原生服务显示悬浮球
      final result = await _nativeOverlayService.showFloatingBubble();
      if (result) {
        _isControlOverlayActive = true;
        _updateStatusMessageUI('悬浮控制球已显示。');
      } else {
        _updateStatusMessageUI('显示悬浮控制球失败。');
      }
    } catch (e, s) {
      log.e('[HomeController] 显示悬浮控制球失败: $e', error: e, stackTrace: s);
      _isControlOverlayActive = false;
      _updateStatusMessageUI('显示悬浮控制球失败: $e');
    }

    await _updatePermissionsStatus();
  }

  Future<void> hideOverlay() async {
    _updateStatusMessageUI('正在关闭悬浮窗...');

    try {
      // 使用原生服务关闭悬浮球
      final result = await _nativeOverlayService.hideFloatingBubble();
      if (result) {
        _isControlOverlayActive = false;
        _updateStatusMessageUI('悬浮控制球已关闭。');
      } else {
        _updateStatusMessageUI('关闭悬浮控制球失败。');
      }

      // 同时关闭译文遮罩
      await _nativeOverlayService.hideTranslationOverlay();
    } catch (e, s) {
      log.e('[HomeController] 关闭悬浮窗失败: $e', error: e, stackTrace: s);
      _updateStatusMessageUI('关闭悬浮窗失败: $e');
    }

    await _updatePermissionsStatus();
  }

  Future<void> setTargetLanguage(String language) async {
    if (language.isNotEmpty) {
      targetLanguageController.text = language;
      await _settingsService.setTargetLanguage(language);
      _updateStatusMessageUI('目标语言已设置为: $language');
    }
  }

  void _updateStatusMessageUI([String? message]) {
    if (message != null) {
      statusMessage = message;
    }
    updateUi();
  }
}
