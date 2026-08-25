import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unified_device_sdk/unified_device_sdk.dart';

enum SoilTestFlowStage {
  connecting,
  connected,
  readyToStartMoisture,
  moistureRunning,
  readyToStartSoilTest,
  soilTestRunning,
  fetchingReport,
  resultReady,
  error,
}

class SoilTestScreen extends StatefulWidget {
  final UnifiedDeviceClient client;
  final bool disposeClientOnExit;

  const SoilTestScreen({
    super.key,
    required this.client,
    this.disposeClientOnExit = false,
  });

  @override
  State<SoilTestScreen> createState() => _SoilTestScreenState();
}

class _SoilTestScreenState extends State<SoilTestScreen> {
  static const int _maxActivityLines = 24;

  late final UnifiedDeviceClient _client;
  late final List<StreamSubscription<dynamic>> _subscriptions;

  SoilTestFlowStage _stage = SoilTestFlowStage.connecting;
  UcpMoistureSample? _latestMoistureSample;
  UcpLastReport? _lastReport;
  String _progressMessage = 'Waiting for an active UCP session.';
  int? _soilTestProgressPercent;
  String? _errorMessage;
  final List<String> _activityLines = <String>[];
  Future<void> Function()? _retryAction;
  bool _actionInFlight = false;
  bool _reportFetchInFlight = false;
  bool _resultDialogShown = false;

  @override
  void initState() {
    super.initState();
    _client = widget.client;
    _stage = _client.isSessionActive
        ? SoilTestFlowStage.readyToStartMoisture
        : SoilTestFlowStage.connecting;
    _progressMessage = _client.isSessionActive
        ? 'Session active. Start a live moisture read first.'
        : 'Waiting for the device session to become active.';
    _subscriptions = <StreamSubscription<dynamic>>[
      _client.connectionState.listen(_handleConnectionState),
      _client.moistureSamples.listen(_handleMoistureSample),
      _client.events.listen(_handleEvent),
      _client.communicationLogs.listen(_handleCommunicationLog),
    ];
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    if (widget.disposeClientOnExit) {
      unawaited(_client.dispose());
    }
    super.dispose();
  }

  bool get _canSendCommands => _client.isSessionActive;

  Future<void> _startMoisture() async {
    if (!_canSendCommands) {
      _setError(
        'The UCP session is not active yet.',
        retryAction: _startMoisture,
      );
      return;
    }
    await _runAction(
      progressMessage: 'Starting live moisture stream...',
      retryAction: _startMoisture,
      action: () async {
        await _client.moistGetOn();
        setState(() {
          _stage = SoilTestFlowStage.moistureRunning;
          _errorMessage = null;
          _progressMessage = 'Live moisture stream is running.';
        });
        _addActivity('moist_get_on ACK accepted');
      },
    );
  }

  Future<void> _stopMoisture() async {
    if (!_canSendCommands) {
      _setError(
        'The UCP session is not active yet.',
        retryAction: _stopMoisture,
      );
      return;
    }
    await _runAction(
      progressMessage: 'Stopping live moisture stream...',
      retryAction: _stopMoisture,
      action: () async {
        await _client.moistGetOff();
        setState(() {
          _stage = SoilTestFlowStage.readyToStartSoilTest;
          _errorMessage = null;
          _progressMessage =
              'Moisture stream stopped. You can start the soil test.';
        });
        _addActivity('moist_get_off ACK accepted');
      },
    );
  }

