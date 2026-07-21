import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'models/horalink_measurement.dart';
import 'models/horalink_product.dart';
import 'screens/product_selection_screen.dart';
import 'services/horalink_scanner.dart';
import 'services/product_preferences.dart';
import 'settings/app_settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HoraLinkApp());
}

class HoraLinkApp extends StatefulWidget {
  const HoraLinkApp({super.key});

  @override
  State<HoraLinkApp> createState() => _HoraLinkAppState();
}

class _HoraLinkAppState extends State<HoraLinkApp> {
  late final AppSettingsController settings;

  @override
  void initState() {
    super.initState();
    settings = AppSettingsController()..addListener(_refresh);
    settings.load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    settings.removeListener(_refresh);
    settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = settings.themeMode == ThemeMode.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: dark
            ? const Color(0xff101719)
            : const Color(0xfff3f6f5),
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
    return MaterialApp(
      title: 'HoraLink',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      locale: Locale(settings.language.code),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => AppSettingsScope(
        controller: settings,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HoraLinkProductRouter(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff126e82),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xff101719)
          : const Color(0xfff3f6f5),
      appBarTheme: AppBarTheme(
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xff182326) : Colors.white,
      ),
      useMaterial3: true,
    );
  }
}

class HoraLinkProductRouter extends StatefulWidget {
  const HoraLinkProductRouter({super.key});

  @override
  State<HoraLinkProductRouter> createState() => _HoraLinkProductRouterState();
}

class _HoraLinkProductRouterState extends State<HoraLinkProductRouter> {
  HoraLinkProduct? selectedProduct;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadSelection();
  }

  Future<void> _loadSelection() async {
    final product = await ProductPreferences.load();
    if (!mounted) return;
    setState(() {
      selectedProduct = product;
      loading = false;
    });
  }

  Future<void> _selectProduct(HoraLinkProduct product) async {
    if (product != HoraLinkProduct.ble) return;
    setState(() => loading = true);
    try {
      await ProductPreferences.save(product);
      if (!mounted) return;
      setState(() {
        selectedProduct = product;
        loading = false;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedPlatformError(context, error))),
      );
    }
  }

  Future<void> _changeProduct() async {
    try {
      await ProductPreferences.clear();
    } on PlatformException {
      // El selector también puede mostrarse aunque Android no guarde el cambio.
    }
    if (mounted) setState(() => selectedProduct = null);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return switch (selectedProduct) {
      HoraLinkProduct.ble => HoraLinkDashboard(onChangeProduct: _changeProduct),
      HoraLinkProduct.lora ||
      null => ProductSelectionScreen(onSelected: _selectProduct),
    };
  }
}

class HoraLinkDashboard extends StatefulWidget {
  const HoraLinkDashboard({super.key, required this.onChangeProduct});

  final Future<void> Function() onChangeProduct;

  @override
  State<HoraLinkDashboard> createState() => _HoraLinkDashboardState();
}

class _HoraLinkDashboardState extends State<HoraLinkDashboard> {
  late final HoraLinkScanner scanner;
  bool configurationBusy = false;

