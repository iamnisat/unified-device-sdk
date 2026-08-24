import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:unified_device_sdk_example/main.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

void main() {
  testWidgets('renders debug console shell', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(platform: _FakePlatform()));
    await tester.pumpAndSettle();

    expect(find.text('Unified Device Debug Console'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });
}

class _FakePlatform extends UnifiedDevicePlatform {
  final StreamController<Map<String, dynamic>> _scanController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _connectionController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get connectionState =>
      _connectionController.stream;

  @override
  Stream<Map<String, dynamic>> get notificationData =>
      _notificationController.stream;

  @override
  Stream<Map<String, dynamic>> get scanResults => _scanController.stream;

  @override
  Future<void> connect(String deviceId, {BleGattProfile? bleProfile}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    await _scanController.close();
    await _connectionController.close();
    await _notificationController.close();
  }

  @override
  Future<String?> getPlatformVersion() async => 'Android Test';

  @override
  Future<bool> isBluetoothAvailable() async => true;

  @override
  Future<bool> isBluetoothEnabled() async => true;

  @override
  Future<bool> requestBluetoothPermissions() async => true;

  @override
  Future<void> startScan({BleGattProfile? bleProfile}) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> write(List<int> data) async {}
}
