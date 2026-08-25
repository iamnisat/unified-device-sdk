import 'dart:async';

import 'unified_device_hardware_profile.dart';
import 'unified_device_session.dart';
import '../errors/protocol_exception.dart';
import '../errors/transport_exception.dart';
import '../response/device_event.dart';
import '../response/device_response.dart';
import '../response/response_manager.dart';
import '../transport/connection_state.dart';
import '../transport/device_transport.dart';
import '../../logging/ucp_log_mode.dart';
import '../../protocol/commands/command_options.dart';
import '../../protocol/constants/ble_constants.dart';
import '../../protocol/constants/command_classes.dart';
import '../../protocol/constants/command_ids.dart';
import '../../protocol/constants/operation_codes.dart';
import '../../protocol/constants/protocol_constants.dart';
import '../../protocol/constants/tlv_types.dart';
import '../../protocol/constants/ucp_status_codes.dart';
import '../../protocol/models/decoded_tlv.dart';
import '../../protocol/payloads/tlv_builder.dart';

/// Drives the official UCP bootstrap and session lifecycle on the Dart side.
class UcpSessionManager {
  final DeviceTransport _transport;
  final UcpResponseManager _responseManager;
  final UnifiedDeviceHardwareProfile _hardwareProfile;

  final StreamController<DeviceConnectionState> _stateController =
      StreamController<DeviceConnectionState>.broadcast();

  StreamSubscription<DeviceConnectionState>? _transportSubscription;
  StreamSubscription<DeviceEvent>? _eventSubscription;
  StreamSubscription<dynamic>? _streamSubscription;

  UnifiedDeviceSession? _currentSession;
  DeviceConnectionState _state = DeviceConnectionState.disconnected;
  Completer<void>? _bootstrapCompleter;
  Completer<void>? _disconnectCompleter;
  bool _bootstrapStarted = false;
  bool _isDisposed = false;
  String? _pendingSessionId;

  // Heartbeat
  Timer? _heartbeatTimer;
  Timer? _heartbeatTimeoutTimer;
  int _missedHeartbeats = 0;
  static const int _maxMissedHeartbeats = 3;
  int _sessionCounter = 0;
  void Function(String event, Map<String, dynamic> param, UcpLogMode mode)?
  onLogEvent;

  UcpSessionManager({
    required DeviceTransport transport,
    required UcpResponseManager responseManager,
    required UnifiedDeviceHardwareProfile hardwareProfile,
    this.onLogEvent,
  }) : _transport = transport,
       _responseManager = responseManager,
       _hardwareProfile = hardwareProfile {
    _bind();
  }

  Stream<DeviceConnectionState> get states => _stateController.stream;
  DeviceConnectionState get state => _state;
  UnifiedDeviceSession? get currentSession => _currentSession;

  bool get isSessionActive => _currentSession?.sessionActive ?? false;

  void _bind() {
    _transportSubscription = _transport.connectionState.listen(
      _handleTransportState,
    );
    _eventSubscription = _responseManager.events.listen(_handleEvent);
    _streamSubscription = _responseManager.streamFrames.listen((_) {
      markStreamActive(true);
    });
  }

