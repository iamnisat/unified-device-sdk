import 'package:flutter_test/flutter_test.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

void main() {
  group('UcpFrame', () {
    test('encodes TLVs into payload automatically', () {
      final frame = UcpFrame(
        version: ProtocolConstants.currentProtocolVersion,
        productId: ProductIds.aunkurUcp1,
        op: OperationCodes.req,
        commandClass: CommandClasses.measurement,
        commandId: MeasurementCommandIds.startTest,
        sequence: 7,
        flags: 0,
        tlvs: [
          Tlv(type: TlvTypes.agentId, value: 'AGENT-DEMO'.codeUnits),
          Tlv(type: TlvTypes.testId, value: 'TEST-0001'.codeUnits),
        ],
        crc: 0,
      );

      expect(frame.profileId, ProfileIds.defaultProfile);
      expect(frame.sourceAddress, UcpAddresses.defaultSource);
      expect(frame.destinationAddress, UcpAddresses.defaultDestination);
      expect(frame.payload, [
        TlvTypes.agentId,
        0x00,
        0x0A,
        ...'AGENT-DEMO'.codeUnits,
        TlvTypes.testId,
        0x00,
        0x09,
        ...'TEST-0001'.codeUnits,
      ]);
      expect(frame.tlvs, hasLength(2));
    });

    test('DeviceFrame keeps address alias for destination', () {
      final frame = DeviceFrame(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        address: UcpAddresses.device,
        op: OperationCodes.ack,
        commandClass: CommandClasses.system,
        commandId: SystemCommandIds.deviceInfo,
        sequence: 3,
        flags: 0,
        crc: 0,
      );

      expect(frame.address, UcpAddresses.device);
      expect(frame.destinationAddress, UcpAddresses.device);
      expect(frame.sourceAddress, UcpAddresses.software);
    });

    test('rejects old 16-bit product and 32-bit address assumptions', () {
      expect(
        () => DeviceFrame(
          version: 1,
          productId: 0x1001,
          address: UcpAddresses.device,
          op: OperationCodes.req,
          commandClass: CommandClasses.system,
          commandId: SystemCommandIds.deviceInfo,
          sequence: 0,
          flags: 0,
          crc: 0,
        ),
        throwsArgumentError,
      );

      expect(
        () => DeviceFrame(
          version: 1,
          productId: ProductIds.aunkurUcp1,
          address: 0x01020304,
          op: OperationCodes.req,
          commandClass: CommandClasses.system,
          commandId: SystemCommandIds.deviceInfo,
          sequence: 0,
          flags: 0,
          crc: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