  @override
  void initState() {
    super.initState();
    scanner = HoraLinkScanner()..addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _openConfiguration() async {
    setState(() => configurationBusy = true);
    try {
      final name = await scanner.connectForConfiguration();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) =>
            HoraLinkConfigurationSheet(scanner: scanner, initialName: name),
      );
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizedPlatformError(context, error))),
        );
      }
    } finally {
      await scanner.disconnectConfiguration();
      if (mounted) setState(() => configurationBusy = false);
    }
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
        title: Text(scanner.deviceName),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: () => showAppSettings(context),
            tooltip: context.tr('Ajustes', 'Settings'),
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            onPressed: widget.onChangeProduct,
            tooltip: context.tr('Cambiar producto', 'Change product'),
            icon: const Icon(Icons.grid_view_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _StatusBanner(state: scanner.state),
            const SizedBox(height: 18),
            _RuntimeCard(measurement: measurement),
            if (scanner.usageLimitHours != null) ...[
              const SizedBox(height: 14),
              _UsageGoalCard(
                measurement: measurement,
                limitHours: scanner.usageLimitHours!,
              ),
            ],
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
                    ? context.tr('Detener búsqueda', 'Stop scanning')
                    : context.tr('Buscar HoraLink', 'Find HoraLink'),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: scanner.deviceId == null || configurationBusy
                  ? null
                  : _openConfiguration,
              icon: configurationBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.settings_bluetooth_rounded),
              label: Text(
                configurationBusy
                    ? context.tr('Conectando…', 'Connecting…')
                    : context.tr('Configurar HoraLink', 'Configure HoraLink'),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              context.tr(
                'Pulsa “Buscar HoraLink” y después el botón físico del equipo. '
                    'HoraLink publicará sus datos durante 10 segundos.',
                'Tap “Find HoraLink”, then press the device button. HoraLink '
                    'will advertise its data for 10 seconds.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            if (scanner.state == HoraLinkScanState.permissionDenied)
              _MessageCard(
                icon: Icons.lock_outline,
                text: context.tr(
                  'Autoriza Bluetooth/dispositivos cercanos en los ajustes de Android.',
                  'Allow Bluetooth/nearby devices in Android settings.',
                ),
              ),
            if (scanner.errorMessage != null)
              _MessageCard(
                icon: Icons.error_outline,
                text: scanner.platformError == null
                    ? scanner.errorMessage!
                    : localizedPlatformError(context, scanner.platformError!),
              ),
          ],
        ),
      ),
    );
  }
}

class HoraLinkConfigurationSheet extends StatefulWidget {
  const HoraLinkConfigurationSheet({
    super.key,
    required this.scanner,
    required this.initialName,
  });

  final HoraLinkScanner scanner;
  final String initialName;

  @override
  State<HoraLinkConfigurationSheet> createState() =>
      _HoraLinkConfigurationSheetState();
}

