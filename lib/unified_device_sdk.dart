// Unified Device SDK - A cross-platform Flutter plugin for BLE device communication.
//
// This SDK provides a comprehensive framework for discovering, connecting,
// and communicating with Bluetooth Low Energy (BLE) devices using a
// custom frame-based protocol with CRC validation.
// Core exports - Client
export 'src/core/client/unified_device_client.dart';
export 'src/core/client/unified_device_client_config.dart';
export 'src/core/client/unified_device_hardware_profile.dart';
export 'src/core/client/ucp_session_manager.dart';
export 'src/core/client/unified_device_session.dart';

// Logging exports
export 'src/logging/device_communication_log.dart';
export 'src/logging/device_communication_log_controller.dart';
export 'src/logging/ucp_log_mode.dart';

// Core exports - Transport
export 'src/core/transport/device_transport.dart';
export 'src/core/transport/ble_transport.dart';
export 'src/core/transport/connection_state.dart';
export 'src/core/transport/discovered_device.dart';
export 'src/core/transport/transport_event.dart';

// Core exports - Frame
export 'src/core/frame/device_frame.dart';
export 'src/core/frame/frame_builder.dart';
export 'src/core/frame/frame_parser.dart';
export 'src/core/frame/frame_buffer.dart';
export 'src/core/frame/frame_validation_result.dart';

// Core exports - CRC
export 'src/core/crc/crc16_ccitt.dart';

// Core exports - Response
export 'src/core/response/response_manager.dart';
export 'src/core/response/pending_request.dart';
export 'src/core/response/device_response.dart';
export 'src/core/response/device_event.dart';
export 'src/core/response/sequence_generator.dart';

// Core exports - Bytes
export 'src/core/bytes/byte_reader.dart';
export 'src/core/bytes/byte_writer.dart';
export 'src/core/bytes/endian_utils.dart';

// Core exports - Errors
export 'src/core/errors/unified_device_exception.dart';
export 'src/core/errors/transport_exception.dart';
export 'src/core/errors/frame_exception.dart';
export 'src/core/errors/crc_exception.dart';
export 'src/core/errors/timeout_exception.dart';
export 'src/core/errors/protocol_exception.dart';

// Protocol exports - Constants
export 'src/protocol/constants/protocol_constants.dart';
export 'src/protocol/constants/ble_constants.dart';
export 'src/protocol/constants/operation_codes.dart';
export 'src/protocol/constants/protocol_flags.dart';
export 'src/protocol/constants/product_ids.dart';
export 'src/protocol/constants/profile_ids.dart';
export 'src/protocol/constants/ucp_addresses.dart';
export 'src/protocol/constants/common_command_ids.dart';
export 'src/protocol/constants/command_classes.dart';
export 'src/protocol/constants/command_ids.dart';
export 'src/protocol/constants/tlv_types.dart';

// Protocol exports - Commands
export 'src/protocol/commands/device_command.dart';
export 'src/protocol/commands/command_options.dart';
export 'src/protocol/commands/command_result.dart';
export 'src/protocol/commands/common_commands.dart';

// Protocol exports - Payloads
export 'src/protocol/payloads/payload_builder.dart';
export 'src/protocol/payloads/payload_codec.dart';
export 'src/protocol/payloads/common_payloads.dart';
export 'src/protocol/payloads/tlv_builder.dart';

// Protocol exports - Parsers
export 'src/protocol/parsers/response_parser.dart';
export 'src/protocol/parsers/common_response_parser.dart';
export 'src/protocol/parsers/nack_parser.dart';
export 'src/protocol/parsers/event_parser.dart';
export 'src/protocol/parsers/tlv_parser.dart';

// Protocol exports - Models
export 'src/protocol/models/device_info.dart';
export 'src/protocol/models/firmware_info.dart';
export 'src/protocol/models/battery_info.dart';
export 'src/protocol/models/device_status.dart';
export 'src/protocol/models/protocol_version.dart';
export 'src/protocol/models/tlv.dart';
export 'src/protocol/models/decoded_tlv.dart';
export 'src/protocol/models/ucp_device_info.dart';
export 'src/protocol/models/ucp_time_snapshot.dart';
export 'src/protocol/models/ucp_last_report.dart';
export 'src/protocol/models/ucp_moisture_sample.dart';
export 'src/protocol/models/ucp_nack_details.dart';
export 'src/protocol/models/ucp_packet_trace.dart';

// Platform exports
export 'src/platform/unified_device_platform.dart';
export 'src/platform/method_channel_unified_device.dart';
export 'src/platform/platform_event_mapper.dart';

// Utils exports
export 'src/utils/logger.dart';
export 'src/utils/validation.dart';
