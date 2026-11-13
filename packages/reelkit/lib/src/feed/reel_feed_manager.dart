import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import '../config/reel_kit_config.dart';
import '../controller/reel_playback_state.dart';
import '../controller/reel_player_controller.dart';
import '../manager/reel_kit_manager.dart';
import '../pool/reel_player_pool.dart';
import 'reel_feed_config.dart';
import 'reel_feed_item.dart';
import 'reel_feed_stats.dart';
import 'reel_preload_window.dart';

/// Services a feed needs from its manager.
@internal
abstract interface class ReelFeedHost {
  ReelPlayerController createFeedController(
    ReelSource source,
    ReelPlayerConfig? config,
  );
  ValueListenable<ReelNetworkStatus> get networkStatus;
  ReelPlatformCapabilities get capabilities;
  int get maxPlayers;
  bool get exclusivePlayback;
  void feedDisposed(ReelFeedManager feed);
}

/// The engine behind a video feed: a list of videos, their players, and
/// which ones play and preload.
///
/// Most apps never touch it: `ReelFeedView(items: ...)` creates and manages
/// one. Create your own (`ReelKitManager.createFeed`) when your code edits
/// the list (insert, remove, update a URL) or when several screens share a
/// feed, and show it with `ReelFeedView.feed`:
///
/// ```dart
/// final feed = manager.createFeed(
///   [for (final post in posts) ReelFeedItem(ReelSource.network(post.url), id: post.id, data: post)],
///   config: ReelFeedConfig.reels,
/// );
/// ReelFeedView<Post>.feed(feed: feed);
/// feed.insert(0, ReelFeedItem(ReelSource.network(newPost.url), id: newPost.id, data: newPost));
/// ```
///
/// A custom scroll view can drive a feed too: show `controllerAt(index)` in a
/// `ReelVideoView` and report the item in view with [setActiveIndex].
///
/// Whenever the item in view changes, the feed:
///
/// * plays it (with [ReelFeedConfig.autoplay]) and pauses the previous one;
/// * prepares the items around it, next item first, so the next swipe shows
///   a frame at once;
/// * limits that work by the pool size, the network (mobile data, data
///   saver, offline), device memory and memory warnings;
/// * hands the players of items that leave the window back to the pool and
///   cancels their unfinished preparations, so fast scrolling never piles
///   up work.
///
/// Item ids stay stable across [insert], [removeAt], [replaceAll] and
/// [updateSource], so a playing video keeps playing. The feed notifies its
/// listeners when its items change. Dispose it, or its manager, when done.
class ReelFeedManager extends ChangeNotifier {
  /// Use `ReelKitManager.createFeed` instead.
  @internal
  ReelFeedManager.internal({
    required this._host,
    required List<ReelFeedItem> items,
    required this.config,
  }) : _items = <ReelFeedItem>[] {
    _addItems(items, at: 0);
    _host.networkStatus.addListener(_onNetworkChanged);
    _lastNetwork = _host.networkStatus.value;
  }

  final ReelFeedHost _host;

  /// How many items this feed prepares ahead and behind, and its other preloading settings.
  final ReelFeedConfig config;

  /// The manager that created this feed and lends it native players.
  ReelKitManager get manager => _host as ReelKitManager;
  final List<ReelFeedItem> _items;
  final Map<String, ReelPlayerController> _controllers =
      <String, ReelPlayerController>{};

  final ValueNotifier<int?> _activeIndex = ValueNotifier<int?>(null);
  final ValueNotifier<ReelPreloadWindow> _window =
      ValueNotifier<ReelPreloadWindow>(ReelPreloadWindow.none);

  /// Incremented on every re-plan; running preload loops stop when it moves.
  final ValueNotifier<int> _plan = ValueNotifier<int>(0);

  final Set<String> _preloading = <String>{};
  final Map<String, int> _preloadRetries = <String, int>{};
  String? _activeId;
  ReelFeedStats _stats = const ReelFeedStats();
  ReelNetworkStatus _lastNetwork = ReelNetworkStatus.unknown;
  Timer? _memoryCooldown;
  VoidCallback? _cancelStartMeasurement;
  bool _paused = false;
  bool _disposed = false;
  bool? _muted;

  /// A copy of the items, in display order. For one item use [itemAt], which does not copy.
  List<ReelFeedItem> get items => List<ReelFeedItem>.unmodifiable(_items);

  /// The item at [index], without copying the list like [items].
  ReelFeedItem itemAt(int index) {
    RangeError.checkValidIndex(index, _items);
    return _items[index];
  }

