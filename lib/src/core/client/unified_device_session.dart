import '../transport/connection_state.dart';

/// Represents an active session with a connected device.
class UnifiedDeviceSession {
  /// Runtime-generated BLE connection session identifier.
  final String sessionId;

  /// The ID of the connected device.
  final String deviceId;

  /// The device name, if available.
  final String? deviceName;

  /// The time when the session was established.
  final DateTime startedAt;

  /// The current connection state.
  DeviceConnectionState state;

  /// Whether the UCP session bootstrap has completed.
  bool sessionActive;

  /// Whether a measurement workflow is active.
  bool measurementActive;

  /// Whether a stream workflow is active.
  bool streamActive;

  /// Whether a graceful close is pending.
  bool safeDisconnectPending;

  /// Firmware-provided UCP session identifier.
  int? ucpSessionId;

  /// Creates a [UnifiedDeviceSession].
  UnifiedDeviceSession({
    required this.sessionId,
    required this.deviceId,
    this.deviceName,
    DateTime? startedAt,
    this.state = DeviceConnectionState.connected,
    this.sessionActive = false,
    this.measurementActive = false,
    this.streamActive = false,
    this.safeDisconnectPending = false,
    this.ucpSessionId,
  }) : startedAt = startedAt ?? DateTime.now();

  /// The duration the session has been active.
  Duration get duration => DateTime.now().difference(startedAt);

  /// Whether the session is still active.
  bool get isActive =>
      state != DeviceConnectionState.disconnected &&
      state != DeviceConnectionState.connectionLost;

  @override
  String toString() {
    return 'UnifiedDeviceSession(sessionId: $sessionId, device: $deviceId, '
        'name: $deviceName, '
        'state: $state, sessionActive: $sessionActive, '
        'measurementActive: $measurementActive, streamActive: $streamActive, '
        'safeDisconnectPending: $safeDisconnectPending, duration: $duration)';
  }
}
