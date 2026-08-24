import '../models/tlv.dart';

/// TLV types used by Porokh production UCP.
///
/// Some byte values are reused by the older guide in different command
/// contexts. The generic decoder is therefore length-aware for overlapping
/// values such as 0x10 and 0x15.
class TlvTypes {
  TlvTypes._();

  static const int epochU64 = 0x01;
  static const int agentId = 0x02;
  static const int farmerId = 0x03;
  static const int fieldIndex = 0x04;
  static const int fieldTestIndex = 0x05;
  static const int aunkurIdCore = 0x06;
  static const int configKeyId = 0x07;
  static const int configValueType = 0x08;
  static const int configValue = 0x09;
  static const int calibKeyId = 0x0A;
  static const int float32BE = 0x0B;
  static const int sensorAddr = 0x0C;
  static const int dateYmd = 0x0D;
  static const int enable = 0x0E;
  static const int languageU8 = 0x0F;
  static const int clientName = 0x10;
  static const int dumpTimestamp = 0x11;
  static const int debugAdcMode = 0x12;
  static const int lowPowerMode = 0x13;
  static const int rebootReason = 0x14;
  static const int statusCode = 0x15;
  static const int messageText = 0x16;
  static const int sampleSizePercent = 0x17;
  static const int reportIdU32 = 0x18;
  static const int scope = 0x19;
  static const int configCount = 0x1A;
  static const int fwMode = 0x1B;
  static const int rawArgument = 0x1C;
  static const int globalLandLocation = 0x1D;
  static const int aez = 0x1E;
  static const int soilCategory = 0x1F;

  static const int sessionId = 0x30;
  static const int appInstanceId = 0x31;
  static const int appUserId = 0x32;
  static const int connectionState = 0x33;
  static const int sessionEventId = 0x34;
  static const int linkType = 0x35;
  static const int handshakeStatus = 0x36;
  static const int disconnectReason = 0x37;
  static const int heartbeatIntervalMs = 0x38;
  static const int lastRxSeq = 0x39;
  static const int uptimeMs = 0x3A;
  static const int disconnectDelayMs = 0x3B;
  static const int lastCmdClass = 0x3C;
  static const int lastCmdId = 0x3D;
  static const int safeDisconnectAllowed = 0x3E;
  static const int eventRecordId = 0x3F;
  static const int unexpectedDisconnectCount = 0x40;
  static const int startDateYmd = 0x41;
  static const int endDateYmd = 0x42;
  static const int fileType = 0x43;
  static const int fileName = 0x44;
  static const int fileId = 0x45;
  static const int lineStart = 0x46;
  static const int lineCount = 0x47;
  static const int byteOffset = 0x48;
  static const int byteCount = 0x49;
  static const int totalLines = 0x4A;
  static const int totalBytes = 0x4B;
  static const int chunkIndex = 0x4C;
  static const int chunkCount = 0x4D;
  static const int lineRecord = 0x4E;
  static const int lineNo = 0x4F;
  static const int lineText = 0x50;
  static const int fileData = 0x51;
  static const int hasMore = 0x52;
  static const int eofReached = 0x53;
  static const int recordCount = 0x54;
  static const int checksum16 = 0x55;
  static const int readToken = 0x56;