  Future<void> _startSoilTest() async {
    if (!_canSendCommands) {
      _setError(
        'The UCP session is not active yet.',
        retryAction: _startSoilTest,
      );
      return;
    }
    if (_client.currentSession?.streamActive ?? false) {
      _setError(
        'Stop the moisture stream before starting the soil test.',
        retryAction: _stopMoisture,
      );
      return;
    }
    await _runAction(
      progressMessage: 'Starting soil test...',
      retryAction: _startSoilTest,
      action: () async {
        _resultDialogShown = false;
        await _client.startTest(
          agentId: 'AGENT-DEMO1',
          farmerId: 'FARMER-0012',
          fieldIndex: 'FIELD-A3',
          fieldTestIndex: 'TEST-0001',
        );
        setState(() {
          _stage = SoilTestFlowStage.soilTestRunning;
          _errorMessage = null;
          _lastReport = null;
          _soilTestProgressPercent = 0;
          _progressMessage =
              'start_test ACK accepted. Waiting for device progress events...';
        });
        _addActivity('start_test ACK accepted');
      },
    );
  }

  Future<void> _fetchLastReport({bool afterCompletion = false}) async {
    if (_reportFetchInFlight) {
      return;
    }
    if (!afterCompletion &&
        (_client.currentSession?.measurementActive ?? false)) {
      setState(() {
        _stage = SoilTestFlowStage.soilTestRunning;
        _errorMessage = null;
        _progressMessage =
            'Device is still running the soil test. Waiting for completion before fetching the report.';
      });
      _addActivity('last_report skipped: DEVICE_BUSY');
      return;
    }
    _reportFetchInFlight = true;
    setState(() {
      _stage = SoilTestFlowStage.fetchingReport;
      _errorMessage = null;
      _progressMessage = 'Fetching the final soil test report...';
    });
    try {
      final report = await _client.lastReport();
      if (!mounted) {
        return;
      }
      setState(() {
        _lastReport = report;
        _stage = SoilTestFlowStage.resultReady;
        _soilTestProgressPercent = 100;
        _progressMessage = 'Result ready.';
        _retryAction = null;
      });
      _addActivity('last_report DATA received');
      _showResultDialog();
    } on ProtocolException catch (error) {
      if (error.errorCode == UcpStatusCodes.deviceBusy) {
        if (!mounted) {
          return;
        }
        setState(() {
          _stage = SoilTestFlowStage.soilTestRunning;
          _errorMessage = null;
          _progressMessage =
              'Device is busy running the soil test. The report will be available after the final completion status.';
          _retryAction = null;
        });
        _addActivity('last_report blocked: DEVICE_BUSY');
        return;
      }
      _setError(
        'Could not fetch the final report: ${_friendlyError(error)}',
        retryAction: _fetchLastReport,
      );
    } on Object catch (error) {
      _setError(
        'Could not fetch the final report: ${_friendlyError(error)}',
        retryAction: _fetchLastReport,
      );
    } finally {
      _reportFetchInFlight = false;
    }
  }

  Future<void> _runAction({
    required String progressMessage,
    required Future<void> Function() action,
    required Future<void> Function() retryAction,
  }) async {
    if (_actionInFlight) {
      return;
    }
    setState(() {
      _actionInFlight = true;
      _errorMessage = null;
      _retryAction = retryAction;
      _progressMessage = progressMessage;
    });
    try {
      await action();
    } on Object catch (error) {
      _setError(_friendlyError(error), retryAction: retryAction);
    } finally {
      if (mounted) {
        setState(() {
          _actionInFlight = false;
        });
      }
    }
  }

  void _handleConnectionState(DeviceConnectionState state) {
    if (!mounted) {
      return;
    }
    setState(() {
      if (state == DeviceConnectionState.sessionActive &&
          _stage == SoilTestFlowStage.connecting) {
        _stage = SoilTestFlowStage.readyToStartMoisture;
        _progressMessage = 'Session active. Start a live moisture read first.';
      }
    });
    _addActivity('State: ${_stateLabel(state)}');

    if (state == DeviceConnectionState.disconnected ||
        state == DeviceConnectionState.connectionLost ||
        state == DeviceConnectionState.error) {
      _setError('Device connection is no longer active.', retryAction: null);
    }
  }

  void _handleMoistureSample(UcpMoistureSample sample) {
    if (!mounted) {
      return;
    }
    setState(() {
      _latestMoistureSample = sample;
      if (_stage == SoilTestFlowStage.readyToStartMoisture) {
        _stage = SoilTestFlowStage.moistureRunning;
      }
    });
  }

