import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/horalink_measurement.dart';

enum HoraLinkScanState { idle, scanning, found, permissionDenied, error }

class HoraLinkScanner extends ChangeNotifier {
  static const _commands = MethodChannel('horalink/ble_commands');
  static const _results = EventChannel('horalink/ble_results');

  StreamSubscription<dynamic>? _scanSubscription;
  Timer? _stopTimer;

  HoraLinkScanState state = HoraLinkScanState.idle;
  HoraLinkMeasurement? measurement;
  String? errorMessage;

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
        final payloadValues = (values['payload'] as List).cast<int>();
        final parsed = HoraLinkMeasurement.fromPayload(
          Uint8List.fromList(payloadValues),
          values['rssi'] as int,
        );
        if (parsed == null) return;
        measurement = parsed;
        state = HoraLinkScanState.found;
        notifyListeners();
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
      state = HoraLinkScanState.error;
      notifyListeners();
    }

    _stopTimer = Timer(const Duration(seconds: 15), () {
      stop(setIdle: measurement == null);
    });
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
