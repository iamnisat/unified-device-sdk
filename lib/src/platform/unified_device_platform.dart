import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../core/client/unified_device_hardware_profile.dart';
import 'method_channel_unified_device.dart';

/// Platform interface for the Unified Device SDK.
///
/// This is the contract between Dart and native (Android/iOS) code.
/// Native implementations must extend this class.
///
/// ## Method Channels
///
/// ### Main Channel: `unified_device_sdk`
/// Used for platform queries (version, BLE availability).
///
/// ### BLE Channel: `unified_device_sdk/ble`
/// Used for BLE operations. See [MethodChannelUnifiedDevice].
///
/// ### BLE Scan Event Channel: `unified_device_sdk/ble/scan`
/// ### BLE Connection Event Channel: `unified_device_sdk/ble/connection`
/// ### BLE Notification Event Channel: `unified_device_sdk/ble/notification`
///
/// See [MethodChannelUnifiedDevice] for detailed method/event channel contracts.
abstract class UnifiedDevicePlatform extends PlatformInterface {
  /// Constructs a [UnifiedDevicePlatform].
  UnifiedDevicePlatform() : super(token: _token);

  static final Object _token = Object();

  static UnifiedDevicePlatform? _instance;

  /// The default instance of [UnifiedDevicePlatform] to use.
  static UnifiedDevicePlatform get instance {
    _instance ??= MethodChannelUnifiedDevice();
    return _instance!;
  }

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [UnifiedDevicePlatform] when
  /// they register themselves.
  static set instance(UnifiedDevicePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // ---- Platform Queries ----

  /// Returns the platform version string (e.g., "Android 14" or "iOS 17.0").
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  /// Returns whether Bluetooth is available on this device.
  Future<bool> isBluetoothAvailable() {
    throw UnimplementedError(
      'isBluetoothAvailable() has not been implemented.',
    );
  }

  /// Returns whether Bluetooth is currently enabled.
  Future<bool> isBluetoothEnabled() {
    throw UnimplementedError('isBluetoothEnabled() has not been implemented.');
  }

  /// Requests Bluetooth permissions from the user.
  ///
  /// Returns `true` if permissions were granted.
  Future<bool> requestBluetoothPermissions() {
    throw UnimplementedError(
      'requestBluetoothPermissions() has not been implemented.',
    );
  }

  // ---- BLE Event Streams ----

  /// Stream of raw scan result event maps from the platform BLE layer.
  Stream<Map<String, dynamic>> get scanResults {
    throw UnimplementedError('scanResults has not been implemented.');
  }

  /// Stream of raw connection state event maps from the platform BLE layer.
  Stream<Map<String, dynamic>> get connectionState {
    throw UnimplementedError('connectionState has not been implemented.');
  }

  /// Stream of raw notification event maps from the platform BLE layer.
  Stream<Map<String, dynamic>> get notificationData {
    throw UnimplementedError('notificationData has not been implemented.');
  }

  // ---- BLE Operations ----

  /// Starts scanning for BLE devices.
  Future<void> startScan({BleGattProfile? bleProfile}) {
    throw UnimplementedError('startScan() has not been implemented.');
  }

  /// Stops scanning for BLE devices.
  Future<void> stopScan() {
    throw UnimplementedError('stopScan() has not been implemented.');
  }

  /// Connects to a BLE device by its platform identifier.
  Future<void> connect(String deviceId, {BleGattProfile? bleProfile}) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  /// Disconnects from the currently connected BLE device.
  Future<void> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  /// Writes raw bytes to the currently connected BLE device.
  Future<void> write(List<int> data) {
    throw UnimplementedError('write() has not been implemented.');
  }

  /// Releases platform resources for BLE streams and channels.
  Future<void> dispose() {
    throw UnimplementedError('dispose() has not been implemented.');
  }
}
