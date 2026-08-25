import '../bytes/endian_utils.dart';
import '../../protocol/constants/command_classes.dart';
import '../../protocol/constants/operation_codes.dart';
import '../../protocol/constants/profile_ids.dart';
import '../../protocol/constants/protocol_constants.dart';
import '../../protocol/constants/ucp_addresses.dart';
import '../../protocol/models/tlv.dart';
import '../../protocol/payloads/tlv_builder.dart';

/// Represents a complete official UCP frame.
class UcpFrame {
  final int version;
  final int productId;
  final int profileId;
  final int sourceAddress;
  final int destinationAddress;
  final int op;
  final int commandClass;
  final int commandId;
  final int sequence;
  final int flags;
  final List<int> payload;
  final List<Tlv> tlvs;
  final int crc;
  final List<int>? rawBytes;
  final int minSequence;
  final int maxSequence;

  UcpFrame({
    required this.version,
    required this.productId,
    this.profileId = ProfileIds.defaultProfile,
    this.sourceAddress = UcpAddresses.defaultSource,
    this.destinationAddress = UcpAddresses.defaultDestination,
    required this.op,
    required this.commandClass,
    required this.commandId,
    required this.sequence,
    required this.flags,
    List<int> payload = const [],
    List<Tlv> tlvs = const [],
    required this.crc,
    List<int>? rawBytes,
    this.minSequence = ProtocolConstants.initialSequenceNumber,
    this.maxSequence = ProtocolConstants.maxSequenceNumber,
  }) : payload = List<int>.unmodifiable(
         _resolvePayload(payload: payload, tlvs: tlvs),
       ),
       tlvs = List<Tlv>.unmodifiable(
         _resolveTlvs(payload: payload, tlvs: tlvs),
       ),
       rawBytes = rawBytes == null ? null : List<int>.unmodifiable(rawBytes) {
    _validateUint8(version, 'version');
    _validateUint8(productId, 'productId');
    _validateUint8(profileId, 'profileId');
    _validateUint8(sourceAddress, 'sourceAddress');
    _validateUint8(destinationAddress, 'destinationAddress');
    _validateUint8(op, 'op');
    _validateUint8(commandClass, 'commandClass');
    _validateUint8(commandId, 'commandId');
    _validateSequence(sequence, minSequence, maxSequence);
    _validateUint8(flags, 'flags');
    _validatePayload(this.payload);
    _validateUint16(crc, 'crc');
  }

  int get payloadLength => payload.length;

  int get address => destinationAddress;

  bool get isRequest => op == OperationCodes.req;
  bool get isAck => op == OperationCodes.ack;
  bool get isNack => op == OperationCodes.nack;
  bool get isData => op == OperationCodes.data;
  bool get isEvent => op == OperationCodes.event;
  bool get isStream => op == OperationCodes.stream;
  bool get isHeartbeat => op == OperationCodes.heartbeat;

  // Legacy operation aliases retained for older response logic.
  bool get isRead => isRequest;
  bool get isWrite => isRequest;
  bool get isAction => isRequest;

  UcpFrame copyWith({
    int? version,
    int? productId,
    int? profileId,
    int? sourceAddress,
    int? destinationAddress,
    int? op,
    int? commandClass,
    int? commandId,
    int? sequence,
    int? flags,
    List<int>? payload,
    List<Tlv>? tlvs,
    int? crc,
    List<int>? rawBytes,
    int? minSequence,
    int? maxSequence,
  }) {
    return UcpFrame(
      version: version ?? this.version,
      productId: productId ?? this.productId,
      profileId: profileId ?? this.profileId,
      sourceAddress: sourceAddress ?? this.sourceAddress,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      op: op ?? this.op,
      commandClass: commandClass ?? this.commandClass,
      commandId: commandId ?? this.commandId,
      sequence: sequence ?? this.sequence,
      flags: flags ?? this.flags,
      payload: payload ?? this.payload,
      tlvs: tlvs ?? this.tlvs,
      crc: crc ?? this.crc,
      rawBytes: rawBytes ?? this.rawBytes,
      minSequence: minSequence ?? this.minSequence,
      maxSequence: maxSequence ?? this.maxSequence,
    );
  }

