import 'package:flutter/foundation.dart';

/// Transport of the default network.
enum ReelNetworkType {
  /// No network.
  none,
  wifi,
  cellular,
  ethernet,

  /// Another transport (VPN, Bluetooth, ...).
  other,

  /// The engine cannot tell (for example most browsers).
  unknown,
}

/// Connectivity as reported by the operating system or browser.
@immutable
class ReelNetworkStatus {
  const ReelNetworkStatus({
    required this.isConnected,
    this.isMetered = false,
    this.isConstrained = false,
    this.type = ReelNetworkType.unknown,
  });

  /// Used when the engine cannot observe the network: connected, unmetered,
  /// unknown transport. Preloading then behaves as on an unmetered network.
  static const unknown = ReelNetworkStatus(isConnected: true);

  /// Whether a network is available. False means offline.
  final bool isConnected;

  /// Whether traffic is billed by volume: Android "metered", iOS
  /// "expensive" (cellular, personal hotspot), web `connection.type ==
  /// 'cellular'` where exposed.
  final bool isMetered;

  /// Whether the user asked to save data: Android Data Saver, iOS Low Data
  /// Mode, web `connection.saveData` or a 2G effective type.
  final bool isConstrained;

  final ReelNetworkType type;

  @override
  bool operator ==(Object other) =>
      other is ReelNetworkStatus &&
      other.isConnected == isConnected &&
      other.isMetered == isMetered &&
      other.isConstrained == isConstrained &&
      other.type == type;

  @override
  int get hashCode => Object.hash(isConnected, isMetered, isConstrained, type);

  @override
  String toString() =>
      'ReelNetworkStatus(${type.name}, connected: $isConnected, '
      'metered: $isMetered, constrained: $isConstrained)';
}
