import 'dart:async';

import '../errors/crc_exception.dart';
import '../errors/frame_exception.dart';
import '../errors/protocol_exception.dart';
import '../errors/timeout_exception.dart' as sdk_errors;
import '../errors/transport_exception.dart';
import '../frame/device_frame.dart';
import '../frame/frame_buffer.dart';
import '../frame/frame_builder.dart';
import '../frame/frame_parser.dart';
import '../transport/connection_state.dart';
import '../transport/device_transport.dart';
import '../../logging/ucp_log_mode.dart';
import '../../protocol/commands/command_options.dart';
import '../../protocol/constants/command_classes.dart';
import '../../protocol/constants/operation_codes.dart';
import '../../protocol/constants/profile_ids.dart';
import '../../protocol/constants/ucp_addresses.dart';
import '../../protocol/models/decoded_tlv.dart';
import '../../protocol/models/ucp_packet_trace.dart';
import '../../protocol/parsers/common_response_parser.dart';
import '../../protocol/parsers/nack_parser.dart';
import 'device_event.dart';
import 'device_response.dart';
import 'pending_request.dart';
import 'sequence_generator.dart';

/// Manages request/response correlation for official UCP traffic.
class UcpResponseManager {
  final DeviceTransport _transport;
  final FrameBuilder _frameBuilder;
  final FrameBuffer _frameBuffer;
  final FrameParser _frameParser;
  final SequenceGenerator _sequenceGenerator;
  final int _protocolVersion;
  final CommonResponseParser _responseParser;
  final NackParser _nackParser;

  final Map<_PendingRequestKey, PendingRequest> _pendingRequests =
      <_PendingRequestKey, PendingRequest>{};
  final StreamController<DeviceEvent> _eventController =
      StreamController<DeviceEvent>.broadcast();
  final StreamController<DeviceFrame> _frameController =
      StreamController<DeviceFrame>.broadcast();
  final StreamController<DeviceResponse> _dataController =
      StreamController<DeviceResponse>.broadcast();
  final StreamController<DeviceFrame> _streamController =
      StreamController<DeviceFrame>.broadcast();
  final StreamController<UcpPacketTrace> _traceController =
      StreamController<UcpPacketTrace>.broadcast();

  StreamSubscription<List<int>>? _incomingSubscription;
  StreamSubscription<DeviceConnectionState>? _connectionSubscription;
  bool _isDisposed = false;
  void Function(String event, Map<String, dynamic> param, UcpLogMode mode)?
  onLogEvent;

  /// Default timeout for command operations.
  final Duration defaultTimeout;

  UcpResponseManager({
    required DeviceTransport transport,
    this.defaultTimeout = const Duration(seconds: 5),
    FrameBuilder? frameBuilder,
    FrameBuffer? frameBuffer,
    FrameParser? frameParser,
    SequenceGenerator? sequenceGenerator,
    int protocolVersion = 1,
    CommonResponseParser responseParser = const CommonResponseParser(),
    this.onLogEvent,
  }) : _transport = transport,
       _frameBuilder = frameBuilder ?? FrameBuilder(),
       _frameBuffer = frameBuffer ?? FrameBuffer(),
       _frameParser = frameParser ?? FrameParser(),
       _sequenceGenerator = sequenceGenerator ?? SequenceGenerator(),
       _protocolVersion = protocolVersion,
       _responseParser = responseParser,
       _nackParser = NackParser(responseParser: responseParser) {
    _frameBuffer.onFrameError = _handleFrameBufferError;
    _bindTransport();
  }

  /// Stream of generic EVENT frames.
  Stream<DeviceEvent> get events => _eventController.stream;

  /// Stream of parsed inbound frames.
  Stream<DeviceFrame> get frames => _frameController.stream;

  /// Stream of DATA frames, including unmatched unsolicited DATA packets.
  Stream<DeviceResponse> get dataResponses => _dataController.stream;

  /// Stream of STREAM frames.
  Stream<DeviceFrame> get streamFrames => _streamController.stream;

