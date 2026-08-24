import 'dart:async';
import 'command_result.dart';
import '../../core/client/unified_device_client.dart';
import '../constants/common_command_ids.dart';
import '../constants/command_classes.dart';
import '../constants/operation_codes.dart';
import '../constants/tlv_types.dart';
import '../models/battery_info.dart';
import '../models/device_info.dart';
import '../models/firmware_info.dart';
import '../payloads/tlv_builder.dart';

/// Provides convenience methods for common device commands.
class CommonCommands {
  final UnifiedDeviceClient _client;

  /// Creates a [CommonCommands] instance bound to a client.
  CommonCommands(this._client);

  /// Pings the device to check if it's responsive.
  Future<PingResult> ping() async {
    final stopwatch = Stopwatch()..start();
    await _client.sendCommand(
      productId: _client.hardwareProfile.productId,
      profileId: _client.hardwareProfile.profileId,
      sourceAddress: _client.hardwareProfile.sourceAddress,
      destinationAddress: _client.hardwareProfile.destinationAddress,
      op: OperationCodes.heartbeat,
      commandClass: CommandClasses.session,
      commandId: CommonCommandIds.ping,
      payload: _sessionIdPayload(),
    );
    stopwatch.stop();
    return PingResult(stopwatch.elapsedMilliseconds);
  }

  /// Retrieves device information.
  Future<DeviceInfoResult> getDeviceInfo() async {
    final response = await _client.deviceInfo();
    return DeviceInfoResult(
      DeviceInfo(
        productId: _client.hardwareProfile.productId,
        hardwareVersion: 0,
        serialNumber: response.aunkurId ?? '',
        manufacturerName: '',
        modelName: response.deviceName ?? '',
      ),
    );
  }

  /// Retrieves firmware version information.
  Future<FirmwareVersionResult> getFirmwareVersion() async {
    final response = await _client.deviceInfo();
    return FirmwareVersionResult(
      FirmwareInfo(
        major: 0,
        minor: 0,
        patch: 0,
        buildNumber: 0,
        versionString: response.firmwareVersion ?? '',
      ),
    );
  }

  /// Retrieves battery level information.
  Future<BatteryLevelResult> getBatteryLevel() async {
    final response = await _client.deviceInfo();
    return BatteryLevelResult(
      BatteryInfo(
        level: response.batterySoc ?? 0,
        voltage: ((response.batteryVoltage ?? 0) * 100).round(),
      ),
    );
  }

  /// Sets the device time using a shared common payload contract.
  Future<GenericCommandResult> setTime(DateTime time) async {
    final response = await _client.sendCommand(
      productId: _client.hardwareProfile.productId,
      profileId: _client.hardwareProfile.profileId,
      sourceAddress: _client.hardwareProfile.sourceAddress,
      destinationAddress: _client.hardwareProfile.destinationAddress,
      op: OperationCodes.write,
      commandClass: CommandClasses.system,
      commandId: CommonCommandIds.setTime,
      payload: TlvBuilder()
          .addUint64BE(
            TlvTypes.epochU64,
            time.toUtc().millisecondsSinceEpoch ~/ 1000,
          )
          .build(),
    );
    return GenericCommandResult(
      response.payload,
      statusCode: response.statusCode,
    );
  }

  /// Sends a custom command with raw payload.
  Future<GenericCommandResult> sendCustomCommand({
    required int commandId,
    List<int> payload = const [],
    Duration? timeout,
  }) async {
    final response = await _client.sendCommand(
      productId: _client.hardwareProfile.productId,
      profileId: _client.hardwareProfile.profileId,
      sourceAddress: _client.hardwareProfile.sourceAddress,
      destinationAddress: _client.hardwareProfile.destinationAddress,
      op: OperationCodes.action,
      commandClass: CommandClasses.system,
      commandId: commandId,
      payload: payload,
      timeout: timeout,
    );
    return GenericCommandResult(
      response.payload,
      statusCode: response.statusCode,
    );
  }

  List<int> _sessionIdPayload() {
    final sessionId = _client.currentSession?.ucpSessionId;
    if (sessionId == null) {
      return const <int>[];
    }
    return TlvBuilder().addUint32BE(TlvTypes.sessionId, sessionId).build();
  }
}
