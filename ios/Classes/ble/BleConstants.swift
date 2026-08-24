import Foundation
import CoreBluetooth

struct BleConstants {
    static let mainChannelName = "unified_device_sdk"
    static let bleChannelName = "unified_device_sdk/ble"
    static let scanEventChannelName = "unified_device_sdk/ble/scan"
    static let connectionEventChannelName = "unified_device_sdk/ble/connection"
    static let notificationEventChannelName = "unified_device_sdk/ble/notification"

    static let defaultServiceUUID = CBUUID(string: "FFE0")
    static let defaultNotifyCharacteristicUUID = CBUUID(string: "FFE1")
    static let defaultWriteCharacteristicUUID = CBUUID(string: "FFE2")

    static let stateConnecting = "connecting"
    static let stateConnected = "connected"
    static let stateReady = "ready"
    static let stateDisconnecting = "disconnecting"
    static let stateDisconnected = "disconnected"
    static let stateError = "error"
    static let stateConnectionLost = "connectionLost"
    static let stateMtuReady = "mtuReady"

    static let bluetoothUnavailableError = "bluetooth_unavailable"
    static let bluetoothDisabledError = "bluetooth_disabled"
    static let permissionDeniedError = "permission_denied"
    static let invalidArgumentError = "invalid_argument"
    static let scanFailedError = "scan_failed"
    static let scanAlreadyRunningError = "scan_already_running"
    static let connectFailedError = "connect_failed"
    static let disconnectFailedError = "disconnect_failed"
    static let deviceNotFoundError = "device_not_found"
    static let serviceNotFoundError = "service_not_found"
    static let characteristicNotFoundError = "characteristic_not_found"
    static let notificationEnableFailedError = "notification_enable_failed"
    static let writeFailedError = "write_failed"
    static let operationInProgressError = "operation_in_progress"
    static let gattError = "gatt_error"
    static let unknownError = "unknown_error"
}
