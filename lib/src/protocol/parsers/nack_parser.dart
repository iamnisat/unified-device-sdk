import '../../core/errors/protocol_exception.dart';
import '../../core/response/device_response.dart';
import '../../protocol/constants/operation_codes.dart';
import '../models/ucp_nack_details.dart';
import 'common_response_parser.dart';

/// Optional parser for generic NACK responses.
class NackParser {
  final CommonResponseParser _responseParser;

  const NackParser({
    CommonResponseParser responseParser = const CommonResponseParser(),
  }) : _responseParser = responseParser;

  /// Converts a NACK response into a [ProtocolException].
  ///
  /// Supports production TLV NACKs and legacy raw one/two-byte error payloads.
  ProtocolException parse(DeviceResponse response) {
    if (response.op != OperationCodes.nack) {
      throw const ProtocolException(
        'Response is not a NACK frame',
        protocolErrorType: ProtocolErrorType.responseParsingFailed,
      );
    }

    final details = parseDetails(response);
    final message = details.text == null && response.errorMessage != null
        ? response.errorMessage!
        : details.displayMessage;
    return ProtocolException(
      message,
      errorCode: details.effectiveCode ?? _flagErrorCode(response),
      protocolErrorType: ProtocolErrorType.nackReceived,
    );
  }

  UcpNackDetails parseDetails(DeviceResponse response) {
    return _responseParser.parseNack(response);
  }

  int? _flagErrorCode(DeviceResponse response) =>
      response.flags == 0 ? null : response.flags;
}
