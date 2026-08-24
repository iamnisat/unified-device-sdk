import 'package:flutter_test/flutter_test.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

void main() {
  group('NackParser', () {
    const parser = NackParser();

    test('parses NACK response into ProtocolException', () {
      final response = DeviceResponse.failure(
        sequence: 5,
        productId: 0x1001,
        address: 0x01020304,
        commandId: 0x21,
        op: OperationCodes.nack,
        flags: 0x01,
        payload: [0x7F],
        errorMessage: 'Command not supported',
      );

      final exception = parser.parse(response);

      expect(exception.protocolErrorType, ProtocolErrorType.nackReceived);
      expect(exception.errorCode, 0x7F);
      expect(exception.message, 'Command not supported');
    });

    test('parses diagnostic text TLV from hardware NACK response', () {
      final frame = FrameBuilder().build(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        profileId: ProfileIds.defaultProfile,
        sourceAddress: UcpAddresses.device,
        destinationAddress: UcpAddresses.software,
        op: OperationCodes.nack,
        commandClass: CommandClasses.session,
        commandId: SessionCommandIds.btTransportOpen,
        sequence: 1,
        flags: 0,
        payload: TlvBuilder()
            .addUint8(TlvTypes.sessionStateU8, 0)
            .addUtf8(
              TlvTypes.diagnosticText,
              'unsupported UCP version/product/profile',
            )
            .build(),
      );
      final response = DeviceResponse.fromFrame(FrameParser().parse(frame));

      final exception = parser.parse(response);

      expect(exception.protocolErrorType, ProtocolErrorType.nackReceived);
      expect(exception.message, 'unsupported UCP version/product/profile');
    });

    test('throws when response is not a NACK', () {
      final response = DeviceResponse.success(
        sequence: 1,
        productId: 0,
        address: 0,
        commandId: 0x10,
        op: OperationCodes.ack,
      );

      expect(() => parser.parse(response), throwsA(isA<ProtocolException>()));
    });
  });
}
