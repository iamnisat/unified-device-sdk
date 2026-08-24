import '../../core/frame/device_frame.dart';
import '../../core/response/device_response.dart';
import '../models/battery_info.dart';
import '../constants/tlv_types.dart';
import '../models/decoded_tlv.dart';
import '../models/device_info.dart';
import '../models/device_status.dart';
import '../models/firmware_info.dart';
import '../models/protocol_version.dart';
import '../models/tlv.dart';
import '../models/ucp_device_info.dart';
import '../models/ucp_last_report.dart';
import '../models/ucp_moisture_sample.dart';
import '../models/ucp_nack_details.dart';
import '../models/ucp_time_snapshot.dart';
import 'tlv_parser.dart';
import '../../core/bytes/byte_reader.dart';
import '../../core/errors/protocol_exception.dart';

/// TLV-driven parser for official UCP responses.
class CommonResponseParser {
  final TlvParser tlvParser;

  const CommonResponseParser({this.tlvParser = const TlvParser()});

  List<Tlv> parseTlvs(List<int> payload) => tlvParser.parseAll(payload);

  List<DecodedTlv> decodePayload(List<int> payload) {
    return decodeTlvs(parseTlvs(payload));
  }

  List<DecodedTlv> decodeTlvs(List<Tlv> tlvs) {
    return List<DecodedTlv>.unmodifiable(tlvs.map(DecodedTlv.fromTlv));
  }

  List<DecodedTlv> decodeFrame(DeviceFrame frame) => decodeTlvs(frame.tlvs);

  UcpNackDetails parseNack(DeviceResponse response) {
    final decoded = _decodedFromResponse(response, fallbackToRaw: true);
    final lookup = _index(decoded);
    return UcpNackDetails(
      status:
          _intValue(lookup[TlvTypes.statusCode]) ??
          _intValue(lookup[TlvTypes.statusU8]),
      errorCode:
          _intValue(lookup[TlvTypes.errorCodeU16]) ??
          _intValue(lookup[TlvTypes.statusCode]) ??
          (response.payload.isNotEmpty
              ? response.payload.first
              : response.flags),
      text:
          _stringValue(lookup[TlvTypes.messageText]) ??
          _stringValue(lookup[TlvTypes.textUtf8]),
      tlvs: decoded,
    );
  }

  UcpDeviceInfo parseUcpDeviceInfo(DeviceResponse response) {
    final decoded = _decodedFromResponse(response);
    final lookup = _index(decoded);
    return UcpDeviceInfo(
      deviceName: _stringValue(lookup[TlvTypes.deviceName]),
      firmwareVersion: _stringValue(lookup[TlvTypes.fwVersion]),
      uptimeSeconds: _intValue(lookup[TlvTypes.uptimeU32]),
      counter: _intValue(lookup[TlvTypes.counterU32]),
      firmwareLevel: _intValue(lookup[TlvTypes.fwLevelU8]),
      firmwareStage: _intValue(lookup[TlvTypes.fwStageU8]),
      firmwareState: _intValue(lookup[TlvTypes.fwStateU8]),
      date: _stringValue(lookup[TlvTypes.date]),
      time: _stringValue(lookup[TlvTypes.time]),
      aunkurId: _stringValue(lookup[TlvTypes.aunkurId]),
      hardwareVersion: _stringValue(lookup[TlvTypes.hwVersion]),
      totalTests: _intValue(lookup[TlvTypes.totalTestsU32]),
      sdStorage: _stringValue(lookup[TlvTypes.sdStorage]),
      batteryCurrent: _doubleValue(lookup[TlvTypes.batteryCurrentX100]),
      batteryVoltage: _doubleValue(lookup[TlvTypes.batteryVoltageX100]),
      batterySoc: _intValue(lookup[TlvTypes.batterySocU8]),
      testRemaining: _intValue(lookup[TlvTypes.testRemainingU16]),
      batteryTemperature: _doubleValue(lookup[TlvTypes.batteryTemperatureX10]),
      ambientTemperature: _doubleValue(lookup[TlvTypes.ambientTemperatureX10]),
      ambientHumidity: _doubleValue(lookup[TlvTypes.ambientHumidityX10]),
      errorMessage: _stringValue(lookup[TlvTypes.errorMsg]),
      deviceIndex: _intValue(lookup[TlvTypes.deviceIndex]),
      reportTestNumber: _intValue(lookup[TlvTypes.reportTestNoU32]),
      tlvs: decoded,
    );
  }

  UcpTimeSnapshot parseUcpTime(DeviceResponse response) {
    final decoded = _decodedFromResponse(response);
    final lookup = _index(decoded);
    return UcpTimeSnapshot(
      epochSeconds: _intValue(lookup[TlvTypes.epochU64]),
      uptimeSeconds: _intValue(lookup[TlvTypes.uptimeU32]),
      text: _stringValue(lookup[TlvTypes.textUtf8]),
      tlvs: decoded,
    );
  }

  UcpLastReport parseUcpLastReport(DeviceResponse response) {
    final decoded = _decodedFromResponse(response);
    final lookup = _index(decoded);
    return UcpLastReport(
      reportId: _intValue(lookup[TlvTypes.reportIdU32]),
      testNumber: _intValue(lookup[TlvTypes.reportTestNoU32]),
      nitrogen: _doubleValue(lookup[TlvTypes.resultNX100]),
      phosphorus: _doubleValue(lookup[TlvTypes.resultPX100]),
      potassium: _doubleValue(lookup[TlvTypes.resultKX100]),
      moisture: _doubleValue(lookup[TlvTypes.resultMoistX100]),
      ph: _doubleValue(lookup[TlvTypes.resultPhX100]),
      ec: _doubleValue(lookup[TlvTypes.resultEcX100]),
      temperature: _doubleValue(lookup[TlvTypes.resultTempX100]),
      error: _stringValue(lookup[TlvTypes.reportError]),
      tlvs: decoded,
    );
  }

