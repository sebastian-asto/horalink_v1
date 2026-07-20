import 'package:flutter/material.dart';

import 'models/horalink_measurement.dart';
import 'services/horalink_scanner.dart';

void main() => runApp(const HoraLinkApp());

class HoraLinkApp extends StatelessWidget {
  const HoraLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HoraLink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff126e82),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff3f6f5),
        useMaterial3: true,
      ),
      home: const HoraLinkDashboard(),
    );
  }
}

class HoraLinkDashboard extends StatefulWidget {
  const HoraLinkDashboard({super.key});

  @override
  State<HoraLinkDashboard> createState() => _HoraLinkDashboardState();
}

class _HoraLinkDashboardState extends State<HoraLinkDashboard> {
  late final HoraLinkScanner scanner;

  @override
  void initState() {
    super.initState();
    scanner = HoraLinkScanner()..addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    scanner.removeListener(_refresh);
    scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final measurement = scanner.measurement;
    return Scaffold(
      appBar: AppBar(
        title: const Text('HoraLink'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _StatusBanner(state: scanner.state),
            const SizedBox(height: 18),
            _RuntimeCard(measurement: measurement),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _BatteryCard(measurement: measurement)),
                const SizedBox(width: 14),
                Expanded(child: _ChannelCard(measurement: measurement)),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: scanner.state == HoraLinkScanState.scanning
                  ? () => scanner.stop()
                  : scanner.start,
              icon: Icon(
                scanner.state == HoraLinkScanState.scanning
                    ? Icons.stop_rounded
                    : Icons.bluetooth_searching_rounded,
              ),
              label: Text(
                scanner.state == HoraLinkScanState.scanning
                    ? 'Detener búsqueda'
                    : 'Buscar HoraLink',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Pulsa “Buscar HoraLink” y después el botón físico del equipo. '
              'El ESP32-C3 publicará los datos durante 10 segundos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xff61706d), height: 1.35),
            ),
            if (scanner.state == HoraLinkScanState.permissionDenied)
              const _MessageCard(
                icon: Icons.lock_outline,
                text:
                    'Autoriza Bluetooth/dispositivos cercanos en los ajustes de Android.',
              ),
            if (scanner.errorMessage != null)
              _MessageCard(
                icon: Icons.error_outline,
                text: scanner.errorMessage!,
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.state});
  final HoraLinkScanState state;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (state) {
      HoraLinkScanState.scanning => (
        Icons.radar_rounded,
        'Buscando publicidad BLE…',
        const Color(0xff126e82),
      ),
      HoraLinkScanState.found => (
        Icons.check_circle_outline,
        'Datos recibidos',
        const Color(0xff218739),
      ),
      HoraLinkScanState.permissionDenied => (
        Icons.bluetooth_disabled,
        'Permiso requerido',
        const Color(0xffa65b00),
      ),
      HoraLinkScanState.error => (
        Icons.warning_amber_rounded,
        'No fue posible buscar',
        const Color(0xffb3261e),
      ),
      HoraLinkScanState.idle => (
        Icons.bluetooth_rounded,
        'Listo para buscar',
        const Color(0xff61706d),
      ),
    };

    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 9),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _RuntimeCard extends StatelessWidget {
  const _RuntimeCard({required this.measurement});
  final HoraLinkMeasurement? measurement;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xff123b44),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TIEMPO ACUMULADO',
              style: TextStyle(
                color: Color(0xffa9c8c6),
                fontSize: 12,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            FittedBox(
              child: Text(
                measurement?.formattedRuntime ?? '-- días  --:--:--',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              measurement == null
                  ? 'Sin lectura todavía'
                  : 'Actualizado ${_formatTime(measurement!.receivedAt)}  •  RSSI ${measurement!.rssi} dBm',
              style: const TextStyle(color: Color(0xffc5d9d7)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}:'
      '${date.second.toString().padLeft(2, '0')}';
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({required this.measurement});
  final HoraLinkMeasurement? measurement;

  @override
  Widget build(BuildContext context) {
    final valid = measurement?.batteryValid ?? false;
    final percent = valid ? measurement!.batteryPercent : null;
    return _MetricCard(
      icon: Icons.battery_charging_full_rounded,
      title: 'Batería',
      value: percent == null ? '-- %' : '$percent %',
      subtitle: valid
          ? '${(measurement!.batteryMillivolts / 1000).toStringAsFixed(3)} V'
          : 'No disponible',
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.measurement});
  final HoraLinkMeasurement? measurement;

  @override
  Widget build(BuildContext context) {
    final running = measurement?.channelRunning;
    return _MetricCard(
      icon: Icons.power_settings_new_rounded,
      title: 'Canal 1',
      value: running == null ? '--' : (running ? 'Activo' : 'Apagado'),
      subtitle: running == true ? 'Contabilizando' : 'Estado recibido',
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 13),
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: ListTile(leading: Icon(icon), title: Text(text)),
    );
  }
}