class _HoraLinkConfigurationSheetState
    extends State<HoraLinkConfigurationSheet> {
  late final TextEditingController nameController;
  late final TextEditingController usageLimitController;
  bool savingName = false;
  bool savingLimit = false;
  bool resetting = false;
  String? message;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.initialName);
    usageLimitController = TextEditingController(
      text: widget.scanner.usageLimitHours?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    usageLimitController.dispose();
    super.dispose();
  }

  Future<void> _saveUsageLimit() async {
    final hours = int.tryParse(usageLimitController.text.trim());
    if (hours == null || hours <= 0 || hours > 10000000) {
      setState(
        () => message = context.tr(
          'Ingresa un límite entre 1 y 10 000 000 horas.',
          'Enter a limit between 1 and 10,000,000 hours.',
        ),
      );
      return;
    }

    setState(() {
      savingLimit = true;
      message = null;
    });
    try {
      await widget.scanner.saveUsageLimitHours(hours);
      if (mounted) {
        setState(
          () => message = context.tr(
            'Límite de $hours horas guardado.',
            '$hours-hour limit saved.',
          ),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => message = localizedPlatformError(context, error));
      }
    } finally {
      if (mounted) setState(() => savingLimit = false);
    }
  }

  Future<void> _saveName() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      setState(
        () => message = context.tr(
          'Escribe un nombre para el equipo.',
          'Enter a name for the device.',
        ),
      );
      return;
    }

    setState(() {
      savingName = true;
      message = null;
    });
    try {
      await widget.scanner.saveDeviceName(name);
      if (mounted) {
        setState(
          () => message = context.tr(
            'Nombre guardado correctamente.',
            'Name saved successfully.',
          ),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => message = localizedPlatformError(context, error));
      }
    } finally {
      if (mounted) setState(() => savingName = false);
    }
  }

  Future<void> _requestReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text(context.tr('¿Reiniciar contador?', 'Reset hour counter?')),
        content: Text(
          context.tr(
            'Se eliminarán permanentemente las horas acumuladas de '
                '“${widget.scanner.deviceName}”. Después deberás confirmar '
                'pulsando nuevamente el botón físico de HoraLink.',
            'The accumulated hours for “${widget.scanner.deviceName}” will be '
                'permanently deleted. You must then confirm by pressing the '
                'physical HoraLink button again.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancelar', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.tr('Continuar', 'Continue')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      resetting = true;
      message = context.tr(
        'Pulsa ahora el botón físico de HoraLink para confirmar.',
        'Press the physical HoraLink button now to confirm.',
      );
    });
    try {
      await widget.scanner.requestHourCounterReset();
      final deadline = DateTime.now().add(const Duration(seconds: 17));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final status = await widget.scanner.readResetStatus();
        if (!mounted) return;
        if (status == 2) {
          widget.scanner.applySuccessfulReset();
          setState(() {
            resetting = false;
            message = context.tr(
              'Contador reiniciado correctamente.',
              'Hour counter reset successfully.',
            );
          });
          return;
        }
        if (status == 3) {
          setState(() {
            resetting = false;
            message = context.tr(
              'La confirmación física expiró. No se borró el contador.',
              'Physical confirmation expired. The counter was not erased.',
            );
          });
          return;
        }
      }
      if (mounted) {
        setState(() {
          resetting = false;
          message = context.tr(
            'Tiempo agotado. No se confirmó el reinicio.',
            'Time expired. The reset was not confirmed.',
          );
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          resetting = false;
          message = localizedPlatformError(context, error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 20),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings_bluetooth_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  context.tr('Configurar HoraLink', 'Configure HoraLink'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'La conexión permanecerá abierta durante un máximo de 60 segundos.',
                'The connection will remain open for up to 60 seconds.',
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: nameController,
              enabled: !savingName && !resetting,
              maxLength: 32,
              decoration: InputDecoration(
                labelText: context.tr('Nombre del equipo', 'Device name'),
                hintText: context.tr(
                  'HoraLink - Lámpara UV',
                  'HoraLink - UV Lamp',
                ),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.label_outline_rounded),
              ),
            ),
            FilledButton.icon(
              onPressed: savingName || savingLimit || resetting
                  ? null
                  : _saveName,
              icon: savingName
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(context.tr('Guardar nombre', 'Save name')),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'Vida útil o mantenimiento',
                'Service life or maintenance',
              ),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'Define el límite de funcionamiento recomendado por el fabricante. '
                    'Por ejemplo, una lámpara UV puede configurarse en 10 000 horas.',
                'Set the operating limit recommended by the manufacturer. For '
                    'example, a UV lamp can be set to 10,000 hours.',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: usageLimitController,
              enabled: !savingName && !savingLimit && !resetting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: context.tr('Límite de uso', 'Usage limit'),
                hintText: '10000',
                suffixText: context.tr('horas', 'hours'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.speed_rounded),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: savingName || savingLimit || resetting
                  ? null
                  : _saveUsageLimit,
              icon: savingLimit
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.donut_large_rounded),
              label: Text(
                context.tr('Guardar límite de uso', 'Save usage limit'),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              context.tr('Reinicio del horómetro', 'Hour meter reset'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'El nombre y la configuración se conservarán. Solo se reiniciarán '
                    'las horas y las transiciones del canal.',
                'The name and settings will be preserved. Only the hours and '
                    'channel transitions will be reset.',
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: savingName || savingLimit || resetting
                  ? null
                  : _requestReset,
              icon: resetting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restart_alt_rounded),
              label: Text(
                resetting
                    ? context.tr(
                        'Esperando botón físico…',
                        'Waiting for physical button…',
                      )
                    : context.tr('Reiniciar contador', 'Reset hour counter'),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 14),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
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
        context.tr('Buscando publicidad BLE…', 'Scanning for BLE data…'),
        const Color(0xff126e82),
      ),
      HoraLinkScanState.found => (
        Icons.check_circle_outline,
        context.tr('Datos recibidos', 'Data received'),
        const Color(0xff218739),
      ),
      HoraLinkScanState.permissionDenied => (
        Icons.bluetooth_disabled,
        context.tr('Permiso requerido', 'Permission required'),
        const Color(0xffa65b00),
      ),
      HoraLinkScanState.error => (
        Icons.warning_amber_rounded,
        context.tr('No fue posible buscar', 'Unable to scan'),
        const Color(0xffb3261e),
      ),
      HoraLinkScanState.idle => (
        Icons.bluetooth_rounded,
        context.tr('Listo para buscar', 'Ready to scan'),
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
            Text(
              context.tr('TIEMPO ACUMULADO', 'ACCUMULATED TIME'),
              style: const TextStyle(
                color: Color(0xffa9c8c6),
                fontSize: 12,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _RuntimeUnit(
                  value: measurement?.runtimeMonths,
                  label: context.tr('meses', 'months'),
                ),
                _RuntimeUnit(
                  value: measurement?.runtimeDays,
                  label: context.tr('días', 'days'),
                ),
                _RuntimeUnit(
                  value: measurement?.runtimeHours,
                  label: context.tr('horas', 'hours'),
                ),
                _RuntimeUnit(value: measurement?.runtimeMinutes, label: 'min'),
                _RuntimeUnit(
                  value: measurement?.runtimeSeconds,
                  label: context.tr('seg', 'sec'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              measurement == null
                  ? context.tr('Sin lectura todavía', 'No reading yet')
                  : context.tr(
                      'Actualizado ${_formatTime(measurement!.receivedAt)}  •  RSSI ${measurement!.rssi} dBm',
                      'Updated ${_formatTime(measurement!.receivedAt)}  •  RSSI ${measurement!.rssi} dBm',
                    ),
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

class _RuntimeUnit extends StatelessWidget {
  const _RuntimeUnit({required this.value, required this.label});

  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value?.toString().padLeft(2, '0') ?? '--',
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xffa9c8c6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageGoalCard extends StatelessWidget {
  const _UsageGoalCard({required this.measurement, required this.limitHours});

  final HoraLinkMeasurement? measurement;
  final int limitHours;

  @override
  Widget build(BuildContext context) {
    final usedHours = (measurement?.accumulatedSeconds ?? 0) / 3600;
    final ratio = usedHours / limitHours;
    final progress = ratio.clamp(0.0, 1.0);
    final percentage = (ratio * 100).round();
    final remainingHours = (limitHours - usedHours)
        .clamp(0.0, limitHours)
        .toDouble();
    final color = ratio >= 0.9
        ? const Color(0xffb3261e)
        : ratio >= 0.75
        ? const Color(0xffa65b00)
        : const Color(0xff218739);

    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 108,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      color: color,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$percentage %',
                        style: TextStyle(
                          color: color,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        context.tr('utilizado', 'used'),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(
                      'VIDA ÚTIL / MANTENIMIENTO',
                      'SERVICE LIFE / MAINTENANCE',
                    ),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    context.tr(
                      '${_formatHours(usedHours)} h de $limitHours h',
                      '${_formatHours(usedHours)} h of $limitHours h',
                    ),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    ratio >= 1
                        ? context.tr(
                            'Límite alcanzado: revisa el equipo.',
                            'Limit reached: inspect the equipment.',
                          )
                        : context.tr(
                            'Restan ${_formatHours(remainingHours)} horas',
                            '${_formatHours(remainingHours)} hours remaining',
                          ),
                    style: TextStyle(
                      color: ratio >= 1 ? color : scheme.onSurfaceVariant,
                      height: 1.3,
                      fontWeight: ratio >= 1
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatHours(double hours) =>
      hours < 100 ? hours.toStringAsFixed(1) : hours.round().toString();
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
      title: context.tr('Batería', 'Battery'),
      value: percent == null ? '-- %' : '$percent %',
      subtitle: valid
          ? '${(measurement!.batteryMillivolts / 1000).toStringAsFixed(3)} V'
          : context.tr('No disponible', 'Unavailable'),
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
      title: context.tr('Canal 1', 'Channel 1'),
      value: running == null
          ? '--'
          : (running
                ? context.tr('Activo', 'Running')
                : context.tr('Apagado', 'Off')),
      subtitle: running == true
          ? context.tr('Contabilizando', 'Counting time')
          : context.tr('Estado recibido', 'Status received'),
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
