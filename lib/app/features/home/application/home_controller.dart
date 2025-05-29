import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path_provider/path_provider.dart';
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

class HomeController {
  final VoidCallback updateUi;
  final BuildContext Function() getContext;
  StreamSubscription<dynamic>? _overlayMessageSubscription;

  bool _isOverlayVisible =
      false; // Tracks our desired state / if permission granted
  bool _isOverlayActive =
      false; // Tracks if FlutterOverlayWindow.isActive() is true
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

  bool get isOverlayEffectivelyVisible =>
      _isOverlayActive; // UI should react to this
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
      final directory = await getExternalStorageDirectory();
      await _commandServerService!.startServer();
      statusMessage +=
          "\n命令服务器已启动: http://localhost:10080 | ${directory?.path}/app.log";
    } catch (e, s) {
      log.e("[CommandServer] Error starting server: $e",
          error: e, stackTrace: s);
      statusMessage += "\n命令服务器启动失败: $e";
    }

    // Check current overlay status
    _isOverlayActive = await FlutterOverlayWindow.isActive() ?? false;
    _isOverlayVisible = await FlutterOverlayWindow.isPermissionGranted();

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
    await _updateOverlayStatus(); // This updates _isOverlayVisible, _isOverlayActive and statusMessage
    capturedImageBytes = null;
    ocrResults = [];
    // statusMessage is handled by _updateOverlayStatus
    _updateStatusMessageUI();
  }

  Future<void> _updateOverlayStatus({String? baseMessage}) async {
    final bool permGranted = await FlutterOverlayWindow.isPermissionGranted();
    _isOverlayActive = await FlutterOverlayWindow.isActive() ?? false;
    _isOverlayVisible = permGranted;

    String permStatus = "悬浮窗权限: ${permGranted ? '已授予' : '未授予'}.";
    String activeStatus = _isOverlayActive ? "悬浮窗当前状态: 活动中." : "悬浮窗当前状态: 未活动.";

    List<String> statusParts = [];
    if (baseMessage != null && baseMessage.isNotEmpty)
      statusParts.add(baseMessage);
    statusParts.add(permStatus);
    statusParts.add(activeStatus);

    if (!permGranted && !isInitializing) {
      // Only add request prompt if not initializing and not granted
      statusParts.add("请通过按钮请求权限或显示悬浮窗。");
    }

    statusMessage = statusParts.join("\n");
    _updateStatusMessageUI();
  }

  Future<void> requestOverlayPermission() async {
    _updateStatusMessageUI('正在请求悬浮窗权限...');
    bool? granted = await FlutterOverlayWindow.requestPermission();
    if (granted == true) {
      _isOverlayVisible = true; // Permission granted
      _updateStatusMessageUI('悬浮窗权限已授予。');
      await showOverlay(); // Try to show it if permission was just granted
    } else {
      _isOverlayVisible = false;
      _updateStatusMessageUI('悬浮窗权限请求被拒绝或失败。');
    }
    await _updateOverlayStatus(); // Refresh full status
  }

  Future<void> toggleScreenCaptureAndOcr({bool sendToOverlay = true}) async {
    capturedImageBytes = null;
    ocrResults = [];
    translatedText = "";
    _updateStatusMessageUI('准备捕获屏幕...');

    if (sendToOverlay) {
      if (!_isOverlayVisible) {
        _updateStatusMessageUI('悬浮窗权限未授予。请先授权再尝试发送到悬浮窗。');
        await requestOverlayPermission(); // Prompt for permission
        if (!await FlutterOverlayWindow.isPermissionGranted()) {
          log.w(
              "Overlay permission still not granted after prompt for OCR send.");
          _updateStatusMessageUI('悬浮窗权限未授予，无法发送结果。');
          return;
        }
      }
      if (!_isOverlayActive) {
        log.i("Overlay not active. Attempting to show for OCR results.");
        await showOverlay(); // Attempt to show it if not active
        if (!_isOverlayActive) {
          // Re-check active status
          _updateStatusMessageUI('尝试显示悬浮窗失败，无法发送OCR结果。');
          return;
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
          if (_openAiOcrService!.apiKey.isEmpty ||
              _openAiOcrService!.apiKey == 'YOUR_OPENAI_API_KEY') {
            _updateStatusMessageUI('OpenAI API Key 未配置，转用本地OCR。');
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
      } catch (e, s) {
        log.e("Error during OCR processing: $e", error: e, stackTrace: s);
        _updateStatusMessageUI("OCR 处理出错: $e");
        return;
      }

      ocrResults = currentResultsList;
      String ocrMsg;
      bool hasValidOcrText = false;
      if (ocrResults.isNotEmpty) {
        if (ocrResults.length == 1 &&
            (ocrResults.first.text.contains("API Key not configured") ||
                ocrResults.first.text
                    .contains("Error: Translation API Key not configured"))) {
          ocrMsg = "OCR 完成，但检测到API配置问题: ${ocrResults.first.text}";
          log.w(ocrMsg);
        } else if (ocrResults.every((r) => r.text.trim().isEmpty)) {
          ocrMsg = "OCR 完成 (${_selectedOcrEngine.name})，但未识别到有效文本字符。";
        } else {
          ocrMsg =
              'OCR完成 (${_selectedOcrEngine.name})！识别到 ${ocrResults.length} 个文本块。';
          hasValidOcrText = true;
        }
      } else {
        ocrMsg = 'OCR完成 (${_selectedOcrEngine.name})，但未识别到文本。';
      }
      _updateStatusMessageUI(ocrMsg);

      if (hasValidOcrText) {
        await _translateOcrResults(sendToOverlay: sendToOverlay);
      } else if (sendToOverlay) {
        log.i(
            "No valid text from OCR to translate, but sending to overlay to clear/update.");
        await _sendDataToOverlay(
            ocrResults: ocrResults,
            translatedText: "",
            imageBytes: capturedImageBytes);
      }
    } else {
      _updateStatusMessageUI('屏幕捕获失败或被取消。');
    }
  }

  Future<void> _translateOcrResults({bool sendToOverlay = true}) async {
    if (ocrResults.isEmpty || ocrResults.every((r) => r.text.trim().isEmpty)) {
      _updateStatusMessageUI(
          statusMessage + "\n没有有效文本可翻译。"); // Append to existing OCR status
      if (sendToOverlay) {
        await _sendDataToOverlay(
            ocrResults: ocrResults,
            translatedText: "",
            imageBytes: capturedImageBytes);
      }
      return;
    }

    if (_translationService == null) {
      log.w("Translation service not available, skipping translation.");
      _updateStatusMessageUI(
          statusMessage + "\n翻译服务不可用 (API Key 未配置?)，仅显示OCR结果。");
      if (sendToOverlay) {
        await _sendDataToOverlay(
            ocrResults: ocrResults,
            translatedText: null,
            imageBytes: capturedImageBytes);
      }
      return;
    }

    _updateStatusMessageUI(
        statusMessage + "\n正在翻译 (目标: ${targetLanguageController.text})...");
    String combinedText = ocrResults.map((r) => r.text).join("\n").trim();
    String currentTranslatedText = "";

    if (combinedText.isNotEmpty) {
      try {
        currentTranslatedText = await _translationService!
            .translate(combinedText, targetLanguageController.text);
        translatedText = currentTranslatedText; // For in-app display
        _updateStatusMessageUI(statusMessage + "\n翻译完成！");
      } catch (e, s) {
        log.e("Error during translation: $e", error: e, stackTrace: s);
        currentTranslatedText = "翻译时发生错误。";
        _updateStatusMessageUI(statusMessage + "\n翻译出错: $e");
      }
    } else {
      _updateStatusMessageUI(statusMessage + "\n没有识别到可翻译的文本内容。");
      currentTranslatedText = "";
    }

    if (sendToOverlay) {
      await _sendDataToOverlay(
          ocrResults: ocrResults,
          translatedText: currentTranslatedText,
          imageBytes: capturedImageBytes);
    }
  }

  Future<void> _sendDataToOverlay(
      {required List<OcrResult> ocrResults,
      String? translatedText,
      Uint8List? imageBytes}) async {
    if (!_isOverlayActive && _isOverlayVisible) {
      // Permitted but not active
      log.w("Overlay not active despite permission. Attempting to show.");
      await showOverlay();
      if (!_isOverlayActive) {
        // Re-check
        _updateStatusMessageUI('无法激活悬浮窗以发送结果。');
        return;
      }
      await Future.delayed(
          const Duration(milliseconds: 500)); // Give it a moment to appear
    } else if (!_isOverlayVisible) {
      _updateStatusMessageUI("悬浮窗权限未授予，无法发送数据。");
      return;
    }

    final List<Map<String, dynamic>> ocrDataForOverlay = ocrResults.map((r) {
      return {
        'text': r.text,
        'rect': {
          'left': r.boundingBox.left,
          'top': r.boundingBox.top,
          'width': r.boundingBox.width,
          'height': r.boundingBox.height,
        },
      };
    }).toList();

    final messageToOverlay = {
      'type': 'ocr_results',
      'data': {
        'ocr_results': ocrDataForOverlay,
        'translated_text': translatedText,
        'image_bytes_count': imageBytes?.lengthInBytes ?? 0, // Info about image
        'timestamp': DateTime.now().toIso8601String(),
      }
    };
    // To send image bytes, it might need to be chunked or sent via a different mechanism if too large for shareData.
    // For now, we just send a reference or its size. The overlay_widget doesn't seem to use it directly yet.

    try {
      log.d(
          "Sending to overlay: type ocr_results. Text blocks: ${ocrDataForOverlay.length}, Translation: ${translatedText != null && translatedText.isNotEmpty}");
      await FlutterOverlayWindow.shareData(messageToOverlay);
      _updateStatusMessageUI(statusMessage + "\n结果已发送到悬浮窗。");
    } catch (e, s) {
      log.e("Error sending data to overlay: $e", error: e, stackTrace: s);
      _updateStatusMessageUI(statusMessage + "\n发送数据到悬浮窗失败: $e");
    }
  }

  Future<void> toggleOverlay() async {
    _isOverlayActive = await FlutterOverlayWindow.isActive() ?? false;
    if (_isOverlayActive) {
      await closeOverlay();
    } else {
      await showOverlay();
    }
  }

  Future<void> showOverlay() async {
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      await requestOverlayPermission(); // This will update status and try to show if granted
      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        // check again
        log.w(
            "Overlay permission still not granted after request from showOverlay.");
        _updateStatusMessageUI("悬浮窗权限未授予，无法显示。");
        return;
      }
    }

    _isOverlayActive = await FlutterOverlayWindow.isActive() ?? false;
    if (_isOverlayActive) {
      log.i("Overlay is already active.");
      // Consider bringing to front if platform supports it via a message
      // await FlutterOverlayWindow.shareData({'type': 'bring_to_front'});
      _updateOverlayStatus(baseMessage: "悬浮窗已活动。");
      return;
    }

    _updateStatusMessageUI('正在显示悬浮窗...');
    try {
      await FlutterOverlayWindow.showOverlay(
        height: 300, // Example initial size
        width: 400,
        alignment: OverlayAlignment.center,
        enableDrag: true,
        overlayTitle: "TranslaScreen OCR",
        flag: OverlayFlag.focusPointer,
      );
      // isActive might not update immediately. Rely on listener or next check.
      // We set _isOverlayActive via listener or explicit checks like _updateOverlayStatus
      log.i("FlutterOverlayWindow.showOverlay call succeeded.");
      // The listener for 'overlay_shown' should update _isOverlayActive
      // For now, optimistically assume it will show, status will be updated by listener or next check
      await Future.delayed(
          Duration(milliseconds: 200)); // Short delay for system to process
      await _updateOverlayStatus(baseMessage: "悬浮窗已请求显示。");
    } catch (e, s) {
      log.e("Error calling showOverlay: $e", error: e, stackTrace: s);
      _isOverlayActive = false; // Explicitly false on error
      _updateOverlayStatus(baseMessage: "显示悬浮窗失败: $e");
    }
  }

  Future<void> closeOverlay() async {
    _isOverlayActive = await FlutterOverlayWindow.isActive() ?? false;
    if (!_isOverlayActive) {
      log.i("Overlay is not active, cannot close.");
      await _updateOverlayStatus(baseMessage: "悬浮窗未运行。");
      return;
    }
    _updateStatusMessageUI('正在关闭悬浮窗...');
    try {
      await FlutterOverlayWindow.closeOverlay();
      // The listener for 'overlay_closed_by_user' or subsequent isActive checks will set _isOverlayActive = false
      log.i("FlutterOverlayWindow.closeOverlay call succeeded.");
      await Future.delayed(
          Duration(milliseconds: 200)); // Short delay for system to process
      await _updateOverlayStatus(baseMessage: "悬浮窗已关闭。");
    } catch (e, s) {
      log.e("Error closing overlay: $e", error: e, stackTrace: s);
      // State of _isOverlayActive might be uncertain here, _updateOverlayStatus will check
      await _updateOverlayStatus(baseMessage: "关闭悬浮窗失败: $e");
    }
  }

  void _handleDataFromOverlay(dynamic data) {
    log.i("[HomeController] Received data from overlay listener: $data");
    if (data is Map && data.containsKey('action')) {
      final String action = data['action'] as String;
      final Map<String, dynamic>? params =
          data['params'] as Map<String, dynamic>?;
      _handleOverlayCommand(action, params: params);
    } else if (data is String) {
      // Handle simple string messages if any (e.g. for state changes)
      if (data == 'overlay_closed_by_user') {
        _isOverlayActive = false;
        _updateOverlayStatus(baseMessage: "悬浮窗已被用户关闭。");
      } else if (data == 'overlay_shown') {
        _isOverlayActive = true;
        _updateOverlayStatus(baseMessage: "悬浮窗已显示并活动。");
      } else {
        log.i("[HomeController] Received string message from overlay: $data");
      }
    }
  }

  // Handles commands initiated FROM the overlay UI
  void _handleOverlayCommand(String command, {Map<String, dynamic>? params}) {
    log.i(
        "[HomeController] Handling command from overlay UI: $command, Params: $params");
    String commandStatus = "悬浮窗命令 '$command' ";

    switch (command) {
      case 'capture_and_ocr':
        commandStatus += "执行中...";
        toggleScreenCaptureAndOcr(
            sendToOverlay: true); // Overlay always wants results back
        break;
      case 'close_overlay_request': // Renamed to be specific
        commandStatus += "请求关闭...";
        closeOverlay();
        break;
      case 'request_show_main_app': // For overlay to bring main app to front
        // This would be platform specific or via a plugin that can bring app to foreground
        log.i("Overlay requested to show main app. (Feature not implemented)");
        commandStatus += "请求显示主应用 (暂未实现)";
        break;
      default:
        log.w("[HomeController] Unknown command from overlay UI: $command");
        commandStatus += "未知。";
    }
    _updateStatusMessageUI(
        statusMessage + "\n" + commandStatus); // Append command status
  }

  // Handles commands from the external HTTP server
  void _handleExternalCommand(String command, {Map<String, dynamic>? params}) {
    log.i(
        "[HomeController] Handling command from HTTP server: $command, Params: $params");
    String commandStatus = "外部命令 '$command' ";
    switch (command) {
      case 'capture_and_ocr':
        commandStatus += "执行中...";
        toggleScreenCaptureAndOcr(
            sendToOverlay: params?['sendToOverlay'] as bool? ?? true);
        break;
      case 'translate_fullscreen':
        commandStatus += "开始全屏翻译...";
        _startFullscreenTranslation(params?['language'] as String?);
        break;
      case 'close_overlay':
        commandStatus += "正在关闭悬浮窗...";
        closeOverlay();
        break;
      case 'show_overlay':
        commandStatus += "正在显示悬浮窗...";
        showOverlay();
        break;
      case 'reset_overlay_ui':
        log.i(
            "[HomeController] Received reset_overlay_ui command from external.");
        ocrResults = [];
        capturedImageBytes = null;
        translatedText = "";
        _sendDataToOverlay(
            ocrResults: [],
            translatedText: "",
            imageBytes: null); // Clear overlay
        commandStatus += "悬浮窗UI已重置。";
        break;
      default:
        log.w("[HomeController] Unknown external command: $command");
        commandStatus += "未知。";
    }
    _updateStatusMessageUI(
        statusMessage + "\n" + commandStatus); // Append command status
  }

  Future<void> _startFullscreenTranslation(String? targetLang) {
    log.i(
        "Placeholder: Fullscreen translation requested for language: ${targetLang ?? 'default'}");
    _updateStatusMessageUI("全屏翻译功能暂未实现。");
    return Future.value(); // Return a completed future
  }

  Future<void> saveSettingsAndReload(Map<String, dynamic> newSettings) async {
    _updateStatusMessageUI("正在保存设置...");
    bool requiresReload = false;

    final currentTargetLang = targetLanguageController.text;
    if (newSettings.containsKey('targetLanguage') &&
        newSettings['targetLanguage'] != currentTargetLang) {
      await _settingsService.setTargetLanguage(newSettings['targetLanguage']);
      targetLanguageController.text =
          newSettings['targetLanguage']; // Update local controller
      requiresReload = true; // Reload, as translation service might use this
    }

    if (newSettings.containsKey('openAiApiKey') &&
        newSettings['openAiApiKey'] !=
            await _settingsService.getOpenAiApiKey()) {
      await _settingsService.setOpenAiApiKey(newSettings['openAiApiKey']);
      requiresReload = true;
    }
    if (newSettings.containsKey('openAiApiEndpoint') &&
        newSettings['openAiApiEndpoint'] !=
            await _settingsService.getOpenAiApiEndpoint()) {
      await _settingsService
          .setOpenAiApiEndpoint(newSettings['openAiApiEndpoint']);
      requiresReload = true;
    }
    if (newSettings.containsKey('openAiModelName') &&
        newSettings['openAiModelName'] !=
            await _settingsService.getOpenAiModelName()) {
      await _settingsService.setOpenAiModelName(newSettings['openAiModelName']);
      requiresReload = true;
    }
    if (newSettings.containsKey('openAiTranslationApiKey') &&
        newSettings['openAiTranslationApiKey'] !=
            await _settingsService.getOpenAiTranslationApiKey()) {
      await _settingsService
          .setOpenAiTranslationApiKey(newSettings['openAiTranslationApiKey']);
      requiresReload = true;
    }
    if (newSettings.containsKey('openAiTranslationApiEndpoint') &&
        newSettings['openAiTranslationApiEndpoint'] !=
            await _settingsService.getOpenAiTranslationApiEndpoint()) {
      await _settingsService.setOpenAiTranslationApiEndpoint(
          newSettings['openAiTranslationApiEndpoint']);
      requiresReload = true;
    }
    if (newSettings.containsKey('openAiTranslationModelName') &&
        newSettings['openAiTranslationModelName'] !=
            await _settingsService.getOpenAiTranslationModelName()) {
      await _settingsService.setOpenAiTranslationModelName(
          newSettings['openAiTranslationModelName']);
      requiresReload = true;
    }

    if (newSettings.containsKey('selectedOcrEngine')) {
      OcrEngineType newEngine = newSettings['selectedOcrEngine'];
      if (newEngine != _selectedOcrEngine) {
        await _settingsService.setSelectedOcrEngine(newEngine);
        // _selectedOcrEngine will be updated in loadAndInitializeServices
        requiresReload = true;
      }
    }

    if (requiresReload) {
      log.i("Settings changed, reloading services.");
      await loadAndInitializeServices(); // This reloads services and updates statusMessage
    } else {
      _updateStatusMessageUI("设置已保存 (无变化)。");
    }
  }

  Future<Map<String, dynamic>> getSettingsForDialog() async {
    final openAIConfig = await _settingsService.getOpenAiConfig();
    final translationConfig =
        await _settingsService.getOpenAiTranslationConfig();
    return {
      'openAiApiKey': openAIConfig['apiKey'] ?? '',
      'openAiApiEndpoint':
          openAIConfig['apiEndpoint'] ?? SettingsService.defaultOpenAiEndpoint,
      'openAiModelName':
          openAIConfig['modelName'] ?? SettingsService.defaultOpenAiModel,
      'openAiTranslationApiKey': translationConfig['apiKey'] ?? '',
      'openAiTranslationApiEndpoint': translationConfig['apiEndpoint'] ??
          SettingsService.defaultOpenAiTranslationEndpoint,
      'openAiTranslationModelName': translationConfig['modelName'] ??
          SettingsService.defaultOpenAiTranslationModel,
      'selectedOcrEngine': await _settingsService.getSelectedOcrEngine(),
      'targetLanguage': await _settingsService.getTargetLanguage(),
    };
  }

  void _updateStatusMessageUI([String? newMessage]) {
    if (newMessage != null) {
      statusMessage = newMessage;
    }
    updateUi();
  }

  void showSettingsDialog() {
    // final context = getContext();
    // showDialog(
    //   context: context,
    //   builder: (BuildContext dialogContext) {
    //     return SettingsDialog( // This would be your custom settings dialog widget
    //       currentSettingsFuture: getSettingsForDialog(), // Pass as future
    //       onSave: (newSettings) async {
    //         await saveSettingsAndReload(newSettings);
    //         Navigator.of(dialogContext).pop();
    //         _updateStatusMessageUI();
    //       },
    //     );
    //   },
    // );
    log.i(
        "Settings dialog display is currently commented out pending SettingsDialog widget availability.");
    _updateStatusMessageUI(statusMessage + "\n打开设置对话框功能当前被注释。");
  }

  void showHelpDialog() {
    final context = getContext();
    // Construct the log path string at runtime
    final String logPathsInfo =
        "(路径: ${LoggerService.logFilePath}, ${LoggerService.crashLogFilePath})";
    final String helpContent = "欢迎使用 TranslaScreen!\n\n"
        "主要功能:\n"
        "1. **屏幕截图与OCR**: 点击 \"截图并OCR\" 按钮或使用悬浮窗按钮进行屏幕捕获和文字识别。\n"
        "   - **本地OCR**: 默认使用设备上的ML Kit进行识别。\n"
        "   - **OpenAI OCR**: 如果在设置中配置了OpenAI API密钥和相关参数，可以选择使用更强大的云端OCR。\n"
        "2. **文本翻译**: OCR识别出的文本会自动尝试使用OpenAI翻译服务进行翻译 (如果已配置)。\n"
        "   - **目标语言**: 您可以在主界面或设置中更改翻译的目标语言。\n"
        "3. **悬浮窗**: \n"
        "   - **权限**: 需要授予悬浮窗权限才能使用此功能。\n"
        "   - **显示/隐藏**: 通过主界面的 \"显示/隐藏悬浮窗\" 按钮或系统通知控制。\n"
        "   - **交互**: 悬浮窗可以显示OCR和翻译结果，并提供如重新截图、关闭等快捷操作。\n"
        "4. **命令服务器**: 应用内启动一个本地HTTP服务器 (通常在 http://localhost:10080)，用于接收外部命令。\n\n"
        "设置:\n"
        "- 点击主界面的设置图标进入设置页面 (如果设置对话框已实现)。\n"
        "- 配置OpenAI API密钥、API端点、模型名称等。\n"
        "- 选择默认的OCR引擎和翻译目标语言。\n\n"
        "日志:\n"
        "- 应用日志记录在应用文档目录下的 `app.log`。\n"
        "- 崩溃日志记录在 `crash.log`。\n"
        "$logPathsInfo\n\n"
        "提示:\n"
        "- 首次使用或权限更改后，某些功能可能需要应用重启或重新授权。\n"
        "- 确保网络连接对于使用OpenAI服务是必须的。";

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("帮助与信息"),
          content: SingleChildScrollView(
            child: Text(helpContent), // Use the dynamically built string
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("关闭"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
