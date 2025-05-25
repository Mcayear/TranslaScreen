import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class SimpleOverlayWidget extends StatefulWidget {
  const SimpleOverlayWidget({super.key});

  @override
  State<SimpleOverlayWidget> createState() => _SimpleOverlayWidgetState();
}

class _SimpleOverlayWidgetState extends State<SimpleOverlayWidget> {
  dynamic dataFromMainApp;

  @override
  void initState() {
    super.initState();
    // Listen for data from the main app
    FlutterOverlayWindow.overlayListener.listen((event) {
      setState(() {
        dataFromMainApp = event;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent, // Important for overlay
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '悬浮窗内容',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                '从主应用接收的数据: ${dataFromMainApp ?? "暂无"}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Example of sending data back to main app or closing
                  FlutterOverlayWindow.shareData('来自悬浮窗的消息: ${DateTime.now()}');
                },
                child: const Text('发送消息给主应用'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () {
                  FlutterOverlayWindow.closeOverlay();
                },
                child: const Text('关闭悬浮窗'),
              )
            ],
          ),
        ),
      ),
    );
  }
}