  /// Timestamped packet trace stream for diagnostics.
  Stream<UcpPacketTrace> get packetTraces => _traceController.stream;

  /// The number of currently pending requests.
  int get pendingCount => _pendingRequests.length;

  List<DecodedTlv> decodeTlvs(DeviceFrame frame) {
    return _responseParser.decodeFrame(frame);
  }

  void _bindTransport() {
    _incomingSubscription = _transport.incomingBytes.listen(
      processIncomingBytes,
    );

    _connectionSubscription = _transport.connectionState.listen((state) {
      if (state == DeviceConnectionState.disconnected ||
          state == DeviceConnectionState.connectionLost) {
        failAllPendingOnDisconnect(state);
        _frameBuffer.clear();
      }
    });
  }

  /// Sends a command frame and tracks its expected response lifecycle.
  Future<DeviceResponse> sendCommand({
    required int commandId,
    int productId = 0,
    int profileId = ProfileIds.defaultProfile,
    int sourceAddress = UcpAddresses.defaultSource,
    int address = UcpAddresses.defaultDestination,
    int? destinationAddress,
    int op = OperationCodes.req,
    int commandClass = CommandClasses.system,
    int version = -1,
    List<int> payload = const [],
    int flags = 0,
    Duration? timeout,
    CommandOptions? options,
  }) async {
    _throwIfDisposed();

    final sequence = _sequenceGenerator.next();
    final effectiveOptions = _resolveOptions(
      timeout: timeout,
      options: options,
    );
    final resolvedDestination = destinationAddress ?? address;
    final pending = PendingRequest(
      sequence: sequence,
      productId: productId,
      profileId: profileId,
      sourceAddress: sourceAddress,
      destinationAddress: resolvedDestination,
      commandId: commandId,
      op: op,
      commandClass: commandClass,
      flags: flags,
      payload: payload,
      options: effectiveOptions,
    );
    final key = _PendingRequestKey(
      sequence: sequence,
      commandClass: commandClass,
      commandId: commandId,
    );
    _pendingRequests[key] = pending;

    final frameBytes = _frameBuilder.build(
      version: version == -1 ? _protocolVersion : version,
      productId: productId,
      profileId: profileId,
      sourceAddress: sourceAddress,
      destinationAddress: resolvedDestination,
      op: op,
      commandClass: commandClass,
      commandId: commandId,
      sequence: sequence,
      flags: flags,
      payload: payload,
    );

    try {
      await _transport.write(frameBytes);
      _emitTrace(UcpPacketDirection.tx, frameBytes);
    } on Object {
      _pendingRequests.remove(key);
      rethrow;
    }

    if (!effectiveOptions.waitForAck &&
        !effectiveOptions.waitForData &&
        !effectiveOptions.completeOnEvent) {
      _pendingRequests.remove(key);
      final response = DeviceResponse.success(
        sequence: sequence,
        productId: productId,
        profileId: profileId,
        sourceAddress: sourceAddress,
        destinationAddress: resolvedDestination,
        commandId: commandId,
        op: op,
        commandClass: commandClass,
        flags: flags,
        payload: payload,
      );
      pending.complete(response);
      return response;
    }

    if (effectiveOptions.waitForAck) {
      pending.startAckTimeout(_onAckTimeout);
    } else if (effectiveOptions.waitForData) {
      pending.startDataTimeout(_onDataTimeout);
    }

    return pending.future;
  }

  /// Sends a prebuilt frame through the transport without request tracking.
  Future<void> sendFrame(DeviceFrame frame) async {
    _throwIfDisposed();
    final bytes = _frameBuilder.buildFromFrame(frame);
    await _transport.write(bytes);
    _emitTrace(UcpPacketDirection.tx, bytes, frame: frame);
  }

  CommandOptions _resolveOptions({Duration? timeout, CommandOptions? options}) {
    if (options != null) {
      if (timeout == null) {
        return options;
      }
      return options.copyWith(ackTimeout: timeout, dataTimeout: timeout);
    }

    final effectiveTimeout = timeout ?? defaultTimeout;
    return CommandOptions(
      ackTimeout: effectiveTimeout,
      dataTimeout: effectiveTimeout,
      waitForAck: true,
      waitForData: false,
    );
  }

