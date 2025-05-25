import 'dart:typed_data'; // Ensure Uint8List is imported
import 'package:flutter/material.dart';
import 'services/native_bridge.dart'; // 导入 NativeBridge

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
  // Add WidgetsBindingObserver
  bool _canDrawOverlays = false;
  bool _screenCaptureProcessed =
      false; // Tracks if capture process was initiated and completed/failed
  String _statusMessage = "";
  Uint8List? _capturedImageBytes; // To store the captured image

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Register observer
    _checkInitialPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Unregister observer
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 当应用从后台恢复时 (例如从系统设置页返回后)
    // 重新检查悬浮窗权限
    if (state == AppLifecycleState.resumed) {
      _checkOverlayPermission();
    }
  }

  Future<void> _checkInitialPermissions() async {
    await _checkOverlayPermission();
    // 屏幕捕获状态通常在用户操作后才改变，初始为 false
    setState(() {
      _screenCaptureProcessed = false;
      _capturedImageBytes = null;
    });
  }

  Future<void> _checkOverlayPermission() async {
    final bool granted = await NativeBridge.canDrawOverlays();
    setState(() {
      _canDrawOverlays = granted;
      _updateStatusMessage();
    });
  }

  Future<void> _requestOverlayPermission() async {
    setState(() {
      _statusMessage = '正在请求悬浮窗权限...';
      _capturedImageBytes = null; // Clear previous image if any
    });
    // 即使原生端在 startActivityForResult 后立即返回 false，
    // 我们也应该提示用户去设置。用户返回后，didChangeAppLifecycleState 会触发检查。
    await NativeBridge.requestSystemAlertWindowPermission();
    // 提示用户检查设置，因为我们无法直接得到结果
    // 真正的状态更新会在 app resumed 时通过 _checkOverlayPermission 完成
    setState(() {
      _statusMessage = '如果权限未授予，请在系统设置中开启本应用的"显示在其他应用的上层"权限。';
    });
    // 短暂延迟后再次检查，以防用户快速操作
    await Future.delayed(const Duration(seconds: 1));
    await _checkOverlayPermission();
  }

  Future<void> _toggleScreenCapture() async {
    // Reset previous capture attempt state
    setState(() {
      _capturedImageBytes = null;
      _screenCaptureProcessed = false;
      _statusMessage = '正在准备开始屏幕捕获...';
    });

    if (!_canDrawOverlays) {
      setState(() {
        _statusMessage = '请先授予悬浮窗权限，才能开始屏幕捕获。';
        _screenCaptureProcessed =
            true; // Mark as processed (failed due to permission)
      });
      return;
    }

    setState(() {
      _statusMessage = '正在请求屏幕捕获权限和截图...';
    });

    final Uint8List? imageBytes = await NativeBridge.startScreenCapture();

    setState(() {
      _capturedImageBytes = imageBytes;
      _screenCaptureProcessed = true; // Mark as processed
      if (imageBytes != null) {
        _statusMessage = '屏幕截图已成功捕获！';
      } else {
        _statusMessage = '屏幕捕获失败或未返回图像数据。';
      }
      _updateStatusMessage(); // Update the general status part
    });
  }

  void _updateStatusMessage() {
    String permStatus = "悬浮窗权限: ${_canDrawOverlays ? '已授予' : '未授予'}";
    String captureStatus = "";

    if (_screenCaptureProcessed) {
      captureStatus =
          _capturedImageBytes != null ? "截图状态: 成功捕获" : "截图状态: 失败或无数据";
    }

    // Keep the specific message from _toggleScreenCapture if image is just captured or failed
    // Otherwise, show a general status.
    if (_statusMessage.startsWith('正在') ||
        _statusMessage.startsWith('如果') ||
        _statusMessage.contains('截图已成功捕获') ||
        _statusMessage.contains('失败或未返回图像数据')) {
      // Use the more specific status message already set.
    } else {
      _statusMessage = permStatus + "\n" + captureStatus;
    }

    // This ensures the UI updates if _statusMessage was changed by other methods.
    // If only called from other setState blocks, this direct setState here might be redundant
    // but helps if _updateStatusMessage is called from somewhere else without its own setState.
    if (mounted) {
      setState(() {}); // Re-render with the potentially updated _statusMessage
    }
  }

  @override
  Widget build(BuildContext context) {
    // Call _updateStatusMessage directly here if you want it to execute before every build.
    // However, it's better to update the message only when state actually changes.
    // The current setup updates it in initState and after permission checks/toggles.
    // If you need it to be absolutely fresh on every build, uncomment the next line
    // and consider removing some setState calls within _updateStatusMessage or make it smarter.
    // _updateStatusMessage();

    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: const Text('TranslaScreen - 控制面板'),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Padding(
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
              const SizedBox(height: 10),
              if (_capturedImageBytes != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: InteractiveViewer(
                        child: Image.memory(_capturedImageBytes!,
                            fit: BoxFit.contain)),
                  ),
                ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (!_canDrawOverlays) {
                    await _requestOverlayPermission();
                  } else {
                    // 如果已经有权限，可以提示用户，或者什么都不做
                    setState(() {
                      _statusMessage = '悬浮窗权限已经授予。';
                      _capturedImageBytes =
                          null; // Clear image when re-checking permission
                    });
                    await _checkOverlayPermission(); // 再次确认
                  }
                },
                child: Text(_canDrawOverlays ? '悬浮窗权限已授予' : '检查/请求悬浮窗权限'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _toggleScreenCapture,
                child: const Text('捕获一次屏幕截图'), // Changed button text
              ),
              const SizedBox(height: 20),
              const Text(
                '使用说明:\n1. 点击"检查/请求悬浮窗权限"。如果未授予，将跳转到系统设置。请手动开启权限后返回本应用。\n2. 权限授予后，按钮文字会更新。\n3. 点击"捕获一次屏幕截图"以获取当前屏幕内容图像。',
                textAlign: TextAlign.left,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
