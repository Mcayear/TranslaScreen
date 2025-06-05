import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:overlay_windows_plugin/overlay_windows_plugin.dart';
import 'package:overlay_windows_plugin/overlay_windows_api.g.dart';
import 'package:transla_screen/app/services/native_bridge.dart';
import 'package:transla_screen/app/services/ocr_service.dart';
import 'package:transla_screen/app/services/openai_ocr_service.dart';
import 'package:transla_screen/app/services/openai_translation_service.dart';
import 'package:transla_screen/app/services/settings_service.dart';
import 'package:transla_screen/app/core/models/ocr_result.dart';
import 'package:transla_screen/app/core/constants/enums.dart';
import 'package:transla_screen/app/services/command_server_service.dart';
import 'package:transla_screen/app/services/logger_service.dart';
// import 'package:transla_screen/app/features/settings/presentation/settings_dialog.dart'; // Commented out for now

// 定义命令处理回调类型
typedef CommandHandlerCallback = void Function(
    String action, Map<String, dynamic>? params);

class HomeController {
  final VoidCallback updateUi;
  final BuildContext Function() getContext;
  StreamSubscription<dynamic>? _overlayMessageSubscription;
  final _overlayPlugin = OverlayWindowsPlugin.defaultInstance;

  // 定义悬浮球和翻译遮罩的ID
  final String _controlOverlayId = "control_overlay";
  final String _translationMaskId = "translation_mask_overlay";

  // 记录当前活跃的overlay窗口ID
  final Set<String> _activeOverlayIds = <String>{};

  bool _isOverlayPermissionGranted = false; // 是否授予了悬浮窗权限
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

  CommandServerService? _commandServerService;

  bool get isOverlayEffectivelyVisible => _isControlOverlayActive;
  bool get isTranslationServiceAvailable => _translationService != null;

  HomeController({required this.updateUi, required this.getContext}) {
    // Listen to overlay messages passed from main.dart
    // This will be set up via a method called from main after construction.
  }

  void listenToOverlayMessages(Stream<dynamic> stream) {
    _overlayMessageSubscription?.cancel();
    _overlayMessageSubscription = stream.listen(_handleDataFromOverlay);
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

    _commandServerService = CommandServerService(
        onCommandReceived: _handleExternalCommand,
        updateStatusMessage: (msg) {
          log.i("[CommandServer] $msg");
        });

    try {
      await _commandServerService!.startServer();
      statusMessage += "\n命令服务器已启动: http://localhost:10080";
    } catch (e, s) {
      log.e("[CommandServer] Error starting server: $e",
          error: e, stackTrace: s);
      statusMessage += "\n命令服务器启动失败: $e";
    }

    // 检查当前overlay权限状态
    if (Platform.isAndroid || Platform.isIOS) {
      _isOverlayPermissionGranted = await _overlayPlugin.isPermissionGranted();
    } else {
      _isOverlayPermissionGranted = true;
    }

    // 检查当前悬浮球是否活跃（不检查是否已创建，因为新API创建后就会自动启动）
    _isControlOverlayActive = _activeOverlayIds.contains(_controlOverlayId);

    isInitializing = false;
    _updateStatusMessageUI(); // Update with the final status
  }

  void dispose() {
    _localOcrService.dispose();
    _openAiOcrService?.dispose();
    _translationService?.dispose();
    targetLanguageController.dispose();
    _commandServerService?.stopServer();
    _overlayMessageSubscription?.cancel();

    // 关闭所有活跃的overlay窗口
    for (final id in _activeOverlayIds) {
      _overlayPlugin.closeOverlayWindow(id);
    }
    _activeOverlayIds.clear();
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
    await _updateOverlayStatus(); // This updates _isOverlayPermissionGranted, _isControlOverlayActive and statusMessage
    capturedImageBytes = null;
    ocrResults = [];
    // statusMessage is handled by _updateOverlayStatus
    _updateStatusMessageUI();
  }

  Future<void> _updateOverlayStatus({String? baseMessage}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      _isOverlayPermissionGranted = await _overlayPlugin.isPermissionGranted();
    } else {
      _isOverlayPermissionGranted = true;
    }

    String permStatus =
        "悬浮窗权限: ${_isOverlayPermissionGranted ? '已授予' : '未授予'}.";
    String activeStatus =
        _isControlOverlayActive ? "悬浮控制球: 活动中." : "悬浮控制球: 未活动.";

    List<String> statusParts = [];
    if (baseMessage != null && baseMessage.isNotEmpty) {
      statusParts.add(baseMessage);
    }
    statusParts.add(permStatus);
    statusParts.add(activeStatus);