  String toHexString() {
    final bytes = <int>[
      version,
      productId,
      profileId,
      sourceAddress,
      destinationAddress,
      op,
      commandClass,
      commandId,
      ...EndianUtils.uint16ToBytesBE(sequence),
      flags,
      ...EndianUtils.uint16ToBytesBE(payloadLength),
      ...payload,
      ...EndianUtils.uint16ToBytesBE(crc),
    ];
    return EndianUtils.toHexString(bytes);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UcpFrame &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          productId == other.productId &&
          profileId == other.profileId &&
          sourceAddress == other.sourceAddress &&
          destinationAddress == other.destinationAddress &&
          op == other.op &&
          commandClass == other.commandClass &&
          commandId == other.commandId &&
          sequence == other.sequence &&
          flags == other.flags &&
          _listEquals(payload, other.payload) &&
          _listEquals(tlvs, other.tlvs) &&
          crc == other.crc;

  @override
  int get hashCode => Object.hash(
    version,
    productId,
    profileId,
    sourceAddress,
    destinationAddress,
    op,
    commandClass,
    commandId,
    sequence,
    flags,
    Object.hashAll(payload),
    Object.hashAll(tlvs),
    crc,
  );

  @override
  String toString() {
    return 'UcpFrame('
        'ver: $version, '
        'product: 0x${productId.toRadixString(16).toUpperCase().padLeft(2, '0')}, '
        'profile: 0x${profileId.toRadixString(16).toUpperCase().padLeft(2, '0')}, '
        'src: 0x${sourceAddress.toRadixString(16).toUpperCase().padLeft(2, '0')}, '
        'dst: 0x${destinationAddress.toRadixString(16).toUpperCase().padLeft(2, '0')}, '
        'op: 0x${op.toRadixString(16).toUpperCase().padLeft(2, '0')}, '
        'class: 0x${commandClass.toRadixString(16).toUpperCase().padLeft(2, '0')}, '
        'cmd: 0x${commandId.toRadixString(16).toUpperCase().padLeft(2, '0')}, '
        'seq: $sequence, '
        'flags: 0x${flags.toRadixString(16).toUpperCase().padLeft(2, '0')}, '
        'payload: [${payload.length} bytes], '
        'crc: 0x${crc.toRadixString(16).toUpperCase().padLeft(4, '0')})';
  }

  static List<int> _resolvePayload({
    required List<int> payload,
    required List<Tlv> tlvs,
  }) {
    if (payload.isEmpty) {
      return TlvBuilder.encode(tlvs);
    }

    if (tlvs.isNotEmpty) {
      final encodedTlvs = TlvBuilder.encode(tlvs);
      if (!_listEquals(payload, encodedTlvs)) {
        throw ArgumentError('payload bytes do not match encoded TLVs');
      }
    }

    return payload;
  }

  static List<Tlv> _resolveTlvs({
    required List<int> payload,
    required List<Tlv> tlvs,
  }) {
    if (tlvs.isEmpty) {
      return const <Tlv>[];
    }

    if (payload.isNotEmpty) {
      final encodedTlvs = TlvBuilder.encode(tlvs);
      if (!_listEquals(payload, encodedTlvs)) {
        throw ArgumentError('payload bytes do not match encoded TLVs');
      }
    }

    return tlvs;
  }

  static void _validateUint8(int value, String name) {
    if (value < 0 || value > 0xFF) {
      throw ArgumentError('$name must be 0-255, but got $value');
    }
  }

  static void _validateUint16(int value, String name) {
    if (value < 0 || value > 0xFFFF) {
      throw ArgumentError('$name must be 0-65535, but got $value');
    }
  }

  static void _validateSequence(int value, int min, int max) {
    if (value < min || value > max) {
      throw ArgumentError('sequence must be $min-$max, but got $value');
    }
  }

  static void _validatePayload(List<int> payload) {
    if (payload.length > ProtocolConstants.maxPayloadSize) {
      throw ArgumentError(
        'payload length must not exceed ${ProtocolConstants.maxPayloadSize}, '
        'but got ${payload.length}',
      );
    }
    for (var i = 0; i < payload.length; i++) {
      _validateUint8(payload[i], 'payload[$i]');
    }
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// Backward-compatible wrapper over [UcpFrame].
class DeviceFrame extends UcpFrame {
  DeviceFrame({
    required super.version,
    required super.productId,
    super.profileId = ProfileIds.defaultProfile,
    int? address,
    int? sourceAddress,
    int? destinationAddress,
    required super.op,
    super.commandClass = CommandClasses.system,
    required super.commandId,
    required super.sequence,
    required super.flags,
    super.payload,
    super.tlvs,
    required super.crc,
    super.rawBytes,
    super.minSequence = ProtocolConstants.initialSequenceNumber,
    super.maxSequence = ProtocolConstants.maxSequenceNumber,
  }) : super(
         sourceAddress: sourceAddress ?? UcpAddresses.defaultSource,
         destinationAddress:
             destinationAddress ?? address ?? UcpAddresses.defaultDestination,
       );

  factory DeviceFrame.fromUcpFrame(UcpFrame frame) {
    return DeviceFrame(
      version: frame.version,
      productId: frame.productId,
      profileId: frame.profileId,
      sourceAddress: frame.sourceAddress,
      destinationAddress: frame.destinationAddress,
      op: frame.op,
      commandClass: frame.commandClass,
      commandId: frame.commandId,
      sequence: frame.sequence,
      flags: frame.flags,
      payload: frame.payload,
      tlvs: frame.tlvs,
      crc: frame.crc,
      rawBytes: frame.rawBytes,
      minSequence: frame.minSequence,
      maxSequence: frame.maxSequence,
    );
  }
}