  /// Number of items in the feed.
  int get length => _items.length;

  /// Whether the feed has no items.
  bool get isEmpty => _items.isEmpty;

  /// Index of the active item, or null before [setActiveIndex] and when the
  /// feed is empty.
  ValueListenable<int?> get activeIndex => _activeIndex;

  /// The controller of the item in view, or null before [setActiveIndex] and
  /// when the feed is empty. Use it to pause, seek or read the playing video.
  ReelPlayerController? get activeController {
    final id = _activeId;
    return id == null ? null : _controllers[id];
  }

  /// The window currently prepared around the active item, after network,
  /// memory and pool limits.
  ValueListenable<ReelPreloadWindow> get preloadWindow => _window;

  /// Whether the feed was paused with [pause] and not resumed yet.
  bool get isPaused => _paused;

  /// Whether [dispose] was called. A disposed feed cannot be used again.
  bool get isDisposed => _disposed;

  /// The mute state set with [setMuted], or null when every controller
  /// follows its configuration.
  bool? get muted => _muted;

  /// Counters since the feed was created: how often the next video was ready
  /// on arrival, how long starts took, how many preloads ran or were
  /// cancelled. Useful to tune [ReelFeedConfig].
  ReelFeedStats get stats => _stats;

  /// The controller of the item at [index], created on first use.
  ///
  /// Controllers are cheap Dart objects; native players are attached only
  /// to the active item and the preload window. Controllers of items far
  /// outside the window are disposed (see
  /// [ReelFeedConfig.controllerRetention]); call this from `build` rather
  /// than caching the result for long.
  ReelPlayerController controllerAt(int index) {
    _throwIfDisposed();
    RangeError.checkValidIndex(index, _items);
    return _controllerFor(_items[index]);
  }

  /// The controller of the item with [id], or null when there is no such
  /// item.
  ReelPlayerController? controllerOf(String id) {
    _throwIfDisposed();
    final index = indexOf(id);
    return index < 0 ? null : _controllerFor(_items[index]);
  }

  /// Index of the item with [id], or -1 when there is none.
  int indexOf(String id) => _items.indexWhere((item) => item.id == id);

  /// Makes the item at [index] the active one: it plays (with autoplay) and
  /// the preload window moves around it. Call it from `onPageChanged` or
  /// whenever the item in view changes; calling it many times in a row is
  /// cheap and cancels work for windows that were left.
  void setActiveIndex(int index) {
    _throwIfDisposed();
    RangeError.checkValidIndex(index, _items);
    final id = _items[index].id;
    if (id == _activeId) return;
    final previous = activeController;
    _activeId = id;
    _activeIndex.value = index;
    final controller = _controllerFor(_items[index]);
    _stats = _stats.copyWith(
      transitions: _stats.transitions + 1,
      preparedOnArrival:
          _stats.preparedOnArrival + (controller.value.isInitialized ? 1 : 0),
    );
    if (previous != null && !_host.exclusivePlayback) {
      unawaited(previous.pause().catchError(_ignore));
    }
    _measureStart(controller);
    _schedule(activate: true);
  }

  /// Pauses the active item and stops preloading, for example while another
  /// route covers the feed. Prepared items stay prepared.
  void pause() {
    _throwIfDisposed();
    if (_paused) return;
    _paused = true;
    final active = activeController;
    if (active != null) unawaited(active.pause().catchError(_ignore));
    _schedule();
  }

  /// Undoes [pause]: plays the active item again (with autoplay) and
  /// resumes preloading.
  void resume() {
    _throwIfDisposed();
    if (!_paused) return;
    _paused = false;
    _schedule(activate: true);
  }

  /// Mutes or unmutes every item of the feed, including items created
  /// later, like the sound switch of a short-video app.
  void setMuted(bool muted) {
    _throwIfDisposed();
    _muted = muted;
    for (final controller in _controllers.values) {
      unawaited(controller.setMuted(muted).catchError(_ignore));
    }
    notifyListeners();
  }

  /// Adds [item] at the end.
  void add(ReelFeedItem item) => insertAll(_items.length, [item]);

  /// Appends [items], for example the next page of an endless feed.
  void addAll(Iterable<ReelFeedItem> items) => insertAll(_items.length, items);

  /// Inserts [item] at [index]. The active item stays active.
  void insert(int index, ReelFeedItem item) => insertAll(index, [item]);

