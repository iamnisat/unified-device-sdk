import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

import '../hardware_profiles.dart';
import '../widgets/connection_status_bar.dart';
import 'soil_test_screen.dart';

class SoilTestConnectionScreen extends StatefulWidget {
  final UnifiedDevicePlatform? platform;
  final UnifiedDeviceClient? client;

  const SoilTestConnectionScreen({super.key, this.platform, this.client});

  @override
  State<SoilTestConnectionScreen> createState() =>
      _SoilTestConnectionScreenState();
}

class _SoilTestConnectionScreenState extends State<SoilTestConnectionScreen> {
  static const int _maxActivityLines = 20;

  late final UnifiedDevicePlatform _platform;
  late final UnifiedDeviceClient _client;
  late final List<StreamSubscription<dynamic>> _subscriptions;

  final Map<String, DiscoveredDevice> _devices = <String, DiscoveredDevice>{};
  final List<String> _activityLines = <String>[];

  String? _selectedDeviceId;
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  String? _platformVersion;
  bool? _bluetoothAvailable;
  bool? _bluetoothEnabled;
  bool? _permissionsGranted;
  int _pendingActions = 0;
  bool _navigatingToSoilTest = false;
  bool _transferredClientOwnership = false;
  bool _ownsClient = false;

  DiscoveredDevice? get _selectedDevice =>
      _selectedDeviceId == null ? null : _devices[_selectedDeviceId];

  bool get _busy => _pendingActions > 0;

  bool get _canConnect =>
      _selectedDevice != null &&
      (_connectionState == DeviceConnectionState.disconnected ||
          _connectionState == DeviceConnectionState.connectionLost);

  bool get _canDisconnect =>
      _connectionState != DeviceConnectionState.disconnected &&
      _connectionState != DeviceConnectionState.connectionLost;

