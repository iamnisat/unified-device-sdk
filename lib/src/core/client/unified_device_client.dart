import 'dart:async';

import 'ucp_session_manager.dart';
import 'unified_device_client_config.dart';
import 'unified_device_hardware_profile.dart';
import 'unified_device_session.dart';
import '../../logging/device_communication_log.dart';
import '../../logging/device_communication_log_controller.dart';
import '../../logging/ucp_log_mode.dart';
import '../errors/protocol_exception.dart';
import '../errors/transport_exception.dart';
import '../errors/unified_device_exception.dart';
import '../frame/device_frame.dart';
import '../frame/frame_buffer.dart';
import '../frame/frame_builder.dart';
import '../response/device_event.dart';
import '../response/device_response.dart';
import '../response/response_manager.dart';
import '../transport/ble_transport.dart';
import '../transport/connection_state.dart';
import '../transport/device_transport.dart';
import '../transport/discovered_device.dart';
import '../../protocol/commands/command_options.dart';
import '../../protocol/constants/command_classes.dart';
import '../../protocol/constants/command_ids.dart';
import '../../protocol/constants/operation_codes.dart';
import '../../protocol/constants/profile_ids.dart';
import '../../protocol/constants/protocol_constants.dart';
import '../../protocol/constants/tlv_types.dart';
import '../../protocol/constants/ucp_addresses.dart';
import '../../protocol/models/ucp_device_info.dart';
import '../../protocol/models/ucp_last_report.dart';
import '../../protocol/models/ucp_moisture_sample.dart';
import '../../protocol/models/ucp_packet_trace.dart';
import '../../protocol/models/ucp_time_snapshot.dart';
import '../../protocol/parsers/common_response_parser.dart';
import '../../protocol/payloads/tlv_builder.dart';

/// Generic client for discovery, connection, and official UCP command exchange.
class UnifiedDeviceClient {
  final UnifiedDeviceClientConfig _config;
  final DeviceTransport _transport;
  final FrameBuilder _frameBuilder;
  final FrameBuffer _frameBuffer;
  final UcpResponseManager _responseManager;
  final UcpSessionManager _sessionManager;
  final DeviceCommunicationLogController _communicationLogController =
      DeviceCommunicationLogController();
  final CommonResponseParser _responseParser = const CommonResponseParser();

  bool _isDisposed = false;
  int _logCounter = 0;

  /// Creates a client from an explicit configuration.
  factory UnifiedDeviceClient(UnifiedDeviceClientConfig config) {
    final frameBuilder = FrameBuilder(
      sof: config.sofDelimiter,
      eof: config.eofDelimiter,
    );
    final frameBuffer = FrameBuffer(sofDelimiter: config.sofDelimiter);
    final responseManager = UcpResponseManager(
      transport: config.transport,
      defaultTimeout: config.defaultTimeout,
      frameBuilder: FrameBuilder(
        sof: config.sofDelimiter,
        eof: config.eofDelimiter,
      ),
      frameBuffer: FrameBuffer(sofDelimiter: config.sofDelimiter),
      protocolVersion: config.protocolVersion,
    );

    return UnifiedDeviceClient._(
      config: config,
      transport: config.transport,
      frameBuilder: frameBuilder,
      frameBuffer: frameBuffer,
      responseManager: responseManager,
      sessionManager: UcpSessionManager(
        transport: config.transport,
        responseManager: responseManager,
        hardwareProfile: config.hardwareProfile,
      ),
    );
  }

  UnifiedDeviceClient._({
    required UnifiedDeviceClientConfig config,
    required DeviceTransport transport,
    required FrameBuilder frameBuilder,
    required FrameBuffer frameBuffer,
    required UcpResponseManager responseManager,
    required UcpSessionManager sessionManager,
  }) : _config = config,
       _transport = transport,
       _frameBuilder = frameBuilder,
       _frameBuffer = frameBuffer,
       _responseManager = responseManager,
       _sessionManager = sessionManager {
    _responseManager.onLogEvent = _handleInternalLogEvent;
    _sessionManager.onLogEvent = _handleInternalLogEvent;
  }

