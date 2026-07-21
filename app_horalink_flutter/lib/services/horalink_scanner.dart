import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/horalink_measurement.dart';
import 'product_preferences.dart';

enum HoraLinkScanState { idle, scanning, found, permissionDenied, error }

class HoraLinkScanner extends ChangeNotifier {
  static const _commands = MethodChannel('horalink/ble_commands');
  static const _results = EventChannel('horalink/ble_results');

  StreamSubscription<dynamic>? _scanSubscription;
  Timer? _stopTimer;

  HoraLinkScanState state = HoraLinkScanState.idle;
  HoraLinkMeasurement? measurement;
  String? deviceId;
  String deviceName = 'HoraLink';
  int? usageLimitHours;
  String? errorMessage;
  PlatformException? platformError;
  String? _loadedLimitDeviceId;

  Future<bool> _requestPermissions() async {
    if (!Platform.isAndroid) return true;

    final scan = await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    final legacyLocation = await Permission.locationWhenInUse.request();

    // BLUETOOTH_SCAN applies on Android 12+; location applies on older Android.
    return scan.isGranted || legacyLocation.isGranted;
  }

  Future<void> start() async {
    await stop(setIdle: false);
    errorMessage = null;
    platformError = null;

    if (!await _requestPermissions()) {
      state = HoraLinkScanState.permissionDenied;
      notifyListeners();
      return;
    }

    state = HoraLinkScanState.scanning;
    notifyListeners();

    _scanSubscription = _results.receiveBroadcastStream().listen(
      (dynamic event) {
        final values = Map<Object?, Object?>.from(event as Map);
        if (values['type'] != 'advertisement') return;
        final payloadValues = (values['payload'] as List).cast<int>();
        final parsed = HoraLinkMeasurement.fromPayload(
          Uint8List.fromList(payloadValues),
          values['rssi'] as int,
        );
        if (parsed == null) return;
        measurement = parsed;
        deviceId = values['deviceId'] as String?;
        deviceName = values['deviceName'] as String? ?? 'HoraLink';
        state = HoraLinkScanState.found;
        notifyListeners();
        final id = deviceId;
        if (id != null) unawaited(_loadUsageLimit(id));
      },
      onError: (Object error) {
        errorMessage = error.toString();
        state = HoraLinkScanState.error;
        notifyListeners();
      },
    );

    try {
      await _commands.invokeMethod<void>('startScan');
    } on PlatformException catch (error) {
      errorMessage = error.message ?? error.code;
      platformError = error;
      state = HoraLinkScanState.error;
      notifyListeners();
    }

    _stopTimer = Timer(const Duration(seconds: 15), () {
      stop(setIdle: measurement == null);
    });
  }

  Future<String> connectForConfiguration() async {
    final id = deviceId;
    if (id == null) {
      throw PlatformException(
        code: 'NO_DEVICE',
        message: 'Primero recibe una lectura de HoraLink.',
      );
    }
    await stop(setIdle: false);
    final response = await _commands.invokeMapMethod<String, dynamic>(
      'connect',
      {'deviceId': id},
    );
    deviceName = response?['name'] as String? ?? deviceName;
    notifyListeners();
    return deviceName;
  }

  Future<void> saveDeviceName(String name) async {
    final saved = await _commands.invokeMethod<String>('writeName', {
      'name': name,
    });
    deviceName = saved ?? name;
    notifyListeners();
  }

  Future<void> _loadUsageLimit(String id) async {
    if (_loadedLimitDeviceId == id) return;
    _loadedLimitDeviceId = id;
    try {
      usageLimitHours = await ProductPreferences.loadUsageLimitHours(id);
    } on PlatformException {
      usageLimitHours = null;
    }
    notifyListeners();
  }

  Future<void> saveUsageLimitHours(int hours) async {
    final id = deviceId;
    if (id == null) {
      throw PlatformException(
        code: 'NO_DEVICE',
        message: 'Primero recibe una lectura de HoraLink.',
      );
    }
    await ProductPreferences.saveUsageLimitHours(id, hours);
    usageLimitHours = hours;
    _loadedLimitDeviceId = id;
    notifyListeners();
  }

  Future<void> requestHourCounterReset() =>
      _commands.invokeMethod<void>('requestReset');

  Future<int> readResetStatus() async =>
      await _commands.invokeMethod<int>('readResetStatus') ?? 0;

  void applySuccessfulReset() {
    measurement = measurement?.copyWith(
      accumulatedSeconds: 0,
      receivedAt: DateTime.now(),
    );
    notifyListeners();
  }

  Future<void> disconnectConfiguration() async {
    try {
      await _commands.invokeMethod<void>('disconnect');
    } on PlatformException {
      // The ESP32-C3 may already have closed the temporary session.
    }
  }

  Future<void> stop({bool setIdle = true}) async {
    _stopTimer?.cancel();
    _stopTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (Platform.isAndroid) {
      try {
        await _commands.invokeMethod<void>('stopScan');
      } on PlatformException {
        // The Android scanner may already be stopped.
      }
    }
    if (setIdle && state == HoraLinkScanState.scanning) {
      state = HoraLinkScanState.idle;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    unawaited(stop(setIdle: false));
    super.dispose();
  }
}
