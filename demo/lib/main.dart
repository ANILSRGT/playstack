import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:playstack/playstack.dart';

import 'drama/offline.dart';
import 'launcher_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A reels app is portrait. Turning the phone sideways while a video plays
  // still opens it fullscreen (PlayStackFeedView.fullscreenOnRotate reads the
  // motion sensors), and the portrait lock comes back afterwards.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Downloads are off until the user is premium (the switch on the
  // downloads page of the drama app).
  await offline.initialize();
  // Every video event of the app, ready for an analytics service.
  PlayStackAnalytics.all.listen(
    (event) => debugPrint('[analytics] ${event.name} ${event.parameters}'),
  );
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
