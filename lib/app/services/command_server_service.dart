import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

typedef CommandHandlerCallback = void Function(String action);

class CommandServerService {
  HttpServer? _server;
  final CommandHandlerCallback onCommandReceived;
  final Function(String) _updateStatusMessage;

  CommandServerService(
      {required this.onCommandReceived,
      required Function(String) updateStatusMessage})
      : _updateStatusMessage = updateStatusMessage;

  Future<void> startServer() async {
    try {
      var handler = const shelf.Pipeline()
          .addMiddleware(shelf
              .logRequests()) // Consider making logging optional or configurable
          .addHandler(_requestHandler);

      _server = await shelf_io.serve(handler, 'localhost', 10080);
      print('[CommandServerService] Server started at http://localhost:10080');
      _updateStatusMessage("命令服务器已启动: http://localhost:10080");
    } catch (e) {
      print('[CommandServerService] Error starting server: $e');
      _updateStatusMessage("命令服务器启动失败: $e");
    }
  }

  Future<shelf.Response> _requestHandler(shelf.Request request) async {
    if (request.method == 'POST' && request.url.path == 'command') {
      try {
        final body = await request.readAsString();
        final Map<String, dynamic> data = jsonDecode(body);
        final String? action = data['action'] as String?;

        print(
            '[CommandServerService] Received command via HTTP: $action, data: $data');

        if (action != null) {
          onCommandReceived(action);
          return shelf.Response.ok(jsonEncode({
            'status': 'Command received and processed by CommandServerService',
            'action': action
          }));
        } else {
          return shelf.Response.badRequest(
              body: jsonEncode({'error': 'Missing action in command'}));
        }
      } catch (e, s) {
        print(
            '[CommandServerService] Error processing HTTP command: $e\nStack trace: $s');
        return shelf.Response.internalServerError(
            body: jsonEncode({'error': 'Error processing command: $e'}));
      }
    }
    return shelf.Response.notFound(jsonEncode({'error': 'Not found'}));
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    print('[CommandServerService] Server stopped.');
  }
}
