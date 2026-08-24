import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'connection_state.dart';
import 'device_transport.dart';
import 'discovered_device.dart';
import '../client/unified_device_hardware_profile.dart';
import '../../platform/platform_event_mapper.dart';
import '../../platform/unified_device_platform.dart';

/// BLE implementation of [DeviceTransport] backed by [UnifiedDevicePlatform].
///
/// This transport is intentionally byte-oriented only. It delegates BLE
/// operations to the platform layer and exposes typed streams for discovery,
/// connection state, and incoming notification bytes.
class BleTransport implements DeviceTransport {
  final UnifiedDevicePlatform _platform;
  final BleGattProfile _bleProfile;

  final StreamController<DiscoveredDevice> _discoveredDevicesController =
      StreamController<DiscoveredDevice>.broadcast();
  final StreamController<DeviceConnectionState> _connectionStateController =
      StreamController<DeviceConnectionState>.broadcast();
  final StreamController<List<int>> _incomingBytesController =
      StreamController<List<int>>.broadcast();

  StreamSubscription<Map<String, dynamic>>? _scanSubscription;
  StreamSubscription<Map<String, dynamic>>? _connectionSubscription;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;

  int _negotiatedMtu = 0;
  DeviceConnectionState _currentConnectionState =
      DeviceConnectionState.disconnected;
  String? _connectedDeviceId;
  String? _connectedDeviceName;
  bool _isScanning = false;
  bool _isDisposed = false;

  /// Creates a BLE transport using the configured platform implementation.
  BleTransport({UnifiedDevicePlatform? platform, BleGattProfile? bleProfile})
    : _platform = platform ?? UnifiedDevicePlatform.instance,
      _bleProfile = bleProfile ?? const BleGattProfile() {
    _bindPlatformStreams();
  }

  @override
  Stream<DiscoveredDevice> get discoveredDevices =>
      _discoveredDevicesController.stream;

  @override
  Stream<DeviceConnectionState> get connectionState =>
      _connectionStateController.stream;

  @override
  Stream<List<int>> get incomingBytes => _incomingBytesController.stream;

  @override
  bool get isScanning => _isScanning;

  @override
  bool get isConnected =>
      _connectedDeviceId != null &&
      _currentConnectionState != DeviceConnectionState.disconnected &&
      _currentConnectionState != DeviceConnectionState.disconnecting &&
      _currentConnectionState != DeviceConnectionState.error &&
      _currentConnectionState != DeviceConnectionState.connectionLost;

  @override
  String? get connectedDeviceId => _connectedDeviceId;

  @override
  String? get connectedDeviceName => _connectedDeviceName;

  @override
  int get negotiatedMtu => _negotiatedMtu;

  void _bindPlatformStreams() {
    _scanSubscription = _platform.scanResults.listen(
      _handleScanResult,
      onError: _discoveredDevicesController.addError,
    );

    _connectionSubscription = _platform.connectionState.listen(
      _handleConnectionState,
      onError: _handleConnectionError,
    );

    _notificationSubscription = _platform.notificationData.listen(
      _handleNotificationData,
      onError: _incomingBytesController.addError,
    );
  }

  void _handleScanResult(Map<String, dynamic> event) {
    final mapped = PlatformEventMapper.mapScanResult(event);

    try {
      _discoveredDevicesController.add(
        DiscoveredDevice(
          deviceId: mapped['deviceId'] as String,
          name: mapped['name'] as String?,
          rssi: mapped['rssi'] as int,
          manufacturerData: _decodeBytes(mapped['manufacturerData']),
          serviceUuids: List<String>.from(
            mapped['serviceUuids'] as List<dynamic>,
          ),
        ),
      );
    } on Object catch (error, stackTrace) {
      _discoveredDevicesController.addError(error, stackTrace);
    }
  }

