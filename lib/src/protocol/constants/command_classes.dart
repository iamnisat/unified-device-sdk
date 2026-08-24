class CommandClasses {
  CommandClasses._();

  static const int system = 0x01;
  static const int deviceInfo = 0x02;
  static const int configuration = 0x03;
  static const int measurement = 0x04;
  static const int calibration = 0x05;
  static const int dataLog = 0x06;
  static const int firmwareUpdate = 0x07;
  static const int diagnostic = 0x08;
  static const int session = 0x09;
  static const int power = 0x0A;

  // Legacy semantic aliases mapped onto the production command model.
  static const int report = measurement;
  static const int moisture = measurement;
  static const int ui = configuration;
  static const int connectivity = deviceInfo;
  static const int fileTransfer = dataLog;

  static bool isValid(int value) => value >= 0x00 && value <= 0xFF;
}