  /// Converts incoming raw bytes into frames and processes them.
  void processIncomingBytes(List<int> bytes) {
    _throwIfDisposed();
    final frames = _frameBuffer.addBytes(bytes);
    for (final frame in frames) {
      processFrame(frame);
    }
  }

  /// Processes a parsed frame.
  void processFrame(DeviceFrame frame) {
    _throwIfDisposed();
    if (!_frameController.isClosed) {
      _frameController.add(frame);
    }
    _emitTrace(
      UcpPacketDirection.rx,
      _frameBuilder.buildFromFrame(frame),
      frame: frame,
    );

    if (frame.isEvent) {
      final event = DeviceEvent.fromFrame(
        frame,
        inferEventCodeFromPayload: true,
      );
      _emitEvent(event);
      _emitFrameKindLog(
        event: 'event_received',
        frame: frame,
        minimumMode: UcpLogMode.verbose,
        extra: <String, dynamic>{'eventCode': event.eventCode},
      );
      final pending = _pendingRequests[_keyForFrame(frame)];
      if (pending != null && pending.options.completeOnEvent) {
        _pendingRequests.remove(_keyForFrame(frame));
        pending.complete(DeviceResponse.fromFrame(frame));
      }
      return;
    }

    if (frame.isStream) {
      if (!_streamController.isClosed) {
        _streamController.add(frame);
      }
      _emitFrameKindLog(
        event: 'stream_received',
        frame: frame,
        minimumMode: UcpLogMode.verbose,
      );
      return;
    }

    final response = DeviceResponse.fromFrame(
      frame,
      errorMessage: frame.isNack ? 'Device returned NACK' : null,
    );

    if (frame.isData && !_dataController.isClosed) {
      _dataController.add(response);
    }

    final pending = _pendingRequests[_keyForFrame(frame)];
    if (pending == null) {
      return;
    }

    if (frame.isAck) {
      _emitFrameKindLog(
        event: 'ack_received',
        frame: frame,
        minimumMode: UcpLogMode.verbose,
      );
      _handleAck(_keyForFrame(frame), pending, response);
      return;
    }

    if (frame.isNack) {
      _handleNack(_keyForFrame(frame), pending, response);
      return;
    }

    if (frame.isData) {
      _emitFrameKindLog(
        event: 'data_received',
        frame: frame,
        minimumMode: UcpLogMode.verbose,
      );
      _handleData(_keyForFrame(frame), pending, response);
    }
  }

  void _handleAck(
    _PendingRequestKey key,
    PendingRequest pending,
    DeviceResponse response,
  ) {
    pending.markAckReceived(response);

    if (!pending.options.waitForData) {
      _pendingRequests.remove(key);
      pending.complete(response);
      return;
    }

    pending.startDataTimeout(_onDataTimeout);
  }

  void _handleNack(
    _PendingRequestKey key,
    PendingRequest pending,
    DeviceResponse response,
  ) {
    _pendingRequests.remove(key);
    final details = _nackParser.parseDetails(response);
    _emitLog('nack_received', <String, dynamic>{
      ..._frameSummary(
        response.sourceFrame,
        includeBytesHex: true,
        includeTlvs: true,
      ),
      'level': 'error',
      'layer': 'ucp',
      'status': details.status,
      'errorCode': details.errorCode,
      'message':
          details.text ?? response.errorMessage ?? 'Device returned NACK',
    }, UcpLogMode.errorOnly);
    pending.completeError(
      ProtocolException(
        details.text ?? response.errorMessage ?? 'Device returned NACK',
        errorCode: details.errorCode ?? response.flags,
        protocolErrorType: ProtocolErrorType.nackReceived,
      ),
    );
  }

  void _handleData(
    _PendingRequestKey key,
    PendingRequest pending,
    DeviceResponse response,
  ) {
    if (pending.options.waitForAck && !pending.ackReceived) {
      return;
    }

    if (!pending.options.waitForData) {
      return;
    }

    _pendingRequests.remove(key);
    pending.complete(response);
  }

