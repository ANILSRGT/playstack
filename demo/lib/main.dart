import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'launcher_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A reels app is portrait; PlayStackFeedView turns the screen for landscape
  // videos in fullscreen and back again.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlayStack Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.pinkAccent,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const LauncherPage(),
    );
  }
}
