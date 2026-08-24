import Foundation
import CoreBluetooth
import Flutter

final class BleManager: NSObject {
    private let scanEventHandler: ScanEventHandler
    private let connectionEventHandler: ConnectionEventHandler
    private let notificationEventHandler: NotificationEventHandler
    private lazy var centralManager = CBCentralManager(delegate: self, queue: .main)

    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var activePeripheral: CBPeripheral?
    private var notifyCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?
    private var activeDeviceId: String?
    private var serviceUUID = BleConstants.defaultServiceUUID
    private var notifyCharacteristicUUID = BleConstants.defaultNotifyCharacteristicUUID
    private var writeCharacteristicUUID = BleConstants.defaultWriteCharacteristicUUID

    private var pendingConnectResult: FlutterResult?
    private var pendingDisconnectResult: FlutterResult?
    private var pendingWriteResult: FlutterResult?
    private var isScanning = false
    private var connectionReady = false
    private var isDisposed = false
    private var pendingStartScanResult: FlutterResult?

    init(
        scanEventHandler: ScanEventHandler,
        connectionEventHandler: ConnectionEventHandler,
        notificationEventHandler: NotificationEventHandler
    ) {
        self.scanEventHandler = scanEventHandler
        self.connectionEventHandler = connectionEventHandler
        self.notificationEventHandler = notificationEventHandler
        super.init()
        _ = centralManager
    }

    func isBluetoothAvailable() -> Bool {
        // Bluetooth hardware is considered available on all states except .unsupported
        // .unknown is the initial state before the central manager is ready
        // .poweredOff, .unauthorized, .resetting all mean hardware exists but isn't ready
        centralManager.state != .unsupported
    }

    func isBluetoothEnabled() -> Bool {
        centralManager.state == .poweredOn
    }

    func requestBluetoothPermissions() -> Bool {
        // On iOS, Bluetooth permissions are requested automatically by the system
        // when CBCentralManager is initialized. If the user denied permission,
        // the state will be .unauthorized and we cannot re-prompt programmatically.
        // The user must go to Settings to grant permission.
        switch centralManager.state {
        case .poweredOn:
            return true
        case .unauthorized:
            // Permission was denied; return false so the Flutter layer can
            // show a dialog directing the user to Settings
            return false
        case .unknown:
            // Central manager is still initializing; return true optimistically
            // since the permission dialog may still be shown by the system
            return true
        default:
            return false
        }
    }

