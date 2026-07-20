package com.example.app_horalink_flutter

import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.os.ParcelUuid
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    companion object {
        private const val COMMAND_CHANNEL = "horalink/ble_commands"
        private const val RESULT_CHANNEL = "horalink/ble_results"
        private const val SERVICE_UUID = "7e57d004-2b97-0e7a-e511-9b9941e4a8f2"
    }

    private var eventSink: EventChannel.EventSink? = null
    private var scanning = false
    private val serviceParcelUuid = ParcelUuid(UUID.fromString(SERVICE_UUID))

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val payload = result.scanRecord?.getServiceData(serviceParcelUuid) ?: return
            eventSink?.success(
                mapOf(
                    "payload" to payload.map { it.toInt() and 0xff },
                    "rssi" to result.rssi,
                ),
            )
        }

        override fun onScanFailed(errorCode: Int) {
            scanning = false
            eventSink?.error("SCAN_FAILED", "Error del escáner BLE: $errorCode", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, RESULT_CHANNEL)
            .setStreamHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COMMAND_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startScan" -> startBleScan(result)
                    "stopScan" -> {
                        stopBleScan()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("MissingPermission")
    private fun startBleScan(result: MethodChannel.Result) {
        val manager = getSystemService(BLUETOOTH_SERVICE) as BluetoothManager
        val scanner = manager.adapter?.bluetoothLeScanner
        if (scanner == null) {
            result.error("BLE_UNAVAILABLE", "Bluetooth está apagado o no disponible.", null)
            return
        }

        if (!scanning) {
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()
            scanner.startScan(null, settings, scanCallback)
            scanning = true
        }
        result.success(null)
    }

    @Suppress("MissingPermission")
    private fun stopBleScan() {
        if (!scanning) return
        val manager = getSystemService(BLUETOOTH_SERVICE) as BluetoothManager
        manager.adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        scanning = false
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onDestroy() {
        stopBleScan()
        super.onDestroy()
    }
}
