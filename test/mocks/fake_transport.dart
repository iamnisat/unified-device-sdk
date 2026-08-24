import 'dart:async';
import 'package:unified_device_sdk/unified_device_sdk.dart';

/// A fake transport implementation for testing.
class FakeTransport implements DeviceTransport {
  final StreamController<DiscoveredDevice> _discoveryController =
      StreamController<DiscoveredDevice>.broadcast();

  final StreamController<DeviceConnectionState> _connectionStateController =
      StreamController<DeviceConnectionState>.broadcast();

  final StreamController<List<int>> _incomingController =
      StreamController<List<int>>.broadcast();

  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  String? _connectedDeviceId;
  String? _connectedDeviceName;
  bool _isScanning = false;
  bool _isDisposed = false;

  /// List of written data chunks for inspection.
  final List<List<int>> writtenData = [];

  /// Whether to simulate errors.
  bool simulateErrors = false;

  @override
  Stream<DiscoveredDevice> get discoveredDevices => _discoveryController.stream;

  @override
  Stream<DeviceConnectionState> get connectionState =>
      _connectionStateController.stream;

  @override
  Stream<List<int>> get incomingBytes => _incomingController.stream;

  @override
  bool get isScanning => _isScanning;

  @override
  bool get isConnected => _connectionState == DeviceConnectionState.connected;

  @override
  String? get connectedDeviceId => _connectedDeviceId;

  @override
  String? get connectedDeviceName => _connectedDeviceName;

  @override
  int get negotiatedMtu => _negotiatedMtu;

  final int _negotiatedMtu = 0;

  @override
  Future<void> startScan() async {
    _isScanning = true;
  }

  @override
  Future<void> stopScan() async {
    _isScanning = false;
  }

  @override
  Future<void> connect(DiscoveredDevice device) async {
    if (simulateErrors) {
      throw Exception('Simulated connection error');
    }
    _connectionState = DeviceConnectionState.connected;
    _connectedDeviceId = device.deviceId;
    _connectedDeviceName = device.name;
    _connectionStateController.add(_connectionState);
    _connectionState = DeviceConnectionState.mtuReady;
    _connectionStateController.add(_connectionState);
  }

  @override
  Future<void> disconnect() async {
    _connectionState = DeviceConnectionState.disconnected;
    _connectedDeviceId = null;
    _connectedDeviceName = null;
    _connectionStateController.add(_connectionState);
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (simulateErrors) {
      throw Exception('Simulated write error');
    }
    writtenData.add(List.unmodifiable(bytes));
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _discoveryController.close();
    await _connectionStateController.close();
    await _incomingController.close();
    _isScanning = false;
    _connectionState = DeviceConnectionState.disconnected;
    _connectedDeviceId = null;
    _connectedDeviceName = null;
  }

  /// Simulates receiving data from a device.
  void simulateIncomingData(List<int> data) {
    _incomingController.add(data);
  }

  /// Simulates a device being discovered.
  void simulateDeviceDiscovered(DiscoveredDevice device) {
    _discoveryController.add(device);
  }

  /// Simulates a transport connection state update.
  void simulateConnectionState(
    DeviceConnectionState state, {
    String? deviceId,
  }) {
    _connectionState = state;
    _connectedDeviceId = state == DeviceConnectionState.connected
        ? deviceId
        : null;
    if (state != DeviceConnectionState.connected) {
      _connectedDeviceName = null;
    }
    _connectionStateController.add(state);
  }
}
