import 'package:flutter_test/flutter_test.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

void main() {
  group('UcpFrameBuilder', () {
    late UcpFrameBuilder builder;

    setUp(() {
      builder = UcpFrameBuilder();
    });

    test('builds production open_rtc_sync request', () {
      final bytes = builder.build(
        version: 0x01,
        productId: ProductIds.aunkurUcp1,
        profileId: ProfileIds.defaultProfile,
        sourceAddress: UcpAddresses.software,
        destinationAddress: UcpAddresses.device,
        op: OperationCodes.req,
        commandClass: CommandClasses.session,
        commandId: SessionCommandIds.sessionOpenRtcSync,
        sequence: 0x0001,
        flags: 0x00,
        tlvs: [
          Tlv(
            type: TlvTypes.epochU64,
            value: [0, 0, 0, 0, 0x6A, 0x50, 0x91, 0x68],
          ),
          Tlv(type: TlvTypes.clientName, value: 'PorokhTester'.codeUnits),
          Tlv(type: TlvTypes.appInstanceId, value: 'app-001'.codeUnits),
        ],
      );

      final frame = UcpFrameParser().parse(bytes);
      expect(frame.profileId, ProfileIds.defaultProfile);
      expect(frame.commandClass, CommandClasses.session);
      expect(frame.commandId, SessionCommandIds.sessionOpenRtcSync);
      expect(frame.tlvs.map((tlv) => tlv.type), [
        TlvTypes.epochU64,
        TlvTypes.clientName,
        TlvTypes.appInstanceId,
      ]);
    });

    test('builds device_info request', () {
      final bytes = builder.build(
        version: 0x01,
        productId: ProductIds.aunkurUcp1,
        profileId: ProfileIds.defaultProfile,
        sourceAddress: UcpAddresses.software,
        destinationAddress: UcpAddresses.device,
        op: OperationCodes.req,
        commandClass: CommandClasses.deviceInfo,
        commandId: DeviceInfoCommandIds.getDeviceInfo,
        sequence: 0x0003,
        flags: 0x00,
      );

      final frame = UcpFrameParser().parse(bytes);
      expect(frame.commandClass, CommandClasses.deviceInfo);
      expect(frame.commandId, DeviceInfoCommandIds.getDeviceInfo);
      expect(frame.payload, isEmpty);
    });

    test('builds time read request', () {
      final bytes = builder.build(
        version: 0x01,
        productId: ProductIds.aunkurUcp1,
        profileId: ProfileIds.defaultProfile,
        sourceAddress: UcpAddresses.software,
        destinationAddress: UcpAddresses.device,
        op: OperationCodes.req,
        commandClass: CommandClasses.system,
        commandId: SystemCommandIds.time,
        sequence: 0x0004,
        flags: 0x00,
      );

      final frame = UcpFrameParser().parse(bytes);
      expect(frame.commandClass, CommandClasses.system);
      expect(frame.commandId, SystemCommandIds.time);
      expect(frame.payload, isEmpty);
    });

    test('builds start_test request with production TLVs', () {
      final bytes = builder.build(
        version: 0x01,
        productId: ProductIds.aunkurUcp1,
        profileId: ProfileIds.defaultProfile,
        sourceAddress: UcpAddresses.software,
        destinationAddress: UcpAddresses.device,
        op: OperationCodes.req,
        commandClass: CommandClasses.measurement,
        commandId: MeasurementCommandIds.startTest,
        sequence: 0x0007,
        flags: 0x00,
        tlvs: [
          Tlv(type: TlvTypes.agentId, value: 'AGENT-DEMO'.codeUnits),
          Tlv(type: TlvTypes.farmerId, value: 'FARMER-001'.codeUnits),
          Tlv(type: TlvTypes.fieldId, value: 'FIELD-A'.codeUnits),
          Tlv(type: TlvTypes.testId, value: 'TEST-0001'.codeUnits),
          Tlv(type: TlvTypes.globalLandLocation, value: [0, 0, 0, 0]),
          Tlv(type: TlvTypes.aez, value: [0, 0, 0, 0]),
          Tlv(type: TlvTypes.soilCategory, value: [0, 0, 0, 0]),
        ],
      );

      final frame = UcpFrameParser().parse(bytes);
      expect(frame.profileId, ProfileIds.defaultProfile);
      expect(frame.commandClass, CommandClasses.measurement);
      expect(frame.commandId, MeasurementCommandIds.startTest);
      expect(frame.tlvs.map((tlv) => tlv.type), [
        TlvTypes.agentId,
        TlvTypes.farmerId,
        TlvTypes.fieldId,
        TlvTypes.testId,
        TlvTypes.globalLandLocation,
        TlvTypes.aez,
        TlvTypes.soilCategory,
      ]);
    });
  });
}
