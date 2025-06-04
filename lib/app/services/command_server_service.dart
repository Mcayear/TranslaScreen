import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:transla_screen/app/services/logger_service.dart';

typedef CommandHandlerCallback = void Function(
    String action, Map<String, dynamic>? params);

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
      var handler = const shelf.Pipeline().addMiddleware(shelf.logRequests(
        logger: (message, isError) {
          if (isError) {
            log.e('[Shelf] $message');
          } else {
            log.i('[Shelf] $message');
          }
        },
      )).addHandler(_requestHandler);

      _server = await shelf_io.serve(handler, 'localhost', 10080);
      log.i('[CommandServerService] Server started at http://localhost:10080');
      _updateStatusMessage("命令服务器已启动: http://localhost:10080");
    } catch (e, s) {
      log.e('[CommandServerService] Error starting server: $e',
          error: e, stackTrace: s);
      _updateStatusMessage("命令服务器启动失败: $e");
    }
  }

  Future<shelf.Response> _requestHandler(shelf.Request request) async {
    if (request.method == 'POST' && request.url.path == 'command') {
      try {
        final body = await request.readAsString();
        final Map<String, dynamic> data = jsonDecode(body);
        final String? action = data['action'] as String?;
        final Map<String, dynamic>? params =
            data['params'] as Map<String, dynamic>?;

        log.i(
            '[CommandServerService] Received command via HTTP: $action, data: $data');

        if (action != null) {
          onCommandReceived(action, params);
          return shelf.Response.ok(jsonEncode({
            'status': 'Command received and processed by CommandServerService',
            'action': action
          }));
        } else {
          return shelf.Response.badRequest(
              body: jsonEncode({'error': 'Missing action in command'}));
        }
      } catch (e, s) {
        log.e('[CommandServerService] Error processing HTTP command: $e',
            error: e, stackTrace: s);
        return shelf.Response.internalServerError(
            body: jsonEncode({'error': 'Error processing command: $e'}));
      }
    }
    return shelf.Response.notFound(jsonEncode({'error': 'Not found'}));
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    log.i('[CommandServerService] Server stopped.');
  }
}
