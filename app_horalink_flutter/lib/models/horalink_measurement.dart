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
    final days = accumulatedSeconds ~/ 86400;
    final hours = (accumulatedSeconds ~/ 3600) % 24;
    final minutes = (accumulatedSeconds ~/ 60) % 60;
    final seconds = accumulatedSeconds % 60;
    return '${days.toString().padLeft(2, '0')} días  '
        '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
