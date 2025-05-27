import 'dart:developer'; // For log
import 'dart:typed_data';
import 'dart:ui' as ui; // For ui.Image and ui.Size for OCR service
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'services/native_bridge.dart';
import 'services/ocr_service.dart'; // Import Local OCR Service
import 'services/openai_ocr_service.dart'; // Import OpenAI OCR Service
import 'services/openai_translation_service.dart'; // Import OpenAI Translation Service
import 'services/settings_service.dart'; // Import Settings Service
import 'overlay_widget.dart'; // Import the overlay widget with InteractiveOverlayUI
import 'settings_page.dart'; // Import Settings Page
import 'dart:convert';
import 'dart:io'; // For HttpServer
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

// Overlay Entry Point
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: InteractiveOverlayUI(), // 使用新创建的交互式悬浮窗 UI
    ),
  );
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TranslaScreen',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  // bool _canDrawOverlays = false; // Now handled by flutter_overlay_window
  bool _isOverlayVisible = false;
  bool _screenCaptureProcessed = false;
  String _statusMessage = "";
  Uint8List? _capturedImageBytes;
  String _dataFromOverlay = "";
  List<OcrResult> _ocrResults = []; // To store OCR results

  late LocalOcrService _localOcrService; // Declare Local OCR service instance
  OpenAiOcrService?
      _openAiOcrService; // Declare OpenAI OCR service instance (nullable)
  late SettingsService _settingsService; // Declare SettingsService instance
  OcrEngineType _selectedOcrEngine = OcrEngineType.local; // Default
  bool _isInitializing = true; // Loading settings and services

  // New state variables for Translation
  OpenAiTranslationService? _translationService;
  final TextEditingController _targetLanguageController =
      TextEditingController(text: '中文'); // Default target language
  String _translatedText = "";
  bool _isTranslating = false;
  String _textToTranslate = ""; // To store combined OCR text

  HttpServer? _commandServer; // HTTP服务器实例

  @override
  void initState() {
    super.initState();
    _settingsService = SettingsService(); // Initialize SettingsService
    _localOcrService =
        LocalOcrService(); // Initialize Local OCR Service (always available as fallback or default)
    _loadAndInitializeServices(); // New method to load settings and init appropriate OCR service
    WidgetsBinding.instance.addObserver(this);
    _startCommandServer(); // 启动HTTP命令服务器
  }

  Future<void> _startCommandServer() async {
    try {
      var handler = const shelf.Pipeline()
          .addMiddleware(shelf.logRequests())
          .addHandler(_commandRequestHandler);

      _commandServer = await shelf_io.serve(handler, 'localhost', 8080);
      print('[Main] Command server started at http://localhost:8080');
      setState(() {
        _statusMessage = "命令服务器已启动: http://localhost:8080";
        _updateStatusMessage();
      });
    } catch (e) {
      print('[Main] Error starting command server: $e');
      setState(() {
        _statusMessage = "命令服务器启动失败: $e";
        _updateStatusMessage();
      });
    }
  }

  Future<shelf.Response> _commandRequestHandler(shelf.Request request) async {
    if (request.method == 'POST' && request.url.path == 'command') {
      try {
        final body = await request.readAsString();
        final Map<String, dynamic> data = jsonDecode(body);
        final String? action = data['action'] as String?;

        print('[Main] Received command via HTTP: $action, data: $data');

        if (action != null) {
          // 直接调用，不再使用 addPostFrameCallback 进行测试
          print(
              '[Main] Attempting to call _handleOverlayCommand directly for action: $action');
          _handleOverlayCommand(action);
          print(
              '[Main] _handleOverlayCommand was called directly for action: $action');
          return shelf.Response.ok(jsonEncode({
            'status': 'Command received and processed (direct call)',
            'action': action
          }));
        } else {
          return shelf.Response.badRequest(
              body: jsonEncode({'error': 'Missing action in command'}));
        }
      } catch (e, s) {
        // 添加堆栈跟踪
        print('[Main] Error processing HTTP command: $e\nStack trace: $s');
        return shelf.Response.internalServerError(
            body: jsonEncode({'error': 'Error processing command: $e'}));
      }
    }
    return shelf.Response.notFound(jsonEncode({'error': 'Not found'}));
  }

  @override
  void dispose() {
    _localOcrService.dispose(); // Dispose Local OCR Service
    _openAiOcrService?.dispose(); // Dispose OpenAI OCR Service if it exists
    _translationService?.dispose(); // Dispose translation service
    _targetLanguageController.dispose(); // Dispose language controller
    WidgetsBinding.instance.removeObserver(this);
    _commandServer?.close(force: true).then((_) {
      print('[Main] Command server stopped.');
    });
    // It's good practice to close overlay if app is completely closing, if applicable.
    // FlutterOverlayWindow.closeOverlay();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkOverlayPermissionStatus();
    }
  }

  Future<void> _checkInitialPermissions() async {
    await _checkOverlayPermissionStatus();
    setState(() {
      _screenCaptureProcessed = false;
      _capturedImageBytes = null;
      _ocrResults = [];
      _updateStatusMessage();
    });
  }

  Future<void> _checkOverlayPermissionStatus() async {
    final bool granted = await FlutterOverlayWindow.isPermissionGranted();
    setState(() {
      // _canDrawOverlays = granted; // No longer need this state variable directly for UI logic if using plugin's request
      _updateStatusMessage();
      if (!granted) {
        _statusMessage = "悬浮窗权限未授予。请通过按钮请求权限。";
      } else {
        // If already granted, ensure status message reflects this if it was previously showing 'not granted'
        if (_statusMessage.contains("悬浮窗权限未授予")) _statusMessage = "悬浮窗权限已授予。";
      }
    });
  }

  Future<void> _requestOverlayPermission() async {
    setState(() {
      _statusMessage = '正在请求悬浮窗权限...';
      _capturedImageBytes = null;
      _ocrResults = [];
    });
    final bool? granted = await FlutterOverlayWindow.requestPermission();
    setState(() {
      if (granted == true) {
        _statusMessage = '悬浮窗权限已授予。';
      } else {
        _statusMessage = '悬浮窗权限请求被拒绝或失败。';
      }
      _updateStatusMessage();
    });
  }

  Future<void> _loadAndInitializeServices() async {
    setState(() {
      _isInitializing = true;
      _translatedText = ""; // Reset translated text on reload
      _textToTranslate = ""; // Reset text to translate
    });
    _selectedOcrEngine = await _settingsService.getSelectedOcrEngine();
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
      } else {
        _selectedOcrEngine = OcrEngineType.local;
        _openAiOcrService = null;
        log("OpenAI OCR API key not configured or invalid. Falling back to Local OCR.");
      }
    } else {
      _openAiOcrService = null;
    }

    // Initialize Translation Service
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
    } else {
      _translationService = null; // Ensure it's null if not configured
      log("OpenAI Translation API key not configured or invalid. Translation will be unavailable.");
      // We don't force fallback for translation, it just won't be available.
    }

    await _checkInitialPermissions();
    setState(() {
      _isInitializing = false;
    });
  }

  Future<void> _toggleScreenCaptureAndOcr({bool sendToOverlay = false}) async {
    setState(() {
      _capturedImageBytes = null;
      _screenCaptureProcessed = false;
      _ocrResults = [];
      _statusMessage = '正在准备开始屏幕捕获...';
    });

    final bool overlayPermGranted =
        await FlutterOverlayWindow.isPermissionGranted();
    if (!overlayPermGranted) {
      setState(() {
        _statusMessage = '进行OCR前，请先授予悬浮窗权限（后续用于显示结果）。';
        _screenCaptureProcessed = true;
      });
      return;
    }

    setState(() {
      _statusMessage = '正在请求屏幕捕获权限和截图...';
    });

    final Uint8List? imageBytes = await NativeBridge.startScreenCapture();

    if (imageBytes != null) {
      setState(() {
        _capturedImageBytes = imageBytes;
        _statusMessage =
            '截图成功！正在进行OCR识别 (${_selectedOcrEngine == OcrEngineType.openai ? "OpenAI" : "本地"})...';
      });

      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final int imageWidth = frame.image.width;
      final int imageHeight = frame.image.height;
      frame.image.dispose();

      List<OcrResult> results = [];
      try {
        if (_selectedOcrEngine == OcrEngineType.openai &&
            _openAiOcrService != null) {
          if (_openAiOcrService!.apiKey.isEmpty ||
              _openAiOcrService!.apiKey == 'YOUR_OPENAI_API_KEY') {
            _statusMessage = 'OpenAI API Key 未配置。请在设置中配置。转用本地OCR。';
            results = await _localOcrService.processImageBytes(imageBytes);
          } else {
            results = await _openAiOcrService!
                .processImageBytes(imageBytes, imageWidth, imageHeight);
          }
        } else {
          results = await _localOcrService.processImageBytes(imageBytes);
        }
      } catch (e) {
        log("Error during OCR processing: $e");
        _statusMessage = "OCR 处理出错: $e";
        setState(() {
          _screenCaptureProcessed = true;
        });
        return;
      }

      setState(() {
        _ocrResults = results;
        _screenCaptureProcessed = true;
        if (results.isNotEmpty &&
            !(results.length == 1 &&
                results.first.text.contains("API Key not configured"))) {
          _statusMessage =
              'OCR完成 (${_selectedOcrEngine == OcrEngineType.openai ? "OpenAI" : "本地"})！识别到 ${results.length} 个文本块。';
        } else if (results.isNotEmpty &&
            results.first.text.contains("API Key not configured")) {
          // Status already set above for this specific case
        } else {
          _statusMessage =
              'OCR完成 (${_selectedOcrEngine == OcrEngineType.openai ? "OpenAI" : "本地"})，但未识别到文本。';
        }
      });

      // 如果需要发送到悬浮窗并且有OCR结果，直接处理翻译和发送
      if (sendToOverlay && results.isNotEmpty && _translationService != null) {
        setState(() {
          _statusMessage = '正在准备翻译并发送到悬浮窗...';
        });
        await _sendDataToOverlay(); // 此方法现在已增强，会处理翻译和发送到悬浮窗
      }
    } else {
      setState(() {
        _capturedImageBytes = null;
        _screenCaptureProcessed = true;
        _statusMessage = '屏幕捕获失败或未返回图像数据。';
      });
    }
    _updateStatusMessage();
  }

  Future<void> _toggleOverlay(BuildContext context) async {
    if (_isOverlayVisible) {
      await FlutterOverlayWindow.closeOverlay();
      setState(() {
        _isOverlayVisible = false;
        _statusMessage = "悬浮窗已关闭。";
      });
    } else {
      final bool permGranted = await FlutterOverlayWindow.isPermissionGranted();
      if (!permGranted) {
        setState(() {
          _statusMessage = "无法显示悬浮窗：权限未授予。请先请求权限。";
        });
        await _requestOverlayPermission(); // Attempt to request if not granted
        // Recheck after request attempt
        if (!await FlutterOverlayWindow.isPermissionGranted()) return;
      }

      // // 获取屏幕尺寸，用于全屏悬浮窗
      // final MediaQueryData mediaQuery =
      //     MediaQueryData.fromView(View.of(context));
      // final double screenWidth = mediaQuery.size.width;
      // final double screenHeight = mediaQuery.size.height;

      // Show overlay with full screen size
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true, // 保持 FAB 可拖动
        overlayTitle: "TranslaScreen 悬浮窗",
        overlayContent: "悬浮窗正在运行",
        flag: OverlayFlag.defaultFlag, // 允许交互
        visibility: NotificationVisibility.visibilityPublic,
        // positionGravity: PositionGravity.auto,
        height: 56 * 4,
        width: 56 * 4,
        startPosition: const OverlayPosition(0, -259),
      );
      setState(() {
        _isOverlayVisible = true;
        _statusMessage = "悬浮窗已显示。";
      });
    }
    _updateStatusMessage();
  }

  Future<void> _sendDataToOverlay() async {
    if (!_isOverlayVisible) {
      setState(() {
        _statusMessage = "悬浮窗未激活，无法发送数据。";
      });
      return;
    }

    // 如果有 OCR 结果，尝试翻译并发送遮罩数据
    if (_ocrResults.isNotEmpty) {
      setState(() {
        _statusMessage = "正在准备翻译结果并发送到悬浮窗...";
      });

      // 如果配置了翻译服务，执行翻译
      if (_translationService != null) {
        try {
          // 构建要翻译的文本列表
          final List<String> textsToTranslate =
              _ocrResults.map((result) => result.text).toList();
          final List<Map<String, dynamic>> maskItems = [];

          // 对每个 OCR 块分别翻译
          for (int i = 0; i < _ocrResults.length; i++) {
            final OcrResult ocrResult = _ocrResults[i];
            final String text = textsToTranslate[i];

            // 翻译文本
            final String translatedText = await _translationService!.translate(
              text,
              _targetLanguageController.text.trim().isEmpty
                  ? '中文' // 默认翻译为中文
                  : _targetLanguageController.text.trim(),
            );

            // 转换 OcrResult.boundingBox 为悬浮窗期望的格式
            final maskItem = {
              'bbox': {
                'l': ocrResult.boundingBox.left,
                't': ocrResult.boundingBox.top,
                'w': ocrResult.boundingBox.width,
                'h': ocrResult.boundingBox.height,
              },
              'translatedText': translatedText,
              'originalText': text, // 原始文本，可用于调试或后续功能
            };

            maskItems.add(maskItem);
          }

          // 将翻译遮罩数据发送到悬浮窗
          final data = {
            'type': 'display_translation_mask',
            'items': maskItems,
          };

          await FlutterOverlayWindow.shareData(jsonEncode(data));
          setState(() {
            _statusMessage = "已将翻译结果发送到悬浮窗显示。";
          });
        } catch (e) {
          log("翻译或发送数据时出错: $e");
          setState(() {
            _statusMessage = "翻译出错: $e";
          });
        }
      } else {
        // 无翻译服务时，发送普通摘要数据
        String dataToSend =
            "OCR发现: ${_ocrResults.first.text.substring(0, (_ocrResults.first.text.length > 20 ? 20 : _ocrResults.first.text.length))}...";
        await FlutterOverlayWindow.shareData(dataToSend);
        setState(() {
          _statusMessage = "已发送 OCR 摘要到悬浮窗 (无翻译服务): $dataToSend";
        });
      }
    } else {
      // 无 OCR 结果时，发送普通消息
      String dataToSend = "来自主应用的消息: ${DateTime.now().second}";
      await FlutterOverlayWindow.shareData(dataToSend);
      setState(() {
        _statusMessage = "已发送消息到悬浮窗: $dataToSend";
      });
    }
  }

  void _updateStatusMessage() {
    final bool permGranted = FlutterOverlayWindow.isPermissionGranted() == true;
    String permStatus = "悬浮窗权限: ${permGranted ? '已授予' : '未授予'}";
    String overlayStatus = "悬浮窗状态: ${_isOverlayVisible ? '可见' : '已关闭'}";
    String captureMsg = "";
    String ocrMsg = "";

    if (_screenCaptureProcessed) {
      captureMsg = _capturedImageBytes != null ? "\n截图: 已捕获" : "\n截图: 失败";
      if (_capturedImageBytes != null) {
        ocrMsg = _ocrResults.isNotEmpty
            ? "\nOCR: 发现 ${_ocrResults.length} 项"
            : "\nOCR: 未发现文本";
      }
    }

    // Prioritize specific action messages
    if (!(_statusMessage.startsWith('正在') ||
        _statusMessage.startsWith('如果') ||
        _statusMessage.contains('截图成功') ||
        _statusMessage.contains('OCR完成') ||
        _statusMessage.contains('屏幕捕获失败') ||
        _statusMessage.contains('悬浮窗已关闭') ||
        _statusMessage.contains('悬浮窗已显示') ||
        _statusMessage.contains('无法显示悬浮窗') ||
        _statusMessage.contains('已发送数据'))) {
      _statusMessage = "$permStatus\n$overlayStatus$captureMsg$ocrMsg";
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _translateOcrResults() async {
    if (_ocrResults.isEmpty) {
      setState(() {
        _translatedText = "没有文本可供翻译。";
      });
      return;
    }
    if (_translationService == null) {
      setState(() {
        _translatedText = "翻译服务未配置或API密钥无效。请检查设置。";
      });
      return;
    }

    setState(() {
      _isTranslating = true;
      _translatedText = "正在翻译...";
      // Combine text from all OCR blocks
      _textToTranslate = _ocrResults.map((r) => r.text).join("\n");
    });

    try {
      final String translationResult = await _translationService!.translate(
        _textToTranslate,
        _targetLanguageController.text.trim().isEmpty
            ? '中文' // Default to Chinese if field is empty
            : _targetLanguageController.text.trim(),
      );
      setState(() {
        _translatedText = translationResult;
      });
    } catch (e) {
      log("Error during translation call: $e");
      setState(() {
        _translatedText = "翻译时发生错误: $e";
      });
    } finally {
      setState(() {
        _isTranslating = false;
      });
    }
  }

  // 处理来自悬浮窗的命令 (现在由HTTP服务器调用)
  void _handleOverlayCommand(String? action) {
    print("[Main] _handleOverlayCommand CALLED with action: $action");
    if (action == null) {
      print("[Main] _handleOverlayCommand received null action.");
      return;
    }

    print("[Main] Handling overlay command: $action");

    if (action == "start_fullscreen_translation") {
      _startFullscreenTranslation();
    } else if (action == "start_area_selection") {
      _startAreaSelection();
    } else if (action == "reset_overlay_ui") {
      // 如果悬浮窗需要主应用重置某些状态（虽然它现在自己处理UI）
      // 可以在这里添加逻辑，例如清除主应用中与悬浮窗相关的状态
      print(
          "[Main] Received reset_overlay_ui command. (No specific action taken in main app for now)");
    } else {
      print("[Main] Unknown overlay command: $action");
    }
    setState(() {
      _statusMessage = "收到命令: $action";
      _updateStatusMessage();
    });
  }

  // 开始全屏翻译流程
  Future<void> _startFullscreenTranslation() async {
    // 使用现有的截图和 OCR 逻辑，但将结果发送到悬浮窗而非显示在主应用中
    await _toggleScreenCaptureAndOcr(sendToOverlay: true);
  }

  // 开始选区翻译流程
  Future<void> _startAreaSelection() async {
    // 暂时使用全屏翻译流程代替，后续实现区域选择功能
    log("选区翻译功能尚未实现，暂时使用全屏翻译代替");
    await _startFullscreenTranslation();

    // 选区翻译的完整实现应该包括：
    // 1. 在悬浮窗中显示区域选择 UI
    // 2. 用户选择区域后获取该区域坐标
    // 3. 仅对该区域进行截图
    // 4. 对截图进行 OCR 和翻译
    // 5. 将结果发送到悬浮窗显示为遮罩
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('TranslaScreen - 控制面板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
              // 设置页面返回后，重新加载服务配置
              await _loadAndInitializeServices();
            },
            tooltip: '设置',
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(
              child: CircularProgressIndicator(semanticsLabel: "正在加载设置..."))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    _statusMessage, // This will display the latest status
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  if (_dataFromOverlay.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        "来自悬浮窗的数据: $_dataFromOverlay",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.blueAccent),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (_capturedImageBytes != null)
                    Column(
                      children: [
                        SizedBox(
                          height: 150, // Constrain image height
                          child: InteractiveViewer(
                              child: Image.memory(_capturedImageBytes!,
                                  fit: BoxFit.contain)),
                        ),
                        if (_ocrResults.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                                "OCR识别文本 (首条): '${_ocrResults.first.text}'",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.deepPurpleAccent)),
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _requestOverlayPermission,
                    child: const Text('检查/请求悬浮窗权限 (插件)'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      _toggleOverlay(context);
                    },
                    child: Text(_isOverlayVisible ? '关闭悬浮窗' : '显示悬浮窗'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed:
                        _toggleScreenCaptureAndOcr, // Changed to new combined function
                    child: const Text('截图并执行OCR'),
                  ),
                  const SizedBox(height: 20),

                  // 保留翻译设置，但简化UI
                  if (_translationService != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: TextField(
                        controller: _targetLanguageController,
                        decoration: const InputDecoration(
                          labelText: '设置翻译目标语言 (默认: 中文)',
                          border: OutlineInputBorder(),
                          hintText: '例如: English, 中文, 日本語',
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),
                  const Text(
                    '使用说明:\n'
                    '1. 点击"检查/请求悬浮窗权限 (插件)"。\n'
                    '2. 点击"显示悬浮窗"激活翻译悬浮球 (可拖动)。\n'
                    '3. 单击悬浮球展开功能菜单：\n'
                    '   - 绿色图标: 全屏翻译\n'
                    '   - 蓝色图标: 选区翻译 (暂未完全实现)\n'
                    '4. 长按悬浮球直接触发全屏翻译。\n'
                    '5. 翻译完成后在屏幕上显示翻译遮罩，再次点击悬浮球关闭遮罩。\n'
                    '\n注意: OCR 结果的质量取决于屏幕内容的清晰度和文本布局。',
                    textAlign: TextAlign.left,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
    );
  }
}
