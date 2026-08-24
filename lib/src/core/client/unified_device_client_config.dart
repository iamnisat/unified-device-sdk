import '../transport/device_transport.dart';
import '../../logging/ucp_log_mode.dart';
import '../../protocol/constants/protocol_constants.dart';
import 'unified_device_hardware_profile.dart';

/// Configuration for the [UnifiedDeviceClient].
class UnifiedDeviceClientConfig {
  /// The transport to use for device communication.
  final DeviceTransport transport;

  /// Default timeout for device operations.
  final Duration defaultTimeout;

  /// Whether to automatically reconnect on connection loss.
  final bool autoReconnect;

  /// Maximum number of reconnection attempts.
  final int maxReconnectAttempts;

  /// Delay between reconnection attempts.
  final Duration reconnectDelay;

  /// The SOF delimiter for frame parsing.
  final int sofDelimiter;

  /// The EOF delimiter for frame parsing.
  final int eofDelimiter;

  /// The protocol version to use.
  final int protocolVersion;

  /// Controls how much communication detail the SDK emits.
  final UcpLogMode logMode;

  /// Hardware-specific BLE and UCP values.
  final UnifiedDeviceHardwareProfile hardwareProfile;

  /// Creates a [UnifiedDeviceClientConfig] with the given parameters.
  const UnifiedDeviceClientConfig({
    required this.transport,
    this.defaultTimeout = const Duration(seconds: 5),
    this.autoReconnect = false,
    this.maxReconnectAttempts = 3,
    this.reconnectDelay = const Duration(seconds: 2),
    this.sofDelimiter = ProtocolConstants.sof,
    this.eofDelimiter = ProtocolConstants.eof,
    this.protocolVersion = ProtocolConstants.currentProtocolVersion,
    this.logMode = UcpLogMode.off,
    this.hardwareProfile = UnifiedDeviceHardwareProfile.aunkurUcp1,
  });
}
