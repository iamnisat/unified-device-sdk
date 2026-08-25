import 'package:flutter_test/flutter_test.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

import '../mocks/fake_transport.dart';

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('ResponseManager', () {
    late FakeTransport transport;
    late ResponseManager manager;
    late FrameBuilder frameBuilder;
    late FrameParser frameParser;

    setUp(() {
      transport = FakeTransport();
      manager = ResponseManager(transport: transport);
      frameBuilder = FrameBuilder();
      frameParser = FrameParser();
    });

    tearDown(() async {
      manager.dispose();
      await transport.dispose();
    });

    test('ACK-only success with official header fields', () async {
      final future = manager.sendCommand(
        commandId: SystemCommandIds.deviceInfo,
        productId: ProductIds.aunkurUcp1,
        profileId: ProfileIds.dummyM2m,
        sourceAddress: UcpAddresses.software,
        destinationAddress: UcpAddresses.device,
        op: OperationCodes.req,
        commandClass: CommandClasses.system,
      );

      final requestFrame = frameParser.parse(transport.writtenData.single);
      expect(requestFrame.sequence, 0);

      transport.simulateIncomingData(
        frameBuilder.build(
          version: 1,
          productId: ProductIds.aunkurUcp1,
          profileId: ProfileIds.dummyM2m,
          sourceAddress: UcpAddresses.device,
          destinationAddress: UcpAddresses.software,
          op: OperationCodes.ack,
          commandClass: CommandClasses.system,
          commandId: SystemCommandIds.deviceInfo,
          sequence: requestFrame.sequence,
          flags: 0,
        ),
      );

      final response = await future;
      expect(response.commandId, SystemCommandIds.deviceInfo);
      expect(response.commandClass, CommandClasses.system);
      expect(manager.pendingCount, 0);
    });

    test('ACK then DATA success', () async {
      final future = manager.sendCommand(
        commandId: SessionCommandIds.btTransportOpen,
        commandClass: CommandClasses.session,
        options: const CommandOptions(
          waitForAck: true,
          waitForData: true,
          ackTimeout: Duration(seconds: 1),
          dataTimeout: Duration(seconds: 1),
        ),
      );

      final requestFrame = frameParser.parse(transport.writtenData.single);
      transport.simulateIncomingData(
        frameBuilder.build(
          version: 1,
          productId: ProductIds.aunkurUcp1,
          profileId: ProfileIds.dummyM2m,
          sourceAddress: UcpAddresses.device,
          destinationAddress: UcpAddresses.software,
          op: OperationCodes.ack,
          commandClass: CommandClasses.session,
          commandId: SessionCommandIds.btTransportOpen,
          sequence: requestFrame.sequence,
          flags: 0,
        ),
      );
      await _flushMicrotasks();

      transport.simulateIncomingData(
        frameBuilder.build(
          version: 1,
          productId: ProductIds.aunkurUcp1,
          profileId: ProfileIds.dummyM2m,
          sourceAddress: UcpAddresses.device,
          destinationAddress: UcpAddresses.software,
          op: OperationCodes.data,
          commandClass: CommandClasses.session,
          commandId: SessionCommandIds.btTransportOpen,
          sequence: requestFrame.sequence,
          flags: 0,
          payload: const [0xAA, 0xBB],
        ),
      );

      final response = await future;
      expect(response.op, OperationCodes.data);
      expect(response.payload, [0xAA, 0xBB]);
    });

    test('NACK failure uses raw payload error code', () async {
      final future = manager.sendCommand(
        commandId: SystemCommandIds.deviceInfo,
        commandClass: CommandClasses.system,
      );

      final requestFrame = frameParser.parse(transport.writtenData.single);
      transport.simulateIncomingData(
        frameBuilder.build(
          version: 1,
          productId: ProductIds.aunkurUcp1,
          profileId: ProfileIds.dummyM2m,
          sourceAddress: UcpAddresses.device,
          destinationAddress: UcpAddresses.software,
          op: OperationCodes.nack,
          commandClass: CommandClasses.system,
          commandId: SystemCommandIds.deviceInfo,
          sequence: requestFrame.sequence,
          flags: 0x01,
          payload: const [0x7F],
        ),
      );

      await expectLater(
        future,
        throwsA(
          isA<ProtocolException>()
              .having(
                (e) => e.protocolErrorType,
                'type',
                ProtocolErrorType.nackReceived,
              )
              .having((e) => e.errorCode, 'errorCode', 0x7F),
        ),
      );
    });

    test('EVENT emission decodes event frame', () async {
      final events = <DeviceEvent>[];
      final subscription = manager.events.listen(events.add);
      addTearDown(subscription.cancel);

      transport.simulateIncomingData(
        frameBuilder.build(
          version: 1,
          productId: ProductIds.aunkurUcp1,
          profileId: ProfileIds.dummyM2m,
          sourceAddress: UcpAddresses.device,
          destinationAddress: UcpAddresses.software,
          op: OperationCodes.event,
          commandClass: CommandClasses.session,
          commandId: SessionCommandIds.heartbeat,
          sequence: 1,
          flags: 0,
          payload: const [0xAB],
        ),
      );
      await _flushMicrotasks();

      expect(events, hasLength(1));
      expect(events.single.commandId, SessionCommandIds.heartbeat);
      expect(events.single.eventCode, 0xAB);
    });

    test('RX packet trace uses original parsed frame bytes', () async {
      final traceFuture = manager.packetTraces.firstWhere(
        (trace) => trace.direction == UcpPacketDirection.rx,
      );
      final bytes = frameBuilder.build(
        version: 1,
        productId: ProductIds.aunkurUcp1,
        profileId: ProfileIds.defaultProfile,
        sourceAddress: UcpAddresses.device,
        destinationAddress: UcpAddresses.software,
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

      transport.simulateIncomingData(bytes);

      final trace = await traceFuture;
      expect(trace.bytes, bytes);
      expect(trace.frame?.rawBytes, bytes);
    });
  });
}
