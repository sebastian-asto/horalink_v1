package com.example.app_horalink_flutter

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    companion object {
        private const val COMMAND_CHANNEL = "horalink/ble_commands"
        private const val RESULT_CHANNEL = "horalink/ble_results"
        private const val PREFERENCE_CHANNEL = "horalink/preferences"
        private const val SERVICE_UUID = "7e57d004-2b97-0e7a-e511-9b9941e4a8f2"
        private const val NAME_UUID = "7e57d005-2b97-0e7a-e511-9b9941e4a8f2"
        private const val RESET_UUID = "7e57d006-2b97-0e7a-e511-9b9941e4a8f2"
        private const val RESET_COMMAND: Byte = 0xa5.toByte()
        private const val PREFERENCES = "horalink_devices"
        private const val APP_PREFERENCES = "horalink_app_settings"
        private const val SELECTED_PRODUCT_KEY = "selected_product"
        private const val USAGE_LIMIT_PREFIX = "usage_limit_hours_"
        private const val THEME_KEY = "theme"
        private const val LANGUAGE_KEY = "language"
    }

    private enum class PendingOperation { CONNECT, WRITE_NAME, WRITE_RESET, READ_RESET }

    private val handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var scanning = false
    private val devices = mutableMapOf<String, BluetoothDevice>()
    private val serviceParcelUuid = ParcelUuid(UUID.fromString(SERVICE_UUID))
    private val serviceUuid = UUID.fromString(SERVICE_UUID)
    private val nameUuid = UUID.fromString(NAME_UUID)
    private val resetUuid = UUID.fromString(RESET_UUID)

    private var bluetoothGatt: BluetoothGatt? = null
    private var horaLinkService: BluetoothGattService? = null
    private var pendingOperation: PendingOperation? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingName: String? = null

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val payload = result.scanRecord?.getServiceData(serviceParcelUuid) ?: return
            devices[result.device.address] = result.device
            val savedName = getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                .getString(result.device.address, "HoraLink") ?: "HoraLink"
            eventSink?.success(
                mapOf(
                    "type" to "advertisement",
                    "payload" to payload.map { it.toInt() and 0xff },
                    "rssi" to result.rssi,
                    "deviceId" to result.device.address,
                    "deviceName" to savedName,
                ),
            )
        }

        override fun onScanFailed(errorCode: Int) {
            scanning = false
            eventSink?.error("SCAN_FAILED", "Error del escáner BLE: $errorCode", null)
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        @Suppress("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (bluetoothGatt !== gatt) {
                gatt.close()
                return
            }
            if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED) {
                runOnUiThread {
                    failPending("CONNECTION_LOST", "HoraLink se desconectó.")
                    eventSink?.success(mapOf("type" to "configDisconnected"))
                }
                gatt.close()
                if (bluetoothGatt === gatt) bluetoothGatt = null
                horaLinkService = null
                return
            }

            if (newState == BluetoothProfile.STATE_CONNECTED) {
                if (!gatt.requestMtu(64)) {
                    gatt.discoverServices()
                }
            }
        }

        @Suppress("MissingPermission")
        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            gatt.discoverServices()
        }

        @Suppress("MissingPermission")
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val service = gatt.getService(serviceUuid)
            if (status != BluetoothGatt.GATT_SUCCESS || service == null) {
                runOnUiThread {
                    failPending("SERVICE_NOT_FOUND", "Servicio de configuración no encontrado.")
                }
                return
            }
            horaLinkService = service
            val characteristic = service.getCharacteristic(nameUuid)
            if (characteristic == null || !gatt.readCharacteristic(characteristic)) {
                runOnUiThread {
                    failPending("NAME_READ_FAILED", "No se pudo leer el nombre de HoraLink.")
                }
            }
        }

        @Deprecated("Deprecated in Android 13")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            handleCharacteristicRead(gatt, characteristic, characteristic.value ?: byteArrayOf(), status)
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) {
            handleCharacteristicRead(gatt, characteristic, value, status)
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            runOnUiThread {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    failPending("WRITE_FAILED", "HoraLink rechazó la escritura GATT.")
                    return@runOnUiThread
                }
                when (pendingOperation) {
                    PendingOperation.WRITE_NAME -> {
                        val name = pendingName ?: "HoraLink"
                        getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                            .edit().putString(gatt.device.address, name).apply()
                        completePending(name)
                    }
                    PendingOperation.WRITE_RESET -> completePending(true)
                    else -> failPending("UNEXPECTED_WRITE", "Respuesta GATT inesperada.")
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, RESULT_CHANNEL)
            .setStreamHandler(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COMMAND_CHANNEL)
            .setMethodCallHandler(::handleMethodCall)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PREFERENCE_CHANNEL)
            .setMethodCallHandler { call, result ->
                val preferences = getSharedPreferences(APP_PREFERENCES, MODE_PRIVATE)
                when (call.method) {
                    "getSelectedProduct" -> result.success(
                        preferences.getString(SELECTED_PRODUCT_KEY, null),
                    )
                    "setSelectedProduct" -> {
                        val product = call.argument<String>("product")
                        if (product == "ble" || product == "lora") {
                            preferences.edit().putString(SELECTED_PRODUCT_KEY, product).apply()
                            result.success(null)
                        } else {
                            result.error("INVALID_PRODUCT", "Producto HoraLink inválido.", null)
                        }
                    }
                    "clearSelectedProduct" -> {
                        preferences.edit().remove(SELECTED_PRODUCT_KEY).apply()
                        result.success(null)
                    }
                    "getUsageLimitHours" -> {
                        val deviceId = call.argument<String>("deviceId")
                        if (deviceId.isNullOrBlank()) {
                            result.error("INVALID_DEVICE", "Identificador HoraLink inválido.", null)
                        } else {
                            val key = USAGE_LIMIT_PREFIX + deviceId
                            result.success(if (preferences.contains(key)) preferences.getInt(key, 0) else null)
                        }
                    }
                    "setUsageLimitHours" -> {
                        val deviceId = call.argument<String>("deviceId")
                        val hours = call.argument<Int>("hours")
                        if (deviceId.isNullOrBlank() || hours == null || hours <= 0) {
                            result.error("INVALID_LIMIT", "El límite de horas no es válido.", null)
                        } else {
                            preferences.edit().putInt(USAGE_LIMIT_PREFIX + deviceId, hours).apply()
                            result.success(null)
                        }
                    }
                    "getTheme" -> result.success(preferences.getString(THEME_KEY, "light"))
                    "setTheme" -> {
                        val theme = call.argument<String>("theme")
                        if (theme == "light" || theme == "dark") {
                            preferences.edit().putString(THEME_KEY, theme).apply()
                            result.success(null)
                        } else {
                            result.error("INVALID_THEME", "Tema inválido.", null)
                        }
                    }
                    "getLanguage" -> result.success(preferences.getString(LANGUAGE_KEY, "es"))
                    "setLanguage" -> {
                        val language = call.argument<String>("language")
                        if (language == "es" || language == "en") {
                            preferences.edit().putString(LANGUAGE_KEY, language).apply()
                            result.success(null)
                        } else {
                            result.error("INVALID_LANGUAGE", "Idioma inválido.", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startScan" -> startBleScan(result)
            "stopScan" -> {
                stopBleScan()
                result.success(null)
            }
            "connect" -> connectHoraLink(call.argument<String>("deviceId"), result)
            "writeName" -> writeName(call.argument<String>("name"), result)
            "requestReset" -> writeResetRequest(result)
            "readResetStatus" -> readResetStatus(result)
            "disconnect" -> {
                disconnectHoraLink()
                result.success(null)
            }
            else -> result.notImplemented()
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

    @Suppress("MissingPermission")
    private fun connectHoraLink(deviceId: String?, result: MethodChannel.Result) {
        if (deviceId.isNullOrBlank()) {
            result.error("NO_DEVICE", "Primero busca y selecciona un HoraLink.", null)
            return
        }
        if (!beginOperation(PendingOperation.CONNECT, result, 12_000)) return

        stopBleScan()
        disconnectHoraLink(keepPending = true)
        val manager = getSystemService(BLUETOOTH_SERVICE) as BluetoothManager
        val device = devices[deviceId] ?: try {
            manager.adapter.getRemoteDevice(deviceId)
        } catch (_: IllegalArgumentException) {
            null
        }
        if (device == null) {
            failPending("NO_DEVICE", "No se encontró el dispositivo anunciado.")
            return
        }
        bluetoothGatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        if (bluetoothGatt == null) {
            failPending("CONNECT_FAILED", "No se pudo iniciar la conexión BLE.")
        }
    }

    private fun handleCharacteristicRead(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
        status: Int,
    ) {
        runOnUiThread {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                failPending("READ_FAILED", "No se pudo leer la característica GATT.")
                return@runOnUiThread
            }
            when {
                characteristic.uuid == nameUuid && pendingOperation == PendingOperation.CONNECT -> {
                    val name = value.toString(Charsets.UTF_8).ifBlank { "HoraLink" }
                    getSharedPreferences(PREFERENCES, MODE_PRIVATE)
                        .edit().putString(gatt.device.address, name).apply()
                    completePending(mapOf("name" to name))
                }
                characteristic.uuid == resetUuid && pendingOperation == PendingOperation.READ_RESET -> {
                    completePending(if (value.isNotEmpty()) value[0].toInt() and 0xff else 0)
                }
                else -> failPending("UNEXPECTED_READ", "Respuesta GATT inesperada.")
            }
        }
    }

    private fun writeName(name: String?, result: MethodChannel.Result) {
        val encoded = name?.trim()?.toByteArray(Charsets.UTF_8)
        if (encoded == null || encoded.isEmpty() || encoded.size > 40) {
            result.error("INVALID_NAME", "El nombre debe ocupar entre 1 y 40 bytes UTF-8.", null)
            return
        }
        if (!beginOperation(PendingOperation.WRITE_NAME, result)) return
        pendingName = name.trim()
        writeCharacteristic(nameUuid, encoded)
    }

    private fun writeResetRequest(result: MethodChannel.Result) {
        if (!beginOperation(PendingOperation.WRITE_RESET, result)) return
        writeCharacteristic(resetUuid, byteArrayOf(RESET_COMMAND))
    }

    @Suppress("MissingPermission")
    private fun readResetStatus(result: MethodChannel.Result) {
        if (!beginOperation(PendingOperation.READ_RESET, result, 4_000)) return
        val characteristic = horaLinkService?.getCharacteristic(resetUuid)
        val gatt = bluetoothGatt
        if (gatt == null || characteristic == null || !gatt.readCharacteristic(characteristic)) {
            failPending("READ_FAILED", "No se pudo consultar el estado del reinicio.")
        }
    }

    @Suppress("MissingPermission")
    private fun writeCharacteristic(uuid: UUID, value: ByteArray) {
        val gatt = bluetoothGatt
        val characteristic = horaLinkService?.getCharacteristic(uuid)
        if (gatt == null || characteristic == null) {
            failPending("NOT_CONNECTED", "HoraLink no está conectado.")
            return
        }

        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(
                characteristic,
                value,
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
            ) == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            characteristic.value = value
            @Suppress("DEPRECATION")
            gatt.writeCharacteristic(characteristic)
        }
        if (!started) {
            failPending("WRITE_FAILED", "No se pudo iniciar la escritura GATT.")
        }
    }

    private fun beginOperation(
        operation: PendingOperation,
        result: MethodChannel.Result,
        timeoutMs: Long = 6_000,
    ): Boolean {
        if (pendingOperation != null) {
            result.error("BUSY", "Hay otra operación BLE en curso.", null)
            return false
        }
        pendingOperation = operation
        pendingResult = result
        handler.postDelayed({
            if (pendingOperation == operation) {
                failPending("TIMEOUT", "La operación BLE agotó el tiempo de espera.")
            }
        }, timeoutMs)
        return true
    }

    private fun completePending(value: Any?) {
        val result = pendingResult
        pendingResult = null
        pendingOperation = null
        pendingName = null
        result?.success(value)
    }

    private fun failPending(code: String, message: String) {
        val result = pendingResult
        pendingResult = null
        pendingOperation = null
        pendingName = null
        result?.error(code, message, null)
    }

    @Suppress("MissingPermission")
    private fun disconnectHoraLink(keepPending: Boolean = false) {
        bluetoothGatt?.disconnect()
        bluetoothGatt?.close()
        bluetoothGatt = null
        horaLinkService = null
        if (!keepPending) failPending("DISCONNECTED", "Conexión cerrada.")
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onDestroy() {
        stopBleScan()
        disconnectHoraLink()
        super.onDestroy()
    }
}
