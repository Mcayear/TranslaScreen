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
import 'overlay_widget.dart'; // Import the overlay widget
import 'settings_page.dart'; // Import Settings Page

// Overlay Entry Point
@pragma("vm:entry-point")
void overlayMain() {
  // runApp an instance of your overlay widget here
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SimpleOverlayWidget(), // Use the widget we created
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
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

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

  @override
  void initState() {
    super.initState();
    _settingsService = SettingsService(); // Initialize SettingsService
    _localOcrService =
        LocalOcrService(); // Initialize Local OCR Service (always available as fallback or default)
    _loadAndInitializeServices(); // New method to load settings and init appropriate OCR service
    WidgetsBinding.instance.addObserver(this);
    // Listen for data from overlay
    FlutterOverlayWindow.overlayListener.listen((data) {
      log("Data from overlay: $data");
      setState(() {
        _dataFromOverlay = data.toString();
      });
    });
  }

  @override
  void dispose() {
    _localOcrService.dispose(); // Dispose Local OCR Service
    _openAiOcrService?.dispose(); // Dispose OpenAI OCR Service if it exists
    _translationService?.dispose(); // Dispose translation service
    _targetLanguageController.dispose(); // Dispose language controller
    WidgetsBinding.instance.removeObserver(this);
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
        print(
            "OpenAI OCR API key not configured or invalid. Falling back to Local OCR.");
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
      print(
          "OpenAI Translation API key not configured or invalid. Translation will be unavailable.");
      // We don't force fallback for translation, it just won't be available.
    }

    await _checkInitialPermissions();
    setState(() {
      _isInitializing = false;
    });
  }

  Future<void> _toggleScreenCaptureAndOcr() async {
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
        _screenCaptureProcessed =
            true; // Still mark as processed to update UI state
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
        print("Error during OCR processing: $e");
        _statusMessage = "OCR 处理出错: $e";
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
    } else {
      setState(() {
        _capturedImageBytes = null;
        _screenCaptureProcessed = true;
        _statusMessage = '屏幕捕获失败或未返回图像数据。';
      });
    }
    _updateStatusMessage(); // This might override specific messages set above, review if needed
  }

  Future<void> _toggleOverlay() async {
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
      // Show overlay
      await FlutterOverlayWindow.showOverlay(
        // entryPoint: overlayMain, // Not needed if only one @pragma("vm:entry-point") void overlayMain() exists
        height: 300, // Example height
        width: 250, // Example width
        alignment: OverlayAlignment.center,
        flag: OverlayFlag.clickThrough, // Example: allow click-through
        overlayTitle: "TranslaScreen 悬浮窗",
        overlayContent: "悬浮窗正在运行",
        enableDrag: true,
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
    // Example: send OCR results count or first result to overlay
    String dataToSend = "来自主应用的消息: ${DateTime.now().second}";
    if (_ocrResults.isNotEmpty) {
      dataToSend =
          "OCR发现: ${_ocrResults.first.text.substring(0, (_ocrResults.first.text.length > 20 ? 20 : _ocrResults.first.text.length))}...";
    }
    await FlutterOverlayWindow.shareData(dataToSend);
    setState(() {
      _statusMessage = "已发送数据到悬浮窗: $dataToSend";
    });
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
      _statusMessage = permStatus + "\n" + overlayStatus + captureMsg + ocrMsg;
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
      print("Error during translation call: $e");
      setState(() {
        _translatedText = "翻译时发生错误: $e";
      });
    } finally {
      setState(() {
        _isTranslating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: const Text('TranslaScreen - 控制面板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
              // Reload settings and re-initialize services when returning from settings page
              _loadAndInitializeServices();
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
                // Column is also a layout widget. It takes a list of children and
                // arranges them vertically. By default, it sizes itself to fit its
                // children horizontally, and tries to be as tall as its parent.
                //
                // Column has various properties to control how it sizes itself and
                // how it positions its children. Here we use mainAxisAlignment to
                // center the children vertically; the main axis here is the vertical
                // axis because Columns are vertical (the cross axis would be
                // horizontal).
                //
                // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
                // action in the IDE, or press "p" in the console), to see the
                // wireframe for each widget.
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
                                style:
                                    TextStyle(color: Colors.deepPurpleAccent)),
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
                    onPressed: _toggleOverlay,
                    child: Text(_isOverlayVisible ? '关闭悬浮窗' : '显示悬浮窗'),
                  ),
                  if (_isOverlayVisible)
                    Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: ElevatedButton(
                        onPressed: _sendDataToOverlay,
                        child: const Text('发送OCR摘要到悬浮窗'), // Updated button text
                      ),
                    ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed:
                        _toggleScreenCaptureAndOcr, // Changed to new combined function
                    child: const Text('截图并执行OCR'),
                  ),
                  const SizedBox(height: 20),
                  if (_ocrResults.isNotEmpty && _translationService != null)
                    Column(
                      children: [
                        const Divider(height: 20, thickness: 1),
                        const Text('翻译设置和结果',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _targetLanguageController,
                          decoration: const InputDecoration(
                            labelText: '目标翻译语言',
                            border: OutlineInputBorder(),
                            hintText: '例如: English, 中文, 日本語',
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed:
                              _isTranslating ? null : _translateOcrResults,
                          child: _isTranslating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Text('翻译OCR文本 (OpenAI)'),
                        ),
                      ],
                    ),
                  if (_isTranslating || _translatedText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("翻译结果:",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.all(8.0),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                            child: SelectableText(_translatedText,
                                textAlign: TextAlign.left,
                                style: const TextStyle(fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    '使用说明:\n1. 点击"检查/请求悬浮窗权限 (插件)"。\n2. 点击"显示悬浮窗"以激活。可拖动。\n3. 点击"截图并执行OCR"获取图像并执行OCR。\n4. (可选) 在设置中配置OpenAI OCR和/或翻译API密钥。\n5. 如果OCR成功且翻译服务已配置，输入目标语言并点击翻译按钮。',
                    textAlign: TextAlign.left,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
    );
  }
}
