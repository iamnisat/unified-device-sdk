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

    test('maps production status_code TLV to named exception metadata', () {
      final frame = FrameBuilder().build(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        profileId: ProfileIds.defaultProfile,
        sourceAddress: UcpAddresses.device,
        destinationAddress: UcpAddresses.software,
        op: OperationCodes.nack,
        commandClass: CommandClasses.measurement,
        commandId: MeasurementCommandIds.startTest,
        sequence: 2,
        flags: 0,
        payload: TlvBuilder()
            .addUint16BE(TlvTypes.statusCode, UcpStatusCodes.deviceBusy)
            .build(),
      );
      final response = DeviceResponse.fromFrame(FrameParser().parse(frame));

      final exception = parser.parse(response);
      final details = parser.parseDetails(response);

      expect(exception.errorCode, UcpStatusCodes.deviceBusy);
      expect(exception.errorName, 'DEVICE_BUSY');
      expect(exception.errorDescription, 'Device cannot accept command now.');
      expect(exception.isRetryable, isTrue);
      expect(
        exception.message,
        'DEVICE_BUSY: Device cannot accept command now.',
      );
      expect(details.errorName, 'DEVICE_BUSY');
      expect(details.isRetryable, isTrue);
    });

    test('decodes raw two-byte production NACK error code', () {
      final response = DeviceResponse.failure(
        sequence: 5,
        productId: ProductIds.aunkurUcp1,
        address: UcpAddresses.software,
        commandId: MeasurementCommandIds.startTest,
        op: OperationCodes.nack,
        flags: 0,
        payload: const [0x00, 0x0E],
      );

      final exception = parser.parse(response);

      expect(exception.errorCode, UcpStatusCodes.lowBattery);
      expect(exception.errorName, 'LOW_BATTERY');
      expect(exception.message, 'LOW_BATTERY: Battery too low for operation.');
      expect(exception.isRetryable, isFalse);
    });

    test('does not treat message-only TLV bytes as a raw error code', () {
      final frame = FrameBuilder().build(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        profileId: ProfileIds.defaultProfile,
        sourceAddress: UcpAddresses.device,
        destinationAddress: UcpAddresses.software,
        op: OperationCodes.nack,
        commandClass: CommandClasses.measurement,
        commandId: MeasurementCommandIds.startTest,
        sequence: 3,
        flags: 0,
        payload: TlvBuilder()
            .addUtf8(TlvTypes.messageText, 'Required TLV missing')
            .build(),
      );
      final response = DeviceResponse.fromFrame(FrameParser().parse(frame));

      final exception = parser.parse(response);

      expect(exception.errorCode, isNull);
      expect(exception.errorName, isNull);
      expect(exception.message, 'Required TLV missing');
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
