/// Production UCP status/error codes returned by hardware NACK responses.
class UcpStatusCodes {
  UcpStatusCodes._();

  static const int ok = 0x0000;
  static const int unknownCmd = 0x0001;
  static const int unsupportedVersion = 0x0002;
  static const int badCrc = 0x0003;
  static const int invalidLength = 0x0004;
  static const int invalidPayload = 0x0005;
  static const int authOrTransportSyncRequired = 0x0006;
  static const int permissionDenied = 0x0007;
  static const int deviceBusy = 0x0008;
  static const int timeout = 0x0009;
  static const int invalidState = 0x000A;
  static const int storageError = 0x000B;
  static const int sensorError = 0x000C;
  static const int calibrationRequired = 0x000D;
  static const int lowBattery = 0x000E;
  static const int notImplemented = 0x000F;
  static const int internalError = 0x0010;
  static const int sessionNotOpen = 0x0100;
  static const int sessionAlreadyOpen = 0x0101;
  static const int sessionIdMismatch = 0x0102;
  static const int safeDisconnectDenied = 0x0103;
  static const int heartbeatTimeout = 0x0104;
  static const int unexpectedDisconnectRecorded = 0x0105;
  static const int clientIdRequired = 0x0106;

  static const Map<int, UcpStatusCodeInfo> all = <int, UcpStatusCodeInfo>{
    ok: UcpStatusCodeInfo(ok, 'OK', 'Success.'),
    unknownCmd: UcpStatusCodeInfo(
      unknownCmd,
      'UNKNOWN_CMD',
      'Class/command combination is not recognized.',
    ),
    unsupportedVersion: UcpStatusCodeInfo(
      unsupportedVersion,
      'UNSUPPORTED_VERSION',
      'VER/product/profile mismatch.',
    ),
    badCrc: UcpStatusCodeInfo(badCrc, 'BAD_CRC', 'CRC check failed.'),
    invalidLength: UcpStatusCodeInfo(
      invalidLength,
      'INVALID_LENGTH',
      'Frame or TLV length invalid.',
    ),
    invalidPayload: UcpStatusCodeInfo(
      invalidPayload,
      'INVALID_PAYLOAD',
      'Required TLV missing or invalid.',
    ),
    authOrTransportSyncRequired: UcpStatusCodeInfo(
      authOrTransportSyncRequired,
      'AUTH_OR_TRANSPORT_SYNC_REQUIRED',
      'RTC/security sync required.',
      retryable: true,
    ),
    permissionDenied: UcpStatusCodeInfo(
      permissionDenied,
      'PERMISSION_DENIED',
      'Operation not allowed.',
    ),
    deviceBusy: UcpStatusCodeInfo(
      deviceBusy,
      'DEVICE_BUSY',
      'Device cannot accept command now.',
      retryable: true,
    ),
    timeout: UcpStatusCodeInfo(
      timeout,
      'TIMEOUT',
      'Operation timeout.',
      retryable: true,
    ),
    invalidState: UcpStatusCodeInfo(
      invalidState,
      'INVALID_STATE',
      'Command not valid in current state.',
    ),
    storageError: UcpStatusCodeInfo(
      storageError,
      'STORAGE_ERROR',
      'SD/config/storage failure.',
    ),
    sensorError: UcpStatusCodeInfo(
      sensorError,
      'SENSOR_ERROR',
      'Sensor failure.',
    ),
    calibrationRequired: UcpStatusCodeInfo(
      calibrationRequired,
      'CALIBRATION_REQUIRED',
      'Calibration needed before operation.',
    ),
    lowBattery: UcpStatusCodeInfo(
      lowBattery,
      'LOW_BATTERY',
      'Battery too low for operation.',
    ),
    notImplemented: UcpStatusCodeInfo(
      notImplemented,
      'NOT_IMPLEMENTED',
      'Command exists but is not implemented.',
    ),
    internalError: UcpStatusCodeInfo(
      internalError,
      'INTERNAL_ERROR',
      'Unexpected firmware error.',
    ),
    sessionNotOpen: UcpStatusCodeInfo(
      sessionNotOpen,
      'SESSION_NOT_OPEN',
      'Normal command sent before session open.',
    ),
    sessionAlreadyOpen: UcpStatusCodeInfo(
      sessionAlreadyOpen,
      'SESSION_ALREADY_OPEN',
      'Duplicate open request.',
    ),
    sessionIdMismatch: UcpStatusCodeInfo(
      sessionIdMismatch,
      'SESSION_ID_MISMATCH',
      'Supplied session_id does not match active session.',
    ),
    safeDisconnectDenied: UcpStatusCodeInfo(
      safeDisconnectDenied,
      'SAFE_DISCONNECT_DENIED',
      'Controlled disconnect denied.',
    ),
    heartbeatTimeout: UcpStatusCodeInfo(
      heartbeatTimeout,
      'HEARTBEAT_TIMEOUT',
      'Reserved heartbeat timeout error; defined but not currently enforced.',
      retryable: true,
    ),
    unexpectedDisconnectRecorded: UcpStatusCodeInfo(
      unexpectedDisconnectRecorded,
      'UNEXPECTED_DISCONNECT_RECORDED',
      'Unexpected disconnect was logged.',
    ),
    clientIdRequired: UcpStatusCodeInfo(
      clientIdRequired,
      'CLIENT_ID_REQUIRED',
      'client_name and app_instance_id are required.',
    ),
  };

  static UcpStatusCodeInfo? lookup(int? code) =>
      code == null ? null : all[code];

  static String hex(int code) =>
      '0x${code.toRadixString(16).toUpperCase().padLeft(4, '0')}';
}

class UcpStatusCodeInfo {
  final int code;
  final String name;
  final String description;
  final bool retryable;

  const UcpStatusCodeInfo(
    this.code,
    this.name,
    this.description, {
    this.retryable = false,
  });

  String get hex => UcpStatusCodes.hex(code);
  bool get isOk => code == UcpStatusCodes.ok;
  bool get isError => !isOk;

  @override
  String toString() => '$name ($hex): $description';
}