    func startScan(arguments: [String: Any]?, result: @escaping FlutterResult) {
        guard applyGattProfile(arguments: arguments, result: result) else {
            return
        }
        guard !isDisposed else {
            result(
                NativeErrorMapper.flutterError(
                    code: BleConstants.unknownError,
                    message: "BLE manager disposed"
                )
            )
            return
        }

        // If the central manager is still initializing (unknown state),
        // defer the scan until the state resolves.
        if centralManager.state == .unknown {
            if isScanning {
                result(
                    NativeErrorMapper.flutterError(
                        code: BleConstants.scanAlreadyRunningError,
                        message: "BLE scan is already running"
                    )
                )
                return
            }
            pendingStartScanResult = result
            return
        }

        guard let stateError = currentBluetoothStateError() else {
            if isScanning {
                result(
                    NativeErrorMapper.flutterError(
                        code: BleConstants.scanAlreadyRunningError,
                        message: "BLE scan is already running"
                    )
                )
                return
            }

            discoveredPeripherals.removeAll()
            centralManager.scanForPeripherals(
                withServices: [serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            isScanning = true
            result(nil)
            return
        }

        result(stateError)
    }

    func stopScan(result: @escaping FlutterResult) {
        stopScanInternal()
        result(nil)
    }

    func connect(deviceId: String, arguments: [String: Any]?, result: @escaping FlutterResult) {
        guard applyGattProfile(arguments: arguments, result: result) else {
            return
        }
        guard !isDisposed else {
            result(
                NativeErrorMapper.flutterError(
                    code: BleConstants.unknownError,
                    message: "BLE manager disposed"
                )
            )
            return
        }

        if let stateError = currentBluetoothStateError() {
            result(stateError)
            return
        }

        if pendingConnectResult != nil || pendingDisconnectResult != nil {
            result(
                NativeErrorMapper.flutterError(
                    code: BleConstants.operationInProgressError,
                    message: "Another BLE operation is already in progress"
                )
            )
            return
        }

        guard let peripheral = discoveredPeripherals[deviceId] else {
            result(
                NativeErrorMapper.flutterError(
                    code: BleConstants.deviceNotFoundError,
                    message: "Bluetooth device not found"
                )
            )
            return
        }

        if let currentPeripheral = activePeripheral,
           currentPeripheral.identifier.uuidString != deviceId,
           currentPeripheral.state != .disconnected {
            result(
                NativeErrorMapper.flutterError(
                    code: BleConstants.operationInProgressError,
                    message: "A BLE connection is already active"
                )
            )
            return
        }

        pendingConnectResult = result
        activePeripheral = peripheral
        activeDeviceId = deviceId
        notifyCharacteristic = nil
        writeCharacteristic = nil
        connectionReady = false
        peripheral.delegate = self

        emitConnectionState(BleConstants.stateConnecting, deviceId: deviceId)
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect(result: @escaping FlutterResult) {
        if pendingDisconnectResult != nil {
            result(
                NativeErrorMapper.flutterError(
                    code: BleConstants.operationInProgressError,
                    message: "Another disconnect is already in progress"
                )
            )
            return
        }

        guard let peripheral = activePeripheral else {
            let deviceId = activeDeviceId
            resetConnectionState(clearDeviceId: true)
            emitConnectionState(BleConstants.stateDisconnected, deviceId: deviceId)
            result(nil)
            return
        }

        pendingDisconnectResult = result
        emitConnectionState(
            BleConstants.stateDisconnecting,
            deviceId: peripheral.identifier.uuidString
        )

        if peripheral.state == .disconnected {
            handleDisconnect(for: peripheral, error: nil, unexpected: false)
            return
        }

        centralManager.cancelPeripheralConnection(peripheral)
    }

    func write(data: Data, result: @escaping FlutterResult) {
        guard !isDisposed else {
            result(
                NativeErrorMapper.flutterError(
                    code: BleConstants.unknownError,
                    message: "BLE manager disposed"
                )
            )
            return
        }

        if let stateError = currentBluetoothStateError() {
            result(stateError)
            return
        }

        guard
            let peripheral = activePeripheral,
            let characteristic = writeCharacteristic,
            connectionReady
        else {
            result(
                NativeErrorMapper.flutterError(
                    code: BleConstants.characteristicNotFoundError,
                    message: "No writable BLE characteristic is available"
                )
            )
            return
        }

        if pendingWriteResult != nil {
            result(
                NativeErrorMapper.flutterError(
                    code: BleConstants.operationInProgressError,
                    message: "Another write is already in progress"
                )
            )
            return
        }

        let properties = characteristic.properties
        let supportsWrite = properties.contains(.write)
        let supportsWriteWithoutResponse = properties.contains(.writeWithoutResponse)

        guard supportsWrite || supportsWriteWithoutResponse else {
            result(
                NativeErrorMapper.flutterError(
                    code: BleConstants.characteristicNotFoundError,
                    message: "Characteristic does not support write"
                )
            )
            return
        }

        let writeType: CBCharacteristicWriteType = supportsWrite ? .withResponse : .withoutResponse
        if writeType == .withResponse {
            pendingWriteResult = result
        }

        peripheral.writeValue(data, for: characteristic, type: writeType)

        if writeType == .withoutResponse {
            result(nil)
        }
    }

    func dispose() {
        guard !isDisposed else {
            return
        }

        isDisposed = true
        stopScanInternal()
        completePendingResultsOnDispose()

        // Complete any deferred scan operation
        if let deferredResult = pendingStartScanResult {
            deferredResult(
                NativeErrorMapper.flutterError(
                    code: BleConstants.unknownError,
                    message: "BLE manager disposed"
                )
            )
            pendingStartScanResult = nil
        }

        if let peripheral = activePeripheral {
            peripheral.delegate = nil
            if peripheral.state != .disconnected {
                centralManager.cancelPeripheralConnection(peripheral)
            }
        }

        resetConnectionState(clearDeviceId: true)
        discoveredPeripherals.removeAll()
        scanEventHandler.clear()
        connectionEventHandler.clear()
        notificationEventHandler.clear()
        centralManager.delegate = nil
    }

    private func stopScanInternal() {
        if isScanning {
            centralManager.stopScan()
            isScanning = false
        }
    }

    private func currentBluetoothStateError() -> FlutterError? {
        guard !isDisposed else {
            return NativeErrorMapper.flutterError(
                code: BleConstants.unknownError,
                message: "BLE manager disposed"
            )
        }

        if centralManager.state == .poweredOn {
            return nil
        }

        return NativeErrorMapper.bluetoothStateError(for: centralManager.state)
    }

    private func applyGattProfile(arguments: [String: Any]?, result: @escaping FlutterResult) -> Bool {
        guard
            let serviceUUID = parseUuid(
                arguments?["serviceUuid"],
                fallback: BleConstants.defaultServiceUUID
            ),
            let notifyCharacteristicUUID = parseUuid(
                arguments?["notifyCharacteristicUuid"],
                fallback: BleConstants.defaultNotifyCharacteristicUUID
            ),
            let writeCharacteristicUUID = parseUuid(
                arguments?["writeCharacteristicUuid"],
                fallback: BleConstants.defaultWriteCharacteristicUUID
            )
        else {
            result(
                NativeErrorMapper.flutterError(
                    code: BleConstants.invalidArgumentError,
                    message: "Invalid BLE UUID in hardware profile"
                )
            )
            return false
        }

        self.serviceUUID = serviceUUID
        self.notifyCharacteristicUUID = notifyCharacteristicUUID
        self.writeCharacteristicUUID = writeCharacteristicUUID
        return true
    }

    private func parseUuid(_ value: Any?, fallback: CBUUID) -> CBUUID? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return fallback
        }
        return CBUUID(string: text)
    }

    private func emitConnectionState(
        _ state: String,
        deviceId: String?,
        message: String? = nil,
        details: [String: Any]? = nil
    ) {
        connectionEventHandler.emit(
            NativeErrorMapper.connectionEvent(
                state: state,
                deviceId: deviceId,
                message: message,
                details: details
            )
        )
    }

    private func resetConnectionState(clearDeviceId: Bool) {
        activePeripheral?.delegate = nil
        activePeripheral = nil
        notifyCharacteristic = nil
        writeCharacteristic = nil
        connectionReady = false
        if clearDeviceId {
            activeDeviceId = nil
        }
    }

    private func completePendingResultsOnDispose() {
        pendingConnectResult?(
            NativeErrorMapper.flutterError(
                code: BleConstants.connectFailedError,
                message: "BLE manager disposed"
            )
        )
        pendingConnectResult = nil

        pendingDisconnectResult?(nil)
        pendingDisconnectResult = nil

        pendingWriteResult?(
            NativeErrorMapper.flutterError(
                code: BleConstants.writeFailedError,
                message: "BLE manager disposed"
            )
        )
        pendingWriteResult = nil
    }

    private func failPendingConnect(code: String, message: String, error: Error? = nil) {
        pendingConnectResult?(
            NativeErrorMapper.centralError(code: code, message: message, error: error)
        )
        pendingConnectResult = nil
        emitConnectionState(BleConstants.stateError, deviceId: activeDeviceId, message: message)
    }

    private func failPendingWrite(code: String, message: String, error: Error? = nil) {
        pendingWriteResult?(
            NativeErrorMapper.centralError(code: code, message: message, error: error)
        )
        pendingWriteResult = nil
    }

    private func finishConnectionIfReady(for peripheral: CBPeripheral) {
        guard
            activePeripheral?.identifier == peripheral.identifier,
            !connectionReady,
            writeCharacteristic != nil,
            let notifyCharacteristic,
            notifyCharacteristic.isNotifying
        else {
            return
        }

        connectionReady = true
        pendingConnectResult?(nil)
        pendingConnectResult = nil
        emitConnectionState(BleConstants.stateReady, deviceId: peripheral.identifier.uuidString)

        // Query the negotiated MTU and emit mtuReady state
        let mtu = peripheral.maximumWriteValueLength(for: .withResponse)
        let effectiveMtu = max(mtu, peripheral.maximumWriteValueLength(for: .withoutResponse))
        let mtuValue = effectiveMtu > 0 ? effectiveMtu : 256
        emitConnectionState(
            BleConstants.stateMtuReady,
            deviceId: peripheral.identifier.uuidString,
            message: nil,
            details: ["mtu": mtuValue]
        )
    }

    private func handleDisconnect(
        for peripheral: CBPeripheral,
        error: Error?,
        unexpected: Bool
    ) {
        let deviceId = peripheral.identifier.uuidString
        let shouldEmitConnectionLost = unexpected && connectionReady

        pendingConnectResult?(
            NativeErrorMapper.centralError(
                code: BleConstants.connectFailedError,
                message: "BLE connection failed",
                error: error
            )
        )
        pendingConnectResult = nil

        if let disconnectResult = pendingDisconnectResult {
            disconnectResult(nil)
            pendingDisconnectResult = nil
        }

        if pendingWriteResult != nil {
            failPendingWrite(
                code: BleConstants.disconnectFailedError,
                message: "Disconnected before write completed",
                error: error
            )
        }

        resetConnectionState(clearDeviceId: true)
        emitConnectionState(
            shouldEmitConnectionLost ? BleConstants.stateConnectionLost : BleConstants.stateDisconnected,
            deviceId: deviceId,
            message: error?.localizedDescription
        )
    }

}

extension BleManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !isDisposed else { return }

