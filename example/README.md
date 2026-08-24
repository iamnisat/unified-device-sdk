# Unified Device SDK Example 📡

A practical Flutter example for integrating `unified_device_sdk` into a mobile app. This SDK provides BLE scanning, connection management, UCP session bootstrap, frame parsing, CRC validation, command execution, packet tracing, and decoded device data streams.

## What This Example Shows ✨

- 🔍 Scan for supported BLE devices
- 🔗 Connect and disconnect from a selected device
- ✅ Bootstrap a UCP session automatically after BLE connection
- 🧾 Read device information and device time
- 🌱 Run the soil-test workflow
- 💧 Start and stop live moisture streaming
- 📊 Fetch the latest soil test report
- 🧩 Send built-in and custom UCP commands
- 🧪 View packet traces, SDK logs, ACK/DATA/EVENT responses, and errors

## Requirements 🛠️

- Flutter SDK with Dart `^3.9.2`
- Android device with BLE support, or iOS device with Bluetooth support
- Android SDK platform installed for your target SDK
- Android NDK installed when building the example app
- A compatible Unified Device BLE peripheral

The verified example Android build uses:

- Gradle `8.14.1`
- Android Gradle Plugin `8.11.1`
- Kotlin Gradle Plugin `2.2.20`
- NDK `29.0.13113456`

## Install the Package 📦

For a published package, add it to your Flutter app:

```yaml
dependencies:
  unified_device_sdk: ^0.0.1
```

For local development from this repository:

```yaml
dependencies:
  unified_device_sdk:
    path: ../unified_device_sdk
```

Then run:

```bash
flutter pub get
```

Import the SDK:

```dart
import 'package:unified_device_sdk/unified_device_sdk.dart';
```

## Platform Setup ⚙️

### Android

Add Bluetooth permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-feature
    android:name="android.hardware.bluetooth_le"
    android:required="false" />

<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

Use compatible Android build versions in your app:

```kotlin
// android/settings.gradle.kts
plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}
```

```properties
# android/gradle/wrapper/gradle-wrapper.properties
distributionUrl=https\://services.gradle.org/distributions/gradle-8.14.1-all.zip
```

If your machine has a specific NDK installed, pin it in `android/app/build.gradle.kts`:

```kotlin
android {
    ndkVersion = "29.0.13113456"
}
```

### iOS

Add Bluetooth usage descriptions to `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to scan for and connect to supported BLE devices.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app uses Bluetooth to communicate with supported BLE devices.</string>
```

Then install pods:

```bash
cd ios
pod install
cd ..
```

## Quick Start 🚀

Create one client and keep it alive while the user is scanning, connecting, and sending commands.

```dart
final client = UnifiedDeviceClient.generic(
  logMode: UcpLogMode.basic,
  defaultTimeout: const Duration(seconds: 5),
);
```

Check Bluetooth status and request permissions:

```dart
final platform = UnifiedDevicePlatform.instance;

final bluetoothAvailable = await platform.isBluetoothAvailable();
final bluetoothEnabled = await platform.isBluetoothEnabled();
final permissionsGranted = await platform.requestBluetoothPermissions();
```

Listen for scan results:

```dart
final scanSub = client.discoveredDevices.listen((device) {
  print('${device.name} ${device.deviceId} RSSI=${device.rssi}');
});

await client.startScan();
```

Connect to a discovered device:

```dart
await client.stopScan();
await client.connect(device);

if (client.isSessionActive) {
  print('UCP session is ready');
}
```

Always clean up when the screen or service is finished:

```dart
await scanSub.cancel();
await client.disconnect();
await client.dispose();
```

## Connection State 🔄

Use `connectionState` to drive your UI:

```dart
final stateSub = client.connectionState.listen((state) {
  switch (state) {
    case DeviceConnectionState.scanning:
      print('Scanning...');
      break;
    case DeviceConnectionState.sessionActive:
      print('Ready to send UCP commands');
      break;
    case DeviceConnectionState.connectionLost:
      print('Connection lost');
      break;
    default:
      print('State: $state');
  }
});
```

Important states include:

| State | Meaning |
| --- | --- |
| `scanning` | BLE scan is active |
| `connecting` | Native BLE connection is in progress |
| `connected` | BLE link is connected |
| `servicesDiscovered` | Required GATT services were found |
| `notifySubscribed` | Notification characteristic is active |
| `mtuReady` | MTU negotiation completed or is ready |
| `transportReady` | BLE transport can send bytes |
| `sessionActive` | UCP session bootstrap completed |
| `measurementActive` | Soil/measurement workflow is running |
| `streamActive` | Live stream workflow is running |
| `disconnected` | Device is disconnected |
| `connectionLost` | Device disconnected unexpectedly |
| `error` | Native BLE layer reported an error |

## Built-in Commands 🧠

The SDK includes high-level helpers for common UCP operations.

### Device Info

```dart
final info = await client.deviceInfo();

print(info.deviceName);
print(info.firmwareVersion);
print(info.hardwareVersion);
print(info.batterySoc);
```

