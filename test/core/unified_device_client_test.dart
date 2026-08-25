import 'package:flutter_test/flutter_test.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

import '../mocks/fake_transport.dart';

Future<void> _drainQueue() async {
  await Future<void>.delayed(Duration.zero);
}

Future<void> _completeBootstrap({
  required FakeTransport transport,
  required FrameBuilder frameBuilder,
  required FrameParser frameParser,
}) async {
  await _drainQueue();
  expect(transport.writtenData, hasLength(1));

  final sessionOpenRequest = frameParser.parse(transport.writtenData.single);
  transport.simulateIncomingData(
    frameBuilder.build(
      version: 1,
      productId: ProductIds.aunkurUcp1,
      profileId: ProfileIds.defaultProfile,
      sourceAddress: UcpAddresses.device,
      destinationAddress: UcpAddresses.software,
      op: OperationCodes.ack,
      commandClass: CommandClasses.session,
      commandId: SessionCommandIds.sessionOpenRtcSync,
      sequence: sessionOpenRequest.sequence,
      flags: 0,
      payload: TlvBuilder()
          .addUint16BE(TlvTypes.statusCode, 0)
          .addUint32BE(TlvTypes.sessionId, 0xA1B2C3D4)
          .build(),
    ),
  );

  await _drainQueue();
}

