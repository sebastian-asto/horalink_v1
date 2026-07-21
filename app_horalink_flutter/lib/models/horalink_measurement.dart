import 'dart:typed_data';

class HoraLinkMeasurement {
  HoraLinkMeasurement({
    required this.accumulatedSeconds,
    required this.channelRunning,
    required this.batteryValid,
    required this.batteryPercent,
    required this.batteryMillivolts,
    required this.rssi,
    required this.receivedAt,
  });

  static const serviceUuid = '7e57d004-2b97-0e7a-e511-9b9941e4a8f2';

  final int accumulatedSeconds;
  final bool channelRunning;
  final bool batteryValid;
  final int batteryPercent;
  final int batteryMillivolts;
  final int rssi;
  final DateTime receivedAt;

  HoraLinkMeasurement copyWith({
    int? accumulatedSeconds,
    bool? channelRunning,
    bool? batteryValid,
    int? batteryPercent,
    int? batteryMillivolts,
    int? rssi,
    DateTime? receivedAt,
  }) {
    return HoraLinkMeasurement(
      accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
      channelRunning: channelRunning ?? this.channelRunning,
      batteryValid: batteryValid ?? this.batteryValid,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      batteryMillivolts: batteryMillivolts ?? this.batteryMillivolts,
      rssi: rssi ?? this.rssi,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }

  static HoraLinkMeasurement? fromPayload(Uint8List payload, int rssi) {
    if (payload.length < 10 || payload[0] != 1) {
      return null;
    }

    final flags = payload[1];
    var seconds = 0;
    for (var index = 4; index >= 0; index--) {
      seconds = (seconds << 8) | payload[5 + index];
    }

    return HoraLinkMeasurement(
      accumulatedSeconds: seconds,
      channelRunning: (flags & 0x01) != 0,
      batteryValid: (flags & 0x02) != 0,
      batteryPercent: payload[2],
      batteryMillivolts: payload[3] | (payload[4] << 8),
      rssi: rssi,
      receivedAt: DateTime.now(),
    );
  }

  String get formattedRuntime {
    return '${runtimeMonths.toString().padLeft(2, '0')} meses  '
        '${runtimeDays.toString().padLeft(2, '0')} días  '
        '${runtimeHours.toString().padLeft(2, '0')}:'
        '${runtimeMinutes.toString().padLeft(2, '0')}:'
        '${runtimeSeconds.toString().padLeft(2, '0')}';
  }

  // Para el horómetro, un mes de mantenimiento equivale a 30 días.
  int get runtimeMonths => accumulatedSeconds ~/ (30 * 86400);
  int get runtimeDays => (accumulatedSeconds ~/ 86400) % 30;
  int get runtimeHours => (accumulatedSeconds ~/ 3600) % 24;
  int get runtimeMinutes => (accumulatedSeconds ~/ 60) % 60;
  int get runtimeSeconds => accumulatedSeconds % 60;
}
