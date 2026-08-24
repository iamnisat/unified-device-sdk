class CommonCommandIds {
  CommonCommandIds._();

  static const int time = 0x01;
  static const int deviceInfo = 0x01;
  static const int sessionOpenRtcSync = 0x01;
  static const int sessionClose = 0x04;
  static const int heartbeat = 0x06;
  static const int btTransportOpen = 0x04;
  static const int startTest = 0x01;
  static const int stopTest = 0x02;
  static const int manTestPermit = 0x05;
  static const int lastReport = 0x05;
  static const int moistGetOn = 0x03;
  static const int moistGetOff = 0x04;
  static const int font = 0x07;
  static const int cdn = 0x02;

  // Legacy aliases retained for older call sites.
  static const int readDeviceInfo = deviceInfo;
  static const int setTime = time;
  static const int ping = heartbeat;
  static const int readFirmwareVersion = 0xF0;
  static const int readBattery = 0xF1;
}