### Device Time

```dart
final time = await client.timeRead();

print(time.epochSeconds);
print(time.uptimeSeconds);
print(time.text);
```

### Soil Test

```dart
await client.startTest(
  agentId: 'AGENT-DEMO1',
  farmerId: 'FARMER-0012',
  fieldIndex: 'FIELD-A3',
  fieldTestIndex: 'TEST-0001',
);
```

Fetch the final/latest report:

```dart
final report = await client.lastReport();

print('N: ${report.nitrogen}');
print('P: ${report.phosphorus}');
print('K: ${report.potassium}');
print('Moisture: ${report.moisture}');
print('pH: ${report.ph}');
print('EC: ${report.ec}');
print('Temperature: ${report.temperature}');
```

### Moisture Stream

Start live moisture streaming:

```dart
final moistureSub = client.moistureSamples.listen((sample) {
  print('Moisture: ${sample.moisturePercent}%');
  print('Raw: ${sample.rawValue}');
});

await client.moistGetOn();
```

Stop live moisture streaming:

```dart
await client.moistGetOff();
await moistureSub.cancel();
```

### UI and Connectivity

```dart
await client.font('english');
await client.cdn('ELAB_SW_01');
```

### Calibration

```dart
await client.calibrationStart(sensorType: 1);
final status = await client.calibrationStatus();
await client.calibrationApply(
  sensorType: 1,
  calibrationData: <int>[0x01, 0x02, 0x03],
);
```

### Configuration

```dart
final config = await client.configRead(configKey: 1001);
await client.configWrite(
  configKey: 1001,
  configValue: <int>[0x01],
);
final allConfigs = await client.configList();
```

### Report History

```dart
final reports = await client.reportList();
final report = await client.reportGet(reportId: 123);
await client.reportExport(reportId: 123, format: 'json');
await client.reportDelete(reportId: 123);
```

### File Transfer

```dart
await client.fileTransferStart(
  fileName: 'firmware.bin',
  fileSize: fileBytes.length,
);

await client.fileTransferChunk(
  offset: 0,
  chunkData: fileBytes.take(128).toList(),
);

final transferStatus = await client.fileTransferStatus();

await client.fileTransferEnd(transferId: 1);
```

## Custom Commands 🧩

Use `sendCommand` when you need direct access to the UCP command fields.

```dart
final response = await client.sendCommand(
  productId: ProductIds.aunkurUcp1,
  profileId: ProfileIds.defaultProfile,
  sourceAddress: UcpAddresses.software,
  destinationAddress: UcpAddresses.device,
  op: OperationCodes.req,
  commandClass: CommandClasses.system,
  commandId: SystemCommandIds.deviceInfo,
  options: const CommandOptions(
    waitForAck: true,
    waitForData: true,
  ),
);

if (response.isSuccess) {
  print('Payload bytes: ${response.payload}');
}
```

Build TLV payloads with `TlvBuilder`:

```dart
final payload = TlvBuilder()
    .addUtf8(TlvTypes.agentId, 'AGENT-DEMO1')
    .addUint16BE(TlvTypes.configKeyU16, 1001)
    .addBytes(TlvTypes.configValue, <int>[0x01])
    .build();
```

## Streams and Debugging 🧪

The client exposes streams for app UI, diagnostics, and protocol-level inspection.

```dart
client.events.listen((event) {
  print('EVENT: $event');
});

client.dataResponses.listen((response) {
  print('DATA response: ${response.payload.length} bytes');
});

client.frames.listen((frame) {
  print('Frame sequence: ${frame.sequence}');
});

client.packetTraces.listen((trace) {
  print(trace);
});

client.communicationLogs.listen((log) {
  print(log.toJson());
});
```

Logging modes:

| Mode | Use case |
| --- | --- |
| `UcpLogMode.off` | Disable SDK communication logs |
| `UcpLogMode.errorOnly` | Capture only failures |
| `UcpLogMode.basic` | Lifecycle and command summaries |
| `UcpLogMode.verbose` | Packet summaries plus basic logs |
| `UcpLogMode.raw` | Verbose logs with raw bytes and TLV details |

Use `raw` while developing and `basic` or `errorOnly` in production.

## Frame and Protocol Utilities 🧱

The SDK also exports lower-level utilities for advanced use cases:

- `DeviceFrame`, `FrameBuilder`, `FrameParser`, `FrameBuffer`
- `Crc16Ccitt` for frame CRC validation
- `ByteReader`, `ByteWriter`, and endian helpers
- `PayloadBuilder`, `PayloadCodec`, `CommonPayloads`, `TlvBuilder`
- `CommonResponseParser`, `EventParser`, `NackParser`, `TlvParser`
- Protocol constants for products, profiles, commands, TLV types, operation codes, flags, and addresses

You can send a complete frame or raw bytes when needed:

```dart
await client.sendFrame(frame);
await client.sendRawData(<int>[0xAA, 0x01, 0x02, 0x55]);
```

## Error Handling 🚨

Wrap commands in `try/catch` and handle SDK-specific exceptions:

