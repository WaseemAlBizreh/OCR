import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/home/presentation/pages/app_home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IdLens Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6623)),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const AppHomePage(),
    );
  }
}
