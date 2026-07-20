import 'dart:typed_data';

import 'package:app_horalink_flutter/models/horalink_measurement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatea el tiempo acumulado', () {
    final measurement = HoraLinkMeasurement(
      accumulatedSeconds: 93784,
      channelRunning: false,
      batteryValid: true,
      batteryPercent: 75,
      batteryMillivolts: 4050,
      rssi: -61,
      receivedAt: DateTime(2026),
    );

    expect(measurement.formattedRuntime, '01 días  02:03:04');
  });

  test('decodifica la trama BLE HoraLink', () {
    final measurement = HoraLinkMeasurement.fromPayload(
      Uint8List.fromList([
        1, // version
        0x03, // canal activo y bateria valida
        82,
        0x04, 0x10, // 4100 mV little-endian
        0x3c, 0x00, 0x00, 0x00, 0x00, // 60 segundos
      ]),
      -55,
    );

    expect(measurement, isNotNull);
    expect(measurement!.accumulatedSeconds, 60);
    expect(measurement.channelRunning, isTrue);
    expect(measurement.batteryPercent, 82);
    expect(measurement.batteryMillivolts, 4100);
    expect(measurement.rssi, -55);
  });
}
