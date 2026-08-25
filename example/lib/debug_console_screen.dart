import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

import 'hardware_profiles.dart';
import 'screens/soil_test_connection_screen.dart';
import 'screens/soil_test_screen.dart';

class DebugConsoleScreen extends StatefulWidget {
  final UnifiedDevicePlatform? platform;
  final bool enablePlatformBootstrap;

  const DebugConsoleScreen({
    super.key,
    this.platform,
    this.enablePlatformBootstrap = true,
  });

  @override
  State<DebugConsoleScreen> createState() => _DebugConsoleScreenState();
}

class _DebugConsoleScreenState extends State<DebugConsoleScreen> {
  static const int _maxTraceItems = 300;
  static const int _maxLogItems = 120;

  late final UnifiedDevicePlatform _platform;
  late final UnifiedDeviceClient _client;
  late final List<StreamSubscription<dynamic>> _subscriptions;

  final Map<String, DiscoveredDevice> _devices = <String, DiscoveredDevice>{};
  final List<UcpPacketTrace> _packetTraces = <UcpPacketTrace>[];
  final List<String> _logLines = <String>[];

  String? _selectedDeviceId;
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  String? _platformVersion;
  bool? _bluetoothAvailable;
  bool? _bluetoothEnabled;
  bool? _permissionsGranted;
  int _pendingActions = 0;

  DiscoveredDevice? get _selectedDevice =>
      _selectedDeviceId == null ? null : _devices[_selectedDeviceId];

  bool get _canConnect =>
      _selectedDevice != null &&
      (_connectionState == DeviceConnectionState.disconnected ||
          _connectionState == DeviceConnectionState.connectionLost);

  bool get _canDisconnect =>
      _connectionState != DeviceConnectionState.disconnected &&
      _connectionState != DeviceConnectionState.connectionLost;

  bool get _sessionReady => _client.isSessionActive;

  bool get _streamActive => _client.currentSession?.streamActive ?? false;

  bool get _canRetryBootstrap =>
      _canDisconnect &&
      !_sessionReady &&
      _connectionState != DeviceConnectionState.scanning &&
      _connectionState != DeviceConnectionState.connecting &&
      _connectionState != DeviceConnectionState.disconnecting;

  bool get _busy => _pendingActions > 0;

