import 'decoded_tlv.dart';
import '../constants/ucp_status_codes.dart';

/// Official NACK details decoded from TLVs.
class UcpNackDetails {
  final int? status;
  final int? errorCode;
  final String? text;
  final List<DecodedTlv> tlvs;

  const UcpNackDetails({
    this.status,
    this.errorCode,
    this.text,
    this.tlvs = const <DecodedTlv>[],
  });

  int? get effectiveCode => errorCode ?? status;
  UcpStatusCodeInfo? get statusInfo => UcpStatusCodes.lookup(effectiveCode);
  String? get errorName => statusInfo?.name;
  String? get errorDescription => statusInfo?.description;
  bool get isRetryable => statusInfo?.retryable ?? false;

  String get displayMessage {
    final normalizedText = text?.trim();
    final info = statusInfo;
    if (normalizedText != null && normalizedText.isNotEmpty) {
      return info == null || info.isOk
          ? normalizedText
          : '${info.name}: $normalizedText';
    }
    if (info != null) {
      return '${info.name}: ${info.description}';
    }
    return 'Device returned NACK';
  }
}
