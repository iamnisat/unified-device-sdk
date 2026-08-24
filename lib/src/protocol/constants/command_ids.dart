class SystemCommandIds {
  SystemCommandIds._();

  static const int rtcSync = 0x01;
  static const int reboot = 0x02;
  static const int idleReboot = 0x03;
  static const int setAunkurId = 0x04;

  static const int time = rtcSync;
  static const int deviceInfo = DeviceInfoCommandIds.getDeviceInfo;
}

class DeviceInfoCommandIds {
  DeviceInfoCommandIds._();

  static const int getDeviceInfo = 0x01;
  static const int setClientName = 0x02;
  static const int getClientNameLog = 0x03;

  static const int deviceInfo = getDeviceInfo;
}

class SessionCommandIds {
  SessionCommandIds._();

  static const int sessionOpenRtcSync = 0x01;
  static const int statusGet = 0x02;
  static const int event = 0x03;
  static const int safeDisconnectRequest = 0x04;
  static const int safeDisconnectCommit = 0x05;
  static const int heartbeat = 0x06;
  static const int abort = 0x07;
  static const int getLog = 0x08;
  static const int clearLog = 0x09;

  static const int sessionClose = safeDisconnectRequest;
  static const int btTransportOpen = 0x04;
}

class MeasurementCommandIds {
  MeasurementCommandIds._();

  static const int startSoilTest = 0x01;
  static const int stopSoilTest = 0x02;
  static const int startMoistureTest = 0x03;
  static const int stopMoistureTest = 0x04;
  static const int getLastReport = 0x05;

  static const int startTest = startSoilTest;
  static const int stopTest = stopSoilTest;
  static const int manTestPermit = 0x05;
}

class ReportCommandIds {
  ReportCommandIds._();

  static const int lastReport = MeasurementCommandIds.getLastReport;
}

class MoistureCommandIds {
  MoistureCommandIds._();

  static const int moistGetOn = MeasurementCommandIds.startMoistureTest;
  static const int moistGetOff = MeasurementCommandIds.stopMoistureTest;
}

class UiCommandIds {
  UiCommandIds._();

  static const int font = 0x07;
}

class ConnectivityCommandIds {
  ConnectivityCommandIds._();

  static const int cdn = DeviceInfoCommandIds.setClientName;
}

class CalibrationCommandIds {
  CalibrationCommandIds._();

  /// Start the calibration process.
  static const int calibrationStart = 0x01;

  /// Get current calibration status.
  static const int calibrationStatus = 0x02;

  /// Apply calibration values.
  static const int calibrationApply = 0x03;
}

class ConfigurationCommandIds {
  ConfigurationCommandIds._();

  /// Read a configuration parameter.
  static const int configRead = 0x08;

  /// Write a configuration parameter.
  static const int configWrite = 0x03;

  /// List all available configuration parameters.
  static const int configList = 0x01;

  static const int restoreDefault = 0x02;
  static const int setMinSampleSizePercent = 0x04;
  static const int setManualTestPermission = 0x05;
  static const int setSoilSensorAddress = 0x06;
  static const int setUiLanguage = 0x07;
}

class ReportHistoryCommandIds {
  ReportHistoryCommandIds._();

  /// Get a list of available report IDs.
  static const int reportList = 0x01;

  /// Get a specific historical report by ID.
  static const int reportGet = 0x02;

  /// Delete a specific historical report.
  static const int reportDelete = 0x03;

  /// Export report data.
  static const int reportExport = 0x04;
}

class FileTransferCommandIds {
  FileTransferCommandIds._();

  /// Start a file transfer session.
  static const int fileTransferStart = 0x01;

  /// Transfer a chunk of file data.
  static const int fileTransferChunk = 0x02;

  /// End a file transfer session.
  static const int fileTransferEnd = 0x03;

  /// Get file transfer status.
  static const int fileTransferStatus = 0x04;
}

class CommandIds {
  CommandIds._();

  static const int systemTime = SystemCommandIds.time;
  static const int systemDeviceInfo = DeviceInfoCommandIds.getDeviceInfo;
  static const int sessionOpenRtcSync = SessionCommandIds.sessionOpenRtcSync;
  static const int sessionClose = SessionCommandIds.sessionClose;
  static const int sessionHeartbeat = SessionCommandIds.heartbeat;
  static const int sessionBtTransportOpen = SessionCommandIds.btTransportOpen;
  static const int measurementStartTest = MeasurementCommandIds.startTest;
  static const int measurementStopTest = MeasurementCommandIds.stopTest;
  static const int measurementManTestPermit =
      MeasurementCommandIds.manTestPermit;
  static const int reportLastReport = ReportCommandIds.lastReport;
  static const int moistureGetOn = MoistureCommandIds.moistGetOn;
  static const int moistureGetOff = MoistureCommandIds.moistGetOff;
  static const int uiFont = UiCommandIds.font;
  static const int connectivityCdn = ConnectivityCommandIds.cdn;
  static const int calibrationStart = CalibrationCommandIds.calibrationStart;
  static const int calibrationStatus = CalibrationCommandIds.calibrationStatus;
  static const int calibrationApply = CalibrationCommandIds.calibrationApply;
  static const int configRead = ConfigurationCommandIds.configRead;
  static const int configWrite = ConfigurationCommandIds.configWrite;
  static const int configList = ConfigurationCommandIds.configList;
  static const int reportList = ReportHistoryCommandIds.reportList;
  static const int reportGet = ReportHistoryCommandIds.reportGet;
  static const int reportDelete = ReportHistoryCommandIds.reportDelete;
  static const int reportExport = ReportHistoryCommandIds.reportExport;
  static const int fileTransferStart = FileTransferCommandIds.fileTransferStart;
  static const int fileTransferChunk = FileTransferCommandIds.fileTransferChunk;
  static const int fileTransferEnd = FileTransferCommandIds.fileTransferEnd;
  static const int fileTransferStatus =
      FileTransferCommandIds.fileTransferStatus;
}
