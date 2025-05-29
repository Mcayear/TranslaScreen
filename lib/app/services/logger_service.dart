import 'dart:io';
import 'dart:ui';

import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode; // 导入 Flutter foundation 库，并只暴露 kDebugMode 常量
import 'package:flutter/material.dart'; // 导入 Flutter Material 库，用于 FlutterError 和 FlutterErrorDetails

class LoggerService {
  static late final Logger logger; // 静态的 Logger 实例，late 表示它将在首次使用前被初始化
  static File? _logFile; // 应用日志文件
  static File? _crashFile; // 崩溃日志文件

  // 公开的 getter 方法，用于获取日志文件路径
  static String get logFilePath =>
      _logFile?.path ??
      "Log file path not initialized"; // 如果 _logFile 为空，则返回未初始化消息
  static String get crashLogFilePath =>
      _crashFile?.path ??
      "Crash log path not initialized"; // 如果 _crashFile 为空，则返回未初始化消息

  // 初始化日志服务的异步方法
  static Future<void> init() async {
    try {
      final directory = await getExternalStorageDirectory(); // 获取外部存储目录
      _logFile = File('${directory?.path}/app.log'); // 设置应用日志文件路径为 app.log
      _crashFile =
          File('${directory?.path}/crash.log'); // 设置崩溃日志文件路径为 crash.log

      // 确保文件存在，如果不存在则创建
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
      }
      if (!await _crashFile!.exists()) {
        await _crashFile!.create(recursive: true);
      }

      // 创建一个文件输出器，用于将日志写入 app.log
      final appFileOutput = FileOutput(
        file: _logFile!, // 指定日志文件
        overrideExisting: false, // 不覆盖现有内容，而是追加
        // filter: ProductionFilter(), // 过滤器通常应用于 MultiOutput 或 Logger 本身
      );

      // 创建一个文件输出器，用于将崩溃日志写入 crash.log
      final crashFileOutput = FileOutput(
        file: _crashFile!, // 指定日志文件
        overrideExisting: false, // 不覆盖现有内容，而是追加
        // filter: CrashLogFilter(), // 过滤器通常应用于 MultiOutput 或 Logger 本身
      );

      final consoleOutput = ConsoleOutput(); // 创建一个控制台输出器，用于调试模式

      // 日志输出列表，根据调试模式添加控制台输出
      List<LogOutput> outputs = [];
      if (kDebugMode) {
        outputs.add(consoleOutput); // 调试模式下在控制台显示日志
      }
      // 最好在 Logger 级别或 MultiOutput 级别应用过滤器，如果不同输出需要不同的过滤器。
      // 为简单起见，我们将有一个主过滤器在 Logger 级别，以及 CrashLogFilter 专门用于 crashFileOutput。
      // 然而，FileOutput 本身没有过滤器。我们需要包装它或在传递事件之前过滤它们。

      // 为应用日志创建一个 MultiOutput（调试模式下到控制台 + appFile）
      // 为崩溃日志创建一个单独的 MultiOutput（调试模式下到控制台 + 带有特定过滤器的 crashFile）

      var appLogOutputs = <LogOutput>[];
      if (kDebugMode) {
        appLogOutputs.add(consoleOutput); // 调试模式下将应用日志输出到控制台
      }
      appLogOutputs.add(appFileOutput); // 将应用日志输出到 app.log

      var crashLogOutputs = <LogOutput>[];
      if (kDebugMode) {
        // 如果控制台输出已经包含在 appLogOutputs 中，并且 logger 使用了两者，我们可能不希望重复控制台输出。
        // 现在，让我们保持简单。
        crashLogOutputs.add(consoleOutput); // 调试模式下将崩溃日志输出到控制台
      }
      crashLogOutputs.add(crashFileOutput); // 将崩溃日志输出到 crash.log

      logger = Logger(
        printer: PrefixPrinter(
          // 使用 PrefixPrinter 包装 PrettyPrinter，以添加前缀
          PrettyPrinter(
            // 美化打印机，用于格式化日志消息
            methodCount: kDebugMode ? 1 : 0, // 调试模式下显示1个方法调用栈，生产环境不显示
            errorMethodCount: 8, // 错误日志显示8个方法调用栈
            lineLength: 120, // 每行最大长度
            colors: true, // 启用颜色输出
            printEmojis: true, // 打印表情符号
            dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart, // 日期时间格式
          ),
        ),
        // 我们将使用自定义调度器根据级别将日志路由到不同的输出
        output: CustomLogDispatcher(
          // 自定义日志调度器
          defaultOutput: MultiOutput(appLogOutputs), // 默认输出（app.log + 调试控制台）
          errorOutput: MultiOutput(crashLogOutputs), // 错误输出（crash.log + 调试控制台）
          crashLogFilter: CrashLogFilter(), // 此过滤器确保只有错误级别日志进入 errorOutput
        ),
        filter: kDebugMode
            ? DevelopmentFilter()
            : ProductionFilter(), // 根据调试模式应用不同的日志过滤器
      );

      logger.i(// 记录一条信息级别日志，表示服务已初始化
          "LoggerService initialized. Logging to: ${logFilePath} and ${crashLogFilePath}");
    } catch (e, s) {
      // 如果初始化失败，打印错误信息到控制台
      print('Failed to initialize LoggerService: $e\n$s');
      // 创建一个备用 Logger，仅将错误信息输出到控制台
      logger = Logger(
        printer: PrettyPrinter(), // 简单的美化打印器
        output: ConsoleOutput(), // 仅输出到控制台
      );
      // 记录初始化失败的错误日志
      logger.e('LoggerService initialization failed. Using console fallback.',
          error: e, stackTrace: s);
    }
  }
}

