import '../../protocol/constants/ble_constants.dart';
import '../../protocol/constants/product_ids.dart';
import '../../protocol/constants/profile_ids.dart';
import '../../protocol/constants/ucp_addresses.dart';

/// Controls which UCP bootstrap commands are sent after BLE is ready.
enum UcpBootstrapStrategy {
  /// Send `bt_transport_open`, then `session_open_rtc_sync`.
  transportOpenThenRtcSync,

  /// Skip `bt_transport_open` and send only `session_open_rtc_sync`.
  rtcSyncOnly,

  /// Do not automatically send UCP bootstrap commands after BLE connects.
  manual,
}

/// BLE GATT UUIDs used by one hardware family.
class BleGattProfile {
  final String serviceUuid;
  final String notifyCharacteristicUuid;
  final String writeCharacteristicUuid;

  const BleGattProfile({
    this.serviceUuid = BleConstants.deviceService,
    this.notifyCharacteristicUuid = BleConstants.notifyCharacteristic,
    this.writeCharacteristicUuid = BleConstants.writeCharacteristic,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'serviceUuid': serviceUuid,
      'notifyCharacteristicUuid': notifyCharacteristicUuid,
      'writeCharacteristicUuid': writeCharacteristicUuid,
    };
  }
}

/// Hardware-specific values required for BLE discovery and UCP framing.
class UnifiedDeviceHardwareProfile {
  final String name;
  final BleGattProfile ble;
  final int productId;
  final int profileId;
  final int sourceAddress;
  final int destinationAddress;
  final String? clientName;
  final String appInstanceId;
  final String? appUserId;
  final UcpBootstrapStrategy bootstrapStrategy;
  final bool heartbeatEnabled;
  final bool syncRtcAsLocalWallClock;

  const UnifiedDeviceHardwareProfile({
    this.name = 'Porokh Production',
    this.ble = const BleGattProfile(),
    this.productId = ProductIds.aunkurUcp1,
    this.profileId = ProfileIds.defaultProfile,
    this.sourceAddress = UcpAddresses.software,
    this.destinationAddress = UcpAddresses.device,
    this.clientName = 'PorokhApp',
    this.appInstanceId = 'flutter-app',
    this.appUserId,
    this.bootstrapStrategy = UcpBootstrapStrategy.rtcSyncOnly,
    this.heartbeatEnabled = true,
    this.syncRtcAsLocalWallClock = true,
  });

  /// Default profile retained for existing development hardware.
  static const UnifiedDeviceHardwareProfile aunkurUcp1 =
      UnifiedDeviceHardwareProfile();

  UnifiedDeviceHardwareProfile copyWith({
    String? name,
    BleGattProfile? ble,
    int? productId,
    int? profileId,
    int? sourceAddress,
    int? destinationAddress,
    String? clientName,
    bool clearClientName = false,
    String? appInstanceId,
    String? appUserId,
    bool clearAppUserId = false,
    UcpBootstrapStrategy? bootstrapStrategy,
    bool? heartbeatEnabled,
    bool? syncRtcAsLocalWallClock,
  }) {
    return UnifiedDeviceHardwareProfile(
      name: name ?? this.name,
      ble: ble ?? this.ble,
      productId: productId ?? this.productId,
      profileId: profileId ?? this.profileId,
      sourceAddress: sourceAddress ?? this.sourceAddress,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      clientName: clearClientName ? null : (clientName ?? this.clientName),
      appInstanceId: appInstanceId ?? this.appInstanceId,
      appUserId: clearAppUserId ? null : (appUserId ?? this.appUserId),
      bootstrapStrategy: bootstrapStrategy ?? this.bootstrapStrategy,
      heartbeatEnabled: heartbeatEnabled ?? this.heartbeatEnabled,
      syncRtcAsLocalWallClock:
          syncRtcAsLocalWallClock ?? this.syncRtcAsLocalWallClock,
    );
  }
}
