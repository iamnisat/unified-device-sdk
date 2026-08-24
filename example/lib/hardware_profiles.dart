import 'package:unified_device_sdk/unified_device_sdk.dart';

const appHardwareProfile = UnifiedDeviceHardwareProfile(
  name: 'Porokh Production',
  clientName: 'PorokhApp',
  appInstanceId: 'app-001',
  bootstrapStrategy: UcpBootstrapStrategy.rtcSyncOnly,
);
