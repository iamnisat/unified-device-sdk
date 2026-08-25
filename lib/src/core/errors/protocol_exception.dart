import 'unified_device_exception.dart';
import '../../protocol/constants/ucp_status_codes.dart';

/// Exception thrown for higher-level protocol errors.
class ProtocolException extends UnifiedDeviceException {
  final ProtocolErrorType protocolErrorType;

  const ProtocolException(
    super.message, {
    super.errorCode,
    super.stackTrace,
    this.protocolErrorType = ProtocolErrorType.unknown,
  });

  UcpStatusCodeInfo? get ucpStatus => UcpStatusCodes.lookup(errorCode);
  String? get errorName => ucpStatus?.name;
  String? get errorDescription => ucpStatus?.description;
  bool get isRetryable => ucpStatus?.retryable ?? false;

  @override
  String toString() => 'ProtocolException[$protocolErrorType]: $message';
}

/// Categorizes protocol errors for easier handling.
enum ProtocolErrorType {
  /// Unsupported command.
  unsupportedCommand,

  /// Invalid command parameters.
  invalidParameters,

  /// Device returned a NACK response.
  nackReceived,

  /// Response parsing failed.
  responseParsingFailed,

  /// Unexpected response sequence.
  unexpectedSequence,

  /// Device is in an invalid state.
  invalidDeviceState,

  /// Command not allowed in current mode.
  commandNotAllowed,

  /// Unknown or uncategorized error.
  unknown,
}