```dart
try {
  final info = await client.deviceInfo(
    timeout: const Duration(seconds: 8),
  );
  print(info.deviceName);
} on TimeoutException catch (error) {
  print('Command timed out: $error');
} on TransportException catch (error) {
  print('BLE transport error: $error');
} on ProtocolException catch (error) {
  print('UCP protocol error: $error');
} on UnifiedDeviceException catch (error) {
  print('SDK error: $error');
}
```

Common causes:

- Bluetooth is turned off
- Runtime Bluetooth permissions were denied
- Device is out of range
- Command was sent before `sessionActive`
- Device returned a NACK
- Android SDK/NDK package is missing or partially installed

## Example App Walkthrough 📱

Run the example:

```bash
cd example
flutter pub get
flutter run
```

The example app includes:

- **Dashboard**: Bluetooth status, scan/connect controls, command buttons, logs, and packet trace viewer
- **Device Scan Panel**: lists discovered BLE devices by name, ID, RSSI, and advertised service UUIDs
- **Command Panel**: runs `deviceInfo`, `timeRead`, `startTest`, `lastReport`, moisture stream, `font`, and `cdn`
- **Trace Viewer**: shows packet-level activity for debugging
- **Log Viewer**: shows SDK lifecycle, command result, and communication logs
- **Soil Test Flow**: guides the user through connect, moisture stream, soil test start, progress events, and final report

## Recommended App Pattern ✅

Use one long-lived `UnifiedDeviceClient` per active device session:

```dart
class DeviceService {
  final UnifiedDeviceClient client = UnifiedDeviceClient.generic(
    logMode: UcpLogMode.basic,
  );

  Future<void> dispose() async {
    await client.dispose();
  }
}
```

Recommended flow:

1. Request Bluetooth permissions.
2. Start scan and show discovered devices.
3. Stop scan before connecting.
4. Call `connect(device)`.
5. Wait for `DeviceConnectionState.sessionActive`.
6. Send high-level commands or custom commands.
7. Listen to `events`, `moistureSamples`, `packetTraces`, and `communicationLogs`.
8. Stop streams before starting workflows that require exclusive device state.
9. Disconnect and dispose when done.

## Troubleshooting 🧯

### Build fails because Gradle, AGP, or Kotlin is too old

Update:

- Gradle wrapper in `android/gradle/wrapper/gradle-wrapper.properties`
- AGP and Kotlin versions in `android/settings.gradle.kts`
- Plugin module versions if you are developing this package locally

### Android build fails while preparing NDK

Install the required NDK in Android Studio or with `sdkmanager`, then pin the installed version:

```kotlin
android {
    ndkVersion = "29.0.13113456"
}
```

### No devices appear while scanning

Check:

- Bluetooth is enabled
- Bluetooth permissions are granted
- Location permission is granted on older Android versions
- The device is powered on and advertising
- Your filter accepts either the target device name or advertised service UUID

### Commands fail with “Command is blocked until sessionActive”

Wait for:

```dart
DeviceConnectionState.sessionActive
```

or check:

```dart
client.isSessionActive
```

The SDK only allows normal commands after UCP session bootstrap is complete.

### Soil test does not start

Stop the moisture stream first:

```dart
await client.moistGetOff();
await client.startTest(
  agentId: 'AGENT-DEMO1',
  farmerId: 'FARMER-0012',
  fieldIndex: 'FIELD-A3',
  fieldTestIndex: 'TEST-0001',
);
```

## Feature Checklist 📋

| Feature | Status |
| --- | --- |
| Android BLE transport | ✅ |
| iOS BLE transport | ✅ |
| Bluetooth availability and permission APIs | ✅ |
| BLE scan results | ✅ |
| BLE connection state stream | ✅ |
| Notification byte stream | ✅ |
| UCP session bootstrap | ✅ |
| ACK/DATA/EVENT response handling | ✅ |
| NACK parsing | ✅ |
| CRC16-CCITT validation | ✅ |
| Frame build/parse/buffer utilities | ✅ |
| TLV build/parse utilities | ✅ |
| Device info command | ✅ |
| Time read command | ✅ |
| Soil test start command | ✅ |
| Last report command | ✅ |
| Moisture stream command and decoded samples | ✅ |
| Font command | ✅ |
| CDN command | ✅ |
| Calibration commands | ✅ |
| Configuration commands | ✅ |
| Report history commands | ✅ |
| File transfer commands | ✅ |
| Custom command API | ✅ |
| Raw frame and raw byte sending | ✅ |
| Packet trace stream | ✅ |
| Communication log stream | ✅ |
| Example dashboard UI | ✅ |
| Example guided soil-test flow | ✅ |

## Notes 📝

- The SDK is byte-oriented at the transport layer and UCP-aware at the client layer.
- `connect(device)` performs BLE connection and UCP bootstrap.
- Most application commands require `sessionActive`.
- Use `packetTraces` and `communicationLogs` when debugging device protocol behavior.
- Dispose the client to release native BLE streams and method-channel resources.
