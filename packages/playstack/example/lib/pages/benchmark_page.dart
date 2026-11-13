import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../benchmark/playstack_benchmark.dart';

/// Runs [PlayStackBenchmark] on this device and shows the report.
///
/// Run a release or profile build for meaningful numbers; debug builds are
/// much slower in Dart.
class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key});

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage> {
  bool _quick = true;
  bool _running = false;
  String? _step;
  PlayStackBenchmarkResults? _results;
  Object? _error;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results = null;
      _error = null;
    });
    final benchmark = _quick
        ? PlayStackBenchmark(
            iterations: 5,
            feedScrollItems: 100,
            swipeTransitions: 6,
            memoryCycles: 20,
            onProgress: _onProgress,
          )
        : PlayStackBenchmark(onProgress: _onProgress);
    try {
      final results = await benchmark.run();
      if (mounted) setState(() => _results = results);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _step = null;
        });
      }
    }
  }

  void _onProgress(String step) {
    if (mounted) setState(() => _step = step);
  }

  Future<void> _copy() async {
    final results = _results;
    if (results == null) return;
    final json = const JsonEncoder.withIndent('  ').convert(results.toJson());
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied as JSON')));
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Benchmark'),
        actions: [
          if (results != null)
            IconButton(
              tooltip: 'Copy JSON',
              icon: const Icon(Icons.copy),
              onPressed: () => unawaited(_copy()),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Measures start latency, preloading, rapid scrolling and '
            'memory with a bundled 1080x1920 clip. Use a profile or '
            'release build; keep the app in the foreground while it runs.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Quick run'),
            subtitle: const Text('Fewer samples; about 30 seconds'),
            value: _quick,
            onChanged: _running
                ? null
                : (value) => setState(() => _quick = value),
          ),
          FilledButton.icon(
            onPressed: _running ? null : () => unawaited(_run()),
            icon: const Icon(Icons.speed),
            label: Text(_running ? 'Running...' : 'Run benchmark'),
          ),
          if (_step case final step?)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(step)),
                ],
              ),
            ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Failed: $error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (results != null) ...[
            const SizedBox(height: 16),
            for (final line in results.toLines())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  line,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