    if (!_isOverlayPermissionGranted && !isInitializing) {
      // Only add request prompt if not initializing and not granted
      statusParts.add("请通过按钮请求权限或显示悬浮窗。");
    }

    statusMessage = statusParts.join("\n");
    _updateStatusMessageUI();
  }

  Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _updateStatusMessageUI('正在请求悬浮窗权限...');
    await _overlayPlugin.requestPermission();
    _isOverlayPermissionGranted = await _overlayPlugin.isPermissionGranted();

    if (_isOverlayPermissionGranted) {
      _updateStatusMessageUI('悬浮窗权限已授予。');
      await showOverlay(); // Try to show it if permission was just granted
    } else {
      _updateStatusMessageUI('悬浮窗权限请求被拒绝或失败。');
    }

    await _updateOverlayStatus(); // Refresh full status
  }

  Future<void> toggleScreenCaptureAndOcr(
      {bool sendToTranslationMask = true}) async {
    capturedImageBytes = null;
    ocrResults = [];
    translatedText = "";
    _updateStatusMessageUI('准备捕获屏幕...');

    if (sendToTranslationMask) {
      if (Platform.isAndroid || Platform.isIOS) {
        if (!_isOverlayPermissionGranted) {
          _updateStatusMessageUI('悬浮窗权限未授予。请先授权再尝试发送到悬浮窗。');
          await requestOverlayPermission(); // Prompt for permission
          if (!await _overlayPlugin.isPermissionGranted()) {
            log.w(
                "Overlay permission still not granted after prompt for OCR send.");
            _updateStatusMessageUI('悬浮窗权限未授予，无法发送结果。');
            return;
          }
        }
      }
    }

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

    // 创建并显示译文遮罩overlay
    await _showTranslationMaskOverlay(maskItems);
  }

  /// 打开翻译遮罩Overlay
  Future<void> _showTranslationMaskOverlay(
      List<Map<String, dynamic>> maskItems) async {
    // 确保有权限
    if (!_isOverlayPermissionGranted) {
      _updateStatusMessageUI('悬浮窗权限未授予，无法显示译文遮罩。');

      // 尝试请求权限
      log.i('[HomeController] 尝试请求悬浮窗权限');
      await requestOverlayPermission();

      if (!_isOverlayPermissionGranted) {
        log.e('[HomeController] 权限请求失败，无法显示译文遮罩');
        return;
      }
    }

    log.i('[HomeController] 准备显示译文遮罩，项目数量: ${maskItems.length}');

    // 如果已经有译文遮罩，先关闭它
    if (_activeOverlayIds.contains(_translationMaskId)) {
      log.i('[HomeController] 关闭已存在的译文遮罩');
      await _overlayPlugin.closeOverlayWindow(_translationMaskId);
      _activeOverlayIds.remove(_translationMaskId);

      // 给系统一些时间清理旧窗口
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // 创建并显示新的译文遮罩
    try {
      log.i('[HomeController] 正在创建译文遮罩窗口');

      // 检查插件状态
      bool isPermGranted = true;
      // 判断是 android, ios 才执行
      if (Platform.isAndroid || Platform.isIOS) {
        isPermGranted = await _overlayPlugin.isPermissionGranted();
      }
      log.i('[HomeController] 插件权限状态: $isPermGranted');

      // 获取当前屏幕尺寸
      final screenSize = ui.window.physicalSize;
      final screenWidth = screenSize.width / ui.window.devicePixelRatio;
      final screenHeight = screenSize.height / ui.window.devicePixelRatio;

      log.i(
          '[HomeController] 屏幕尺寸: ${screenWidth.toInt()} x ${screenHeight.toInt()}');

      await _overlayPlugin.showOverlayWindow(
        _translationMaskId,
        "overlayTranslationMaskMain",
        OverlayWindowConfig(
          width: screenWidth.toInt(), // 使用实际屏幕宽度
          height: screenHeight.toInt(), // 使用实际屏幕高度
          enableDrag: false,
          flag: OverlayFlag.defaultFlag,
        ),
      );

      _activeOverlayIds.add(_translationMaskId);
      log.i('[HomeController] 译文遮罩窗口已创建，ID: $_translationMaskId');

      // 等待一小段时间确保窗口已准备就绪
      await Future.delayed(const Duration(milliseconds: 500));

      // 尝试验证窗口是否存在
      try {
        final isActive = await _overlayPlugin.isActive(_translationMaskId);
        log.i('[HomeController] 译文遮罩活动状态: $isActive');
      } catch (e) {
        log.e('[HomeController] 无法验证译文遮罩状态: $e');
      }

      // 发送译文数据到遮罩
      log.i('[HomeController] 发送译文数据到遮罩窗口');
      await _overlayPlugin.sendMessage(_translationMaskId, {
        'type': 'display_translation_mask',
        'items': maskItems,
      });

      log.i('[HomeController] 数据已发送，等待遮罩窗口处理');
      _updateStatusMessageUI('已显示译文遮罩。');
    } catch (e, s) {
      log.e('[HomeController] 显示译文遮罩失败: $e', error: e, stackTrace: s);
      _updateStatusMessageUI('显示译文遮罩失败: $e');
    }
  }

  Future<void> toggleOverlay() async {
    if (_isControlOverlayActive) {
      await hideOverlay();
    } else {
      await showOverlay();
    }
  }

  Future<void> showOverlay() async {
    if (!_isOverlayPermissionGranted) {
      _updateStatusMessageUI('悬浮窗权限未授予。请先授权。');
      await requestOverlayPermission();
      if (!_isOverlayPermissionGranted) {
        return; // 如果依然没有权限，则退出
      }
    }

    _updateStatusMessageUI('正在显示悬浮控制球...');

    try {
      // 如果悬浮球已存在，则不重复创建
      if (!_activeOverlayIds.contains(_controlOverlayId)) {
        // 显示悬浮球窗口
        await _overlayPlugin.showOverlayWindow(
          _controlOverlayId,
          "overlayControlMain",
          OverlayWindowConfig(
            width: 60,
            height: 60,
            enableDrag: true,
            positionGravity: PositionGravity.right,
          ),
        );

        _activeOverlayIds.add(_controlOverlayId);
        _isControlOverlayActive = true;

        _updateStatusMessageUI('悬浮控制球已显示。');
      } else {
        _updateStatusMessageUI('悬浮控制球已经在运行中。');
      }
    } catch (e, s) {
      log.e('[HomeController] 显示悬浮控制球失败: $e', error: e, stackTrace: s);
      _isControlOverlayActive = false;
      _updateStatusMessageUI('显示悬浮控制球失败: $e');
    }

    await _updateOverlayStatus();
  }

  Future<void> hideOverlay() async {
    _updateStatusMessageUI('正在关闭悬浮窗...');

    // 关闭所有活跃的overlay窗口
    try {
      if (_activeOverlayIds.contains(_controlOverlayId)) {
        await _overlayPlugin.closeOverlayWindow(_controlOverlayId);
        _activeOverlayIds.remove(_controlOverlayId);
      }

      // 同时关闭译文遮罩（如果存在）
      if (_activeOverlayIds.contains(_translationMaskId)) {
        await _overlayPlugin.closeOverlayWindow(_translationMaskId);
        _activeOverlayIds.remove(_translationMaskId);
      }

      _isControlOverlayActive = false;
      _updateStatusMessageUI('悬浮窗已关闭。');
    } catch (e, s) {
      log.e('[HomeController] 关闭悬浮窗失败: $e', error: e, stackTrace: s);
      _updateStatusMessageUI('关闭悬浮窗失败: $e');
    }

    await _updateOverlayStatus();
  }

  void _handleDataFromOverlay(dynamic data) async {
    log.i("[HomeController] Received overlay data: $data");
    if (data is Map<String, dynamic>) {
      if (data['type'] == 'mask_closed') {
        log.i("[HomeController] 收到译文遮罩关闭请求，准备关闭遮罩窗口");
        // 译文遮罩被用户关闭，主动尝试关闭遮罩
        try {
          log.i("[HomeController] 关闭译文遮罩窗口: $_translationMaskId");
          await _overlayPlugin.closeOverlayWindow(_translationMaskId);
          _activeOverlayIds.remove(_translationMaskId);
          await _overlayPlugin.closeOverlayWindow("translation_mask_test");
          log.i("[HomeController] 译文遮罩已从活跃列表中移除");
          // 更新UI状态
          _updateStatusMessageUI("已关闭译文遮罩");
        } catch (e, s) {
          log.e("[HomeController] 关闭译文遮罩窗口失败: $e", error: e, stackTrace: s);
        }
      }
    } else if (data is String) {
      log.i("[HomeController] Received string message from overlay: $data");
    } else {
      log.i(
          "[HomeController] Received unknown type from overlay: ${data.runtimeType}");
    }
  }

  void _handleExternalCommand(String action, Map<String, dynamic>? params) {
    log.i("[HomeController] Received command: $action with params: $params");

    switch (action) {
      case 'translate_fullscreen':
        toggleScreenCaptureAndOcr(sendToTranslationMask: true);
        break;
      case 'start_area_selection':
        _updateStatusMessageUI('区域选择功能尚未实现。');
        break;
      default:
        log.w("[HomeController] Unknown command: $action");
    }
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
