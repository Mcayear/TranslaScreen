import 'package:flutter/material.dart';
import 'package:overlay_windows_plugin/overlay_windows_plugin.dart';
import 'package:transla_screen/app/services/logger_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// 控制Overlay，只有FAB和菜单
class InteractiveOverlayUI extends StatefulWidget {
  const InteractiveOverlayUI({super.key});
  @override
  InteractiveOverlayUIState createState() => InteractiveOverlayUIState();
}

class InteractiveOverlayUIState extends State<InteractiveOverlayUI>
    with SingleTickerProviderStateMixin {
  bool _isMenuOpen = false;
  late AnimationController _menuAnimationController;
  final String _mainAppUrl = 'http://localhost:10080/command';

  @override
  void initState() {
    super.initState();
    _menuAnimationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    log.i('[ControlOverlay] 已初始化');

    // 监听来自主应用的消息
    OverlayWindowsPlugin.defaultInstance.messageStream.listen((event) {
      if (event.message is Map<String, dynamic>) {
        final action = event.message['action']?.toString();
        if (action != null) {
          log.i('[ControlOverlay] 收到命令: $action');
          _sendCommandViaHttp(action,
              params: event.message['params'] as Map<String, dynamic>?);
        }
      }
    });
  }

  Future<void> _sendCommandViaHttp(String action,
      {Map<String, dynamic>? params}) async {
    final payload = {
      'action': action,
      if (params != null) 'params': params,
      'timestamp': DateTime.now().millisecondsSinceEpoch
    };
    try {
      final res = await http.post(
        Uri.parse(_mainAppUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      log.i('[ControlOverlay] 发送命令 $action -> ${res.statusCode}');
    } catch (e, s) {
      log.e('[ControlOverlay] HTTP发送失败: $e', error: e, stackTrace: s);
    }
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
    });
    if (_isMenuOpen) {
      _menuAnimationController.forward();
    } else {
      _menuAnimationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // 菜单
          Positioned(
            top: 70,
            child: AnimatedOpacity(
              opacity: _isMenuOpen ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Column(
                children: [
                  _buildMenuItem(
                      Icons.fullscreen, '全屏', 'translate_fullscreen'),
                  const SizedBox(height: 16),
                  _buildMenuItem(Icons.crop, '选区', 'start_area_selection'),
                ],
              ),
            ),
          ),
          // FAB
          GestureDetector(
            onTap: _toggleMenu,
            onLongPress: () => _sendCommandViaHttp('translate_fullscreen'),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4)
                ],
              ),
              child: Icon(
                _isMenuOpen ? Icons.close : Icons.translate,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String label, String action) {
    return GestureDetector(
      onTap: () {
        _sendCommandViaHttp(action);
        _toggleMenu();
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _menuAnimationController.dispose();
    super.dispose();
  }
}
