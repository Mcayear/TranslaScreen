import 'package:flutter/material.dart';
import 'package:transla_screen/app/features/home/presentation/home_page.dart'; // New Home Page
import 'package:transla_screen/app/features/overlay/overlay_widget.dart';

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
