import 'package:flutter_test/flutter_test.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

void main() {
  group('UcpFrameParser', () {
    late UcpFrameParser parser;
    late UcpFrameBuilder builder;

    setUp(() {
      parser = UcpFrameParser();
      builder = UcpFrameBuilder();
    });

    test('parses official start_test request and decodes TLVs', () {
      final frame = parser.parse(
        builder.build(
          version: 1,
          productId: ProductIds.aunkurUcp1,
          op: OperationCodes.req,
          commandClass: CommandClasses.measurement,
          commandId: MeasurementCommandIds.startTest,
          sequence: 7,
          flags: 0,
          tlvs: [
            Tlv(type: TlvTypes.agentId, value: 'AGENT-DEMO'.codeUnits),
            Tlv(type: TlvTypes.farmerId, value: 'FARMER-001'.codeUnits),
            Tlv(type: TlvTypes.fieldId, value: 'FIELD-A'.codeUnits),
            Tlv(type: TlvTypes.testId, value: 'TEST-0001'.codeUnits),
            Tlv(type: TlvTypes.globalLandLocation, value: [0, 0, 0, 0]),
            Tlv(type: TlvTypes.aez, value: [0, 0, 0, 0]),
            Tlv(type: TlvTypes.soilCategory, value: [0, 0, 0, 0]),
          ],
        ),
      );

      expect(frame.productId, ProductIds.aunkurUcp1);
      expect(frame.profileId, ProfileIds.defaultProfile);
      expect(frame.sourceAddress, UcpAddresses.software);
      expect(frame.destinationAddress, UcpAddresses.device);
      expect(frame.op, OperationCodes.req);
      expect(frame.commandClass, CommandClasses.measurement);
      expect(frame.commandId, MeasurementCommandIds.startTest);
      expect(frame.sequence, 7);
      expect(frame.payloadLength, 69);
      expect(frame.tlvs, hasLength(7));
      expect(frame.tlvs[0].type, TlvTypes.agentId);
      expect(frame.tlvs[0].asAsciiString(), 'AGENT-DEMO');
      expect(frame.tlvs[3].type, TlvTypes.testId);
      expect(frame.tlvs[4].type, TlvTypes.globalLandLocation);
      expect(frame.tlvs[5].type, TlvTypes.aez);
      expect(frame.tlvs[6].type, TlvTypes.soilCategory);
      expect(frame.tlvs[3].asAsciiString(), 'TEST-0001');
    });

    test('parses empty-payload system request', () {
      final frame = parser.parse(
        builder.build(
          version: 1,
          productId: ProductIds.aunkurUcp1,
          op: OperationCodes.req,
          commandClass: CommandClasses.deviceInfo,
          commandId: DeviceInfoCommandIds.getDeviceInfo,
          sequence: 3,
          flags: 0,
        ),
      );

      expect(frame.commandClass, CommandClasses.deviceInfo);
      expect(frame.commandId, DeviceInfoCommandIds.getDeviceInfo);
      expect(frame.sequence, 3);
      expect(frame.payload, isEmpty);
      expect(frame.tlvs, isEmpty);
    });

    test('preserves original raw frame bytes', () {
      final bytes = builder.build(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        op: OperationCodes.nack,
        commandClass: CommandClasses.measurement,
        commandId: MeasurementCommandIds.getLastReport,
        sequence: 13,
        flags: 0,
        payload: TlvBuilder()
            .addUint16BE(TlvTypes.statusCode, UcpStatusCodes.deviceBusy)
            .addUtf8(
              TlvTypes.messageText,
              'TEST_RUNNING_ONLY_MATCHING_STOP_ALLOWED',
            )
            .build(),
      );

      final frame = parser.parse(bytes);

      expect(frame.rawBytes, bytes);
    });

    test('decodes one-byte firmware state on shared 0x54 TLV', () {
      final frame = parser.parse(
        builder.build(
          version: 1,
          productId: ProductIds.aunkurUcp1,
          op: OperationCodes.event,
          commandClass: CommandClasses.measurement,
          commandId: MeasurementCommandIds.startTest,
          sequence: 8,
          flags: 0,
          tlvs: [
            Tlv(type: TlvTypes.fwStateU8, value: const [6]),
          ],
        ),
      );

      final decoded = DecodedTlv.fromTlv(frame.tlvs.single);
      expect(decoded.type, TlvTypes.fwStateU8);
      expect(decoded.value, 6);
    });

    test('preserves raw payload when it is not valid TLV', () {
      final builder = UcpFrameBuilder();
      final bytes = builder.build(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        op: OperationCodes.nack,
        commandClass: CommandClasses.system,
        commandId: SystemCommandIds.deviceInfo,
        sequence: 9,
        flags: 1,
        payload: const [0x7F],
      );

      final frame = parser.parse(bytes);
      expect(frame.payload, [0x7F]);
      expect(frame.tlvs, isEmpty);
    });

    test('throws on CRC mismatch', () {
      final bytes = builder.build(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        op: OperationCodes.req,
        commandClass: CommandClasses.deviceInfo,
        commandId: DeviceInfoCommandIds.getDeviceInfo,
        sequence: 3,
        flags: 0,
      );
      bytes[bytes.length - 2] ^= 0xFF;

      expect(() => parser.parse(bytes), throwsA(isA<CrcException>()));
    });
  });
}