  /// Creates a client with a generic BLE transport by default.
  factory UnifiedDeviceClient.generic({
    DeviceTransport? transport,
    Duration defaultTimeout = const Duration(seconds: 5),
    bool autoReconnect = false,
    int maxReconnectAttempts = 3,
    Duration reconnectDelay = const Duration(seconds: 2),
    int sofDelimiter = ProtocolConstants.sof,
    int eofDelimiter = ProtocolConstants.eof,
    int protocolVersion = ProtocolConstants.currentProtocolVersion,
    UcpLogMode logMode = UcpLogMode.off,
    UnifiedDeviceHardwareProfile hardwareProfile =
        UnifiedDeviceHardwareProfile.aunkurUcp1,
  }) {
    return UnifiedDeviceClient(
      UnifiedDeviceClientConfig(
        transport: transport ?? BleTransport(bleProfile: hardwareProfile.ble),
        defaultTimeout: defaultTimeout,
        autoReconnect: autoReconnect,
        maxReconnectAttempts: maxReconnectAttempts,
        reconnectDelay: reconnectDelay,
        sofDelimiter: sofDelimiter,
        eofDelimiter: eofDelimiter,
        protocolVersion: protocolVersion,
        logMode: logMode,
        hardwareProfile: hardwareProfile,
      ),
    );
  }

  DeviceTransport get transport => _transport;
  FrameBuilder get frameBuilder => _frameBuilder;
  FrameBuffer get frameBuffer => _frameBuffer;
  UcpResponseManager get responseManager => _responseManager;
  UcpSessionManager get sessionManager => _sessionManager;
  UnifiedDeviceSession? get currentSession => _sessionManager.currentSession;
  UnifiedDeviceHardwareProfile get hardwareProfile => _config.hardwareProfile;

  bool get isConnected => currentSession != null;
  bool get isScanning => _transport.isScanning;
  bool get isSessionActive => _sessionManager.isSessionActive;

  Stream<DiscoveredDevice> get discoveredDevices =>
      _transport.discoveredDevices;
  Stream<DeviceConnectionState> get connectionState => _sessionManager.states;
  Stream<DeviceEvent> get events => _responseManager.events;
  Stream<DeviceFrame> get frames => _responseManager.frames;
  Stream<DeviceResponse> get dataResponses => _responseManager.dataResponses;
  Stream<DeviceFrame> get streamFrames => _responseManager.streamFrames;
  Stream<UcpPacketTrace> get packetTraces => _responseManager.packetTraces;
  Stream<DeviceCommunicationLog> get communicationLogs =>
      _communicationLogController.stream;

  Stream<UcpMoistureSample> get moistureSamples => streamFrames
      .where(
        (frame) =>
            frame.commandClass == CommandClasses.moisture &&
            frame.commandId == MoistureCommandIds.moistGetOn,
      )
      .map(_responseParser.parseMoistureSample);

  /// Legacy aliases retained for existing call sites.
  Stream<DiscoveredDevice> get onDeviceDiscovered => discoveredDevices;
  Stream<DeviceConnectionState> get onConnectionStateChanged => connectionState;
  Stream<DeviceEvent> get onDeviceEvent => events;

  Future<void> startScan() async {
    _throwIfDisposed();
    await _transport.startScan();
  }

  Future<void> stopScan() async {
    _throwIfDisposed();
    await _transport.stopScan();
  }

  Future<void> connect(DiscoveredDevice device) async {
    _throwIfDisposed();
    await _transport.connect(device);
    await Future<void>.delayed(Duration.zero);
    if (_config.hardwareProfile.bootstrapStrategy ==
        UcpBootstrapStrategy.manual) {
      return;
    }
    await _sessionManager.bootstrap();
    await _sessionManager.waitUntilSessionActive();
  }

  Future<void> disconnect() async {
    _throwIfDisposed();
    if (isSessionActive) {
      await _sessionManager.closeSession();
      return;
    }
    await _transport.disconnect();
  }

  Future<DeviceResponse> btTransportOpen() {
    _throwIfDisposed();
    _throwIfNotTransportReady();
    return _sessionManager.openTransport();
  }

  Future<DeviceResponse> sessionOpenRtcSync({DateTime? now}) {
    _throwIfDisposed();
    _throwIfNotTransportReady();
    return _sessionManager.openRtcSession(now: now);
  }

