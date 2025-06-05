import 'package:flutter/material.dart';
import 'package:transla_screen/app/features/home/presentation/home_page.dart';
import 'package:transla_screen/app/services/logger_service.dart';

// 全局HomeController实例
final homeControllerGlobal = GlobalKey<MyHomePageState>();

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
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: MyHomePage(key: homeControllerGlobal),
      debugShowCheckedModeBanner: false,
    );
  }
}
