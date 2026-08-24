import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

class FakeUnifiedDevicePlatform extends UnifiedDevicePlatform {
  final StreamController<Map<String, dynamic>> _scanResultsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _connectionStateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _notificationDataController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool startScanCalled = false;
  bool stopScanCalled = false;
  bool disconnectCalled = false;
  bool disposeCalled = false;
  String? connectDeviceId;
  BleGattProfile? lastScanProfile;
  BleGattProfile? lastConnectProfile;
  List<int>? lastWrite;

  @override
  Stream<Map<String, dynamic>> get scanResults => _scanResultsController.stream;

  @override
  Stream<Map<String, dynamic>> get connectionState =>
      _connectionStateController.stream;

  @override
  Stream<Map<String, dynamic>> get notificationData =>
      _notificationDataController.stream;

  @override
  Future<void> startScan({BleGattProfile? bleProfile}) async {
    startScanCalled = true;
    lastScanProfile = bleProfile;
  }

  @override
  Future<void> stopScan() async {
    stopScanCalled = true;
  }

  @override
  Future<void> connect(String deviceId, {BleGattProfile? bleProfile}) async {
    connectDeviceId = deviceId;
    lastConnectProfile = bleProfile;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
  }

  @override
  Future<void> write(List<int> data) async {
    lastWrite = List<int>.from(data);
  }

  @override
  Future<void> dispose() async {
    disposeCalled = true;
    await _scanResultsController.close();
    await _connectionStateController.close();
    await _notificationDataController.close();
  }

  void emitScanResult({
    required String deviceId,
    String? name,
    required int rssi,
    List<int>? manufacturerData,
    List<String>? serviceUuids,
  }) {
    _scanResultsController.add({
      'deviceId': deviceId,
      'name': name,
      'rssi': rssi,
      if (manufacturerData != null)
        'manufacturerData': base64Encode(manufacturerData),
      if (serviceUuids != null) 'serviceUuids': serviceUuids,
    });
  }

  void emitConnectionState(String state, {String? deviceId}) {
    _connectionStateController.add({
      'state': state,
      if (deviceId != null) 'deviceId': deviceId,
    });
  }

  void emitNotification(List<int> data) {
    _notificationDataController.add({'data': base64Encode(data)});
  }

  void emitScanError(Object error) {
    _scanResultsController.addError(error);
  }

  void emitConnectionError(Object error) {
    _connectionStateController.addError(error);
  }

  void emitNotificationError(Object error) {
    _notificationDataController.addError(error);
  }
}