  Future<void> _handleEvent(DeviceEvent event) async {
    final frame = event.sourceFrame;
    if (frame == null) {
      return;
    }
    if (frame.commandClass != CommandClasses.measurement ||
        frame.commandId != MeasurementCommandIds.startTest) {
      return;
    }

    final decoded = _client.responseManager.decodeTlvs(frame);
    final status =
        _findInt(decoded, TlvTypes.statusCode) ??
        _findInt(decoded, TlvTypes.statusU8);
    final text =
        _findString(decoded, TlvTypes.messageText) ??
        _findString(decoded, TlvTypes.textUtf8);
    final firmwareState = _findInt(decoded, TlvTypes.fwStateU8);
    final progressPercent = _findInt(decoded, TlvTypes.sampleSizePercent);
    final message = text?.trim();
    final progress = _soilTestProgressMessage(
      progressPercent: progressPercent,
      message: message,
      status: status,
    );
    final hasError = (status != null && status != 0) || firmwareState == 6;

    if (!mounted) {
      return;
    }
    if (hasError) {
      setState(() {
        if (progressPercent != null) {
          _soilTestProgressPercent = progressPercent.clamp(0, 100).toInt();
        }
      });
      _setError(_soilTestErrorMessage(message), retryAction: _startSoilTest);
      return;
    }

    setState(() {
      if (_stage != SoilTestFlowStage.fetchingReport) {
        _stage = SoilTestFlowStage.soilTestRunning;
      }
      if (progressPercent != null) {
        _soilTestProgressPercent = progressPercent.clamp(0, 100).toInt();
      }
      _progressMessage = progress;
      _errorMessage = null;
    });
    _addActivity('EVENT: $progress');

    final complete = status == 4 || firmwareState == 5;
    if (complete) {
      await Future.delayed(Duration(seconds: 2));
      unawaited(_fetchLastReport(afterCompletion: true));
    }
  }

  void _handleCommunicationLog(DeviceCommunicationLog log) {
    final event = log.param['event'] as String?;
    if (event == null) {
      return;
    }
    if (event == 'command_result') {
      final commandName = log.param['cmdName'] as String?;
      final result = log.param['result'] as String?;
      if (commandName != null && result != null) {
        _addActivity('${commandName.toUpperCase()} ${result.toUpperCase()}');
      }
      return;
    }
    if (event == 'event_received' || event == 'stream_received') {
      return;
    }
    _addActivity('SDK: $event');
  }

  int? _findInt(List<DecodedTlv> tlvs, int type) {
    for (final tlv in tlvs) {
      if (tlv.type == type && tlv.value is int) {
        return tlv.value as int;
      }
    }
    return null;
  }

  String? _findString(List<DecodedTlv> tlvs, int type) {
    for (final tlv in tlvs) {
      if (tlv.type == type && tlv.value is String) {
        return tlv.value as String;
      }
    }
    return null;
  }

  String _soilTestProgressMessage({
    required int? progressPercent,
    required String? message,
    required int? status,
  }) {
    if (progressPercent != null) {
      final percent = progressPercent.clamp(0, 100).toInt();
      if (percent >= 100) {
        return 'Soil test progress: 100%. Waiting for final device status...';
      }
      return 'Soil test progress: $percent%.';
    }
    if (message != null && message.isNotEmpty) {
      return message;
    }
    if (status != null) {
      return 'Soil test progress update ($status).';
    }
    return 'Soil test event received.';
  }

  String _soilTestErrorMessage(String? diagnosticText) {
    if (diagnosticText == null || diagnosticText.isEmpty) {
      return 'Device reported soil test error.';
    }
    return 'Device reported soil test error: $diagnosticText.';
  }

