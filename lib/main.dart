import 'dart:async'; // Import for StreamController
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart'; // Import for overlay listener
import 'package:transla_screen/app/features/home/presentation/home_page.dart'; // New Home Page
import 'package:transla_screen/app/features/overlay/overlay_widget.dart';
import 'package:transla_screen/app/services/logger_service.dart'; // Import logger service

// Stream controller to pass messages from overlay to HomeController
final StreamController<dynamic> overlayMessageControllerGlobal =
    StreamController.broadcast();
Stream<dynamic> get overlayMessageStreamGlobal =>
    overlayMessageControllerGlobal.stream;

// Overlay Entry Point
@pragma("vm:entry-point")
Future<void> overlayMain() async {
  // Make overlayMain async if LoggerService.init is used here
  WidgetsFlutterBinding.ensureInitialized();
  // It might be beneficial to also initialize logger for the overlay isolate
  await LoggerService
      .init(); // Consider if overlay needs separate log files or config
  setupExceptionHandling(); // And exception handling
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: InteractiveOverlayUI(), // 使用新创建的交互式悬浮窗 UI
    ),
  );
}

Future<void> main() async {
  // Make main async
  WidgetsFlutterBinding
      .ensureInitialized(); // Ensure bindings are initialized before async calls
  await LoggerService.init(); // Initialize LoggerService
  setupExceptionHandling(); // Setup global exception handling

  // Listen to messages from overlay window using the plugin's listener
  FlutterOverlayWindow.overlayListener.listen((dynamic data) {
    log.i("[MainApp Listener] Received data from overlay: $data");
    overlayMessageControllerGlobal.sink
        .add(data); // Pass data to HomeController via global stream
  }).onError((error) {
    log.e("[MainApp Listener] Error in overlay listener: $error");
  });

  // Ensure Flutter bindings are initialized for overlayMain AND main app if needed early.
  // WidgetsFlutterBinding.ensureInitialized(); // Usually called by runApp
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TranslaScreen',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true, // Optional: Use Material 3
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const MyHomePage(), // This is now our refactored HomePage
      debugShowCheckedModeBanner: false,
    );
  }
}

// MyHomePage and _MyHomePageState are now moved to home_page.dart and home_controller.dart
