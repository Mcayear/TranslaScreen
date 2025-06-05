import 'package:flutter/material.dart';
import 'package:transla_screen/app/features/home/application/home_controller.dart';
import 'package:transla_screen/app/features/settings/presentation/settings_page.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  MyHomePageState createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  late final HomeController _controller;

  // 公开controller以便外部访问
  HomeController get controller => _controller;

  @override
  void initState() {
    super.initState();
    _controller = HomeController(
      updateUi: () {
        if (mounted) {
          setState(() {});
        }
      },
      getContext: () => context, // Pass context getter
    );
    _controller.initialize();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _controller.loadAndInitializeServices();
    }
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
              await _controller.loadAndInitializeServices();
            },
            tooltip: '设置',
          ),
        ],
      ),
      body: _controller.isInitializing
          ? const Center(
              child: CircularProgressIndicator(semanticsLabel: "正在加载设置..."))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    _controller.statusMessage, // Display status from controller
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  if (_controller.capturedImageBytes != null)
                    Column(
                      children: [
                        SizedBox(
                          height: 150, // Constrain image height
                          child: InteractiveViewer(
                              child: Image.memory(
                                  _controller.capturedImageBytes!,
                                  fit: BoxFit.contain)),
                        ),
                        if (_controller.ocrResults.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                                "OCR识别结果 (${_controller.ocrResults.length} 条):\n${_controller.ocrResults.map((r) => "  - \"${r.text}\" (区域: ${r.boundingBox.left}, ${r.boundingBox.top}, ${r.boundingBox.width}, ${r.boundingBox.height})").join('\n')}",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.deepPurpleAccent)),
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _controller.requestOverlayPermission,
                    child: const Text('检查/请求悬浮窗权限 (插件)'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      _controller
                          .toggleOverlay(); // Context is now passed via getContext
                    },
                    child: Text(_controller.isOverlayEffectivelyVisible
                        ? '关闭悬浮窗'
                        : '显示悬浮窗'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _controller.toggleScreenCaptureAndOcr,
                    child: const Text('截图并执行OCR'),
                  ),
                  const SizedBox(height: 20),
                  if (_controller.isTranslationServiceAvailable)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: TextField(
                        controller: _controller.targetLanguageController,
                        decoration: const InputDecoration(
                          labelText: '设置翻译目标语言 (默认: 中文)',
                          border: OutlineInputBorder(),
                          hintText: '例如: English, 中文, 日本語',
                        ),
                      ),
                    ),
                  // The translate button and translated text display can be added if needed here
                  // For example, if you want to show translated text in main UI, not just overlay
                  // ElevatedButton(onPressed: _controller.translateOcrResults, child: Text("翻译OCR结果 (在下方显示)")),
                  // if (_controller.translatedText.isNotEmpty)
                  //   Padding(
                  //     padding: const EdgeInsets.symmetric(vertical: 8.0),
                  //     child: Text(
                  //       _controller.translatedText,
                  //       textAlign: TextAlign.center,
                  //     ),
                  //   ),
                  const SizedBox(height: 20),
                  const Text(
                    '使用说明:\n'
                    '1. 点击"检查/请求悬浮窗权限 (插件)".\n'
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
