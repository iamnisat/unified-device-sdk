import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/client/unified_device_hardware_profile.dart';
import 'unified_device_platform.dart';

const _bleChannel = MethodChannel('unified_device_sdk/ble');
const _scanEventChannel = EventChannel('unified_device_sdk/ble/scan');
const _connectionEventChannel = EventChannel(
  'unified_device_sdk/ble/connection',
);
const _notificationEventChannel = EventChannel(
  'unified_device_sdk/ble/notification',
);

/// Method channel implementation of [UnifiedDevicePlatform].
///
/// This class handles all communication between Dart and native platform code
/// through Flutter's method channels and event channels.
///
/// ## Method Channel Contract
///
/// ### BLE Methods (`unified_device_sdk/ble`)
///
/// | Method | Arguments | Returns | Description |
/// |--------|-----------|---------|-------------|
/// | `startScan` | none | `null` | Start BLE scan |
/// | `stopScan` | none | `null` | Stop BLE scan |
/// | `connect` | `{deviceId: String}` | `null` | Connect to device |
/// | `disconnect` | none | `null` | Disconnect from device |
/// | `write` | `{data: Uint8List}` | `null` | Write bytes to device |
///
/// ### Event Channels
///
/// | Channel | Event Payload | Description |
/// |---------|--------------|-------------|
/// | `unified_device_sdk/ble/scan` | `{deviceId, name, rssi, manufacturerData?, serviceUuids?}` | Device discovered |
/// | `unified_device_sdk/ble/connection` | `{state, deviceId?, message?}` | Connection state change |
/// | `unified_device_sdk/ble/notification` | `{data: base64String|Uint8List}` or `Uint8List` | Notification data received |
class MethodChannelUnifiedDevice extends UnifiedDevicePlatform {
  /// The main method channel for platform queries.
  @visibleForTesting
  final methodChannel = const MethodChannel('unified_device_sdk');

  /// Stream of scan result maps from the native BLE scanner.
  ///
  /// Each event map has the following keys:
  /// - `deviceId` (String): The device identifier.
  /// - `name` (String?): The advertised device name.
  /// - `rssi` (int): Signal strength in dBm.
  /// - `manufacturerData` (String?): Base64-encoded manufacturer data.
  /// - `serviceUuids` (`List<String>?`): List of advertised service UUIDs.
  @override
  Stream<Map<String, dynamic>> get scanResults => _scanEventChannel
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));

  /// Stream of connection state maps from the native BLE connection.
  ///
  /// Each event map has the following keys:
  /// - `state` (String): One of `connecting`, `connected`, `disconnecting`,
  ///   `disconnected`, `connectionLost`.
  /// - `deviceId` (String?): The device identifier.
  @override
  Stream<Map<String, dynamic>> get connectionState => _connectionEventChannel
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));

  /// Stream of notification data maps from the native BLE notifications.
  ///
  /// Each event map has the following keys:
  /// - `data` (String): Base64-encoded byte data.
  @override
  Stream<Map<String, dynamic>> get notificationData =>
      _notificationEventChannel.receiveBroadcastStream().map((event) {
        if (event is Map) {
          return Map<String, dynamic>.from(event);
        } else if (event is Uint8List) {
          return {'data': event};
        } else {
          throw ArgumentError('Unsupported event type: ${event.runtimeType}');
        }
      });

  // ---- Platform Queries ----

  @override
  Future<String?> getPlatformVersion() async {
    return await methodChannel.invokeMethod<String>('getPlatformVersion');
  }

  @override
  Future<bool> isBluetoothAvailable() async {
    final result = await methodChannel.invokeMethod<bool>(
      'isBluetoothAvailable',
    );
    return result ?? false;
  }

  @override
  Future<bool> isBluetoothEnabled() async {
    final result = await methodChannel.invokeMethod<bool>('isBluetoothEnabled');
    return result ?? false;
  }

  @override
  Future<bool> requestBluetoothPermissions() async {
    final result = await methodChannel.invokeMethod<bool>(
      'requestBluetoothPermissions',
    );
    return result ?? false;
  }

  // ---- BLE Methods ----

  /// Starts scanning for BLE devices.
  @override
  Future<void> startScan({BleGattProfile? bleProfile}) async {
    await _bleChannel.invokeMethod('startScan', bleProfile?.toJson());
  }

  /// Stops scanning for BLE devices.
  @override
  Future<void> stopScan() async {
    await _bleChannel.invokeMethod('stopScan');
  }

  /// Connects to a BLE device by its identifier.
  @override
  Future<void> connect(String deviceId, {BleGattProfile? bleProfile}) async {
    await _bleChannel.invokeMethod('connect', {
      'deviceId': deviceId,
      if (bleProfile != null) ...bleProfile.toJson(),
    });
  }

  /// Disconnects from the currently connected device.
  @override
  Future<void> disconnect() async {
    await _bleChannel.invokeMethod('disconnect');
  }

  /// Writes raw bytes to the connected device.
  ///
  /// [data] is sent as raw bytes to the native layer.
  @override
  Future<void> write(List<int> data) async {
    await _bleChannel.invokeMethod('write', {'data': Uint8List.fromList(data)});
  }

  /// Disposes resources (no-op as EventChannels are dynamically mapped).
  @override
  Future<void> dispose() async {}
}