  /// Inserts [items] at [index]. The active item stays active.
  void insertAll(int index, Iterable<ReelFeedItem> items) {
    _throwIfDisposed();
    RangeError.checkValueInInterval(index, 0, _items.length, 'index');
    _addItems(items.toList(), at: index);
    _itemsChanged();
  }

  /// Removes the item at [index] and disposes its controller. When it was
  /// the active item, the item that takes its place becomes active.
  ReelFeedItem removeAt(int index) {
    _throwIfDisposed();
    RangeError.checkValidIndex(index, _items);
    final removed = _items.removeAt(index);
    _dropController(removed.id);
    if (removed.id == _activeId) {
      _activeId = null;
      if (_items.isNotEmpty) {
        final next = index < _items.length ? index : _items.length - 1;
        _activeId = _items[next].id;
        _measureStart(_controllerFor(_items[next]));
      }
      _itemsChanged(activate: true);
      return removed;
    }
    _itemsChanged();
    return removed;
  }

  /// Removes the item with [id]. Returns false when there is none.
  bool remove(String id) {
    final index = indexOf(id);
    if (index < 0) return false;
    removeAt(index);
    return true;
  }

  /// Replaces all items, for example after a refresh. Controllers of items
  /// whose id remains are kept (and switch source when it changed). The
  /// active item stays active when its id remains; otherwise the first item
  /// becomes active once an index was set before.
  void replaceAll(Iterable<ReelFeedItem> items) {
    _throwIfDisposed();
    final next = items.toList();
    _checkUniqueIds(next, existing: const []);
    final nextIds = {for (final item in next) item.id};
    for (final id in List<String>.of(_controllers.keys)) {
      if (!nextIds.contains(id)) _dropController(id);
    }
    final previousSources = {for (final item in _items) item.id: item.source};
    _items
      ..clear()
      ..addAll(next);
    for (final item in next) {
      final controller = _controllers[item.id];
      controller?.startPosition = item.startPosition;
      final previous = previousSources[item.id];
      if (controller != null && previous != null && previous != item.source) {
        unawaited(controller.setSource(item.source).catchError(_ignore));
      }
    }
    final hadActive = _activeId != null;
    var activate = false;
    if (_activeId != null && !nextIds.contains(_activeId)) _activeId = null;
    if (_activeId == null && hadActive && _items.isNotEmpty) {
      _activeId = _items.first.id;
      _measureStart(_controllerFor(_items.first));
      activate = true;
    }
    _itemsChanged(activate: activate);
  }

  /// Replaces the source of the item with [id], for example when a signed
  /// URL expired. A prepared controller switches at once and keeps playing.
  void updateSource(String id, ReelSource source) {
    _throwIfDisposed();
    final index = indexOf(id);
    if (index < 0) {
      throw ArgumentError.value(id, 'id', 'No feed item with this id');
    }
    _items[index] = _items[index].copyWith(source: source);
    _preloadRetries.remove(id);
    final controller = _controllers[id];
    if (controller != null) {
      unawaited(controller.setSource(source).catchError(_ignore));
    }
    notifyListeners();
  }