Future<void> _drainEventQueue() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('BleTransport', () {
    late FakeUnifiedDevicePlatform platform;
    late BleTransport transport;

    setUp(() {
      platform = FakeUnifiedDevicePlatform();
      transport = BleTransport(platform: platform);
    });

    tearDown(() async {
      await transport.dispose();
    });

    test('delegates scan lifecycle calls to platform', () async {
      await transport.startScan();
      expect(platform.startScanCalled, isTrue);
      expect(transport.isScanning, isTrue);

      await transport.stopScan();
      expect(platform.stopScanCalled, isTrue);
      expect(transport.isScanning, isFalse);
    });

    test('delegates connect, disconnect, and write to platform', () async {
      final device = DiscoveredDevice(deviceId: 'dev-1', rssi: -42);

      await transport.connect(device);
      await transport.write([1, 2, 3]);
      await transport.disconnect();

      expect(platform.connectDeviceId, 'dev-1');
      expect(platform.lastWrite, [1, 2, 3]);
      expect(platform.disconnectCalled, isTrue);
    });

    test('passes configured GATT profile to scan and connect', () async {
      final profilePlatform = FakeUnifiedDevicePlatform();
      const bleProfile = BleGattProfile(
        serviceUuid: '1234',
        notifyCharacteristicUuid: '1235',
        writeCharacteristicUuid: '1236',
      );
      final profileTransport = BleTransport(
        platform: profilePlatform,
        bleProfile: bleProfile,
      );
      addTearDown(profileTransport.dispose);

      final device = DiscoveredDevice(deviceId: 'dev-1', rssi: -42);
      await profileTransport.startScan();
      await profileTransport.connect(device);

      expect(profilePlatform.lastScanProfile, same(bleProfile));
      expect(profilePlatform.lastConnectProfile, same(bleProfile));
    });

    test('maps scan result events to discovered device stream', () async {
      final events = <DiscoveredDevice>[];
      final subscription = transport.discoveredDevices.listen(events.add);
      addTearDown(subscription.cancel);

      platform.emitScanResult(
        deviceId: 'AA:BB:CC:DD',
        name: 'Device',
        rssi: -60,
        manufacturerData: [0x10, 0x20],
        serviceUuids: ['1234', '5678'],
      );
      await _drainEventQueue();

      expect(events, hasLength(1));
      expect(events.single.deviceId, 'AA:BB:CC:DD');
      expect(events.single.name, 'Device');
      expect(events.single.rssi, -60);
      expect(events.single.manufacturerData, [0x10, 0x20]);
      expect(events.single.serviceUuids, ['1234', '5678']);
    });

    test('forwards scan stream errors', () async {
      final errors = <Object>[];
      final subscription = transport.discoveredDevices.listen(
        (_) {},
        onError: errors.add,
      );
      addTearDown(subscription.cancel);

      platform.emitScanError(StateError('scan failed'));
      await _drainEventQueue();

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    });

    test('maps connection state events to connection stream', () async {
      final states = <DeviceConnectionState>[];
      final subscription = transport.connectionState.listen(states.add);
      addTearDown(subscription.cancel);

      platform.emitConnectionState('connecting', deviceId: 'dev-1');
      platform.emitConnectionState('connected', deviceId: 'dev-1');
      platform.emitConnectionState('disconnecting', deviceId: 'dev-1');
      platform.emitConnectionState('disconnected', deviceId: 'dev-1');
      await _drainEventQueue();

      expect(states, [
        DeviceConnectionState.connecting,
        DeviceConnectionState.connected,
        DeviceConnectionState.disconnecting,
        DeviceConnectionState.disconnected,
      ]);
      expect(transport.isConnected, isFalse);
      expect(transport.connectedDeviceId, isNull);
    });

    test('tracks connected device id from platform events', () async {
      final states = <DeviceConnectionState>[];
      final subscription = transport.connectionState.listen(states.add);
      addTearDown(subscription.cancel);

      platform.emitConnectionState('connected', deviceId: 'dev-9');
      await _drainEventQueue();

      expect(states.single, DeviceConnectionState.connected);
      expect(transport.isConnected, isTrue);
      expect(transport.connectedDeviceId, 'dev-9');
    });

    test('forwards connection stream errors', () async {
      final errors = <Object>[];
      final subscription = transport.connectionState.listen(
        (_) {},
        onError: errors.add,
      );
      addTearDown(subscription.cancel);

      platform.emitConnectionError(StateError('connection failed'));
      await _drainEventQueue();

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect(transport.isConnected, isFalse);
      expect(transport.connectedDeviceId, isNull);
    });

    test('maps notification events to incoming bytes stream', () async {
      final dataEvents = <List<int>>[];
      final subscription = transport.incomingBytes.listen(dataEvents.add);
      addTearDown(subscription.cancel);

      platform.emitNotification([0xAA, 0xBB, 0xCC]);
      await _drainEventQueue();

      expect(dataEvents, [
        [0xAA, 0xBB, 0xCC],
      ]);
    });

    test('forwards notification stream errors', () async {
      final errors = <Object>[];
      final subscription = transport.incomingBytes.listen(
        (_) {},
        onError: errors.add,
      );
      addTearDown(subscription.cancel);

      platform.emitNotificationError(StateError('notify failed'));
      await _drainEventQueue();

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    });

    test(
      'dispose releases platform resources and resets local state',
      () async {
        await transport.startScan();
        platform.emitConnectionState('connected', deviceId: 'dev-4');
        await _drainEventQueue();

        await transport.dispose();

        expect(platform.disposeCalled, isTrue);
        expect(transport.isScanning, isFalse);
        expect(transport.isConnected, isFalse);
        expect(transport.connectedDeviceId, isNull);
      },
    );
  });
}