  // Older guide/runtime aliases retained for existing parsers and apps.
  static const int sessionIdU32 = agentId;
  static const int statusU8 = farmerId;
  static const int textUtf8 = fieldIndex;
  static const int reasonU8 = fieldTestIndex;
  static const int permitU8 = aunkurIdCore;
  static const int fontIdU8 = configKeyId;
  static const int cdnModeU8 = configValueType;
  static const int moistRawU16 = calibKeyId;
  static const int moistPercentX100U16 = float32BE;
  static const int deviceName = enable;
  static const int fwVersion = languageU8;
  static const int uptimeU32 = clientName;
  static const int counterU32 = dumpTimestamp;
  static const int eventIdU8 = debugAdcMode;
  static const int disconnectClassU8 = lowPowerMode;
  static const int connectionIdU32 = rebootReason;
  static const int sessionStateU8 = statusCode;
  static const int diagnosticText = messageText;
  static const int errorCodeU16 = 0x20;
  static const int cdnName = linkType;
  static const int resultNX100 = unexpectedDisconnectCount;
  static const int resultPX100 = startDateYmd;
  static const int resultKX100 = endDateYmd;
  static const int resultMoistX100 = fileType;
  static const int resultPhX100 = fileName;
  static const int resultEcX100 = fileId;
  static const int fwLevelU8 = hasMore;
  static const int fwStageU8 = eofReached;
  static const int fwStateU8 = recordCount;
  static const int date = checksum16;
  static const int time = readToken;
  static const int aunkurId = 0x57;
  static const int hwVersion = 0x58;
  static const int totalTestsU32 = 0x59;
  static const int sdStorage = 0x5A;
  static const int batteryCurrentX100 = 0x5B;
  static const int batteryVoltageX100 = 0x5C;
  static const int batterySocU8 = 0x5D;
  static const int testRemainingU16 = 0x5E;
  static const int batteryTemperatureX10 = 0x5F;
  static const int ambientTemperatureX10 = 0x60;
  static const int ambientHumidityX10 = 0x61;
  static const int errorMsg = 0x62;
  static const int deviceIndex = 0x63;
  static const int reportTestNoU32 = 0x64;
  static const int resultTempX100 = 0x65;
  static const int reportError = 0x66;

  static const int sensorTypeU8 = sensorAddr;
  static const int calData = float32BE;
  static const int configKeyU16 = configKeyId;
  static const int exportFormat = fileType;
  static const int fileSizeU32 = totalBytes;
  static const int fileOffsetU32 = byteOffset;
  static const int transferIdU32 = fileId;

  static const int btTransportClientName = clientName;
  static const int fieldId = fieldIndex;
  static const int testId = fieldTestIndex;