  Future<void> waitUntilSessionActive({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (isSessionActive) {
      return;
    }

    final completer = _bootstrapCompleter;
    if (completer == null) {
      throw const TransportException(
        'Session bootstrap has not started',
        errorType: TransportErrorType.connectionFailed,
      );
    }
    await completer.future.timeout(timeout);
  }

  Future<void> bootstrap() {
    if (isSessionActive) {
      return Future<void>.value();
    }
    return _startBootstrapIfNeeded();
  }

  Future<DeviceResponse> openTransport({bool includeClientName = true}) async {
    final response = await _responseManager.sendCommand(
      productId: _hardwareProfile.productId,
      profileId: _hardwareProfile.profileId,
      sourceAddress: _hardwareProfile.sourceAddress,
      destinationAddress: _hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.session,
      commandId: SessionCommandIds.btTransportOpen,
      payload: _clientNamePayload(includeClientName: includeClientName),
      options: const CommandOptions(
        waitForAck: true,
        waitForData: false,
        completeOnEvent: true,
      ),
    );
    _emitLog('transport_ready', <String, dynamic>{
      'level': 'info',
      'layer': 'ucp',
      'state': DeviceConnectionState.transportReady.name,
    }, UcpLogMode.basic);
    _updateState(DeviceConnectionState.transportReady);
    return response;
  }

  Future<DeviceResponse> openRtcSession({
    DateTime? now,
    bool includeClientName = true,
  }) async {
    final epochSeconds = _epochSecondsForRtc(now ?? DateTime.now());
    final response = await _responseManager.sendCommand(
      productId: _hardwareProfile.productId,
      profileId: _hardwareProfile.profileId,
      sourceAddress: _hardwareProfile.sourceAddress,
      destinationAddress: _hardwareProfile.destinationAddress,
      op: OperationCodes.req,
      commandClass: CommandClasses.session,
      commandId: SessionCommandIds.sessionOpenRtcSync,
      payload: _sessionOpenPayload(
        epochSeconds,
        includeClientName: includeClientName,
      ),
      options: const CommandOptions(
        waitForAck: true,
        waitForData: false,
        completeOnEvent: true,
      ),
    );
    _activateSession(response);
    return response;
  }

  Future<void> closeSession({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_currentSession == null) {
      await _transport.disconnect();
      return;
    }

    _currentSession!
      ..safeDisconnectPending = true
      ..measurementActive = false
      ..streamActive = false;
    _emitLog('session_close_started', <String, dynamic>{
      'level': 'info',
      'layer': 'ucp',
      'state': 'closing',
      'message': 'Graceful session close requested',
    }, UcpLogMode.basic);
    _emitLog('safe_disconnect_pending', <String, dynamic>{
      'level': 'info',
      'layer': 'ucp',
      'state': DeviceConnectionState.safeDisconnectPending.name,
    }, UcpLogMode.basic);
    _updateState(DeviceConnectionState.safeDisconnectPending);
    _disconnectCompleter ??= Completer<void>();

    try {
      await _responseManager.sendCommand(
        productId: _hardwareProfile.productId,
        profileId: _hardwareProfile.profileId,
        sourceAddress: _hardwareProfile.sourceAddress,
        destinationAddress: _hardwareProfile.destinationAddress,
        op: OperationCodes.req,
        commandClass: CommandClasses.session,
        commandId: SessionCommandIds.sessionClose,
        payload: TlvBuilder()
            .addUint32BE(TlvTypes.sessionId, _currentSession?.ucpSessionId ?? 0)
            .addUint8(TlvTypes.disconnectReason, 1)
            .build(),
        options: const CommandOptions(
          waitForAck: true,
          waitForData: false,
          completeOnEvent: true,
        ),
      );
    } on Object {
      await _transport.disconnect();
      rethrow;
    }

    try {
      await _disconnectCompleter!.future.timeout(timeout);
    } on TimeoutException {
      await _transport.disconnect();
    }
  }

  void markMeasurementActive(bool active) {
    if (_currentSession == null) {
      return;
    }
    _currentSession!.measurementActive = active;
    if (!active) {
      _currentSession!.safeDisconnectPending = false;
    }
    _refreshOperationalState();
  }

  void markStreamActive(bool active) {
    if (_currentSession == null) {
      return;
    }
    _currentSession!.streamActive = active;
    _refreshOperationalState();
  }

  void _handleTransportState(DeviceConnectionState state) {
    switch (state) {
      case DeviceConnectionState.scanning:
      case DeviceConnectionState.connecting:
      case DeviceConnectionState.disconnecting:
      case DeviceConnectionState.servicesDiscovered:
      case DeviceConnectionState.notifySubscribed:
        _pendingSessionId ??= _newSessionId();
        _emitStateLog(state);
        _updateState(state);
        break;
      case DeviceConnectionState.connected:
        _currentSession = UnifiedDeviceSession(
          sessionId: _pendingSessionId ?? _newSessionId(),
          deviceId: _transport.connectedDeviceId ?? 'unknown',
          deviceName:
              _transport.connectedDeviceName ?? BleConstants.defaultDeviceName,
          state: DeviceConnectionState.connected,
        );
        _bootstrapStarted = false;
        _emitStateLog(DeviceConnectionState.connected);
        _updateState(DeviceConnectionState.connected);
        break;
      case DeviceConnectionState.mtuReady:
        if (_shouldApplyTransportState(state)) {
          _emitStateLog(
            state,
            extra: <String, dynamic>{'mtu': _transport.negotiatedMtu},
          );
          _updateState(DeviceConnectionState.mtuReady);
          unawaited(_startBootstrapIfNeeded());
        }
        break;
      case DeviceConnectionState.error:
        _emitLog('error', <String, dynamic>{
          'level': 'error',
          'layer': 'ble',
          'state': state.name,
          'message': 'BLE transport reported an error state',
        }, UcpLogMode.errorOnly);
        _updateState(DeviceConnectionState.error);
        break;
      case DeviceConnectionState.disconnected:
      case DeviceConnectionState.connectionLost:
        _stopHeartbeat();
        _emitDisconnectionLog(state);
        _emitLog('reconnect_cleanup', <String, dynamic>{
          'level': 'info',
          'layer': 'ble',
          'state': state.name,
          'message': 'Session state reset after disconnect',
        }, UcpLogMode.basic);
        _currentSession = null;
        _pendingSessionId = null;
        _bootstrapStarted = false;
        _updateState(state);
        _disconnectCompleter?.complete();
        _disconnectCompleter = null;
        if (_bootstrapCompleter != null && !_bootstrapCompleter!.isCompleted) {
          _bootstrapCompleter!.completeError(
            TransportException(
              state == DeviceConnectionState.connectionLost
                  ? 'Connection lost during session bootstrap'
                  : 'Disconnected during session bootstrap',
              errorType: state == DeviceConnectionState.connectionLost
                  ? TransportErrorType.connectionLost
                  : TransportErrorType.connectionFailed,
            ),
          );
        }
        _bootstrapCompleter = null;
        break;
      default:
        if (_shouldApplyTransportState(state)) {
          _updateState(state);
        }
        break;
    }
  }

  bool _shouldApplyTransportState(DeviceConnectionState nextState) {
    if (_state == nextState) {
      return true;
    }

    if (nextState == DeviceConnectionState.disconnected ||
        nextState == DeviceConnectionState.connectionLost ||
        nextState == DeviceConnectionState.error) {
      return true;
    }

    // Native BLE callbacks can report lower-level readiness states like
    // `mtuReady` after the UCP bootstrap has already advanced to
    // `transportReady` or `sessionActive`. Ignore those regressions.
    if (_state.index >= DeviceConnectionState.transportReady.index &&
        nextState.index < DeviceConnectionState.transportReady.index) {
      return false;
    }

    return true;
  }

  Future<void> _startBootstrapIfNeeded() {
    final completer = _bootstrapCompleter ??= Completer<void>();

    if (_bootstrapStarted ||
        _state == DeviceConnectionState.error ||
        _state == DeviceConnectionState.disconnected ||
        _state == DeviceConnectionState.connectionLost ||
        _state.index < DeviceConnectionState.mtuReady.index) {
      return completer.future;
    }

    _bootstrapStarted = true;
    unawaited(_runBootstrap(completer));
    return completer.future;
  }

  Future<void> _runBootstrap(Completer<void> completer) async {
    try {
      final strategy = _hardwareProfile.bootstrapStrategy;
      var usedCompatibilityFallback = false;
      if (strategy == UcpBootstrapStrategy.manual) {
        _emitLog('transport_ready', <String, dynamic>{
          'level': 'info',
          'layer': 'ucp',
          'state': DeviceConnectionState.transportReady.name,
          'message': 'Automatic UCP bootstrap disabled by hardware profile',
        }, UcpLogMode.basic);
        _updateState(DeviceConnectionState.transportReady);
        completer.complete();
        return;
      }

      if (strategy == UcpBootstrapStrategy.transportOpenThenRtcSync) {
        _emitLog('transport_open_started', <String, dynamic>{
          'level': 'info',
          'layer': 'ucp',
          'state': 'bootstrapping',
        }, UcpLogMode.basic);
        try {
          await openTransport();
        } on ProtocolException catch (error) {
          if (!_isBootstrapCompatibilityNack(error)) {
            rethrow;
          }
          _emitLog('bootstrap_compatibility_fallback', <String, dynamic>{
            'level': 'info',
            'layer': 'ucp',
            'state': DeviceConnectionState.mtuReady.name,
            'message':
                'bt_transport_open was rejected; retrying with RTC session only',
            'nackMessage': error.message,
          }, UcpLogMode.basic);
          _updateState(DeviceConnectionState.transportReady);
          usedCompatibilityFallback = true;
        }
      }

      _emitLog('session_open_started', <String, dynamic>{
        'level': 'info',
        'layer': 'ucp',
        'state': 'bootstrapping',
      }, UcpLogMode.basic);
      await openRtcSession(includeClientName: !usedCompatibilityFallback);
      completer.complete();
    } catch (error, stackTrace) {
      _emitLog('handshake_failed', <String, dynamic>{
        'level': 'error',
        'layer': 'ucp',
        'state': _state.name,
        'message': '$error',
        if (stackTrace.toString().isNotEmpty)
          'stackTrace': stackTrace.toString(),
      }, UcpLogMode.errorOnly);
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    } finally {
      if (identical(_bootstrapCompleter, completer)) {
        _bootstrapCompleter = null;
        _bootstrapStarted = false;
      }
    }
  }

  void _handleEvent(DeviceEvent event) {
    final frame = event.sourceFrame;
    if (frame == null) {
      return;
    }

    // Reset heartbeat on any incoming frame from device
    _resetHeartbeatTimeout();

    if (frame.commandClass == CommandClasses.measurement &&
        frame.commandId == MeasurementCommandIds.startTest) {
      final decoded = _responseManager.decodeTlvs(frame);
      final status =
          _findInt(decoded, TlvTypes.statusCode) ??
          _findInt(decoded, TlvTypes.statusU8);
      final firmwareState = _findInt(decoded, TlvTypes.fwStateU8);
      final hasError = (status != null && status != 0) || firmwareState == 6;
      final complete = status == 4 || firmwareState == 5;
      if (hasError || complete) {
        markMeasurementActive(false);
      } else {
        markMeasurementActive(true);
      }
    }

    if (frame.commandClass == CommandClasses.moisture &&
        frame.commandId == MoistureCommandIds.moistGetOff) {
      markStreamActive(false);
    }
  }

  int? _findInt(List<DecodedTlv> tlvs, int type) {
    for (final tlv in tlvs) {
      if (tlv.type == type && tlv.value is int) {
        return tlv.value as int;
      }
    }
    return null;
  }

  bool _isBootstrapCompatibilityNack(ProtocolException error) {
    if (error.protocolErrorType != ProtocolErrorType.nackReceived) {
      return false;
    }
    return error.errorCode == UcpStatusCodes.unsupportedVersion;
  }

  List<int> _clientNamePayload({required bool includeClientName}) {
    if (!includeClientName) {
      return const <int>[];
    }
    final clientName = _hardwareProfile.clientName;
    if (clientName == null || clientName.isEmpty) {
      return const <int>[];
    }
    return TlvBuilder().addUtf8(TlvTypes.clientName, clientName).build();
  }

  List<int> _sessionOpenPayload(
    int epochSeconds, {
    required bool includeClientName,
  }) {
    final builder = TlvBuilder().addUint64BE(TlvTypes.epochU64, epochSeconds);
    final clientName = _hardwareProfile.clientName;
    if (includeClientName && clientName != null && clientName.isNotEmpty) {
      builder.addUtf8(TlvTypes.clientName, clientName);
    }
    builder.addUtf8(TlvTypes.appInstanceId, _hardwareProfile.appInstanceId);
    final appUserId = _hardwareProfile.appUserId;
    if (appUserId != null && appUserId.isNotEmpty) {
      builder.addUtf8(TlvTypes.appUserId, appUserId);
    }
    return builder.build();
  }

  int _epochSecondsForRtc(DateTime value) {
    if (!_hardwareProfile.syncRtcAsLocalWallClock) {
      return value.toUtc().millisecondsSinceEpoch ~/ 1000;
    }
    final local = value.toLocal();
    return DateTime.utc(
          local.year,
          local.month,
          local.day,
          local.hour,
          local.minute,
          local.second,
        ).millisecondsSinceEpoch ~/
        1000;
  }

  void _activateSession(DeviceResponse response) {
    if (_currentSession != null) {
      _currentSession!.ucpSessionId = _sessionIdFromResponse(response);
      _currentSession!
        ..sessionActive = true
        ..safeDisconnectPending = false;
    }
    _emitLog('session_active', <String, dynamic>{
      'level': 'info',
      'layer': 'ucp',
      'state': DeviceConnectionState.sessionActive.name,
    }, UcpLogMode.basic);
    _updateState(DeviceConnectionState.sessionActive);
    if (_hardwareProfile.heartbeatEnabled) {
      _startHeartbeat();
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _missedHeartbeats = 0;
    _heartbeatTimer = Timer.periodic(
      ProtocolConstants.heartbeatInterval,
      (_) => _sendHeartbeat(),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimeoutTimer = null;
    _missedHeartbeats = 0;
  }

  void _resetHeartbeatTimeout() {
    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimeoutTimer = null;
    _missedHeartbeats = 0;
  }

  void _sendHeartbeat() {
    if (!isSessionActive || _isDisposed) {
      _stopHeartbeat();
      return;
    }
    unawaited(_sendHeartbeatFrame());
  }

  Future<void> _sendHeartbeatFrame() async {
    try {
      await _responseManager.sendCommand(
        productId: _hardwareProfile.productId,
        profileId: _hardwareProfile.profileId,
        sourceAddress: _hardwareProfile.sourceAddress,
        destinationAddress: _hardwareProfile.destinationAddress,
        op: OperationCodes.heartbeat,
        commandClass: CommandClasses.session,
        commandId: SessionCommandIds.heartbeat,
        payload: _activeSessionIdPayload(),
        options: const CommandOptions(
          waitForAck: true,
          waitForData: false,
          ackTimeout: ProtocolConstants.heartbeatTimeout,
        ),
      );
      _missedHeartbeats = 0;
    } on Object {
      _missedHeartbeats++;
      if (_missedHeartbeats >= _maxMissedHeartbeats) {
        _onHeartbeatMissed();
      }
    }
  }

  int? _sessionIdFromResponse(DeviceResponse response) {
    final frame = response.sourceFrame;
    if (frame == null) {
      return null;
    }
    for (final decoded in _responseManager.decodeTlvs(frame)) {
      if ((decoded.type == TlvTypes.sessionId ||
              decoded.type == TlvTypes.sessionIdU32) &&
          decoded.value is int) {
        return decoded.value as int;
      }
    }
    return null;
  }

  List<int> _activeSessionIdPayload() {
    final sessionId = _currentSession?.ucpSessionId;
    if (sessionId == null) {
      return const <int>[];
    }
    return TlvBuilder().addUint32BE(TlvTypes.sessionId, sessionId).build();
  }

  void _onHeartbeatMissed() {
    _stopHeartbeat();
    _emitLog('error', <String, dynamic>{
      'level': 'error',
      'layer': 'ucp',
      'state': DeviceConnectionState.connectionLost.name,
      'message': 'Heartbeat threshold exceeded',
      'missedHeartbeats': _missedHeartbeats,
    }, UcpLogMode.errorOnly);
    _updateState(DeviceConnectionState.connectionLost);
    unawaited(_transport.disconnect());
  }

  void _refreshOperationalState() {
    final session = _currentSession;
    if (session == null) {
      return;
    }
    if (session.safeDisconnectPending) {
      _updateState(DeviceConnectionState.safeDisconnectPending);
      return;
    }
    if (session.streamActive) {
      _updateState(DeviceConnectionState.streamActive);
      return;
    }
    if (session.measurementActive) {
      _updateState(DeviceConnectionState.measurementActive);
      return;
    }
    if (session.sessionActive) {
      _updateState(DeviceConnectionState.sessionActive);
    }
  }

  void _updateState(DeviceConnectionState state) {
    _state = state;
    if (_currentSession != null) {
      _currentSession!.state = state;
    }
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _transportSubscription?.cancel();
    await _eventSubscription?.cancel();
    await _streamSubscription?.cancel();
    await _stateController.close();
  }

  String _newSessionId() {
    _sessionCounter++;
    return 'session_${DateTime.now().millisecondsSinceEpoch}_$_sessionCounter';
  }

  void _emitStateLog(
    DeviceConnectionState state, {
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) {
    final event = switch (state) {
      DeviceConnectionState.scanning => 'scanning',
      DeviceConnectionState.connecting => 'connecting',
      DeviceConnectionState.connected => 'connected',
      DeviceConnectionState.servicesDiscovered => 'services_discovered',
      DeviceConnectionState.notifySubscribed => 'notify_subscribed',
      DeviceConnectionState.mtuReady => 'mtu_ready',
      DeviceConnectionState.disconnecting => 'disconnecting',
      _ => state.name,
    };
    _emitLog(event, <String, dynamic>{
      'level': 'info',
      'layer': 'ble',
      'state': state.name,
      ...extra,
    }, UcpLogMode.basic);
  }

  void _emitDisconnectionLog(DeviceConnectionState state) {
    _emitLog(
      'disconnected',
      <String, dynamic>{
        'level': state == DeviceConnectionState.connectionLost
            ? 'error'
            : 'info',
        'layer': 'ble',
        'state': state.name,
        'message': state == DeviceConnectionState.connectionLost
            ? 'BLE connection lost unexpectedly'
            : 'BLE connection closed',
      },
      state == DeviceConnectionState.connectionLost
          ? UcpLogMode.errorOnly
          : UcpLogMode.basic,
    );
  }

  void _emitLog(
    String event,
    Map<String, dynamic> param,
    UcpLogMode minimumMode,
  ) {
    final callback = onLogEvent;
    if (callback == null) {
      return;
    }
    final session = _currentSession;
    callback(event, <String, dynamic>{
      'event': event,
      ...param,
      if (session?.sessionId != null || _pendingSessionId != null)
        'sessionId': session?.sessionId ?? _pendingSessionId,
      if (session != null) 'deviceId': session.deviceId,
      if (session?.deviceName != null) 'deviceName': session!.deviceName,
    }, minimumMode);
  }
}
