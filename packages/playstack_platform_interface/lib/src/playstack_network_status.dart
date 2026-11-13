import 'package:flutter/foundation.dart';

/// Transport of the default network.
enum PlayStackNetworkType {
  /// No network.
  none,

  /// Wi-Fi.
  wifi,

  /// Mobile data.
  cellular,

  /// Wired Ethernet.
  ethernet,

  /// Another transport (VPN, Bluetooth, ...).
  other,

  /// The engine cannot tell (for example most browsers).
  unknown,
}

/// Connectivity as reported by the operating system or browser.
@immutable
class PlayStackNetworkStatus {
  /// Creates a network status.
  const PlayStackNetworkStatus({
    required this.isConnected,
    this.isMetered = false,
    this.isConstrained = false,
    this.type = PlayStackNetworkType.unknown,
  });

  /// Used when the engine cannot observe the network: connected, unmetered,
  /// unknown transport. Preloading then behaves as on an unmetered network.
  static const unknown = PlayStackNetworkStatus(isConnected: true);

  /// Whether a network is available. False means offline.
  final bool isConnected;

  /// Whether traffic is billed by volume: Android "metered", iOS
  /// "expensive" (cellular, personal hotspot), web `connection.type ==
  /// 'cellular'` where exposed.
  final bool isMetered;

  /// Whether the user asked to save data: Android Data Saver, iOS Low Data
  /// Mode, web `connection.saveData` or a 2G effective type.
  final bool isConstrained;

  /// Transport of the default network.
  final PlayStackNetworkType type;

  @override
  bool operator ==(Object other) =>
      other is PlayStackNetworkStatus &&
      other.isConnected == isConnected &&
      other.isMetered == isMetered &&
      other.isConstrained == isConstrained &&
      other.type == type;

  @override
  int get hashCode => Object.hash(isConnected, isMetered, isConstrained, type);

  @override
  String toString() =>
      'PlayStackNetworkStatus(${type.name}, connected: $isConnected, '
      'metered: $isMetered, constrained: $isConstrained)';
}