// 自定义日志调度器，根据日志级别将日志发送到不同的输出
class CustomLogDispatcher extends LogOutput {
  final LogOutput defaultOutput; // 默认日志输出
  final LogOutput errorOutput; // 错误日志输出
  final CrashLogFilter crashLogFilter; // 崩溃日志过滤器

  CustomLogDispatcher({
    required this.defaultOutput,
    required this.errorOutput,
    required this.crashLogFilter,
  });

  @override
  void output(OutputEvent event) {
    // 记录到默认输出（app.log 和调试模式下的控制台）
    defaultOutput.output(event);

    // 此外，过滤器决定是否输出到（crash.log）
    if (crashLogFilter.shouldLog(event.origin)) {
      errorOutput.output(event);
    }
  }

  @override
  Future<void> init() async {
    await defaultOutput.init(); // 初始化默认输出
    await errorOutput.init(); // 初始化错误输出
    super.init(); // 调用父类的初始化方法
  }

  @override
  Future<void> destroy() async {
    await defaultOutput.destroy(); // 销毁默认输出
    await errorOutput.destroy(); // 销毁错误输出
    super.destroy(); // 调用父类的销毁方法
  }
}

// 生产环境日志过滤器：调试模式下记录所有日志，生产环境只记录 debug 级别及以上日志
class ProductionFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (kDebugMode) return true;
    return event.level.index >= Level.debug.index;
  }
}

// 崩溃日志过滤器：只记录 fatal 级别及以上日志
class CrashLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    return event.level.index >= Level.fatal.index;
  }
}

// 方便的 getter，直接通过 log 访问 LoggerService.logger 实例
Logger get log => LoggerService.logger;

// 设置全局异常处理
void setupExceptionHandling() {
  // 捕获 Flutter 框架抛出的错误
  FlutterError.onError = (FlutterErrorDetails details) {
    LoggerService.logger.f(
      'FlutterError caught by framework:',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  // 捕获 PlatformDispatcher 捕获的未处理错误（通常是异步错误）
  PlatformDispatcher.instance.onError = (error, stack) {
    LoggerService.logger.f(
      'Unhandled error caught by PlatformDispatcher:',
      error: error,
      stackTrace: stack,
    );
    return true;
  };
}