  @override
  void initState() {
    super.initState();
    _platform = widget.platform ?? UnifiedDevicePlatform.instance;
    _client = UnifiedDeviceClient(
      UnifiedDeviceClientConfig(
        transport: BleTransport(
          platform: _platform,
          bleProfile: appHardwareProfile.ble,
        ),
        hardwareProfile: appHardwareProfile,
        logMode: UcpLogMode.raw,
      ),
    );
    _subscriptions = <StreamSubscription<dynamic>>[
      _client.discoveredDevices.listen(_handleDevice),
      _client.connectionState.listen(_handleConnectionState),
      _client.packetTraces.listen(_handleTrace),
      _client.events.listen(_handleEvent),
      _client.moistureSamples.listen(_handleMoistureSample),
      _client.communicationLogs.listen(_handleCommunicationLog),
    ];

    if (widget.enablePlatformBootstrap) {
      unawaited(_refreshBluetoothStatus());
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _client.dispose();
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

  Future<void> _requestPermissions() async {
    final granted = await _platform.requestBluetoothPermissions();
    if (!mounted) {
      return;
    }
    setState(() {
      _permissionsGranted = granted;
    });
    await _refreshBluetoothStatus();
  }

  Future<void> _toggleScan() async {
    if (_client.isScanning) {
      await _client.stopScan();
      _appendLog('Scan stopped');
      return;
    }

    setState(() {
      _devices.clear();
      _selectedDeviceId = null;
    });
    await _client.startScan();
    _appendLog(
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

  Future<void> _retryBootstrap() async {
    await _runAction('bootstrap', () async {
      await _client.sessionManager.bootstrap();
      await _client.sessionManager.waitUntilSessionActive();
      _appendLog('session bootstrap completed');
    });
  }

  Future<void> _readDeviceInfo() async {
    await _runAction('device_info', () async {
      final info = await _client.deviceInfo();
      _appendLog(
        'device_info name=${info.deviceName ?? '-'} fw=${info.firmwareVersion ?? '-'} '
        'hw=${info.hardwareVersion ?? '-'} battery=${info.batterySoc ?? '-'}%',
      );
    });
  }

  Future<void> _readTime() async {
    await _runAction('time', () async {
      final snapshot = await _client.timeRead();
      _appendLog(
        'time epoch=${snapshot.epochSeconds ?? '-'} uptime=${snapshot.uptimeSeconds ?? '-'} '
        'text=${snapshot.text ?? '-'}',
      );
    });
  }

  Future<void> _startTest() async {
    await _runAction('start_test', () async {
      await _client.startTest(
        agentId: 'AGENT-DEMO1',
        farmerId: 'FARMER-0012',
        fieldIndex: 'FIELD-A3',
        fieldTestIndex: 'TEST-0001',
      );
      _appendLog('start_test ACK accepted');
    });
  }

  Future<void> _lastReport() async {
    await _runAction('last_report', () async {
      final report = await _readLastReportWhenReady();
      if (report == null) {
        return;
      }
      _appendLog(
        'last_report N=${report.nitrogen ?? '-'} P=${report.phosphorus ?? '-'} '
        'K=${report.potassium ?? '-'} moisture=${report.moisture ?? '-'} '
        'temp=${report.temperature ?? '-'} EC=${report.ec ?? '-'} pH=${report.ph ?? '-'}',
      );
    });
  }

  Future<UcpLastReport?> _readLastReportWhenReady() async {
    if (_client.currentSession?.measurementActive ?? false) {
      _appendLog('last_report skipped: device is still running the soil test');
      return null;
    }
    try {
      return await _client.lastReport();
    } on ProtocolException catch (error) {
      if (error.errorCode == UcpStatusCodes.deviceBusy) {
        _appendLog('last_report blocked: DEVICE_BUSY, wait for completion');
        return null;
      }
      rethrow;
    }
  }

  Future<void> _moistOn() async {
    await _runAction('moist_get_on', () async {
      await _client.moistGetOn();
      _appendLog('moist_get_on ACK accepted');
    });
  }

  Future<void> _moistOff() async {
    await _runAction('moist_get_off', () async {
      await _client.moistGetOff();
      _appendLog('moist_get_off ACK accepted');
    });
  }

  Future<void> _fontEnglish() async {
    await _runAction('font', () async {
      final response = await _client.font('english');
      _appendLog(
        'font response op=0x${response.op.toRadixString(16).toUpperCase()}',
      );
    });
  }

  Future<void> _cdn() async {
    await _runAction('cdn', () async {
      final response = await _client.cdn('ELAB_SW_01');
      _appendLog(
        'cdn response op=0x${response.op.toRadixString(16).toUpperCase()}',
      );
    });
  }

  Future<void> _copyTrace() async {
    await Clipboard.setData(ClipboardData(text: _exportTraceText()));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Packet trace copied')));
  }

  Future<void> _openSoilTestFlow() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _client.isSessionActive
            ? SoilTestScreen(client: _client)
            : SoilTestConnectionScreen(platform: _platform, client: _client),
      ),
    );
  }

  Future<void> _exportTrace() async {
    await Clipboard.setData(ClipboardData(text: _exportTraceText()));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Packet trace export copied')));
  }

  void _clearTrace() {
    setState(() {
      _packetTraces.clear();
      _logLines.clear();
    });
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
      _appendLog('$label failed: $error');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label failed: $error')));
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
    _appendLog('state=${state.name}');
  }

  void _handleTrace(UcpPacketTrace trace) {
    setState(() {
      _packetTraces.insert(0, trace);
      if (_packetTraces.length > _maxTraceItems) {
        _packetTraces.removeLast();
      }
    });
  }

  void _handleCommunicationLog(DeviceCommunicationLog log) {
    debugPrint('SDK communication log: ${log.toJson()}');
  }

  void _handleEvent(DeviceEvent event) {
    final frame = event.sourceFrame;
    if (frame == null) {
      _appendLog(
        'EVENT class=0x${event.commandClass.toRadixString(16)} cmd=0x${event.commandId.toRadixString(16)}',
      );
      return;
    }
    final decoded = _client.responseManager.decodeTlvs(frame);
    final detail = decoded.isEmpty
        ? 'no TLVs'
        : decoded
              .map((tlv) => '${tlv.typeName}=${tlv.displayValue}')
              .join(', ');
    _appendLog(
      'EVENT class=0x${frame.commandClass.toRadixString(16).toUpperCase()} '
      'cmd=0x${frame.commandId.toRadixString(16).toUpperCase()} $detail',
    );
  }

  void _handleMoistureSample(UcpMoistureSample sample) {
    _appendLog(
      'STREAM moisture raw=${sample.rawValue ?? '-'} '
      'percent=${sample.moisturePercent ?? '-'} text=${sample.text ?? '-'}',
    );
  }

  bool _isTargetDevice(DiscoveredDevice device) {
    final matchesName = device.name == BleConstants.defaultDeviceName;
    final matchesService = device.serviceUuids.any(
      (uuid) => uuid.toUpperCase().contains(BleConstants.deviceService),
    );
    return matchesName || matchesService;
  }

  void _appendLog(String line) {
    setState(() {
      _logLines.insert(0, line);
      if (_logLines.length > _maxLogItems) {
        _logLines.removeLast();
      }
    });
  }

  String _exportTraceText() {
    final buffer = StringBuffer();
    buffer.writeln('State: ${_connectionState.name}');
    for (final line in _logLines.reversed) {
      buffer.writeln(line);
    }
    for (final trace in _packetTraces.reversed) {
      buffer.writeln(_formatTrace(trace));
      for (final tlv in trace.decodedTlvs) {
        buffer.writeln(
          '  TLV ${tlv.typeName} '
          '(0x${tlv.type.toRadixString(16).toUpperCase().padLeft(2, '0')}) '
          'len=${tlv.length} value=${tlv.displayValue}',
        );
      }
    }
    return buffer.toString();
  }

  String _formatTrace(UcpPacketTrace trace) {
    final frame = trace.frame;
    final bytes = EndianUtils.toHexString(trace.bytes);
    if (frame == null) {
      return '${trace.directionLabel} bytes=$bytes';
    }
    return '${trace.directionLabel} '
        'OP=0x${frame.op.toRadixString(16).toUpperCase().padLeft(2, '0')} '
        'CLASS=0x${frame.commandClass.toRadixString(16).toUpperCase().padLeft(2, '0')} '
        'CMD=0x${frame.commandId.toRadixString(16).toUpperCase().padLeft(2, '0')} '
        'SEQ=${frame.sequence} '
        'SRC=0x${frame.sourceAddress.toRadixString(16).toUpperCase().padLeft(2, '0')} '
        'DST=0x${frame.destinationAddress.toRadixString(16).toUpperCase().padLeft(2, '0')} '
        'PLEN=${frame.payloadLength} '
        'CRC=0x${frame.crc.toRadixString(16).toUpperCase().padLeft(4, '0')} '
        'BYTES=$bytes';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.developer_board, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Unified Device SDK'),
          ],
        ),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'copy':
                  _copyTrace();
                  break;
                case 'export':
                  _exportTrace();
                  break;
                case 'clear':
                  _clearTrace();
                  break;
                case 'refresh':
                  _refreshBluetoothStatus();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('Refresh Status'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.copy_all),
                  title: Text('Copy Trace'),
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('Export Trace'),
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Clear All'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(),
          const SizedBox(height: 16),
          _buildScanCard(),
          const SizedBox(height: 16),
          _buildCommandCard(),
          const SizedBox(height: 16),
          _buildLogCard(),
          const SizedBox(height: 16),
          _buildTraceCard(),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text('State: ${_connectionState.name}'),
            Text('Session active: ${_sessionReady ? 'yes' : 'no'}'),
            Text('Platform: ${_platformVersion ?? '-'}'),
            Text('Bluetooth available: ${_bluetoothAvailable ?? '-'}'),
            Text('Bluetooth enabled: ${_bluetoothEnabled ?? '-'}'),
            Text('Permissions granted: ${_permissionsGranted ?? '-'}'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _openSoilTestFlow,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Try Soil Test'),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _refreshBluetoothStatus,
                  child: const Text('Refresh Status'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _requestPermissions,
                  child: const Text('Request Permissions'),
                ),
                OutlinedButton(
                  onPressed: _busy || !_canRetryBootstrap
                      ? null
                      : _retryBootstrap,
                  child: const Text('Retry Bootstrap'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: _busy ? null : _toggleScan,
                  child: Text(_client.isScanning ? 'Stop Scan' : 'Scan'),
                ),
                OutlinedButton(
                  onPressed: _busy || !_canConnect ? null : _connectSelected,
                  child: const Text('Connect'),
                ),
                OutlinedButton(
                  onPressed: !_canDisconnect ? null : _disconnect,
                  child: const Text('Disconnect'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_devices.isEmpty)
              const Text('No matching Aunkur_UCP1 / FFE0 devices yet')
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

  Widget _buildCommandCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Official Commands',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              _sessionReady
                  ? 'Normal commands enabled after session bootstrap'
                  : 'Waiting for session bootstrap. If this stays on connected, notifySubscribed, or mtuReady, use Retry Bootstrap or Disconnect.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: _busy || !_sessionReady ? null : _readDeviceInfo,
                  child: const Text('device_info'),
                ),
                FilledButton(
                  onPressed: _busy || !_sessionReady ? null : _readTime,
                  child: const Text('time'),
                ),
                FilledButton(
                  onPressed: _busy || !_sessionReady ? null : _startTest,
                  child: const Text('start_test'),
                ),
                FilledButton(
                  onPressed: _busy || !_sessionReady ? null : _lastReport,
                  child: const Text('last_report'),
                ),
                FilledButton(
                  onPressed: _busy || !_sessionReady || _streamActive
                      ? null
                      : _moistOn,
                  child: const Text('moist_get_on'),
                ),
                FilledButton(
                  onPressed: _busy || !_streamActive ? null : _moistOff,
                  child: const Text('moist_get_off'),
                ),
                FilledButton(
                  onPressed: _busy || !_sessionReady ? null : _fontEnglish,
                  child: const Text('font english'),
                ),
                FilledButton(
                  onPressed: _busy || !_sessionReady ? null : _cdn,
                  child: const Text('cdn'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Log',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (_logLines.isEmpty)
              const Text('No command or lifecycle logs yet')
            else
              ..._logLines.take(20).map(Text.new),
          ],
        ),
      ),
    );
  }

  Widget _buildTraceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Packet Trace',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (_packetTraces.isEmpty)
              const Text('No TX/RX packets yet')
            else
              ..._packetTraces
                  .take(24)
                  .map(
                    (trace) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SelectableText(
                        [
                          _formatTrace(trace),
                          ...trace.decodedTlvs.map(
                            (tlv) =>
                                '  TLV ${tlv.typeName} '
                                '(0x${tlv.type.toRadixString(16).toUpperCase().padLeft(2, '0')}) '
                                'len=${tlv.length} value=${tlv.displayValue}',
                          ),
                        ].join('\n'),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