  Future<void> sessionClose() async {
    _throwIfDisposed();
    await _sessionManager.closeSession();
  }

  Future<UcpDeviceInfo> deviceInfo({Duration? timeout}) async {
    final response = await sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.deviceInfo,
      commandId: DeviceInfoCommandIds.getDeviceInfo,
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
    return _responseParser.parseUcpDeviceInfo(response);
  }

  Future<UcpTimeSnapshot> timeRead({Duration? timeout}) async {
    final response = await sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.system,
      commandId: SystemCommandIds.time,
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
    return _responseParser.parseUcpTime(response);
  }

  Future<DeviceResponse> startTest({
    required String agentId,
    required String farmerId,
    required String fieldIndex,
    required String fieldTestIndex,
    int globalLandLocation = 0,
    int aez = 0,
    int soilCategory = 0,
    Duration? timeout,
  }) async {
    final payloadBuilder = TlvBuilder()
      ..addUtf8(TlvTypes.agentId, agentId)
      ..addUtf8(TlvTypes.farmerId, farmerId)
      ..addUtf8(TlvTypes.fieldIndex, fieldIndex)
      ..addUtf8(TlvTypes.fieldTestIndex, fieldTestIndex)
      ..addUint32BE(TlvTypes.globalLandLocation, globalLandLocation)
      ..addUint32BE(TlvTypes.aez, aez)
      ..addUint32BE(TlvTypes.soilCategory, soilCategory);

    final response = await sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.measurement,
      commandId: MeasurementCommandIds.startTest,
      payload: payloadBuilder.build(),
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: false),
    );
    _sessionManager.markMeasurementActive(true);
    return response;
  }

  Future<UcpLastReport> lastReport({Duration? timeout}) async {
    final response = await sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.report,
      commandId: ReportCommandIds.lastReport,
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
    _sessionManager.markMeasurementActive(false);
    return _responseParser.parseUcpLastReport(response);
  }

  Future<DeviceResponse> moistGetOn({Duration? timeout}) async {
    final response = await sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.moisture,
      commandId: MoistureCommandIds.moistGetOn,
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: false),
    );
    _sessionManager.markStreamActive(true);
    return response;
  }

  Future<DeviceResponse> moistGetOff({Duration? timeout}) async {
    final response = await sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.moisture,
      commandId: MoistureCommandIds.moistGetOff,
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: false),
    );
    _sessionManager.markStreamActive(false);
    return response;
  }

  Future<DeviceResponse> font(String language, {Duration? timeout}) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.ui,
      commandId: UiCommandIds.font,
      payload: TlvBuilder()
          .addUint8(TlvTypes.languageU8, _languageCode(language))
          .build(),
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
  }

  Future<DeviceResponse> cdn(String name, {Duration? timeout}) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.connectivity,
      commandId: ConnectivityCommandIds.cdn,
      payload: TlvBuilder().addUtf8(TlvTypes.clientName, name).build(),
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
  }

  // ---- Calibration Commands ----

  /// Starts calibration for the specified sensor(s).
  Future<DeviceResponse> calibrationStart({
    required int sensorType,
    Duration? timeout,
  }) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.calibration,
      commandId: CalibrationCommandIds.calibrationStart,
      payload: TlvBuilder().addUint8(TlvTypes.sensorTypeU8, sensorType).build(),
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
  }

  /// Gets the current calibration status.
  Future<DeviceResponse> calibrationStatus({Duration? timeout}) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.calibration,
      commandId: CalibrationCommandIds.calibrationStatus,
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
  }

  /// Applies calibration values to the device.
  Future<DeviceResponse> calibrationApply({
    required int sensorType,
    required List<int> calibrationData,
    Duration? timeout,
  }) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.calibration,
      commandId: CalibrationCommandIds.calibrationApply,
      payload: TlvBuilder()
          .addUint8(TlvTypes.sensorTypeU8, sensorType)
          .addBytes(TlvTypes.calData, calibrationData)
          .build(),
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: false),
    );
  }

  // ---- Configuration Commands ----

  /// Reads a configuration parameter from the device.
  Future<DeviceResponse> configRead({
    required int configKey,
    Duration? timeout,
  }) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.configuration,
      commandId: ConfigurationCommandIds.configRead,
      payload: TlvBuilder()
          .addUint16BE(TlvTypes.configKeyU16, configKey)
          .build(),
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
  }

  /// Writes a configuration parameter to the device.
  Future<DeviceResponse> configWrite({
    required int configKey,
    required List<int> configValue,
    Duration? timeout,
  }) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.configuration,
      commandId: ConfigurationCommandIds.configWrite,
      payload: TlvBuilder()
          .addUint16BE(TlvTypes.configKeyU16, configKey)
          .addBytes(TlvTypes.configValue, configValue)
          .build(),
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: false),
    );
  }

  /// Lists all available configuration parameters from the device.
  Future<DeviceResponse> configList({Duration? timeout}) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.configuration,
      commandId: ConfigurationCommandIds.configList,
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
  }

  // ---- Report History Commands ----

  /// Gets a list of available report IDs from the device.
  Future<DeviceResponse> reportList({Duration? timeout}) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.report,
      commandId: ReportHistoryCommandIds.reportList,
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
  }

  /// Gets a specific historical report by ID.
  Future<DeviceResponse> reportGet({required int reportId, Duration? timeout}) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.report,
      commandId: ReportHistoryCommandIds.reportGet,
      payload: TlvBuilder().addUint32BE(TlvTypes.reportIdU32, reportId).build(),
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
  }

  /// Deletes a specific historical report by ID.
  Future<DeviceResponse> reportDelete({
    required int reportId,
    Duration? timeout,
  }) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.report,
      commandId: ReportHistoryCommandIds.reportDelete,
      payload: TlvBuilder().addUint32BE(TlvTypes.reportIdU32, reportId).build(),
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: false),
    );
  }

  /// Exports report data from the device.
  Future<DeviceResponse> reportExport({
    required int reportId,
    required String format,
    Duration? timeout,
  }) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.report,
      commandId: ReportHistoryCommandIds.reportExport,
      payload: TlvBuilder()
          .addUint32BE(TlvTypes.reportIdU32, reportId)
          .addUtf8(TlvTypes.exportFormat, format)
          .build(),
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
  }

  // ---- File Transfer Commands ----

  /// Starts a file transfer session to the device.
  Future<DeviceResponse> fileTransferStart({
    required String fileName,
    required int fileSize,
    Duration? timeout,
  }) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.fileTransfer,
      commandId: FileTransferCommandIds.fileTransferStart,
      payload: TlvBuilder()
          .addUtf8(TlvTypes.fileName, fileName)
          .addUint32BE(TlvTypes.fileSizeU32, fileSize)
          .build(),
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
  }

  /// Sends a chunk of file data to the device.
  Future<DeviceResponse> fileTransferChunk({
    required int offset,
    required List<int> chunkData,
    Duration? timeout,
  }) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.fileTransfer,
      commandId: FileTransferCommandIds.fileTransferChunk,
      payload: TlvBuilder()
          .addUint32BE(TlvTypes.fileOffsetU32, offset)
          .addBytes(TlvTypes.fileData, chunkData)
          .build(),
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: false),
    );
  }

  /// Ends a file transfer session.
  Future<DeviceResponse> fileTransferEnd({
    required int transferId,
    Duration? timeout,
  }) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.fileTransfer,
      commandId: FileTransferCommandIds.fileTransferEnd,
      payload: TlvBuilder()
          .addUint32BE(TlvTypes.transferIdU32, transferId)
          .build(),
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
  }

  /// Gets the current file transfer status.
  Future<DeviceResponse> fileTransferStatus({Duration? timeout}) {
    return sendCommand(
      productId: _config.hardwareProfile.productId,
      profileId: _config.hardwareProfile.profileId,
      sourceAddress: _config.hardwareProfile.sourceAddress,
      destinationAddress: _config.hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.fileTransfer,
      commandId: FileTransferCommandIds.fileTransferStatus,
      timeout: timeout,
      options: const CommandOptions(waitForAck: true, waitForData: true),
    );
  }

  /// Sends a generic command and waits according to [options].
  Future<DeviceResponse> sendCommand({
    required int productId,
    required int op,
    required int commandId,
    List<int> payload = const [],
    int profileId = ProfileIds.defaultProfile,
    int sourceAddress = UcpAddresses.defaultSource,
    int address = UcpAddresses.defaultDestination,
    int? destinationAddress,
    int commandClass = CommandClasses.system,
    int flags = 0,
    CommandOptions options = const CommandOptions(),
    Duration? timeout,
  }) async {
    _throwIfDisposed();
    _validateCommandInput(
      productId: productId,
      op: op,
      commandId: commandId,
      payload: payload,
      profileId: profileId,
      sourceAddress: sourceAddress,
      address: address,
      destinationAddress: destinationAddress,
      commandClass: commandClass,
      flags: flags,
    );
    _throwIfNotConnected();
    _throwIfCommandBlocked(commandClass, commandId);

    final response = await _responseManager.sendCommand(
      commandId: commandId,
      productId: productId,
      profileId: profileId,
      sourceAddress: sourceAddress,
      destinationAddress: destinationAddress ?? address,
      op: op,
      commandClass: commandClass,
      version: _config.protocolVersion,
      payload: payload,
      flags: flags,
      options: timeout == null
          ? options
          : options.copyWith(ackTimeout: timeout, dataTimeout: timeout),
    );
    _emitCommandResultLog(response);
    return response;
  }

  Future<void> sendFrame(DeviceFrame frame) async {
    _throwIfDisposed();
    _throwIfNotConnected();
    _throwIfCommandBlocked(frame.commandClass, frame.commandId);
    await _responseManager.sendFrame(frame);
  }

  Future<void> sendRawData(List<int> data) async {
    _throwIfDisposed();
    _throwIfNotConnected();
    final state = _sessionManager.state;
    if (state != DeviceConnectionState.mtuReady &&
        state != DeviceConnectionState.transportReady &&
        state != DeviceConnectionState.sessionActive &&
        state != DeviceConnectionState.measurementActive &&
        state != DeviceConnectionState.streamActive &&
        state != DeviceConnectionState.safeDisconnectPending) {
      throw const TransportException(
        'Transport is not ready for raw writes',
        errorType: TransportErrorType.writeFailed,
      );
    }
    await _transport.write(data);
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;

    await _sessionManager.dispose();
    _responseManager.dispose();
    await _transport.dispose();
    await _communicationLogController.dispose();
  }

  void _throwIfDisposed() {
    if (_isDisposed) {
      throw const UnifiedDeviceException('Client has been disposed');
    }
  }

  void _throwIfNotConnected() {
    if (!isConnected) {
      throw const TransportException('Not connected to any device');
    }
  }

  void _throwIfNotTransportReady() {
    final state = _sessionManager.state;
    if (state != DeviceConnectionState.connected &&
        state != DeviceConnectionState.servicesDiscovered &&
        state != DeviceConnectionState.notifySubscribed &&
        state != DeviceConnectionState.mtuReady &&
        state != DeviceConnectionState.transportReady &&
        state != DeviceConnectionState.sessionActive &&
        state != DeviceConnectionState.measurementActive &&
        state != DeviceConnectionState.streamActive &&
        state != DeviceConnectionState.safeDisconnectPending) {
      throw const TransportException(
        'BLE transport is not ready',
        errorType: TransportErrorType.connectionFailed,
      );
    }
  }

  void _throwIfCommandBlocked(int commandClass, int commandId) {
    if (isSessionActive || _isPreSessionCommand(commandClass, commandId)) {
      return;
    }
    throw const ProtocolException(
      'Command is blocked until sessionActive',
      protocolErrorType: ProtocolErrorType.invalidDeviceState,
    );
  }

  bool _isPreSessionCommand(int commandClass, int commandId) {
    return commandClass == CommandClasses.session &&
        (commandId == SessionCommandIds.btTransportOpen ||
            commandId == SessionCommandIds.sessionOpenRtcSync ||
            commandId == SessionCommandIds.sessionClose ||
            commandId == SessionCommandIds.heartbeat);
  }

  void _validateCommandInput({
    required int productId,
    required int op,
    required int commandId,
    required List<int> payload,
    required int profileId,
    required int sourceAddress,
    required int address,
    int? destinationAddress,
    required int commandClass,
    required int flags,
  }) {
    _validateUint8(productId, 'productId');
    _validateUint8(profileId, 'profileId');
    _validateUint8(sourceAddress, 'sourceAddress');
    _validateUint8(destinationAddress ?? address, 'destinationAddress');
    _validateUint8(op, 'op');
    _validateUint8(commandClass, 'commandClass');
    _validateUint8(commandId, 'commandId');
    _validateUint8(flags, 'flags');
    for (var i = 0; i < payload.length; i++) {
      _validateUint8(payload[i], 'payload[$i]');
    }
  }

  void _validateUint8(int value, String name) {
    if (value < 0 || value > 255) {
      throw ArgumentError('$name must be 0-255, but got $value');
    }
  }

  int _languageCode(String language) {
    final normalized = language.trim().toLowerCase();
    if (normalized == '1' ||
        normalized == 'bn' ||
        normalized == 'bangla' ||
        normalized == 'bengali') {
      return 1;
    }
    return 0;
  }

  void _handleInternalLogEvent(
    String event,
    Map<String, dynamic> param,
    UcpLogMode minimumMode,
  ) {
    if (!_shouldEmit(minimumMode)) {
      return;
    }
    final session = currentSession;
    final sessionId =
        (param['sessionId'] as String?) ??
        session?.sessionId ??
        'session_${DateTime.now().millisecondsSinceEpoch}';
    final log = DeviceCommunicationLog(
      logId: _newLogId(),
      sessionId: sessionId,
      deviceId: (param['deviceId'] as String?) ?? session?.deviceId,
      deviceName: (param['deviceName'] as String?) ?? session?.deviceName,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      param: _normalizeParam(param),
    );
    _communicationLogController.add(log);
  }

  void _emitCommandResultLog(DeviceResponse response) {
    _handleInternalLogEvent('command_result', <String, dynamic>{
      'event': 'command_result',
      'level': 'info',
      'layer': 'ucp',
      'result': response.isAck
          ? 'ack'
          : response.isNack
          ? 'nack'
          : 'data',
      'seq': response.sequence,
      'op': response.op,
      'opName': _opName(response.op),
      'classId': response.commandClass,
      'className': _className(response.commandClass),
      'cmdId': response.commandId,
      'cmdName': _commandName(response.commandClass, response.commandId),
      'src': response.sourceAddress,
      'dst': response.destinationAddress,
      'flags': response.flags,
      'payloadLength': response.payload.length,
    }, UcpLogMode.basic);
  }

  bool _shouldEmit(UcpLogMode minimumMode) {
    return _config.logMode != UcpLogMode.off &&
        _config.logMode.index >= minimumMode.index;
  }

  String _newLogId() {
    _logCounter++;
    return 'log_${DateTime.now().millisecondsSinceEpoch}_$_logCounter';
  }

  Map<String, dynamic> _normalizeParam(Map<String, dynamic> param) {
    final normalized = <String, dynamic>{};
    for (final entry in param.entries) {
      if (entry.key == 'sessionId' ||
          entry.key == 'deviceId' ||
          entry.key == 'deviceName') {
        continue;
      }
      if (_config.logMode != UcpLogMode.raw &&
          (entry.key == 'bytesHex' || entry.key == 'tlvs')) {
        continue;
      }
      normalized[entry.key] = _jsonSafeValue(entry.value);
    }
    return normalized;
  }

  Object? _jsonSafeValue(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is List<int>) {
      return value
          .map((byte) => byte.toRadixString(16).toUpperCase().padLeft(2, '0'))
          .join(' ');
    }
    if (value is List) {
      return value.map(_jsonSafeValue).toList(growable: false);
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', _jsonSafeValue(item)));
    }
    return '$value';
  }

  String _opName(int op) {
    switch (op) {
      case OperationCodes.req:
        return 'REQ';
      case OperationCodes.ack:
        return 'ACK';
      case OperationCodes.nack:
        return 'NACK';
      case OperationCodes.data:
        return 'DATA';
      case OperationCodes.event:
        return 'EVENT';
      case OperationCodes.stream:
        return 'STREAM';
      case OperationCodes.heartbeat:
        return 'HEARTBEAT';
      default:
        return '0x${op.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    }
  }

  String _className(int commandClass) {
    if (commandClass == CommandClasses.system) {
      return 'SYSTEM';
    }
    if (commandClass == CommandClasses.deviceInfo) {
      return 'DEVICE_INFO';
    }
    if (commandClass == CommandClasses.configuration) {
      return 'CONFIG';
    }
    if (commandClass == CommandClasses.measurement) {
      return 'MEASUREMENT';
    }
    if (commandClass == CommandClasses.calibration) {
      return 'CALIBRATION';
    }
    if (commandClass == CommandClasses.dataLog) {
      return 'DATA_LOG';
    }
    if (commandClass == CommandClasses.firmwareUpdate) {
      return 'FIRMWARE_UPDATE';
    }
    if (commandClass == CommandClasses.diagnostic) {
      return 'DIAGNOSTIC';
    }
    if (commandClass == CommandClasses.session) {
      return 'SESSION';
    }
    if (commandClass == CommandClasses.power) {
      return 'POWER';
    }
    return '0x${commandClass.toRadixString(16).toUpperCase().padLeft(2, '0')}';
  }

  String _commandName(int commandClass, int commandId) {
    if (commandClass == CommandClasses.system) {
      if (commandId == SystemCommandIds.time) {
        return 'rtc_sync';
      }
    }
    if (commandClass == CommandClasses.deviceInfo) {
      if (commandId == DeviceInfoCommandIds.getDeviceInfo) {
        return 'get_device_info';
      }
      if (commandId == DeviceInfoCommandIds.setClientName) {
        return 'set_client_name';
      }
    }
    if (commandClass == CommandClasses.session) {
      if (commandId == SessionCommandIds.sessionOpenRtcSync) {
        return 'open_rtc_sync';
      }
      if (commandId == SessionCommandIds.sessionClose) {
        return 'safe_disconnect_request';
      }
      if (commandId == SessionCommandIds.heartbeat) {
        return 'heartbeat';
      }
      if (commandId == SessionCommandIds.btTransportOpen) {
        return 'bt_transport_open';
      }
    }
    if (commandClass == CommandClasses.measurement) {
      if (commandId == MeasurementCommandIds.startTest) {
        return 'start_test';
      }
      if (commandId == MeasurementCommandIds.stopTest) {
        return 'stop_test';
      }
      if (commandId == MeasurementCommandIds.startMoistureTest) {
        return 'start_moisture_test';
      }
      if (commandId == MeasurementCommandIds.stopMoistureTest) {
        return 'stop_moisture_test';
      }
      if (commandId == MeasurementCommandIds.getLastReport) {
        return 'get_last_report';
      }
    }
    if (commandClass == CommandClasses.ui && commandId == UiCommandIds.font) {
      return 'set_ui_language';
    }
    if (commandClass == CommandClasses.connectivity &&
        commandId == ConnectivityCommandIds.cdn) {
      return 'set_client_name';
    }
    if (commandClass == CommandClasses.calibration) {
      if (commandId == CalibrationCommandIds.calibrationStart) {
        return 'calibration_start';
      }
      if (commandId == CalibrationCommandIds.calibrationStatus) {
        return 'calibration_status';
      }
      if (commandId == CalibrationCommandIds.calibrationApply) {
        return 'calibration_apply';
      }
    }
    if (commandClass == CommandClasses.configuration) {
      if (commandId == ConfigurationCommandIds.configRead) {
        return 'config_read';
      }
      if (commandId == ConfigurationCommandIds.configWrite) {
        return 'config_write';
      }
      if (commandId == ConfigurationCommandIds.configList) {
        return 'config_list';
      }
    }
    if (commandClass == CommandClasses.fileTransfer) {
      if (commandId == FileTransferCommandIds.fileTransferStart) {
        return 'file_transfer_start';
      }
      if (commandId == FileTransferCommandIds.fileTransferChunk) {
        return 'file_transfer_chunk';
      }
      if (commandId == FileTransferCommandIds.fileTransferEnd) {
        return 'file_transfer_end';
      }
      if (commandId == FileTransferCommandIds.fileTransferStatus) {
        return 'file_transfer_status';
      }
    }
    return '0x${commandId.toRadixString(16).toUpperCase().padLeft(2, '0')}';
  }
}