  /// Disposes every controller of this feed. The manager stays usable.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _plan.value++;
    _cancelStartMeasurement?.call();
    _memoryCooldown?.cancel();
    _host.networkStatus.removeListener(_onNetworkChanged);
    for (final controller in _controllers.values) {
      unawaited(controller.dispose());
    }
    _controllers.clear();
    _host.feedDisposed(this);
    _activeIndex.dispose();
    _window.dispose();
    _plan.dispose();
    super.dispose();
  }

  /// Called by the manager on an operating-system memory warning.
  @internal
  void handleMemoryPressure() {
    if (_disposed) return;
    _memoryCooldown?.cancel();
    _memoryCooldown = Timer(config.memoryPressureCooldown, () {
      _memoryCooldown = null;
      _schedule();
    });
    _schedule();
  }

  // ---------------------------------------------------------------------------

  ReelPlayerController _controllerFor(ReelFeedItem item) {
    final existing = _controllers[item.id];
    if (existing != null) return existing;
    final controller = _host.createFeedController(item.source, config.player)
      ..priority = ReelPlayerPriority.background
      ..startPosition = item.startPosition;
    final muted = _muted;
    if (muted != null && controller.value.isMuted != muted) {
      unawaited(controller.setMuted(muted).catchError(_ignore));
    }
    return _controllers[item.id] = controller;
  }

  void _addItems(List<ReelFeedItem> items, {required int at}) {
    _checkUniqueIds(items, existing: _items);
    _items.insertAll(at, items);
  }

  void _checkUniqueIds(
    List<ReelFeedItem> items, {
    required List<ReelFeedItem> existing,
  }) {
    final seen = {for (final item in existing) item.id};
    for (final item in items) {
      if (!seen.add(item.id)) {
        throw ArgumentError.value(item.id, 'items', 'Duplicate feed item id');
      }
    }
  }

  void _dropController(String id) {
    _preloadRetries.remove(id);
    _preloading.remove(id);
    final controller = _controllers.remove(id);
    if (controller != null) unawaited(controller.dispose());
  }

  void _itemsChanged({bool activate = false}) {
    final id = _activeId;
    _activeIndex.value = id == null ? null : indexOf(id);
    notifyListeners();
    _schedule(activate: activate);
  }

  ReelPreloadWindow _resolveWindow() {
    final capabilities = _host.capabilities;
    return ReelPreloadWindow.resolve(
      config: config,
      network: _host.networkStatus.value,
      isLowRamDevice: capabilities.isLowRamDevice,
      underMemoryPressure: _memoryCooldown != null,
      maxPlayers: _host.maxPlayers,
    );
  }

  /// Re-plans synchronously: priorities, releases and, with [activate], the
  /// active item's play (or prepare) command are issued now; preloads run
  /// afterwards in order. Without [activate] the active item's playback is
  /// left as the user set it.
  void _schedule({bool activate = false}) {
    if (_disposed) return;
    final plan = ++_plan.value;
    final id = _activeId;
    final active = id == null ? -1 : indexOf(id);
    final window = _resolveWindow();
    _window.value = window;
    final targets = active < 0 || _paused
        ? const <int>[]
        : window.order(active, _items.length);
    final targetIds = <String, ReelPlayerPriority>{
      for (final index in targets)
        _items[index].id: index > active
            ? ReelPlayerPriority.preload
            : ReelPlayerPriority.background,
    };

    for (final index in targets) {
      _controllerFor(_items[index]);
    }

    // Items that left the window give their native player back first, so
    // the active item does not have to take one by revocation.
    for (final entry in _controllers.entries) {
      if (entry.key == id) continue;
      final controller = entry.value;
      final priority = targetIds[entry.key];
      if (priority != null) {
        controller.priority = priority;
        continue;
      }
      controller.priority = ReelPlayerPriority.background;
      final state = controller.value;
      if (state.isAttached || state.status == ReelPlaybackStatus.initializing) {
        if (_preloading.contains(entry.key)) {
          _stats = _stats.copyWith(
            preloadsCancelled: _stats.preloadsCancelled + 1,
          );
        }
        unawaited(controller.release().catchError(_ignore));
      }
    }

    ReelPlayerController? activeController;
    if (active >= 0) {
      activeController = _controllerFor(_items[active]);
      if (!_paused && activate) {
        if (config.autoplay) {
          unawaited(activeController.play().catchError(_ignore));
        } else {
          activeController.priority = ReelPlayerPriority.visible;
          unawaited(activeController.initialize().catchError(_ignore));
        }
      } else if (activeController.priority.index <
          ReelPlayerPriority.visible.index) {
        activeController.priority = ReelPlayerPriority.visible;
      }
    }

    _trimControllers(active, window);
    if (activeController != null && targets.isNotEmpty) {
      unawaited(
        _runPreloads(plan, activeController, targets, waitForIdle: activate),
      );
    }
  }

  Future<void> _runPreloads(
    int plan,
    ReelPlayerController active,
    List<int> targets, {
    required bool waitForIdle,
  }) async {
    // The active item gets the network and a decoder first, for at most
    // the head start.
    await Future.any([
      _settled(active, plan, waitForIdle: waitForIdle),
      Future<void>.delayed(config.activeHeadStart),
    ]);
    if (plan != _plan.value || _disposed) return;
    final queue = [for (final index in targets) _items[index]];
    Future<void> worker() async {
      while (queue.isNotEmpty && plan == _plan.value && !_disposed) {
        final item = queue.removeAt(0);
        final controller = _controllers[item.id];
        // Null when the item was removed meanwhile.
        if (controller == null || !_needsPreload(item, controller)) continue;
        await _preload(item, controller);
      }
    }

    await Future.wait([
      for (var i = 0; i < config.maxConcurrentPreloads; i++) worker(),
    ]);
  }

  bool _needsPreload(ReelFeedItem item, ReelPlayerController controller) {
    final state = controller.value;
    if (state.isInitialized && state.isAttached) return false;
    if (state.status == ReelPlaybackStatus.initializing) return false;
    if (item.source is ReelNetworkSource &&
        !_host.networkStatus.value.isConnected) {
      return false;
    }
    if (state.status == ReelPlaybackStatus.error) {
      final retries = _preloadRetries[item.id] ?? 0;
      return config.retryFailedPreloads &&
          retries < 1 &&
          _isTransient(state.error);
    }
    return true;
  }

  Future<void> _preload(
    ReelFeedItem item,
    ReelPlayerController controller,
  ) async {
    _preloading.add(item.id);
    _stats = _stats.copyWith(preloadsStarted: _stats.preloadsStarted + 1);
    try {
      await controller.initialize();
      _stats = _stats.copyWith(preloadsCompleted: _stats.preloadsCompleted + 1);
    } on ReelKitException catch (error) {
      if (error.code == ReelKitErrorCode.cancelled ||
          error.code == ReelKitErrorCode.disposed) {
        return;
      }
      _preloadRetries.update(item.id, (n) => n + 1, ifAbsent: () => 1);
      _stats = _stats.copyWith(preloadsFailed: _stats.preloadsFailed + 1);
    } finally {
      _preloading.remove(item.id);
    }
  }

  /// Completes when [controller] finished preparing (successfully or not),
  /// or when the plan changed.
  ///
  /// With [waitForIdle], an idle controller is about to start preparing
  /// (its command is queued) and is waited for.
  Future<void> _settled(
    ReelPlayerController controller,
    int plan, {
    required bool waitForIdle,
  }) {
    bool done() {
      if (_disposed || plan != _plan.value || controller.isDisposed) {
        return true;
      }
      return switch (controller.value.status) {
        ReelPlaybackStatus.idle => !waitForIdle,
        ReelPlaybackStatus.initializing => false,
        _ => true,
      };
    }

    if (done()) return Future<void>.value();
    final completer = Completer<void>();
    void check() {
      if (completer.isCompleted || !done()) return;
      controller.removeListener(check);
      if (!_disposed) _plan.removeListener(check);
      completer.complete();
    }

    controller.addListener(check);
    _plan.addListener(check);
    return completer.future;
  }

  void _trimControllers(int active, ReelPreloadWindow window) {
    if (active < 0) return;
    final keep =
        (window.ahead > window.behind ? window.ahead : window.behind) +
        config.controllerRetention;
    final positions = {for (var i = 0; i < _items.length; i++) _items[i].id: i};
    for (final id in List<String>.of(_controllers.keys)) {
      final index = positions[id];
      if (index == null || (index - active).abs() > keep) {
        _dropController(id);
      }
    }
  }

  void _measureStart(ReelPlayerController controller) {
    _cancelStartMeasurement?.call();
    _cancelStartMeasurement = null;
    if (!config.autoplay) return;
    final clock = Stopwatch()..start();
    void listener() {
      if (!controller.value.isPlaying) return;
      final elapsed = clock.elapsed;
      _stats = _stats.copyWith(
        lastStartLatency: elapsed,
        totalStartLatency: _stats.totalStartLatency + elapsed,
        measuredStarts: _stats.measuredStarts + 1,
      );
      controller.removeListener(listener);
      _cancelStartMeasurement = null;
    }

    controller.addListener(listener);
    _cancelStartMeasurement = () => controller.removeListener(listener);
  }

  void _onNetworkChanged() {
    final status = _host.networkStatus.value;
    final reconnected = status.isConnected && !_lastNetwork.isConnected;
    _lastNetwork = status;
    if (_disposed) return;
    var activate = false;
    if (reconnected) {
      // Failed preloads may try again once more after a reconnection, and an
      // active item that failed for lack of network starts again.
      _preloadRetries.clear();
      final active = activeController;
      activate =
          active != null &&
          active.value.hasError &&
          _isTransient(active.value.error);
    }
    _schedule(activate: activate);
  }

  static bool _isTransient(ReelKitException? error) => switch (error?.code) {
    ReelKitErrorCode.network ||
    ReelKitErrorCode.timeout ||
    ReelKitErrorCode.decoderUnavailable => true,
    _ => false,
  };

  void _throwIfDisposed() {
    if (_disposed) {
      throw const ReelKitException(
        ReelKitErrorCode.disposed,
        'This ReelFeedManager was disposed.',
      );
    }
  }

  static void _ignore(Object _) {}
}
