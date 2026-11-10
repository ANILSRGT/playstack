import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

import '../samples.dart';

/// Shows the engine capabilities, the native player pool and the state of
/// every controller. It exercises the real native allocation path.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final ReelKitManager _manager = ReelKitManager();
  final List<ReelPlayerController> _controllers = <ReelPlayerController>[];
  Object? _initError;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _manager.initialize();
    } on Object catch (error) {
      _initError = error;
    }
    if (mounted) setState(() {});
  }

  void _addController() {
    final url = sampleVideos[_controllers.length % sampleVideos.length];
    final controller = _manager.createController(ReelSource.network(url));
    setState(() => _controllers.add(controller));
    // Errors are reflected in controller.value and shown by the tile.
    unawaited(controller.initialize().catchError((Object _) {}));
  }

  Future<void> _disposeAll() async {
    final controllers = List<ReelPlayerController>.of(_controllers);
    setState(_controllers.clear);
    await Future.wait(controllers.map((c) => c.dispose()));
    if (mounted) setState(() {});
  }

  Future<void> _trim() async {
    await _manager.trimIdlePlayers();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_manager.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ReelKit diagnostics')),
      body: _initError != null
          ? Center(child: Text('Initialization failed:\n$_initError'))
          : !_manager.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _CapabilitiesCard(capabilities: _manager.capabilities),
                const SizedBox(height: 12),
                _PoolCard(stats: _manager.poolStats),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _addController,
                      child: const Text('Add controller'),
                    ),
                    OutlinedButton(
                      onPressed: _controllers.isEmpty ? null : _disposeAll,
                      child: const Text('Dispose all'),
                    ),
                    OutlinedButton(
                      onPressed: _trim,
                      child: const Text('Trim idle players'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final controller in _controllers)
                  _ControllerTile(
                    key: ObjectKey(controller),
                    controller: controller,
                    onChanged: () => setState(() {}),
                  ),
              ],
            ),
    );
  }
}

class _CapabilitiesCard extends StatelessWidget {
  const _CapabilitiesCard({required this.capabilities});

  final ReelPlatformCapabilities capabilities;

  @override
  Widget build(BuildContext context) {
    final memory = capabilities.totalMemoryBytes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${capabilities.engineName} ${capabilities.engineVersion}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Recommended players: ${capabilities.recommendedMaxPlayers}'),
            Text(
              'HW decoder instances: '
              '${capabilities.maxHardwareDecoderInstances ?? 'not reported'}',
            ),
            Text(
              'Memory: ${memory == null ? 'not reported' : '${(memory / (1 << 30)).toStringAsFixed(1)} GiB'}'
              '${capabilities.isLowRamDevice ? ' (low RAM)' : ''}',
            ),
            Text(
              'HLS: ${capabilities.supportsHls}  DASH: ${capabilities.supportsDash}',
            ),
          ],
        ),
      ),
    );
  }
}

class _PoolCard extends StatelessWidget {
  const _PoolCard({required this.stats});

  final ReelPoolStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Pool: ${stats.allocated}/${stats.maxPlayers} native players '
          '(${stats.leased} leased, ${stats.idle} idle)\n'
          'created ${stats.created} · reused ${stats.reused} · '
          'revoked ${stats.revoked} · disposed ${stats.disposed}',
        ),
      ),
    );
  }
}

class _ControllerTile extends StatelessWidget {
  const _ControllerTile({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final ReelPlayerController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReelPlaybackState>(
      valueListenable: controller,
      builder: (context, state, _) {
        // Pool statistics on the page depend on controller state.
        WidgetsBinding.instance.addPostFrameCallback((_) => onChanged());
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 128,
                child: ReelVideoView(
                  controller: controller,
                  fit: BoxFit.cover,
                  placeholderBuilder: (_, _) => const Center(
                    child: Icon(Icons.movie_outlined, color: Colors.white54),
                  ),
                  errorBuilder: (_, _) => const Center(
                    child: Icon(Icons.error_outline, color: Colors.redAccent),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Uri.parse(controller.source.description)
                            .pathSegments
                            .last,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        'status: ${state.status.name}'
                        '${state.isAttached ? ' · native player attached' : ''}',
                      ),
                      if (state.error != null)
                        Text(
                          '${state.error!.code.name}: ${state.error!.message}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