  static String nameOf(int type) =>
      _names[type] ??
      '0x${type.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  static Object decodeValue(Tlv tlv) {
    if (tlv.type == epochU64) {
      return _readUint64(tlv);
    }
    if (tlv.type == statusCode) {
      return tlv.value.length >= 2 ? _readUint16(tlv) : _readUint8(tlv);
    }
    if (tlv.type == clientName) {
      return tlv.value.length == 4 ? _readUint32(tlv) : tlv.asUtf8String();
    }
    if (_u32Types.contains(tlv.type) && tlv.value.length >= 4) {
      return _readUint32(tlv);
    }
    if (_u16Types.contains(tlv.type) && tlv.value.length >= 2) {
      return _readUint16(tlv);
    }
    if (_u8Types.contains(tlv.type) && tlv.value.length == 1) {
      return _readUint8(tlv);
    }
    if (_scaledX100Types.contains(tlv.type)) {
      return _readUint16(tlv) / 100.0;
    }
    if (_scaledX10Types.contains(tlv.type)) {
      return _readUint16(tlv) / 10.0;
    }
    if (_textTypes.contains(tlv.type)) {
      return tlv.asUtf8String();
    }
    return tlv.value;
  }

  static const Set<int> _u32Types = {
    sessionId,
    reportIdU32,
    uptimeMs,
    totalLines,
    totalBytes,
    chunkIndex,
    chunkCount,
    byteOffset,
    byteCount,
    fileId,
    globalLandLocation,
    aez,
    soilCategory,
    totalTestsU32,
    reportTestNoU32,
  };

  static const Set<int> _u16Types = {
    errorCodeU16,
    moistRawU16,
    moistPercentX100U16,
    configCount,
    heartbeatIntervalMs,
    lastRxSeq,
    disconnectDelayMs,
    eventRecordId,
    unexpectedDisconnectCount,
    recordCount,
    checksum16,
    testRemainingU16,
  };

  static const Set<int> _u8Types = {
    statusU8,
    reasonU8,
    permitU8,
    fontIdU8,
    cdnModeU8,
    calibKeyId,
    sensorAddr,
    enable,
    languageU8,
    debugAdcMode,
    lowPowerMode,
    rebootReason,
    sampleSizePercent,
    fwMode,
    connectionState,
    sessionEventId,
    linkType,
    handshakeStatus,
    disconnectReason,
    lastCmdClass,
    lastCmdId,
    safeDisconnectAllowed,
    fileType,
    hasMore,
    eofReached,
    fwStateU8,
    batterySocU8,
    deviceIndex,
  };

  static const Set<int> _scaledX100Types = {
    resultNX100,
    resultPX100,
    resultKX100,
    resultMoistX100,
    resultPhX100,
    resultEcX100,
    batteryCurrentX100,
    batteryVoltageX100,
    resultTempX100,
  };

  static const Set<int> _scaledX10Types = {
    batteryTemperatureX10,
    ambientTemperatureX10,
    ambientHumidityX10,
  };

  static const Set<int> _textTypes = {
    textUtf8,
    messageText,
    agentId,
    farmerId,
    fieldTestIndex,
    aunkurIdCore,
    rawArgument,
    appInstanceId,
    appUserId,
    fileName,
    lineText,
    readToken,
    fwVersion,
    date,
    aunkurId,
    hwVersion,
    sdStorage,
    errorMsg,
    reportError,
    cdnName,
  };

  static const Map<int, String> _names = {
    epochU64: 'epoch_u64',
    agentId: 'agent_id',
    farmerId: 'farmer_id',
    fieldIndex: 'field_index',
    fieldTestIndex: 'field_test_index',
    aunkurIdCore: 'aunkur_id',
    configKeyId: 'config_key_id',
    configValueType: 'config_value_type',
    configValue: 'config_value',
    calibKeyId: 'calib_key_id',
    float32BE: 'float32_be',
    sensorAddr: 'sensor_addr',
    dateYmd: 'date_ymd',
    enable: 'enable',
    languageU8: 'language',
    clientName: 'client_name',
    dumpTimestamp: 'dump_timestamp',
    debugAdcMode: 'debug_adc_mode',
    lowPowerMode: 'low_power_mode',
    rebootReason: 'reboot_reason',
    statusCode: 'status_code',
    messageText: 'message_text',
    sampleSizePercent: 'sample_size_percent',
    reportIdU32: 'report_id',
    sessionId: 'session_id',
    appInstanceId: 'app_instance_id',
    appUserId: 'app_user_id',
    connectionState: 'connection_state',
    sessionEventId: 'session_event_id',
    linkType: 'link_type',
    handshakeStatus: 'handshake_status',
    disconnectReason: 'disconnect_reason',
    heartbeatIntervalMs: 'heartbeat_interval_ms',
    lastRxSeq: 'last_rx_seq',
    uptimeMs: 'uptime_ms',
    disconnectDelayMs: 'disconnect_delay_ms',
    safeDisconnectAllowed: 'safe_disconnect_allowed',
    fileName: 'file_name',
    fileData: 'file_data',
    hasMore: 'has_more',
    eofReached: 'eof_reached',
    recordCount: 'record_count',
    aunkurId: 'guide_aunkur_id',
    hwVersion: 'hw_version',
    totalTestsU32: 'total_tests_u32',
    sdStorage: 'sd_storage',
    batteryVoltageX100: 'battery_voltage_x100',
    batterySocU8: 'battery_soc_u8',
  };

  static int _readUint8(Tlv tlv) => tlv.value.isEmpty ? 0 : tlv.value.first;

  static int _readUint16(Tlv tlv) {
    if (tlv.value.length < 2) {
      return 0;
    }
    return (tlv.value[0] << 8) | tlv.value[1];
  }

  static int _readUint32(Tlv tlv) {
    if (tlv.value.length < 4) {
      return 0;
    }
    return (tlv.value[0] << 24) |
        (tlv.value[1] << 16) |
        (tlv.value[2] << 8) |
        tlv.value[3];
  }

  static int _readUint64(Tlv tlv) {
    if (tlv.value.length < 8) {
      return 0;
    }
    return (tlv.value[0] << 56) |
        (tlv.value[1] << 48) |
        (tlv.value[2] << 40) |
        (tlv.value[3] << 32) |
        (tlv.value[4] << 24) |
        (tlv.value[5] << 16) |
        (tlv.value[6] << 8) |
        tlv.value[7];
  }
}