  @override
  void initState() {
    super.initState();
    _platform = widget.platform ?? UnifiedDevicePlatform.instance;
    _ownsClient = widget.client == null;
    _client =
        widget.client ??
        UnifiedDeviceClient(
          UnifiedDeviceClientConfig(
            transport: BleTransport(
              platform: _platform,
              bleProfile: appHardwareProfile.ble,
            ),
            hardwareProfile: appHardwareProfile,
            logMode: UcpLogMode.raw,
          ),
        );
    _connectionState =
        _client.currentSession?.state ?? _client.sessionManager.state;
    _subscriptions = <StreamSubscription<dynamic>>[
      _client.discoveredDevices.listen(_handleDevice),
      _client.connectionState.listen(_handleConnectionState),
      _client.communicationLogs.listen(_handleCommunicationLog),
    ];
    unawaited(_refreshBluetoothStatus());
    if (_client.isSessionActive) {
      _navigatingToSoilTest = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_openSoilTestScreen());
        }
      });
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    if (_ownsClient && !_transferredClientOwnership) {
      unawaited(_client.dispose());
    }
    super.dispose();
  }

  Future<void> _refreshBluetoothStatus() async {
    final values = await Future.wait<Object?>([
      _platform.getPlatformVersion(),
      _platform.isBluetoothAvailable(),
      _platform.isBluetoothEnabled(),
    ]);
    if (!mounted) {
      return;
    }
    setState(() {
      _platformVersion = values[0] as String?;
      _bluetoothAvailable = values[1] as bool?;
      _bluetoothEnabled = values[2] as bool?;
    });
  }

  Future<void> _toggleScan() async {
    if (_client.isScanning) {
      await _client.stopScan();
      _addActivity('Scan stopped');
      return;
    }

    setState(() {
      _devices.clear();
      _selectedDeviceId = null;
    });
    await _client.startScan();
    _addActivity(
      'Scan started for ${BleConstants.defaultDeviceName} / ${BleConstants.deviceService}',
    );
  }

  Future<void> _connectSelected() async {
    final device = _selectedDevice;
    if (device == null) {
      return;
    }
    await _runAction('Connect', () => _client.connect(device));
  }

  Future<void> _disconnect() async {
    await _runAction('Disconnect', _client.disconnect, allowWhileBusy: true);
  }

  Future<void> _runAction(
    String label,
    Future<void> Function() action, {
    bool allowWhileBusy = false,
  }) async {
    if (_busy && !allowWhileBusy) {
      return;
    }
    setState(() {
      _pendingActions++;
    });
    try {
      await action();
    } on Object catch (error) {
      _addActivity('$label failed: ${_friendlyError(error)}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label failed: ${_friendlyError(error)}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingActions--;
        });
      }
    }
  }

  void _handleDevice(DiscoveredDevice device) {
    if (!_isTargetDevice(device)) {
      return;
    }
    setState(() {
      _devices[device.deviceId] = device;
      _selectedDeviceId ??= device.deviceId;
    });
  }

  void _handleConnectionState(DeviceConnectionState state) {
    setState(() {
      _connectionState = state;
      if (state == DeviceConnectionState.disconnected ||
          state == DeviceConnectionState.connectionLost) {
        _selectedDeviceId = null;
      }
    });
    _addActivity('State: ${_stateLabel(state)}');

    if (state == DeviceConnectionState.sessionActive &&
        !_navigatingToSoilTest) {
      _navigatingToSoilTest = true;
      unawaited(_openSoilTestScreen());
    }
  }

  void _handleCommunicationLog(DeviceCommunicationLog log) {
    final event = log.param['event'] as String?;
    if (event == null) {
      return;
    }
    if (event == 'command_result' || event == 'event_received') {
      return;
    }
    _addActivity('SDK: $event');
  }

  Future<void> _openSoilTestScreen() async {
    if (_client.isScanning) {
      await _client.stopScan();
    }
    if (!mounted) {
      return;
    }
    _transferredClientOwnership = _ownsClient;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            SoilTestScreen(client: _client, disposeClientOnExit: _ownsClient),
      ),
    );
  }

  bool _isTargetDevice(DiscoveredDevice device) {
    final matchesName = device.name == BleConstants.defaultDeviceName;
    final matchesService = device.serviceUuids.any(
      (uuid) => uuid.toUpperCase().contains(BleConstants.deviceService),
    );
    return matchesName || matchesService;
  }

  void _addActivity(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _activityLines.insert(0, message);
      if (_activityLines.length > _maxActivityLines) {
        _activityLines.removeLast();
      }
    });
  }

  String _friendlyError(Object error) {
    final text = error.toString().trim();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  String _stateLabel(DeviceConnectionState state) {
    return switch (state) {
      DeviceConnectionState.disconnected => 'Disconnected',
      DeviceConnectionState.scanning => 'Scanning',
      DeviceConnectionState.connecting => 'Connecting',
      DeviceConnectionState.connected => 'Connected',
      DeviceConnectionState.servicesDiscovered => 'Services discovered',
      DeviceConnectionState.notifySubscribed => 'Notify subscribed',
      DeviceConnectionState.mtuReady => 'MTU ready',
      DeviceConnectionState.transportReady => 'Transport ready',
      DeviceConnectionState.sessionActive => 'Session active',
      DeviceConnectionState.measurementActive => 'Measurement active',
      DeviceConnectionState.streamActive => 'Stream active',
      DeviceConnectionState.safeDisconnectPending => 'Safe disconnect pending',
      DeviceConnectionState.disconnecting => 'Disconnecting',
      DeviceConnectionState.error => 'Error',
      DeviceConnectionState.connectionLost => 'Connection lost',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Soil Test Connection'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ConnectionStatusBar(
            connectionState: _connectionState,
            sessionReady: _client.isSessionActive,
            platformVersion: _platformVersion,
            bluetoothAvailable: _bluetoothAvailable,
            bluetoothEnabled: _bluetoothEnabled,
            permissionsGranted: _permissionsGranted,
          ),

          const SizedBox(height: 16),
          _buildConnectionActionsCard(),
          const SizedBox(height: 16),
          _buildDeviceListCard(),
          const SizedBox(height: 16),
          _buildActivityCard(),
        ],
      ),
    );
  }

  Widget _buildConnectionActionsCard() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection Actions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Use scan, connect, and disconnect only. The session will continue automatically after connect.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _compactActionButton(
                    filled: true,
                    onPressed: _busy ? null : _toggleScan,
                    icon: _client.isScanning
                        ? Icons.stop_circle_outlined
                        : Icons.search_rounded,
                    label: _client.isScanning ? 'Stop' : 'Scan',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _compactActionButton(
                    onPressed: _busy || !_canConnect ? null : _connectSelected,
                    icon: Icons.link_rounded,
                    label: 'Connect',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _compactActionButton(
                    onPressed: !_canDisconnect ? null : _disconnect,
                    icon: Icons.link_off_rounded,
                    label: 'Disconnect',
                    danger: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool filled = false,
    bool danger = false,
  }) {
    final style = filled
        ? FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(38),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          )
        : OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(38),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            foregroundColor: danger ? Colors.red.shade700 : null,
            side: danger && onPressed != null
                ? BorderSide(color: Colors.red.shade300)
                : null,
          );

    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );

    if (filled) {
      return FilledButton(onPressed: onPressed, style: style, child: child);
    }
    return OutlinedButton(onPressed: onPressed, style: style, child: child);
  }

  Widget _buildDeviceListCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Available Devices',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (_devices.isEmpty)
              const Text('No matching Aunkur_UCP1 / FFE0 devices yet.')
            else
              ..._devices.values.map((device) {
                final selected = device.deviceId == _selectedDeviceId;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () {
                    setState(() {
                      _selectedDeviceId = device.deviceId;
                    });
                  },
                  leading: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(device.name ?? BleConstants.defaultDeviceName),
                  subtitle: Text('${device.deviceId}  RSSI ${device.rssi}'),
                  selected: selected,
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Activity',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (_activityLines.isEmpty)
              const Text('No activity yet.')
            else
              ..._activityLines.map(Text.new),
          ],
        ),
      ),
    );
  }
}