void main() {
  group('UnifiedDeviceClient', () {
    late FakeTransport transport;
    late UnifiedDeviceClient client;
    late FrameBuilder frameBuilder;
    late FrameParser frameParser;

    setUp(() {
      transport = FakeTransport();
      client = UnifiedDeviceClient(
        UnifiedDeviceClientConfig(transport: transport),
      );
      frameBuilder = FrameBuilder();
      frameParser = FrameParser();
    });

    tearDown(() async {
      await client.dispose();
      await transport.dispose();
    });

    test(
      'connect auto-runs official transport and session bootstrap',
      () async {
        final states = <DeviceConnectionState>[];
        final subscription = client.connectionState.listen(states.add);
        addTearDown(subscription.cancel);

        final connectFuture = client.connect(
          DiscoveredDevice(
            deviceId: 'dev-1',
            name: BleConstants.defaultDeviceName,
            rssi: -42,
          ),
        );

        await _completeBootstrap(
          transport: transport,
          frameBuilder: frameBuilder,
          frameParser: frameParser,
        );
        await connectFuture;

        final sessionOpenRequest = frameParser.parse(transport.writtenData[0]);
        expect(sessionOpenRequest.commandClass, CommandClasses.session);
        expect(
          sessionOpenRequest.commandId,
          SessionCommandIds.sessionOpenRtcSync,
        );
        expect(sessionOpenRequest.profileId, ProfileIds.defaultProfile);
        expect(
          sessionOpenRequest.tlvs.map((tlv) => tlv.type),
          containsAll([
            TlvTypes.epochU64,
            TlvTypes.clientName,
            TlvTypes.appInstanceId,
          ]),
        );
        expect(client.isSessionActive, isTrue);
        expect(client.currentSession?.ucpSessionId, 0xA1B2C3D4);
        expect(
          client.currentSession?.state,
          anyOf(
            DeviceConnectionState.sessionActive,
            DeviceConnectionState.measurementActive,
            DeviceConnectionState.streamActive,
          ),
        );
      },
    );

    test(
      'ignores late mtuReady updates after session bootstrap completes',
      () async {
        final states = <DeviceConnectionState>[];
        final subscription = client.connectionState.listen(states.add);
        addTearDown(subscription.cancel);

        await _completeBootstrapForClient(
          client: client,
          transport: transport,
          frameBuilder: frameBuilder,
          frameParser: frameParser,
        );

        transport.simulateConnectionState(DeviceConnectionState.mtuReady);
        await _drainQueue();

        expect(client.isSessionActive, isTrue);
        expect(
          client.currentSession?.state,
          DeviceConnectionState.sessionActive,
        );
        expect(states.last, DeviceConnectionState.sessionActive);
      },
    );

    test(
      'rtc-only bootstrap sends production session open without transport open',
      () async {
        final connectFuture = client.connect(
          DiscoveredDevice(
            deviceId: 'dev-1',
            name: BleConstants.defaultDeviceName,
            rssi: -42,
          ),
        );

        await _drainQueue();
        expect(transport.writtenData, hasLength(1));

        final sessionOpenRequest = frameParser.parse(transport.writtenData[0]);
        expect(
          sessionOpenRequest.commandId,
          SessionCommandIds.sessionOpenRtcSync,
        );
        expect(
          sessionOpenRequest.tlvs.map((tlv) => tlv.type),
          containsAll([
            TlvTypes.epochU64,
            TlvTypes.clientName,
            TlvTypes.appInstanceId,
          ]),
        );

        transport.simulateIncomingData(
          frameBuilder.build(
            version: 1,
            productId: ProductIds.aunkurUcp1,
            profileId: ProfileIds.defaultProfile,
            sourceAddress: UcpAddresses.device,
            destinationAddress: UcpAddresses.software,
            op: OperationCodes.ack,
            commandClass: CommandClasses.session,
            commandId: SessionCommandIds.sessionOpenRtcSync,
            sequence: sessionOpenRequest.sequence,
            flags: 0,
            payload: TlvBuilder()
                .addUint16BE(TlvTypes.statusCode, 0)
                .addUint32BE(TlvTypes.sessionId, 0xA1B2C3D4)
                .build(),
          ),
        );

        await connectFuture;
        expect(client.isSessionActive, isTrue);
      },
    );

    test(
      'uses custom hardware profile for session bootstrap headers',
      () async {
        await client.dispose();
        await transport.dispose();
        transport = FakeTransport();
        const hardwareProfile = UnifiedDeviceHardwareProfile(
          name: 'Production Device',
          productId: ProductIds.weatherStation,
          profileId: 0x22,
          sourceAddress: 0x31,
          destinationAddress: 0x41,
          clientName: null,
          appInstanceId: 'custom-app',
          bootstrapStrategy: UcpBootstrapStrategy.rtcSyncOnly,
          heartbeatEnabled: false,
        );
        client = UnifiedDeviceClient(
          UnifiedDeviceClientConfig(
            transport: transport,
            hardwareProfile: hardwareProfile,
          ),
        );

        final connectFuture = client.connect(
          DiscoveredDevice(deviceId: 'prod-1', name: 'Prod', rssi: -42),
        );

        await _drainQueue();
        expect(transport.writtenData, hasLength(1));

        final sessionOpenRequest = frameParser.parse(transport.writtenData[0]);
        expect(sessionOpenRequest.productId, ProductIds.weatherStation);
        expect(sessionOpenRequest.profileId, 0x22);
        expect(sessionOpenRequest.sourceAddress, 0x31);
        expect(sessionOpenRequest.destinationAddress, 0x41);
        expect(
          sessionOpenRequest.commandId,
          SessionCommandIds.sessionOpenRtcSync,
        );
        expect(sessionOpenRequest.tlvs.map((tlv) => tlv.type), [
          TlvTypes.epochU64,
          TlvTypes.appInstanceId,
        ]);

        transport.simulateIncomingData(
          frameBuilder.build(
            version: 1,
            productId: ProductIds.weatherStation,
            profileId: 0x22,
            sourceAddress: 0x41,
            destinationAddress: 0x31,
            op: OperationCodes.ack,
            commandClass: CommandClasses.session,
            commandId: SessionCommandIds.sessionOpenRtcSync,
            sequence: sessionOpenRequest.sequence,
            flags: 0,
            payload: TlvBuilder()
                .addUint16BE(TlvTypes.statusCode, 0)
                .addUint32BE(TlvTypes.sessionId, 0x01020304)
                .build(),
          ),
        );

        await connectFuture;
        expect(client.isSessionActive, isTrue);
      },
    );

    test('blocks normal commands before sessionActive', () async {
      final connectFuture = client.connect(
        DiscoveredDevice(
          deviceId: 'dev-1',
          name: BleConstants.defaultDeviceName,
          rssi: -42,
        ),
      );

      await _drainQueue();
      await expectLater(
        () => client.sendCommand(
          productId: ProductIds.aunkurUcp1,
          profileId: ProfileIds.dummyM2m,
          sourceAddress: UcpAddresses.software,
          destinationAddress: UcpAddresses.device,
          op: OperationCodes.req,
          commandClass: CommandClasses.system,
          commandId: SystemCommandIds.deviceInfo,
        ),
        throwsA(
          isA<ProtocolException>().having(
            (e) => e.protocolErrorType,
            'type',
            ProtocolErrorType.invalidDeviceState,
          ),
        ),
      );

      await _completeBootstrap(
        transport: transport,
        frameBuilder: frameBuilder,
        frameParser: frameParser,
      );
      await connectFuture;
    });

    test('emits EVENT frames through events stream after bootstrap', () async {
      await _completeBootstrapForClient(
        client: client,
        transport: transport,
        frameBuilder: frameBuilder,
        frameParser: frameParser,
      );

      final events = <DeviceEvent>[];
      final subscription = client.events.listen(events.add);
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
          sequence: 2,
          flags: 0,
          payload: const [0xAB],
        ),
      );
      await _drainQueue();

      expect(events, hasLength(1));
      expect(events.single.commandId, SessionCommandIds.heartbeat);
      expect(events.single.eventCode, 0xAB);
    });

    test('tracks production soil test progress and error events', () async {
      await _completeBootstrapForClient(
        client: client,
        transport: transport,
        frameBuilder: frameBuilder,
        frameParser: frameParser,
      );

      transport.simulateIncomingData(
        frameBuilder.build(
          version: 1,
          productId: ProductIds.aunkurUcp1,
          profileId: ProfileIds.defaultProfile,
          sourceAddress: UcpAddresses.device,
          destinationAddress: UcpAddresses.software,
          op: OperationCodes.event,
          commandClass: CommandClasses.measurement,
          commandId: MeasurementCommandIds.startTest,
          sequence: 10,
          flags: 0,
          payload: TlvBuilder()
              .addUint16BE(TlvTypes.statusCode, 0)
              .addUtf8(TlvTypes.messageText, 'T#96%')
              .addUint8(TlvTypes.sampleSizePercent, 96)
              .build(),
        ),
      );
      await _drainQueue();

      expect(client.currentSession?.measurementActive, isTrue);
      expect(
        client.currentSession?.state,
        DeviceConnectionState.measurementActive,
      );

      transport.simulateIncomingData(
        frameBuilder.build(
          version: 1,
          productId: ProductIds.aunkurUcp1,
          profileId: ProfileIds.defaultProfile,
          sourceAddress: UcpAddresses.device,
          destinationAddress: UcpAddresses.software,
          op: OperationCodes.event,
          commandClass: CommandClasses.measurement,
          commandId: MeasurementCommandIds.startTest,
          sequence: 11,
          flags: 0,
          payload: TlvBuilder()
              .addUint16BE(TlvTypes.statusCode, 0)
              .addUint8(TlvTypes.sampleSizePercent, 100)
              .build(),
        ),
      );
      await _drainQueue();

      expect(client.currentSession?.measurementActive, isTrue);

      transport.simulateIncomingData(
        frameBuilder.build(
          version: 1,
          productId: ProductIds.aunkurUcp1,
          profileId: ProfileIds.defaultProfile,
          sourceAddress: UcpAddresses.device,
          destinationAddress: UcpAddresses.software,
          op: OperationCodes.event,
          commandClass: CommandClasses.measurement,
          commandId: MeasurementCommandIds.startTest,
          sequence: 12,
          flags: 0,
          payload: TlvBuilder()
              .addUint16BE(TlvTypes.statusCode, 0)
              .addUtf8(TlvTypes.messageText, 'SOIL_TEST_ERROR')
              .addUint8(TlvTypes.fwStateU8, 6)
              .build(),
        ),
      );
      await _drainQueue();

      expect(client.currentSession?.measurementActive, isFalse);
      expect(client.currentSession?.state, DeviceConnectionState.sessionActive);
    });

    test('emits basic communication logs with a stable session id', () async {
      await client.dispose();
      await transport.dispose();
      transport = FakeTransport();
      client = UnifiedDeviceClient(
        UnifiedDeviceClientConfig(
          transport: transport,
          logMode: UcpLogMode.basic,
        ),
      );

      final logs = <DeviceCommunicationLog>[];
      final subscription = client.communicationLogs.listen(logs.add);
      addTearDown(subscription.cancel);

      await _completeBootstrapForClient(
        client: client,
        transport: transport,
        frameBuilder: frameBuilder,
        frameParser: frameParser,
      );
      await _drainQueue();

      expect(logs, isNotEmpty);
      expect(
        logs.map((log) => log.param['event']),
        containsAll(<String>[
          'connected',
          'mtu_ready',
          'session_open_started',
          'session_active',
        ]),
      );
      expect(logs.map((log) => log.sessionId).toSet(), hasLength(1));
      expect(logs.every((log) => log.deviceId == 'dev-1'), isTrue);
      expect(
        logs.every((log) => log.deviceName == BleConstants.defaultDeviceName),
        isTrue,
      );
    });

    test(
      'emits raw packet details when raw communication logging is enabled',
      () async {
        await client.dispose();
        await transport.dispose();
        transport = FakeTransport();
        client = UnifiedDeviceClient(
          UnifiedDeviceClientConfig(
            transport: transport,
            logMode: UcpLogMode.raw,
          ),
        );

        final logs = <DeviceCommunicationLog>[];
        final subscription = client.communicationLogs.listen(logs.add);
        addTearDown(subscription.cancel);

        await _completeBootstrapForClient(
          client: client,
          transport: transport,
          frameBuilder: frameBuilder,
          frameParser: frameParser,
        );
        await _drainQueue();

        final packetLog = logs.firstWhere(
          (log) => log.param['event'] == 'packet_tx',
        );

        expect(packetLog.param['bytesHex'], isA<String>());
        expect(packetLog.param['tlvs'], isA<List<dynamic>>());
      },
    );
  });
}

Future<void> _completeBootstrapForClient({
  required UnifiedDeviceClient client,
  required FakeTransport transport,
  required FrameBuilder frameBuilder,
  required FrameParser frameParser,
}) async {
  final connectFuture = client.connect(
    DiscoveredDevice(
      deviceId: 'dev-1',
      name: BleConstants.defaultDeviceName,
      rssi: -42,
    ),
  );
  await _completeBootstrap(
    transport: transport,
    frameBuilder: frameBuilder,
    frameParser: frameParser,
  );
  await connectFuture;
}