  void _emitEvent(DeviceEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  void _emitTrace(
    UcpPacketDirection direction,
    List<int> bytes, {
    DeviceFrame? frame,
  }) {
    if (_traceController.isClosed) {
      return;
    }

    final resolvedFrame = frame ?? _tryParseFrame(bytes);
    final decodedTlvs = resolvedFrame == null
        ? const <DecodedTlv>[]
        : decodeTlvs(resolvedFrame);
    _traceController.add(
      UcpPacketTrace(
        direction: direction,
        bytes: bytes,
        frame: resolvedFrame,
        decodedTlvs: decodedTlvs,
      ),
    );
    _emitLog(
      direction == UcpPacketDirection.tx ? 'packet_tx' : 'packet_rx',
      <String, dynamic>{
        'level': 'debug',
        'layer': 'ucp',
        'direction': direction.name,
        ..._frameSummary(
          resolvedFrame,
          fallbackBytes: bytes,
          includeBytesHex: true,
          includeTlvs: true,
          decodedTlvs: decodedTlvs,
        ),
      },
      UcpLogMode.verbose,
    );
  }

  void _handleFrameBufferError(List<int> bytes, Object error) {
    final isCrcError = error is CrcException;
    _emitLog(isCrcError ? 'crc_failed' : 'frame_parse_failed', <
      String,
      dynamic
    >{
      'level': 'error',
      'layer': 'ucp',
      'direction': 'rx',
      'message': '$error',
      'bytesHex': _bytesToHex(bytes),
      if (error is FrameException) 'frameErrorType': error.frameErrorType.name,
      if (error is CrcException) 'crcExpected': _hex16(error.expectedCrc),
      if (error is CrcException) 'crcActual': _hex16(error.actualCrc),
    }, UcpLogMode.errorOnly);
  }

  DeviceFrame? _tryParseFrame(List<int> bytes) {
    try {
      return _frameParser.parse(bytes);
    } on Object {
      return null;
    }
  }

  _PendingRequestKey _keyForFrame(DeviceFrame frame) {
    return _PendingRequestKey(
      sequence: frame.sequence,
      commandClass: frame.commandClass,
      commandId: frame.commandId,
    );
  }

  /// Fails a pending request by sequence number.
  void cancelRequest(int sequenceNumber) {
    MapEntry<_PendingRequestKey, PendingRequest>? matchedEntry;
    for (final entry in _pendingRequests.entries) {
      if (entry.value.sequence == sequenceNumber) {
        matchedEntry = entry;
        break;
      }
    }
    if (matchedEntry == null) {
      return;
    }
    _pendingRequests.remove(matchedEntry.key);
    matchedEntry.value.completeError(
      sdk_errors.TimeoutException(
        'Request cancelled',
        timeoutDuration: Duration.zero,
        operation: 'Request $sequenceNumber',
      ),
    );
  }

  /// Fails all pending requests with a cancellation timeout exception.
  void cancelAll() {
    final requests = Map<_PendingRequestKey, PendingRequest>.from(
      _pendingRequests,
    );
    _pendingRequests.clear();
    for (final pending in requests.values) {
      pending.completeError(
        sdk_errors.TimeoutException(
          'All requests cancelled',
          timeoutDuration: Duration.zero,
          operation: 'Request ${pending.sequence}',
        ),
      );
    }
  }

  /// Fails all pending requests because the transport disconnected.
  void failAllPendingOnDisconnect(DeviceConnectionState state) {
    final requests = Map<_PendingRequestKey, PendingRequest>.from(
      _pendingRequests,
    );
    _pendingRequests.clear();
    for (final pending in requests.values) {
      pending.completeError(
        TransportException(
          state == DeviceConnectionState.connectionLost
              ? 'Connection lost while waiting for response'
              : 'Disconnected while waiting for response',
          errorType: state == DeviceConnectionState.connectionLost
              ? TransportErrorType.connectionLost
              : TransportErrorType.connectionFailed,
        ),
      );
    }
  }

  void _onAckTimeout(PendingRequest request) {
    final key = _keyForPending(request);
    _pendingRequests.remove(key);
    _emitTimeoutLog(request, stage: 'ack');
    request.completeError(
      sdk_errors.TimeoutException(
        'Request ${request.sequence} timed out waiting for ACK',
        timeoutDuration: request.options.ackTimeout,
        operation: 'Request ${request.sequence} ACK',
      ),
    );
  }

  void _onDataTimeout(PendingRequest request) {
    final key = _keyForPending(request);
    _pendingRequests.remove(key);
    _emitTimeoutLog(request, stage: 'data');
    request.completeError(
      sdk_errors.TimeoutException(
        'Request ${request.sequence} timed out waiting for DATA',
        timeoutDuration: request.options.dataTimeout,
        operation: 'Request ${request.sequence} DATA',
      ),
    );
  }

  _PendingRequestKey _keyForPending(PendingRequest request) {
    return _PendingRequestKey(
      sequence: request.sequence,
      commandClass: request.commandClass,
      commandId: request.commandId,
    );
  }

  void _emitTimeoutLog(PendingRequest request, {required String stage}) {
    _emitLog('request_timeout', <String, dynamic>{
      'level': 'error',
      'layer': 'ucp',
      'stage': stage,
      'message':
          'Request ${request.sequence} timed out waiting for ${stage.toUpperCase()}',
      'seq': request.sequence,
      'op': request.op,
      'opName': _opName(request.op),
      'classId': request.commandClass,
      'className': _className(request.commandClass),
      'cmdId': request.commandId,
      'cmdName': _commandName(request.commandClass, request.commandId),
      'src': request.sourceAddress,
      'dst': request.destinationAddress,
      'payloadLength': request.payload.length,
      'timeoutMs':
          (stage == 'ack'
                  ? request.options.ackTimeout
                  : request.options.dataTimeout)
              .inMilliseconds,
    }, UcpLogMode.errorOnly);
  }

  void _emitFrameKindLog({
    required String event,
    required DeviceFrame frame,
    required UcpLogMode minimumMode,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) {
    _emitLog(event, <String, dynamic>{
      'level': event == 'nack_received' ? 'error' : 'debug',
      'layer': 'ucp',
      'direction': 'rx',
      ..._frameSummary(frame, includeBytesHex: true, includeTlvs: true),
      ...extra,
    }, minimumMode);
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
    callback(event, <String, dynamic>{'event': event, ...param}, minimumMode);
  }

  Map<String, dynamic> _frameSummary(
    DeviceFrame? frame, {
    List<int>? fallbackBytes,
    bool includeBytesHex = false,
    bool includeTlvs = false,
    List<DecodedTlv>? decodedTlvs,
  }) {
    if (frame == null) {
      return <String, dynamic>{
        'bytesLength': fallbackBytes?.length ?? 0,
        if (includeBytesHex && fallbackBytes != null)
          'bytesHex': _bytesToHex(fallbackBytes),
      };
    }

    final resolvedTlvs = decodedTlvs ?? decodeTlvs(frame);
    return <String, dynamic>{
      'op': frame.op,
      'opName': _opName(frame.op),
      'classId': frame.commandClass,
      'className': _className(frame.commandClass),
      'cmdId': frame.commandId,
      'cmdName': _commandName(frame.commandClass, frame.commandId),
      'seq': frame.sequence,
      'src': frame.sourceAddress,
      'dst': frame.destinationAddress,
      'flags': frame.flags,
      'payloadLength': frame.payloadLength,
      'crc': _hex16(frame.crc),
      'tlvCount': resolvedTlvs.length,
      if (includeBytesHex)
        'bytesHex': _bytesToHex(
          fallbackBytes ?? _frameBuilder.buildFromFrame(frame),
        ),
      if (includeTlvs) 'tlvs': _serializeTlvs(resolvedTlvs),
    };
  }

  List<Map<String, dynamic>> _serializeTlvs(List<DecodedTlv> tlvs) {
    return tlvs
        .map(
          (tlv) => <String, dynamic>{
            'type': tlv.type,
            'typeHex':
                '0x${tlv.type.toRadixString(16).toUpperCase().padLeft(2, '0')}',
            'typeName': tlv.typeName,
            'length': tlv.length,
            'value': _jsonSafeValue(tlv.value),
          },
        )
        .toList(growable: false);
  }

  Object? _jsonSafeValue(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is List<int>) {
      return _bytesToHex(value);
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
      if (commandId == 0x01) {
        return 'rtc_sync';
      }
    }
    if (commandClass == CommandClasses.deviceInfo) {
      if (commandId == 0x01) {
        return 'get_device_info';
      }
      if (commandId == 0x02) {
        return 'set_client_name';
      }
    }
    if (commandClass == CommandClasses.session) {
      if (commandId == 0x01) {
        return 'open_rtc_sync';
      }
      if (commandId == 0x02) {
        return 'status_get';
      }
      if (commandId == 0x03) {
        return 'event';
      }
      if (commandId == 0x04) {
        return 'safe_disconnect_request';
      }
      if (commandId == 0x05) {
        return 'safe_disconnect_commit';
      }
      if (commandId == 0x06) {
        return 'heartbeat';
      }
    }
    if (commandClass == CommandClasses.measurement) {
      if (commandId == 0x01) {
        return 'start_soil_test';
      }
      if (commandId == 0x02) {
        return 'stop_soil_test';
      }
      if (commandId == 0x03) {
        return 'start_moisture_test';
      }
      if (commandId == 0x04) {
        return 'stop_moisture_test';
      }
      if (commandId == 0x05) {
        return 'get_last_report';
      }
    }
    if (commandClass == CommandClasses.configuration) {
      if (commandId == 0x01) {
        return 'get_all_config';
      }
      if (commandId == 0x03) {
        return 'set_config_value';
      }
      if (commandId == 0x05) {
        return 'set_manual_test_permission';
      }
      if (commandId == 0x07) {
        return 'set_ui_language';
      }
      if (commandId == 0x08) {
        return 'get_config_value';
      }
    }
    if (commandClass == CommandClasses.calibration) {
      if (commandId == 0x01) {
        return 'set_calibration_value';
      }
      if (commandId == 0x02) {
        return 'get_calibration_value';
      }
      if (commandId == 0x03) {
        return 'get_all_calibration_values';
      }
    }
    if (commandClass == CommandClasses.dataLog) {
      if (commandId == 0x07) {
        return 'read_file_chunk';
      }
      if (commandId == 0x09) {
        return 'cancel_file_read';
      }
    }
    return '0x${commandId.toRadixString(16).toUpperCase().padLeft(2, '0')}';
  }

  String _bytesToHex(List<int> bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).toUpperCase().padLeft(2, '0'))
        .join(' ');
  }

  String _hex16(int value) {
    return value.toRadixString(16).toUpperCase().padLeft(4, '0');
  }

  /// Disposes the manager and cancels all pending requests.
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;

    cancelAll();
    _incomingSubscription?.cancel();
    _connectionSubscription?.cancel();
    _eventController.close();
    _frameController.close();
    _dataController.close();
    _streamController.close();
    _traceController.close();
  }

  void _throwIfDisposed() {
    if (_isDisposed) {
      throw StateError('UcpResponseManager has been disposed');
    }
  }
}

/// Backward-compatible alias class.
class ResponseManager extends UcpResponseManager {
  ResponseManager({
    required super.transport,
    super.defaultTimeout,
    super.frameBuilder,
    super.frameBuffer,
    super.frameParser,
    super.sequenceGenerator,
    super.protocolVersion,
    super.responseParser,
  });
}

class _PendingRequestKey {
  final int sequence;
  final int commandClass;
  final int commandId;

  const _PendingRequestKey({
    required this.sequence,
    required this.commandClass,
    required this.commandId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PendingRequestKey &&
          runtimeType == other.runtimeType &&
          sequence == other.sequence &&
          commandClass == other.commandClass &&
          commandId == other.commandId;

  @override
  int get hashCode => Object.hash(sequence, commandClass, commandId);
}
