import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

import 'soil_test_connection_screen.dart';
import 'soil_test_screen.dart';
import '../hardware_profiles.dart';
import '../widgets/connection_status_bar.dart';
import '../widgets/device_scan_panel.dart';
import '../widgets/command_panel.dart';
import '../widgets/log_viewer.dart';
import '../widgets/trace_viewer.dart';

class DashboardScreen extends StatefulWidget {
  final UnifiedDevicePlatform? platform;
  final bool enablePlatformBootstrap;

  const DashboardScreen({
    super.key,
    this.platform,
    this.enablePlatformBootstrap = true,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  static const int _maxTraceItems = 300;
  static const int _maxLogItems = 120;

  late final UnifiedDevicePlatform _platform;
  late final UnifiedDeviceClient _client;
  late final List<StreamSubscription<dynamic>> _subscriptions;
  late final TabController _tabController;

  final Map<String, DiscoveredDevice> _devices = <String, DiscoveredDevice>{};
  final List<UcpPacketTrace> _packetTraces = <UcpPacketTrace>[];
  final List<LogEntry> _logEntries = <LogEntry>[];

  String? _selectedDeviceId;
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  String? _platformVersion;
  bool? _bluetoothAvailable;
  bool? _bluetoothEnabled;
  bool? _permissionsGranted;
  int _pendingActions = 0;
  bool _isScanning = false;

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
      _connectionState == DeviceConnectionState.connected && !_sessionReady;

  bool get _busy => _pendingActions > 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    _tabController.dispose();
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
      _platform.requestBluetoothPermissions(),
    ]);
    if (!mounted) {
      return;
    }
    setState(() {
      _platformVersion = values[0] as String?;
      _bluetoothAvailable = values[1] as bool?;
      _bluetoothEnabled = values[2] as bool?;
      _permissionsGranted = values[3] as bool?;
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
    if (_isScanning) {
      await _client.stopScan();
      _addLog(LogLevel.info, 'Scan stopped');
      setState(() => _isScanning = false);
      return;
    }

    setState(() {
      _devices.clear();
      _selectedDeviceId = null;
      _isScanning = true;
    });
    await _client.startScan();
    _addLog(
      LogLevel.info,
      'Scan started for ${BleConstants.defaultDeviceName} / ${BleConstants.deviceService}',
    );
  }

  Future<void> _connectSelected() async {
    final device = _selectedDevice;
    if (device == null) return;
    await _runAction('Connect', () => _client.connect(device));
  }

  Future<void> _disconnect() async {
    setState(() => _isScanning = false);
    await _runAction('Disconnect', _client.disconnect, allowWhileBusy: true);
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

  Future<void> _retryBootstrap() async {
    await _runAction('Bootstrap', () async {
      await _client.sessionManager.bootstrap();
      await _client.sessionManager.waitUntilSessionActive();
      _addLog(LogLevel.success, 'Session bootstrap completed');
    });
  }

  Future<void> _readDeviceInfo() async {
    await _runAction('device_info', () async {
      final info = await _client.deviceInfo();
      _addLog(
        LogLevel.info,
        'Device Info → Name: ${info.deviceName ?? "-"}, '
        'FW: ${info.firmwareVersion ?? "-"}, '
        'HW: ${info.hardwareVersion ?? "-"}, '
        'Battery: ${info.batterySoc ?? "-"}%',
      );
    });
  }

  Future<void> _readTime() async {
    await _runAction('time', () async {
      final snapshot = await _client.timeRead();
      _addLog(
        LogLevel.info,
        'Time Read → Epoch: ${snapshot.epochSeconds ?? "-"}, '
        'Uptime: ${snapshot.uptimeSeconds ?? "-"}s, '
        'Text: ${snapshot.text ?? "-"}',
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
      _addLog(LogLevel.success, 'Start Test → ACK accepted');
    });
  }

  Future<void> _lastReport() async {
    await _runAction('last_report', () async {
      final report = await _client.lastReport();
      _addLog(
        LogLevel.info,
        'Last Report → N: ${report.nitrogen ?? "-"}, '
        'P: ${report.phosphorus ?? "-"}, '
        'K: ${report.potassium ?? "-"}, '
        'Moisture: ${report.moisture ?? "-"}, '
        'Temp: ${report.temperature ?? "-"}, '
        'EC: ${report.ec ?? "-"}, '
        'pH: ${report.ph ?? "-"}',
      );
    });
  }

  Future<void> _moistOn() async {
    await _runAction('moist_get_on', () async {
      await _client.moistGetOn();
      _addLog(LogLevel.success, 'Moisture Stream → ON (ACK accepted)');
    });
  }

  Future<void> _moistOff() async {
    await _runAction('moist_get_off', () async {
      await _client.moistGetOff();
      _addLog(LogLevel.success, 'Moisture Stream → OFF (ACK accepted)');
    });
  }

  Future<void> _fontEnglish() async {
    await _runAction('font', () async {
      final response = await _client.font('english');
      _addLog(
        LogLevel.info,
        'Font Command → Response OP=0x${response.op.toRadixString(16).toUpperCase()}',
      );
    });
  }

  Future<void> _cdn() async {
    await _runAction('cdn', () async {
      final response = await _client.cdn('ELAB_SW_01');
      _addLog(
        LogLevel.info,
        'CDN Command → Response OP=0x${response.op.toRadixString(16).toUpperCase()}',
      );
    });
  }

  Future<void> _copyTrace() async {
    await Clipboard.setData(ClipboardData(text: _exportTraceText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Packet trace copied to clipboard')),
    );
  }

  Future<void> _exportTrace() async {
    await Clipboard.setData(ClipboardData(text: _exportTraceText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trace export copied to clipboard')),
    );
  }

  void _clearTrace() {
    setState(() {
      _packetTraces.clear();
      _logEntries.clear();
    });
    _addLog(LogLevel.info, 'Logs and traces cleared');
  }

  void _addLog(LogLevel level, String message) {
    setState(() {
      _logEntries.insert(
        0,
        LogEntry(level: level, message: message, timestamp: DateTime.now()),
      );
      if (_logEntries.length > _maxLogItems) {
        _logEntries.removeLast();
      }
    });
  }

  Future<void> _runAction(
    String label,
    Future<void> Function() action, {
    bool allowWhileBusy = false,
  }) async {
    if (_busy && !allowWhileBusy) return;
    setState(() => _pendingActions++);
    try {
      await action();
    } on Object catch (error) {
      _addLog(LogLevel.error, '$label failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label failed: $error'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pendingActions--);
      }
    }
  }

  void _handleDevice(DiscoveredDevice device) {
    if (!_isTargetDevice(device)) return;
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
    _addLog(LogLevel.state, 'Connection → ${state.name}');
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
      _addLog(
        LogLevel.event,
        'Event: class=0x${event.commandClass.toRadixString(16)} '
        'cmd=0x${event.commandId.toRadixString(16)}',
      );
      return;
    }
    final decoded = _client.responseManager.decodeTlvs(frame);
    final detail = decoded.isEmpty
        ? 'no TLVs'
        : decoded
              .map((tlv) => '${tlv.typeName}=${tlv.displayValue}')
              .join(', ');
    _addLog(
      LogLevel.event,
      'Event: class=0x${frame.commandClass.toRadixString(16).toUpperCase()} '
      'cmd=0x${frame.commandId.toRadixString(16).toUpperCase()} → $detail',
    );
  }

  void _handleMoistureSample(UcpMoistureSample sample) {
    _addLog(
      LogLevel.stream,
      'Stream: moisture raw=${sample.rawValue ?? "-"} '
      'percent=${sample.moisturePercent ?? "-"} text=${sample.text ?? "-"}',
    );
  }

  bool _isTargetDevice(DiscoveredDevice device) {
    final matchesName = device.name == BleConstants.defaultDeviceName;
    final matchesService = device.serviceUuids.any(
      (uuid) => uuid.toUpperCase().contains(BleConstants.deviceService),
    );
    return matchesName || matchesService;
  }

  String _exportTraceText() {
    final buffer = StringBuffer();
    buffer.writeln('=== Unified Device SDK Trace Export ===');
    buffer.writeln('Connection State: ${_connectionState.name}');
    buffer.writeln('Session Active: ${_sessionReady ? "yes" : "no"}');
    buffer.writeln('========================================');
    buffer.writeln('');
    buffer.writeln('--- Logs ---');
    for (final entry in _logEntries.reversed) {
      final time =
          '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';
      buffer.writeln('[$time][${entry.level.name}] ${entry.message}');
    }
    buffer.writeln('');
    buffer.writeln('--- Packet Traces ---');
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connection Status Bar
              ConnectionStatusBar(
                connectionState: _connectionState,
                sessionReady: _sessionReady,
                platformVersion: _platformVersion,
                bluetoothAvailable: _bluetoothAvailable,
                bluetoothEnabled: _bluetoothEnabled,
                permissionsGranted: _permissionsGranted,
              ),
              const SizedBox(height: 16),

              // Connection Controls
              _buildConnectionControls(theme),
              const SizedBox(height: 16),

              // Device Scan Panel
              DeviceScanPanel(
                devices: _devices.values.toList(),
                selectedDeviceId: _selectedDeviceId,
                isScanning: _isScanning,
                canConnect: _canConnect,
                canDisconnect: _canDisconnect,
                onToggleScan: _toggleScan,
                onConnect: _connectSelected,
                onDisconnect: _disconnect,
                onSelectDevice: (id) => setState(() => _selectedDeviceId = id),
                onRetryBootstrap: _canRetryBootstrap ? _retryBootstrap : null,
              ),
              const SizedBox(height: 16),

              // Command Panel
              CommandPanel(
                sessionReady: _sessionReady,
                streamActive: _streamActive,
                busy: _busy,
                onDeviceInfo: _readDeviceInfo,
                onTime: _readTime,
                onStartTest: _startTest,
                onLastReport: _lastReport,
                onMoistOn: _moistOn,
                onMoistOff: _moistOff,
                onFont: _fontEnglish,
                onCdn: _cdn,
              ),
              const SizedBox(height: 16),

              // Logs and Traces tabs
              _buildTabSection(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionControls(ThemeData theme) {
    final accentColor = _connectionAccentColor(theme);
    final stateLabel = _connectionState == DeviceConnectionState.disconnected
        ? 'Ready to scan'
        : _connectionState.name;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.hub_outlined, color: accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connection Controls',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _connectionSummary(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    stateLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Soil Test Demo',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Launch the guided hardware flow for connection, live moisture, and final soil report.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _openSoilTestFlow,
                      icon: const Icon(Icons.science_outlined, size: 18),
                      label: const Text('Try Soil Test'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Quick Actions',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _quickActionButton(
                  onPressed: _busy ? null : _requestPermissions,
                  icon: Icons.shield_outlined,
                  label: 'Permissions',
                ),
                if (_canRetryBootstrap)
                  _quickActionButton(
                    onPressed: _busy ? null : _retryBootstrap,
                    icon: Icons.refresh,
                    label: 'Bootstrap',
                    foregroundColor: Colors.orange.shade700,
                    borderColor: Colors.orange.shade300,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _connectionSummary() {
    if (_sessionReady) {
      return 'Session is active. You can run commands or jump into the soil test demo.';
    }
    if (_connectionState == DeviceConnectionState.disconnected) {
      return 'Scan and connect to a supported device to bootstrap the UCP session.';
    }
    if (_canRetryBootstrap) {
      return 'BLE link is up, but the UCP session is not active yet.';
    }
    return 'Connection progress is in flight. Wait for bootstrap to complete.';
  }

  Color _connectionAccentColor(ThemeData theme) {
    if (_sessionReady) {
      return const Color(0xFF2E7D32);
    }
    switch (_connectionState) {
      case DeviceConnectionState.connecting:
      case DeviceConnectionState.disconnecting:
        return Colors.orange;
      case DeviceConnectionState.error:
      case DeviceConnectionState.connectionLost:
        return theme.colorScheme.error;
      case DeviceConnectionState.connected:
      case DeviceConnectionState.servicesDiscovered:
      case DeviceConnectionState.notifySubscribed:
      case DeviceConnectionState.mtuReady:
      case DeviceConnectionState.transportReady:
        return theme.colorScheme.primary;
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  Widget _quickActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    Color? foregroundColor,
    Color? borderColor,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: foregroundColor,
        side: borderColor == null ? null : BorderSide(color: borderColor),
      ),
    );
  }

  Widget _buildTabSection(ThemeData theme) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.terminal, size: 18),
                    const SizedBox(width: 6),
                    Text('Logs (${_logEntries.length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.compare_arrows, size: 18),
                    const SizedBox(width: 6),
                    Text('Packets (${_packetTraces.length})'),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(
            height: 400,
            child: TabBarView(
              controller: _tabController,
              children: [
                LogViewer(logEntries: _logEntries),
                TraceViewer(
                  packetTraces: _packetTraces,
                  formatTrace: _formatTrace,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum LogLevel {
  info('INFO'),
  success('OK'),
  error('ERR'),
  state('STATE'),
  event('EVENT'),
  stream('STREAM');

  final String name;
  const LogLevel(this.name);
}

class LogEntry {
  final LogLevel level;
  final String message;
  final DateTime timestamp;

  LogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
  });
}
