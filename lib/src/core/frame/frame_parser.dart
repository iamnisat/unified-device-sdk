import '../bytes/endian_utils.dart';
import '../crc/crc16_ccitt.dart';
import '../errors/crc_exception.dart';
import '../errors/frame_exception.dart';
import '../errors/protocol_exception.dart';
import '../../protocol/constants/protocol_constants.dart';
import '../../protocol/models/tlv.dart';
import '../../protocol/parsers/tlv_parser.dart';
import 'device_frame.dart';

/// Parses bytes into [UcpFrame] objects using the official UCP layout.
class UcpFrameParser {
  final int sof;
  final int eof;
  final Crc16Ccitt crc;
  final TlvParser tlvParser;

  UcpFrameParser({
    this.sof = ProtocolConstants.sof,
    this.eof = ProtocolConstants.eof,
    Crc16Ccitt? crc,
    TlvParser? tlvParser,
  }) : crc = crc ?? Crc16Ccitt.ccittFalse(),
       tlvParser = tlvParser ?? const TlvParser();

  UcpFrame parse(List<int> bytes) {
    if (bytes.length < ProtocolConstants.minFrameSize) {
      throw FrameException(
        'Frame too short: ${bytes.length} bytes '
        '(minimum ${ProtocolConstants.minFrameSize})',
        frameErrorType: FrameErrorType.frameTooShort,
      );
    }

    if (bytes.first != sof) {
      throw FrameException(
        'Invalid SOF: expected 0x${_hex8(sof)}, got 0x${_hex8(bytes.first)}',
        frameErrorType: FrameErrorType.invalidSof,
        errorCode: bytes.first,
      );
    }

    if (bytes.last != eof) {
      throw FrameException(
        'Invalid EOF: expected 0x${_hex8(eof)}, got 0x${_hex8(bytes.last)}',
        frameErrorType: FrameErrorType.invalidEof,
        errorCode: bytes.last,
      );
    }

    final payloadLength = EndianUtils.bytesToUint16BE(
      bytes,
      ProtocolConstants.payloadLengthOffset,
    );
    final expectedLength =
        ProtocolConstants.headerSize +
        payloadLength +
        ProtocolConstants.trailerSize;
    if (bytes.length != expectedLength) {
      throw FrameException(
        'Length mismatch: header declares payload of $payloadLength bytes '
        '($expectedLength total), but actual frame is ${bytes.length} bytes',
        frameErrorType: FrameErrorType.lengthMismatch,
        errorCode: payloadLength,
      );
    }

    final payloadEnd = ProtocolConstants.payloadOffset + payloadLength;
    final payload = bytes.sublist(ProtocolConstants.payloadOffset, payloadEnd);
    final declaredCrc = EndianUtils.bytesToUint16BE(bytes, payloadEnd);
    final computedCrc = crc.compute(
      bytes.sublist(ProtocolConstants.versionOffset, payloadEnd),
    );
    if (computedCrc != declaredCrc) {
      throw CrcException(
        'CRC mismatch',
        expectedCrc: computedCrc,
        actualCrc: declaredCrc,
      );
    }

    try {
      final tlvs = _tryParseTlvs(payload);
      return UcpFrame(
        version: bytes[ProtocolConstants.versionOffset],
        productId: bytes[ProtocolConstants.productOffset],
        profileId: bytes[ProtocolConstants.profileOffset],
        sourceAddress: bytes[ProtocolConstants.sourceOffset],
        destinationAddress: bytes[ProtocolConstants.destinationOffset],
        op: bytes[ProtocolConstants.operationOffset],
        commandClass: bytes[ProtocolConstants.commandClassOffset],
        commandId: bytes[ProtocolConstants.commandOffset],
        sequence: EndianUtils.bytesToUint16BE(
          bytes,
          ProtocolConstants.sequenceOffset,
        ),
        flags: bytes[ProtocolConstants.flagsOffset],
        payload: payload,
        tlvs: tlvs,
        crc: declaredCrc,
        rawBytes: bytes,
      );
    } on ArgumentError catch (e) {
      throw ProtocolException(
        'Invalid frame field: ${e.message}',
        protocolErrorType: ProtocolErrorType.invalidParameters,
      );
    }
  }

  List<int>? extractPayload(List<int> bytes) {
    if (bytes.length < ProtocolConstants.minFrameSize) {
      return null;
    }
    if (bytes.first != sof || bytes.last != eof) {
      return null;
    }

    final payloadLength = EndianUtils.bytesToUint16BE(
      bytes,
      ProtocolConstants.payloadLengthOffset,
    );
    final expectedLength =
        ProtocolConstants.headerSize +
        payloadLength +
        ProtocolConstants.trailerSize;
    if (bytes.length < expectedLength) {
      return null;
    }

    return bytes.sublist(
      ProtocolConstants.payloadOffset,
      ProtocolConstants.payloadOffset + payloadLength,
    );
  }

  static String _hex8(int value) =>
      value.toRadixString(16).toUpperCase().padLeft(2, '0');

  List<Tlv> _tryParseTlvs(List<int> payload) {
    if (payload.isEmpty) {
      return const <Tlv>[];
    }

    try {
      return tlvParser.parseAll(payload);
    } on ProtocolException {
      return const <Tlv>[];
    }
  }
}

/// Backward-compatible parser that returns [DeviceFrame].
class FrameParser extends UcpFrameParser {
  FrameParser({
    super.sof,
    super.eof,
    super.crc,
    super.tlvParser,
    int crcRangeStart = 1,
    int? crcRangeEnd,
  }) : assert(crcRangeStart == 1 || crcRangeStart == 0),
       assert(crcRangeEnd == null);

  @override
  DeviceFrame parse(List<int> bytes) {
    return DeviceFrame.fromUcpFrame(super.parse(bytes));
  }
}