  void _setError(String message, {Future<void> Function()? retryAction}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = SoilTestFlowStage.error;
      _errorMessage = message;
      _retryAction = retryAction;
      _progressMessage = 'The flow hit an error.';
    });
    _addActivity('Error: $message');
  }

  void _resetFlow() {
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = _client.isSessionActive
          ? SoilTestFlowStage.readyToStartMoisture
          : SoilTestFlowStage.connecting;
      _errorMessage = null;
      _retryAction = null;
      _reportFetchInFlight = false;
      _lastReport = null;
      _latestMoistureSample = null;
      _soilTestProgressPercent = null;
      _progressMessage = _client.isSessionActive
          ? 'Session active. Start a live moisture read first.'
          : 'Waiting for the device session to become active.';
      _resultDialogShown = false;
    });
    _addActivity('Flow reset');
  }

  void _showResultDialog() {
    if (_resultDialogShown || !mounted || _lastReport == null) {
      return;
    }
    _resultDialogShown = true;
    final report = _lastReport!;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Soil Test Result'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _resultRow('Nitrogen', report.nitrogen),
              _resultRow('Phosphorus', report.phosphorus),
              _resultRow('Potassium', report.potassium),
              _resultRow('Moisture', report.moisture),
              _resultRow('Temperature', report.temperature),
              _resultRow('EC', report.ec),
              _resultRow('pH', report.ph),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    });
  }

  Widget _resultRow(String label, double? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(_formatValue(value)),
        ],
      ),
    );
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

  String _stageLabel() {
    return switch (_stage) {
      SoilTestFlowStage.connecting => 'Connecting',
      SoilTestFlowStage.connected => 'Connected',
      SoilTestFlowStage.readyToStartMoisture => 'Ready to start moisture',
      SoilTestFlowStage.moistureRunning => 'Moisture running',
      SoilTestFlowStage.readyToStartSoilTest => 'Ready to start soil test',
      SoilTestFlowStage.soilTestRunning => 'Soil test running',
      SoilTestFlowStage.fetchingReport => 'Fetching report',
      SoilTestFlowStage.resultReady => 'Result ready',
      SoilTestFlowStage.error => 'Error',
    };
  }

  String _primaryButtonLabel() {
    return switch (_stage) {
      SoilTestFlowStage.connecting => 'Connecting...',
      SoilTestFlowStage.connected => 'Continue',
      SoilTestFlowStage.readyToStartMoisture => 'Start Moisture',
      SoilTestFlowStage.moistureRunning => 'Stop Moisture',
      SoilTestFlowStage.readyToStartSoilTest => 'Start Soil Test',
      SoilTestFlowStage.soilTestRunning => 'Testing...',
      SoilTestFlowStage.fetchingReport => 'Fetching Result...',
      SoilTestFlowStage.resultReady => 'Start Again',
      SoilTestFlowStage.error => 'Retry',
    };
  }

  Future<void> Function()? _primaryButtonAction() {
    if (_actionInFlight || _stage == SoilTestFlowStage.soilTestRunning) {
      return null;
    }
    return switch (_stage) {
      SoilTestFlowStage.readyToStartMoisture => _startMoisture,
      SoilTestFlowStage.moistureRunning => _stopMoisture,
      SoilTestFlowStage.readyToStartSoilTest => _startSoilTest,
      SoilTestFlowStage.resultReady => () async => _resetFlow(),
      SoilTestFlowStage.error => () async {
        final retry = _retryAction;
        if (retry != null) {
          await retry();
          return;
        }
        _resetFlow();
      },
      _ => null,
    };
  }

  String _formatValue(double? value) {
    if (value == null) {
      return '--';
    }
    return value.toStringAsFixed(2);
  }

  Color _stageColor(ThemeData theme) {
    return switch (_stage) {
      SoilTestFlowStage.connecting => theme.colorScheme.primary,
      SoilTestFlowStage.connected => theme.colorScheme.primary,
      SoilTestFlowStage.readyToStartMoisture => const Color(0xFF1565C0),
      SoilTestFlowStage.moistureRunning => const Color(0xFF0277BD),
      SoilTestFlowStage.readyToStartSoilTest => const Color(0xFF2E7D32),
      SoilTestFlowStage.soilTestRunning => Colors.orange.shade700,
      SoilTestFlowStage.fetchingReport => Colors.deepOrange.shade600,
      SoilTestFlowStage.resultReady => const Color(0xFF2E7D32),
      SoilTestFlowStage.error => theme.colorScheme.error,
    };
  }

  IconData _stageIcon() {
    return switch (_stage) {
      SoilTestFlowStage.connecting => Icons.bluetooth_searching,
      SoilTestFlowStage.connected => Icons.bluetooth_connected,
      SoilTestFlowStage.readyToStartMoisture => Icons.water_drop_outlined,
      SoilTestFlowStage.moistureRunning => Icons.water_drop,
      SoilTestFlowStage.readyToStartSoilTest => Icons.science_outlined,
      SoilTestFlowStage.soilTestRunning => Icons.biotech_outlined,
      SoilTestFlowStage.fetchingReport => Icons.inventory_2_outlined,
      SoilTestFlowStage.resultReady => Icons.verified_outlined,
      SoilTestFlowStage.error => Icons.warning_amber_rounded,
    };
  }

  String _stageDescription() {
    return switch (_stage) {
      SoilTestFlowStage.connecting =>
        'Waiting for the active device session before commands can be sent.',
      SoilTestFlowStage.connected =>
        'Hardware is connected and preparing the soil test workflow.',
      SoilTestFlowStage.readyToStartMoisture =>
        'Start live moisture streaming to inspect the probe before testing.',
      SoilTestFlowStage.moistureRunning =>
        'Moisture samples are streaming in real time from the device.',
      SoilTestFlowStage.readyToStartSoilTest =>
        'Moisture is stopped. The device is ready to run the soil test.',
      SoilTestFlowStage.soilTestRunning =>
        'The device is running the soil analysis. Progress events will appear below.',
      SoilTestFlowStage.fetchingReport =>
        'The measurement finished. Fetching the final report from device memory.',
      SoilTestFlowStage.resultReady =>
        'The latest soil report is available and ready to review.',
      SoilTestFlowStage.error =>
        'The workflow paused because a step failed or the session dropped.',
    };
  }

  IconData _primaryButtonIcon() {
    return switch (_stage) {
      SoilTestFlowStage.readyToStartMoisture => Icons.play_arrow_rounded,
      SoilTestFlowStage.moistureRunning => Icons.stop_rounded,
      SoilTestFlowStage.readyToStartSoilTest => Icons.science_outlined,
      SoilTestFlowStage.resultReady => Icons.restart_alt_rounded,
      SoilTestFlowStage.error => Icons.refresh_rounded,
      _ => Icons.hourglass_top_rounded,
    };
  }

  String _flowSummaryLabel() {
    if (_stage == SoilTestFlowStage.error && _errorMessage != null) {
      return 'Needs attention';
    }
    return switch (_stage) {
      SoilTestFlowStage.connecting => 'Preparing device',
      SoilTestFlowStage.connected => 'Connected',
      SoilTestFlowStage.readyToStartMoisture => 'Moisture check pending',
      SoilTestFlowStage.moistureRunning => 'Moisture streaming',
      SoilTestFlowStage.readyToStartSoilTest => 'Ready for soil test',
      SoilTestFlowStage.soilTestRunning => 'Test in progress',
      SoilTestFlowStage.fetchingReport => 'Fetching report',
      SoilTestFlowStage.resultReady => 'Report ready',
      SoilTestFlowStage.error => 'Needs attention',
    };
  }

  String _activeStreamLabel() {
    return _client.currentSession?.streamActive ?? false
        ? 'Running'
        : 'Stopped';
  }

  bool _stepComplete(String step) {
    return switch (step) {
      'connect' => _client.isSessionActive,
      'moisture' =>
        _stage.index >= SoilTestFlowStage.moistureRunning.index ||
            _stage == SoilTestFlowStage.resultReady,
      'test' =>
        _stage.index >= SoilTestFlowStage.soilTestRunning.index ||
            _stage == SoilTestFlowStage.resultReady,
      'report' => _stage == SoilTestFlowStage.resultReady,
      _ => false,
    };
  }

  bool _stepActive(String step) {
    return switch (step) {
      'connect' => !_client.isSessionActive,
      'moisture' =>
        _stage == SoilTestFlowStage.readyToStartMoisture ||
            _stage == SoilTestFlowStage.moistureRunning,
      'test' =>
        _stage == SoilTestFlowStage.readyToStartSoilTest ||
            _stage == SoilTestFlowStage.soilTestRunning,
      'report' =>
        _stage == SoilTestFlowStage.fetchingReport ||
            _stage == SoilTestFlowStage.resultReady,
      _ => false,
    };
  }

  bool get _showSoilTestProgress =>
      _soilTestProgressPercent != null &&
      (_stage == SoilTestFlowStage.soilTestRunning ||
          _stage == SoilTestFlowStage.fetchingReport ||
          _stage == SoilTestFlowStage.resultReady ||
          _stage == SoilTestFlowStage.error);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.eco_outlined, color: _stageColor(theme)),
            const SizedBox(width: 8),
            const Text('Soil Test Demo'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              unawaited(_fetchLastReport(afterCompletion: true));
            },
            icon: Icon(Icons.read_more),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomActionBar(theme),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _buildHeroCard(theme),
          const SizedBox(height: 16),
          _buildOverviewCard(theme),
          const SizedBox(height: 16),
          _buildMoistureCard(theme),
          const SizedBox(height: 16),
          if (_lastReport != null) ...[
            _buildResultPreviewCard(theme),
            const SizedBox(height: 16),
          ],
          _buildProgressCard(theme),
          const SizedBox(height: 16),
          _buildActivityCard(theme),
          const SizedBox(height: 88),
        ],
      ),
    );
  }

  Widget _buildHeroCard(ThemeData theme) {
    final accent = _stageColor(theme);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.96),
            accent.withValues(alpha: 0.78),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_stageIcon(), color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Soil Test Workflow',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _flowSummaryLabel(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _stageDescription(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _heroChip(
                  icon: Icons.vpn_key_outlined,
                  label: _client.isSessionActive
                      ? 'Session Active'
                      : 'Session Pending',
                ),

                _heroChip(icon: Icons.flag_outlined, label: _stageLabel()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.dashboard_customize_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Overview',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _metricTile(
                    theme,
                    icon: Icons.vpn_key_outlined,
                    label: 'Session',
                    value: _client.isSessionActive ? 'Ready' : 'Pending',
                    color: _client.isSessionActive
                        ? const Color(0xFF2E7D32)
                        : Colors.orange.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricTile(
                    theme,
                    icon: Icons.water_drop_outlined,
                    label: 'Stream',
                    value: _activeStreamLabel(),
                    color: _client.currentSession?.streamActive ?? false
                        ? const Color(0xFF0277BD)
                        : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricTile(
                    theme,
                    icon: Icons.route_outlined,
                    label: 'Step',
                    value: _flowSummaryLabel(),
                    color: _stageColor(theme),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoistureCard(ThemeData theme) {
    final sample = _latestMoistureSample;
    final moistureColor = sample?.moisturePercent != null
        ? const Color(0xFF0277BD)
        : Colors.grey.shade700;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: moistureColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.water_drop_outlined,
                    color: moistureColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Moisture',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Real-time stream data from `moist_get_on`.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatValue(sample?.moisturePercent),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: moistureColor,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '%',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: moistureColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _softInfoChip(
              theme,
              icon: Icons.memory_outlined,
              label: _client.currentSession?.streamActive ?? false
                  ? 'Stream running'
                  : 'Stream stopped',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultPreviewCard(ThemeData theme) {
    final report = _lastReport!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics_outlined,
                  size: 20,
                  color: const Color(0xFF2E7D32),
                ),
                const SizedBox(width: 8),
                Text(
                  'Latest Report Snapshot',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _resultMetricTile(
                  theme,
                  'Nitrogen',
                  report.nitrogen,
                  Icons.spa,
                ),
                _resultMetricTile(
                  theme,
                  'Phosphorus',
                  report.phosphorus,
                  Icons.scatter_plot_outlined,
                ),
                _resultMetricTile(
                  theme,
                  'Potassium',
                  report.potassium,
                  Icons.grain_outlined,
                ),
                _resultMetricTile(
                  theme,
                  'Moisture',
                  report.moisture,
                  Icons.water_drop_outlined,
                ),
                _resultMetricTile(
                  theme,
                  'pH',
                  report.ph,
                  Icons.science_outlined,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(ThemeData theme) {
    final hasError = _stage == SoilTestFlowStage.error && _errorMessage != null;
    final stageColor = _stageColor(theme);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.timeline_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Workflow Progress',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: stageColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _stageLabel(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: stageColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _progressStepNode(
                    theme,
                    icon: Icons.link_outlined,
                    label: 'Connect',
                    complete: _stepComplete('connect'),
                    active: _stepActive('connect'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _progressStepNode(
                    theme,
                    icon: Icons.water_drop_outlined,
                    label: 'Moisture',
                    complete: _stepComplete('moisture'),
                    active: _stepActive('moisture'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _progressStepNode(
                    theme,
                    icon: Icons.biotech_outlined,
                    label: 'Test',
                    complete: _stepComplete('test'),
                    active: _stepActive('test'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _progressStepNode(
                    theme,
                    icon: Icons.inventory_2_outlined,
                    label: 'Report',
                    complete: _stepComplete('report'),
                    active: _stepActive('report'),
                  ),
                ),
              ],
            ),
            if (_showSoilTestProgress) ...[
              const SizedBox(height: 12),
              _buildSoilTestProgressMeter(theme),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasError
                    ? theme.colorScheme.error.withValues(alpha: 0.08)
                    : theme.colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasError
                      ? theme.colorScheme.error.withValues(alpha: 0.22)
                      : theme.colorScheme.primary.withValues(alpha: 0.10),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    hasError
                        ? Icons.error_outline_rounded
                        : Icons.info_outline_rounded,
                    size: 18,
                    color: hasError
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasError ? 'Issue' : 'Status',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: hasError
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasError ? _errorMessage! : _progressMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoilTestProgressMeter(ThemeData theme) {
    final percent = (_soilTestProgressPercent ?? 0).clamp(0, 100).toInt();
    final progressColor = _stage == SoilTestFlowStage.error
        ? theme.colorScheme.error
        : _stageColor(theme);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: progressColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: progressColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined, size: 18, color: progressColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Soil test sample progress',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: progressColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: progressColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 8,
              backgroundColor: progressColor.withValues(alpha: 0.16),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _stageDescription(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _primaryButtonAction(),
                icon: _actionInFlight
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_primaryButtonIcon()),
                label: _actionInFlight
                    ? const Text('Working...')
                    : Text(_primaryButtonLabel()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Recent Activity',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_activityLines.isEmpty)
              const Text('No activity yet.')
            else
              ..._activityLines
                  .take(10)
                  .map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 6),
                            decoration: BoxDecoration(
                              color: _stageColor(theme).withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              line,
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _heroChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              fontSize: 10,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _softInfoChip(
    ThemeData theme, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultMetricTile(
    ThemeData theme,
    String label,
    double? value,
    IconData icon,
  ) {
    return Container(
      constraints: const BoxConstraints(minWidth: 130, maxWidth: 160),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2E7D32)),
          const SizedBox(height: 10),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatValue(value),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressStepNode(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required bool complete,
    required bool active,
  }) {
    final color = complete
        ? const Color(0xFF2E7D32)
        : active
        ? _stageColor(theme)
        : Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: complete || active ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              complete ? Icons.check_rounded : icon,
              size: 15,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
