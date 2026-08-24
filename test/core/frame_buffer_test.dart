import 'package:flutter_test/flutter_test.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

void main() {
  group('UcpFrameBuffer', () {
    late UcpFrameBuffer buffer;
    late UcpFrameBuilder builder;

    setUp(() {
      buffer = UcpFrameBuffer();
      builder = UcpFrameBuilder();
    });

    test('reassembles a frame split across notifications', () {
      final bytes = builder.build(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        op: OperationCodes.req,
        commandClass: CommandClasses.deviceInfo,
        commandId: DeviceInfoCommandIds.getDeviceInfo,
        sequence: 3,
        flags: 0,
      );

      expect(buffer.addBytes(bytes.sublist(0, 5)), isEmpty);
      final frames = buffer.addBytes(bytes.sublist(5));

      expect(frames, hasLength(1));
      expect(frames.single.commandId, DeviceInfoCommandIds.getDeviceInfo);
      expect(buffer.isEmpty, isTrue);
    });

    test('discards garbage before SOF and parses next frame', () {
      final bytes = builder.build(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        op: OperationCodes.req,
        commandClass: CommandClasses.system,
        commandId: SystemCommandIds.time,
        sequence: 4,
        flags: 0,
      );

      final frames = buffer.addBytes([0x00, 0xAA, 0x55, ...bytes]);
      expect(frames, hasLength(1));
      expect(frames.single.commandId, SystemCommandIds.time);
    });

    test('parses multiple frames from one chunk', () {
      final first = builder.build(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        op: OperationCodes.req,
        commandClass: CommandClasses.deviceInfo,
        commandId: DeviceInfoCommandIds.getDeviceInfo,
        sequence: 3,
        flags: 0,
      );
      final second = builder.build(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        op: OperationCodes.req,
        commandClass: CommandClasses.system,
        commandId: SystemCommandIds.time,
        sequence: 4,
        flags: 0,
      );

      final frames = buffer.addBytes([...first, ...second]);
      expect(frames, hasLength(2));
      expect(frames.first.commandId, DeviceInfoCommandIds.getDeviceInfo);
      expect(frames.last.commandId, SystemCommandIds.time);
    });

    test('skips a bad frame and continues scanning', () {
      final bad = builder.build(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        op: OperationCodes.req,
        commandClass: CommandClasses.deviceInfo,
        commandId: DeviceInfoCommandIds.getDeviceInfo,
        sequence: 3,
        flags: 0,
      )..[15] = 0;
      final good = builder.build(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        op: OperationCodes.req,
        commandClass: CommandClasses.system,
        commandId: SystemCommandIds.time,
        sequence: 4,
        flags: 0,
      );

      final frames = buffer.addBytes([...bad, ...good]);
      expect(frames, hasLength(1));
      expect(frames.single.commandId, SystemCommandIds.time);
    });
  });
}
