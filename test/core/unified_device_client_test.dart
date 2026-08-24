
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

  final transportOpenRequest = frameParser.parse(transport.writtenData[0]);
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
      sequence: transportOpenRequest.sequence,
      flags: 0,
    ),
  );

  await _drainQueue();
  expect(transport.writtenData, hasLength(2));

  final sessionOpenRequest = frameParser.parse(transport.writtenData[1]);
  transport.simulateIncomingData(
    frameBuilder.build(
      version: 1,
      productId: ProductIds.aunkurUcp1,
      profileId: ProfileIds.dummyM2m,
      sourceAddress: UcpAddresses.device,
      destinationAddress: UcpAddresses.software,
      op: OperationCodes.ack,
      commandClass: CommandClasses.session,
      commandId: SessionCommandIds.sessionOpenRtcSync,
      sequence: sessionOpenRequest.sequence,
      flags: 0,
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

        final transportOpenRequest = frameParser.parse(
          transport.writtenData[0],
        );
        final sessionOpenRequest = frameParser.parse(transport.writtenData[1]);

        expect(transportOpenRequest.commandClass, CommandClasses.session);
        expect(
          transportOpenRequest.commandId,
          SessionCommandIds.btTransportOpen,
        );
        expect(sessionOpenRequest.commandClass, CommandClasses.session);
        expect(
          sessionOpenRequest.commandId,
          SessionCommandIds.sessionOpenRtcSync,
        );
        expect(states, contains(DeviceConnectionState.transportReady));
        expect(client.isSessionActive, isTrue);
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
          'transport_ready',
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
