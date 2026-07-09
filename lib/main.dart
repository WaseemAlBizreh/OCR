import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mrz/core/UI/routes/router.dart';
import 'package:mrz/core/config/injection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await configureDependencies();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final navigationKey = GlobalKey<NavigatorState>();
  static final _appRouter = AppRouter(navigationKey);

  static BuildContext? get appContext => navigationKey.currentContext;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _appRouter.config(),
      title: 'OCR Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6623)),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