        if central.state == .poweredOn {
            // Execute any deferred scan operation that was queued while
            // the central manager was still initializing (unknown state).
            if let deferredResult = pendingStartScanResult {
                pendingStartScanResult = nil
                discoveredPeripherals.removeAll()
                centralManager.scanForPeripherals(
                    withServices: [serviceUUID],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
                )
                isScanning = true
                deferredResult(nil)
            }
            return
        }

        // Bluetooth is no longer available (poweredOff, unauthorized, unsupported, etc.)
        stopScanInternal()

        // Fail any deferred scan operation
        if let deferredResult = pendingStartScanResult {
            let error = NativeErrorMapper.bluetoothStateError(for: central.state)
            deferredResult(error)
            pendingStartScanResult = nil
        }

        if pendingConnectResult != nil {
            let error = NativeErrorMapper.bluetoothStateError(for: central.state)
            failPendingConnect(code: error.code, message: error.message ?? "Bluetooth unavailable")
        }

        if pendingWriteResult != nil {
            let error = NativeErrorMapper.bluetoothStateError(for: central.state)
            failPendingWrite(code: error.code, message: error.message ?? "Bluetooth unavailable")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let deviceId = peripheral.identifier.uuidString
        discoveredPeripherals[deviceId] = peripheral

        let payload = NativeErrorMapper.scanEvent(
            deviceId: deviceId,
            name: peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            rssi: RSSI.intValue,
            serviceUuids: (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
                .map { $0.uuidString } ?? [],
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        )
        scanEventHandler.emit(payload)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard activePeripheral?.identifier == peripheral.identifier else {
            central.cancelPeripheralConnection(peripheral)
            return
        }

        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        failPendingConnect(
            code: BleConstants.connectFailedError,
            message: "Failed to connect to BLE device",
            error: error
        )
        resetConnectionState(clearDeviceId: true)
        emitConnectionState(
            BleConstants.stateDisconnected,
            deviceId: peripheral.identifier.uuidString,
            message: error?.localizedDescription
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        handleDisconnect(
            for: peripheral,
            error: error,
            unexpected: pendingDisconnectResult == nil && pendingConnectResult == nil
        )
    }
}

extension BleManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            failPendingConnect(
                code: BleConstants.gattError,
                message: "BLE service discovery failed",
                error: error
            )
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            failPendingConnect(
                code: BleConstants.serviceNotFoundError,
                message: "Required service \(serviceUUID.uuidString) not found"
            )
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        peripheral.discoverCharacteristics(
            [notifyCharacteristicUUID, writeCharacteristicUUID],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            failPendingConnect(
                code: BleConstants.gattError,
                message: "BLE characteristic discovery failed",
                error: error
            )
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        guard let characteristics = service.characteristics else {
            failPendingConnect(
                code: BleConstants.characteristicNotFoundError,
                message: "Required notify/write characteristics were not found"
            )
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        notifyCharacteristic = characteristics.first(where: { $0.uuid == notifyCharacteristicUUID })
        writeCharacteristic = characteristics.first(where: { $0.uuid == writeCharacteristicUUID })

        guard
            let notifyCharacteristic = notifyCharacteristic,
            writeCharacteristic != nil
        else {
            failPendingConnect(
                code: BleConstants.characteristicNotFoundError,
                message: "Required notify/write characteristics were not found"
            )
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        peripheral.setNotifyValue(true, for: notifyCharacteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == notifyCharacteristicUUID else {
            return
        }

        if let error = error {
            failPendingConnect(
                code: BleConstants.notificationEnableFailedError,
                message: "Failed to enable notifications on \(notifyCharacteristicUUID.uuidString)",
                error: error
            )
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        guard characteristic.isNotifying else {
            failPendingConnect(
                code: BleConstants.notificationEnableFailedError,
                message: "Failed to enable notifications on \(notifyCharacteristicUUID.uuidString)"
            )
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        finishConnectionIfReady(for: peripheral)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == notifyCharacteristicUUID else {
            return
        }

        if let error = error {
            notificationEventHandler.emitError(
                NativeErrorMapper.centralError(
                    code: BleConstants.gattError,
                    message: "BLE notification update failed",
                    error: error
                )
            )
            return
        }

        guard let data = characteristic.value else {
            return
        }

        notificationEventHandler.emit(NativeErrorMapper.notificationEvent(data: data))
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == writeCharacteristicUUID else {
            return
        }

        guard let pendingWriteResult = pendingWriteResult else {
            return
        }

        self.pendingWriteResult = nil

        if let error = error {
            pendingWriteResult(
                NativeErrorMapper.centralError(
                    code: BleConstants.gattError,
                    message: "BLE write failed",
                    error: error
                )
            )
            return
        }

        pendingWriteResult(nil)
    }
}
