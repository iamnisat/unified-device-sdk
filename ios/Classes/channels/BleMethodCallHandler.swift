import Flutter
import Foundation

final class BleMethodCallHandler: NSObject, FlutterPlugin {
    private let bleManager: BleManager

    init(bleManager: BleManager) {
        self.bleManager = bleManager
        super.init()
    }

    static func register(with registrar: FlutterPluginRegistrar) {}

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startScan":
            bleManager.startScan(
                arguments: call.arguments as? [String: Any],
                result: result
            )
        case "stopScan":
            bleManager.stopScan(result: result)
        case "connect":
            guard
                let arguments = call.arguments as? [String: Any],
                let deviceId = arguments["deviceId"] as? String,
                !deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                result(
                    NativeErrorMapper.flutterError(
                        code: BleConstants.invalidArgumentError,
                        message: "Missing deviceId"
                    )
                )
                return
            }
            bleManager.connect(
                deviceId: deviceId,
                arguments: arguments,
                result: result
            )
        case "disconnect":
            bleManager.disconnect(result: result)
        case "write":
            guard
                let arguments = call.arguments as? [String: Any],
                let typedData = arguments["data"] as? FlutterStandardTypedData
            else {
                result(
                    NativeErrorMapper.flutterError(
                        code: BleConstants.invalidArgumentError,
                        message: "Missing write payload"
                    )
                )
                return
            }
            bleManager.write(data: typedData.data, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
