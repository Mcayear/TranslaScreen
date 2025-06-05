import 'dart:async'; // Import for StreamController
import 'package:flutter/material.dart';
import 'dart:ui' as ui; // 导入ui库获取屏幕信息
import 'package:overlay_windows_plugin/overlay_windows_plugin.dart';
import 'package:overlay_windows_plugin/overlay_windows_api.g.dart';
import 'package:transla_screen/app/features/home/presentation/home_page.dart';
import 'package:transla_screen/app/features/overlay/overlay_widget.dart';
import 'package:transla_screen/app/services/logger_service.dart';
import 'package:transla_screen/app/features/overlay/translation_mask_overlay.dart';

// Stream controller to pass messages from overlay to HomeController
final StreamController<dynamic> overlayMessageControllerGlobal =
    StreamController.broadcast();
Stream<dynamic> get overlayMessageStreamGlobal =>
    overlayMessageControllerGlobal.stream;

// 悬浮球 Overlay 入口点
@pragma("vm:entry-point")
void overlayControlMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LoggerService.init();
  setupExceptionHandling();

  log.i('[OverlayControlMain] 启动控制悬浮球');

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: InteractiveOverlayUI(),
    ),
  );
}

// 译文遮罩入口点
@pragma("vm:entry-point")
void overlayTranslationMaskMain() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await LoggerService.init();
    setupExceptionHandling();

    log.i('[TranslationOverlay] 启动译文遮罩');

    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          backgroundColor: Colors.black.withOpacity(0.1),
          body: SafeArea(
            child: Stack(
              children: [
                // 添加监听器和渲染译文项
                Builder(
                  builder: (context) {
                    return const TranslationMaskOverlay();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  } catch (e, s) {
    log.e('[TranslationOverlay] 启动错误', error: e, stackTrace: s);
  }
}

// 全局异常处理
void setupExceptionHandling() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    log.e('Flutter Error: ${details.exception}',
        error: details.exception, stackTrace: details.stack);
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LoggerService.init();
  setupExceptionHandling();

  // 初始化并监听overlay消息
  final overlayWindowsPlugin = OverlayWindowsPlugin.defaultInstance;
  overlayWindowsPlugin.messageStream.listen((event) {
    log.i(
        "[MainApp] 收到数据: ${event.overlayWindowId}, message: ${event.message}");
    overlayMessageControllerGlobal.sink.add(event.message);
  }).onError((error) {
    log.e("[MainApp] 监听器错误: $error");
  });

  runApp(const MyApp());
  // runTestAfterAppStart();
}

// 全局HomeController实例
final homeControllerGlobal = GlobalKey<MyHomePageState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TranslaScreen',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: MyHomePage(key: homeControllerGlobal),
      debugShowCheckedModeBanner: false,
    );
  }
}

// 测试方法，用于直接启动遮罩
void runTestAfterAppStart() {
  log.i("[Main] 准备显示译文遮罩");

  // 获取屏幕尺寸
  final screenSize = ui.window.physicalSize;
  final screenWidth = screenSize.width / ui.window.devicePixelRatio;
  final screenHeight = screenSize.height / ui.window.devicePixelRatio;

  log.i("[Main] 屏幕尺寸: ${screenWidth.toInt()} x ${screenHeight.toInt()}");

  // 显示窗口
  final overlayPlugin = OverlayWindowsPlugin.defaultInstance;

  overlayPlugin.isPermissionGranted().then((hasPermission) {
    log.i("[Main] 悬浮窗权限: $hasPermission");

    if (!hasPermission) {
      log.i("[Main] 请求悬浮窗权限");
      overlayPlugin.requestPermission();
      return;
    }

    // 显示译文遮罩窗口
    overlayPlugin
        .showOverlayWindow(
      "translation_mask_overlay",
      "overlayTranslationMaskMain",
      OverlayWindowConfig(
        width: screenWidth.toInt(),
        height: screenHeight.toInt(),
        enableDrag: false,
        flag: OverlayFlag.defaultFlag,
      ),
    )
        .then((_) {
      log.i("[Main] 译文遮罩窗口已创建");

      // 发送测试数据
      Future.delayed(const Duration(milliseconds: 500), () {
        log.i("[Main] 发送测试数据到遮罩");
        overlayPlugin.sendMessage("translation_mask_overlay", {
          'type': 'display_translation_mask',
          'items': [
            {
              'bbox': {'l': 50.0, 't': 50.0, 'w': 300.0, 'h': 80.0},
              'originalText': 'Direct Test 1',
              'translatedText': '直接测试数据1',
            },
            {
              'bbox': {'l': 50.0, 't': 150.0, 'w': 300.0, 'h': 80.0},
              'originalText': 'Direct Test 2',
              'translatedText': '直接测试数据2',
            },
          ],
        });
      });
    }).catchError((e) {
      log.e("[Main] 创建译文遮罩失败: $e");
    });
  });
}
