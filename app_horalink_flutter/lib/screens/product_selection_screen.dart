import 'package:flutter/material.dart';

import '../models/horalink_product.dart';
import '../settings/app_settings.dart';

class ProductSelectionScreen extends StatelessWidget {
  const ProductSelectionScreen({super.key, required this.onSelected});

  final Future<void> Function(HoraLinkProduct product) onSelected;

  void _showLoRaComingSoon(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cell_tower_rounded,
              size: 42,
              color: Color(0xff126e82),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'HoraLink LoRa estará disponible próximamente',
                'HoraLink LoRa will be available soon',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              context.tr(
                'La aplicación ya está preparada para incorporarlo cuando '
                    'finalice el desarrollo del producto LoRa.',
                'The app is ready to include it when development of the LoRa '
                    'product is complete.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      _ProductCard(
        imageAsset: 'assets/products/horalink_ble.png',
        title: 'HoraLink BLE',
        description: context.tr(
          'Consulta y configura tu horómetro directamente por Bluetooth.',
          'Read and configure your hour meter directly over Bluetooth.',
        ),
        badge: context.tr('Disponible', 'Available'),
        enabled: true,
        icon: Icons.bluetooth_rounded,
        onTap: () => onSelected(HoraLinkProduct.ble),
      ),
      _ProductCard(
        imageAsset: 'assets/products/horalink_lora.png',
        title: 'HoraLink LoRa',
        description: context.tr(
          'Monitoreo de largo alcance para instalaciones remotas.',
          'Long-range monitoring for remote installations.',
        ),
        badge: context.tr('Próximamente', 'Coming soon'),
        enabled: false,
        icon: Icons.cell_tower_rounded,
        onTap: () async => _showLoRaComingSoon(context),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return ListView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 36),
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xff123b44),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.timer_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Text(
                      'HoraLink',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => showAppSettings(context),
                      tooltip: context.tr('Ajustes', 'Settings'),
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                Text(
                  context.tr(
                    '¿Qué equipo tienes?',
                    'Which device do you have?',
                  ),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'Selecciona tu producto para ingresar a su panel de monitoreo.',
                    'Select your product to open its monitoring dashboard.',
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < cards.length; index++) ...[
                        Expanded(child: cards[index]),
                        if (index == 0) const SizedBox(width: 18),
                      ],
                    ],
                  )
                else
                  ...cards.expand((card) => [card, const SizedBox(height: 18)]),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'La selección quedará guardada. Podrás cambiar de producto '
                        'más adelante desde el panel.',
                    'Your selection will be saved. You can change products '
                        'later from the dashboard.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.imageAsset,
    required this.title,
    required this.description,
    required this.badge,
    required this.enabled,
    required this.icon,
    required this.onTap,
  });

  final String imageAsset;
  final String title;
  final String description;
  final String badge;
  final bool enabled;
  final IconData icon;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: enabled
              ? primary.withValues(alpha: 0.28)
              : const Color(0xffd7dfdd),
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 245,
                  width: double.infinity,
                  child: Opacity(
                    opacity: enabled ? 1 : 0.58,
                    child: Image.asset(imageAsset, fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: enabled
                          ? const Color(0xffe3f4e7)
                          : const Color(0xffecefed),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: enabled
                            ? const Color(0xff218739)
                            : const Color(0xff61706d),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        color: enabled ? primary : const Color(0xff7c8986),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Icon(
                        enabled
                            ? Icons.arrow_forward_rounded
                            : Icons.lock_clock_rounded,
                        color: enabled ? primary : const Color(0xff7c8986),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
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
}
