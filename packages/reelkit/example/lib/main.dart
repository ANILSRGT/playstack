import 'package:flutter/material.dart';

import 'pages/diagnostics_page.dart';
import 'pages/feed_page.dart';
import 'pages/player_page.dart';

void main() => runApp(const ReelKitExampleApp());

class ReelKitExampleApp extends StatelessWidget {
  const ReelKitExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReelKit',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget page) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(title: const Text('ReelKit')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Single player'),
            subtitle: const Text('Custom controls built by the app'),
            onTap: () => open(const PlayerPage()),
          ),
          ListTile(
            leading: const Icon(Icons.view_carousel_outlined),
            title: const Text('Vertical feed'),
            subtitle: const Text('PageView with a 3-player pool'),
            onTap: () => open(const FeedPage()),
          ),
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Diagnostics'),
            subtitle: const Text('Capabilities and pool usage'),
            onTap: () => open(const DiagnosticsPage()),
          ),
        ],
      ),
    );
  }
}
