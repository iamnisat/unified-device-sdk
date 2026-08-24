package com.example.unified_device_sdk.channels

import com.example.unified_device_sdk.ble.BleManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Handles BLE method channel calls and forwards them to [BleManager]. */
class BleMethodCallHandler(
    private val bleManager: BleManager
) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startScan" -> {
                @Suppress("UNCHECKED_CAST")
                bleManager.startScan(call.arguments as? Map<String, Any?>, result)
            }
            "stopScan" -> bleManager.stopScan(result)
            "connect" -> {
                val deviceId = call.argument<String>("deviceId")
                if (deviceId.isNullOrBlank()) {
                    result.error("invalid_argument", "Missing deviceId", null)
                } else {
                    @Suppress("UNCHECKED_CAST")
                    bleManager.connect(deviceId, call.arguments as? Map<String, Any?>, result)
                }
            }

            "disconnect" -> bleManager.disconnect(result)
            "write" -> {
                val data = call.argument<ByteArray>("data")
                if (data == null || data.isEmpty()) {
                    result.error("invalid_argument", "Missing write payload", null)
                    return
                }
                bleManager.write(data, result)
            }

            else -> result.notImplemented()
        }
    }
}