  void _handleConnectionState(Map<String, dynamic> event) {
    final mapped = PlatformEventMapper.mapConnectionState(event);
    final nextState = _mapConnectionState(mapped['state'] as String);
    final deviceId = mapped['deviceId'] as String?;
    final mtu = mapped['mtu'] as int?;

    _currentConnectionState = nextState;
    if (nextState == DeviceConnectionState.connected ||
        nextState == DeviceConnectionState.servicesDiscovered ||
        nextState == DeviceConnectionState.notifySubscribed ||
        nextState == DeviceConnectionState.mtuReady) {
      _connectedDeviceId = deviceId;
    } else if (nextState == DeviceConnectionState.disconnected ||
        nextState == DeviceConnectionState.error ||
        nextState == DeviceConnectionState.connectionLost) {
      _connectedDeviceId = null;
      _connectedDeviceName = null;
      _negotiatedMtu = 0;
    }

    if (mtu != null && mtu > 0) {
      _negotiatedMtu = mtu;
    }

    _connectionStateController.add(nextState);
  }

  void _handleConnectionError(Object error, StackTrace stackTrace) {
    _currentConnectionState = DeviceConnectionState.disconnected;
    _connectedDeviceId = null;
    _connectedDeviceName = null;
    _connectionStateController.addError(error, stackTrace);
  }

  void _handleNotificationData(Map<String, dynamic> event) {
    final mapped = PlatformEventMapper.mapNotificationData(event);

    try {
      final bytes = _decodeBytes(mapped['data']);
      if (bytes != null) {
        _incomingBytesController.add(bytes);
      }
    } on Object catch (error, stackTrace) {
      _incomingBytesController.addError(error, stackTrace);
    }
  }

  DeviceConnectionState _mapConnectionState(String value) {
    switch (value) {
      case 'connecting':
        return DeviceConnectionState.connecting;
      case 'connected':
      case 'ready':
        return DeviceConnectionState.connected;
      case 'servicesDiscovered':
        return DeviceConnectionState.servicesDiscovered;
      case 'notifySubscribed':
        return DeviceConnectionState.notifySubscribed;
      case 'mtuReady':
        return DeviceConnectionState.mtuReady;
      case 'disconnecting':
        return DeviceConnectionState.disconnecting;
      case 'error':
        return DeviceConnectionState.error;
      case 'connectionLost':
        return DeviceConnectionState.connectionLost;
      case 'disconnected':
      default:
        return DeviceConnectionState.disconnected;
    }
  }

  @override
  Future<void> startScan() async {
    _throwIfDisposed();
    await _platform.startScan(bleProfile: _bleProfile);
    _isScanning = true;
    _connectionStateController.add(DeviceConnectionState.scanning);
  }

  @override
  Future<void> stopScan() async {
    _throwIfDisposed();
    await _platform.stopScan();
    _isScanning = false;
    if (_currentConnectionState == DeviceConnectionState.disconnected) {
      _connectionStateController.add(DeviceConnectionState.disconnected);
    }
  }

  @override
  Future<void> connect(DiscoveredDevice device) async {
    _throwIfDisposed();
    if (_isScanning) {
      _isScanning = false;
    }
    _connectedDeviceName = device.name;
    await _platform.connect(device.deviceId, bleProfile: _bleProfile);
  }

  @override
  Future<void> disconnect() async {
    _throwIfDisposed();
    await _platform.disconnect();
  }

  @override
  Future<void> write(List<int> bytes) async {
    _throwIfDisposed();
    await _platform.write(bytes);
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;

    await _scanSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _notificationSubscription?.cancel();
    await _platform.dispose();

    _isScanning = false;
    _currentConnectionState = DeviceConnectionState.disconnected;
    _connectedDeviceId = null;
    _connectedDeviceName = null;

    await _discoveredDevicesController.close();
    await _connectionStateController.close();
    await _incomingBytesController.close();
  }

  void _throwIfDisposed() {
    if (_isDisposed) {
      throw StateError('BleTransport has been disposed');
    }
  }

  static List<int>? _decodeBytes(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      if (value.isEmpty) {
        return null;
      }
      return base64Decode(value);
    }
    if (value is Uint8List) {
      return value;
    }
    if (value is List<int>) {
      return value;
    }
    return null;
  }
}
