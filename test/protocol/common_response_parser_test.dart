import 'package:flutter_test/flutter_test.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

void main() {
  group('CommonResponseParser', () {
    late CommonResponseParser parser;

    setUp(() {
      parser = const CommonResponseParser();
    });

    test('parses device info', () {
      final payload = [
        0x01, 0x01, // productId: 0x0101
        0x01, 0x00, // hardwareVersion: 1
        0x53, 0x4E, 0x30, 0x30, 0x31, 0x00, // "SN001\0"
      ];
      final info = parser.parseDeviceInfo(payload);
      expect(info.productId, 0x0101);
      expect(info.hardwareVersion, 1);
      expect(info.serialNumber, 'SN001');
    });

    test('parses firmware info', () {
      final payload = [
        0x01, // major
        0x02, // minor
        0x03, // patch
        0x2A, 0x00, // buildNumber: 42
      ];
      final info = parser.parseFirmwareInfo(payload);
      expect(info.major, 1);
      expect(info.minor, 2);
      expect(info.patch, 3);
      expect(info.buildNumber, 42);
      expect(info.formattedVersion, '1.2.3+42');
    });

    test('parses battery info', () {
      final payload = [
        0x5A, // level: 90
        0xE8, 0x03, // voltage: 1000
        0x01, // status: charging
      ];
      final info = parser.parseBatteryInfo(payload);
      expect(info.level, 90);
      expect(info.voltage, 1000);
      expect(info.isCharging, isTrue);
      expect(info.isLow, isFalse);
    });

    test('parses device status', () {
      final payload = [
        0x01, // mode
        0x02, // state
        0x78, 0x56, 0x34, 0x12, // uptime: 0x12345678
        0x00, // errorCode: 0
      ];
      final status = parser.parseDeviceStatus(payload);
      expect(status.mode, 1);
      expect(status.state, 2);
      expect(status.uptimeSeconds, 0x12345678);
      expect(status.hasError, isFalse);
    });

    test('parses protocol version', () {
      final payload = [0x01, 0x02, 0x03];
      final version = parser.parseProtocolVersion(payload);
      expect(version.major, 1);
      expect(version.minor, 2);
      expect(version.patch, 3);
      expect(version.formattedVersion, '1.2.3');
    });
  });
}