  UcpMoistureSample parseMoistureSample(DeviceFrame frame) {
    final decoded = decodeFrame(frame);
    final lookup = _index(decoded);
    return UcpMoistureSample(
      rawValue: _intValue(lookup[TlvTypes.moistRawU16]),
      moisturePercent: _doubleValue(lookup[TlvTypes.moistPercentX100U16]),
      text: _stringValue(lookup[TlvTypes.textUtf8]),
      tlvs: decoded,
    );
  }

  List<DecodedTlv> _decodedFromResponse(
    DeviceResponse response, {
    bool fallbackToRaw = false,
  }) {
    final tlvs = response.sourceFrame?.tlvs ?? _tryParseTlvs(response.payload);
    if (tlvs == null) {
      if (!fallbackToRaw) {
        throw const ProtocolException(
          'Payload is not valid TLV data',
          protocolErrorType: ProtocolErrorType.responseParsingFailed,
        );
      }
      return const <DecodedTlv>[];
    }
    return decodeTlvs(tlvs);
  }

  List<Tlv>? _tryParseTlvs(List<int> payload) {
    try {
      return parseTlvs(payload);
    } on ProtocolException {
      return null;
    }
  }

  Map<int, DecodedTlv> _index(List<DecodedTlv> tlvs) {
    return <int, DecodedTlv>{for (final tlv in tlvs) tlv.type: tlv};
  }

  int? _intValue(DecodedTlv? tlv) {
    final value = tlv?.value;
    return value is int ? value : null;
  }

  double? _doubleValue(DecodedTlv? tlv) {
    final value = tlv?.value;
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return null;
  }

  String? _stringValue(DecodedTlv? tlv) {
    final value = tlv?.value;
    return value is String ? value : null;
  }

  DeviceInfo parseDeviceInfo(List<int> payload) {
    if (payload.length < 4) {
      throw const ProtocolException(
        'Device info payload too short',
        protocolErrorType: ProtocolErrorType.responseParsingFailed,
      );
    }

    final reader = ByteReader(payload);
    final productId = reader.readUint16LE();
    final hardwareVersion = reader.readUint16LE();
    final serialNumber = _readNullTerminatedString(reader);
    final manufacturerName = reader.isEof
        ? ''
        : _readNullTerminatedString(reader);
    final modelName = reader.isEof ? '' : _readNullTerminatedString(reader);

    return DeviceInfo(
      productId: productId,
      hardwareVersion: hardwareVersion,
      serialNumber: serialNumber,
      manufacturerName: manufacturerName,
      modelName: modelName,
    );
  }

  FirmwareInfo parseFirmwareInfo(List<int> payload) {
    if (payload.length < 5) {
      throw const ProtocolException(
        'Firmware info payload too short',
        protocolErrorType: ProtocolErrorType.responseParsingFailed,
      );
    }

    final reader = ByteReader(payload);
    final major = reader.readUint8();
    final minor = reader.readUint8();
    final patch = reader.readUint8();
    final buildNumber = reader.readUint16LE();
    final versionString = reader.isEof ? '' : _readNullTerminatedString(reader);

    return FirmwareInfo(
      major: major,
      minor: minor,
      patch: patch,
      buildNumber: buildNumber,
      versionString: versionString,
    );
  }

  BatteryInfo parseBatteryInfo(List<int> payload) {
    if (payload.isEmpty) {
      throw const ProtocolException(
        'Battery payload too short',
        protocolErrorType: ProtocolErrorType.responseParsingFailed,
      );
    }

    final reader = ByteReader(payload);
    final level = reader.readUint8();
    final voltage = reader.remaining >= 2 ? reader.readUint16LE() : 0;
    final status = reader.remaining >= 1 ? reader.readUint8() : 0;

    return BatteryInfo(
      level: level,
      voltage: voltage,
      isCharging: (status & 0x01) != 0,
      isLow: (status & 0x02) != 0,
    );
  }

  DeviceStatus parseDeviceStatus(List<int> payload) {
    if (payload.length < 6) {
      throw const ProtocolException(
        'Device status payload too short',
        protocolErrorType: ProtocolErrorType.responseParsingFailed,
      );
    }

    final reader = ByteReader(payload);
    final mode = reader.readUint8();
    final state = reader.readUint8();
    final uptimeSeconds = reader.readUint32LE();
    final errorCode = reader.remaining >= 1 ? reader.readUint8() : 0;
    final customData = reader.isEof ? <int>[] : reader.readRemainingBytes();

    return DeviceStatus(
      mode: mode,
      state: state,
      uptimeSeconds: uptimeSeconds,
      errorCode: errorCode,
      customData: customData,
    );
  }

  ProtocolVersion parseProtocolVersion(List<int> payload) {
    if (payload.length < 2) {
      throw const ProtocolException(
        'Protocol version payload too short',
        protocolErrorType: ProtocolErrorType.responseParsingFailed,
      );
    }

    final reader = ByteReader(payload);
    final major = reader.readUint8();
    final minor = reader.readUint8();
    final patch = reader.remaining >= 1 ? reader.readUint8() : 0;
    return ProtocolVersion(major: major, minor: minor, patch: patch);
  }
}

String _readNullTerminatedString(ByteReader reader) {
  final bytes = <int>[];
  while (!reader.isEof) {
    final byte = reader.readUint8();
    if (byte == 0) {
      break;
    }
    bytes.add(byte);
  }
  return String.fromCharCodes(bytes);
}
