import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/product_preferences.dart';

enum AppLanguage {
  spanish('es'),
  english('en');

  const AppLanguage(this.code);
  final String code;

  static AppLanguage fromCode(String? code) =>
      code == english.code ? english : spanish;
}

class AppSettingsController extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.light;
  AppLanguage language = AppLanguage.spanish;

  Future<void> load() async {
    try {
      final values = await Future.wait([
        ProductPreferences.loadTheme(),
        ProductPreferences.loadLanguage(),
      ]);
      themeMode = values[0] == 'dark' ? ThemeMode.dark : ThemeMode.light;
      language = AppLanguage.fromCode(values[1]);
    } catch (_) {
      // Conserva español y tema claro si el canal nativo no está disponible.
    }
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await ProductPreferences.saveTheme(
      mode == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  Future<void> setLanguage(AppLanguage value) async {
    language = value;
    notifyListeners();
    await ProductPreferences.saveLanguage(value.code);
  }
}

class AppSettingsScope extends InheritedNotifier<AppSettingsController> {
  const AppSettingsScope({
    super.key,
    required AppSettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppSettingsController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSettingsScope>()!.notifier!;
}

extension HoraLinkTranslations on BuildContext {
  String tr(String spanish, String english) =>
      AppSettingsScope.of(this).language == AppLanguage.spanish
      ? spanish
      : english;
}

String localizedPlatformError(BuildContext context, PlatformException error) {
  if (AppSettingsScope.of(context).language == AppLanguage.spanish) {
    return error.message ?? 'Ocurrió un error (${error.code}).';
  }
  return switch (error.code) {
    'BLE_UNAVAILABLE' => 'Bluetooth is off or unavailable.',
    'NO_DEVICE' => 'Find and select a HoraLink first.',
    'INVALID_NAME' => 'The name must use between 1 and 40 UTF-8 bytes.',
    'INVALID_LIMIT' => 'The usage limit is invalid.',
    'CONNECTION_LOST' || 'DISCONNECTED' => 'HoraLink disconnected.',
    'SERVICE_NOT_FOUND' => 'Configuration service not found.',
    'NAME_READ_FAILED' => 'Unable to read the HoraLink name.',
    'WRITE_FAILED' => 'Unable to write the setting to HoraLink.',
    'READ_FAILED' => 'Unable to read the setting from HoraLink.',
    'CONNECT_FAILED' => 'Unable to start the Bluetooth connection.',
    'NOT_CONNECTED' => 'HoraLink is not connected.',
    'BUSY' => 'Another Bluetooth operation is in progress.',
    'TIMEOUT' => 'The Bluetooth operation timed out.',
    'INVALID_PRODUCT' => 'Invalid HoraLink product.',
    'INVALID_DEVICE' => 'Invalid HoraLink identifier.',
    'INVALID_THEME' => 'Invalid theme.',
    'INVALID_LANGUAGE' => 'Invalid language.',
    _ => 'An error occurred (${error.code}).',
  };
}

Future<void> showAppSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => const _AppSettingsSheet(),
  );
}

class _AppSettingsSheet extends StatelessWidget {
  const _AppSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                context.tr('Apariencia e idioma', 'Appearance and language'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            context.tr('Tema', 'Theme'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.light,
                icon: const Icon(Icons.light_mode_rounded),
                label: Text(context.tr('Claro', 'Light')),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: const Icon(Icons.dark_mode_rounded),
                label: Text(context.tr('Oscuro', 'Dark')),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (value) => settings.setTheme(value.first),
          ),
          const SizedBox(height: 24),
          Text(
            context.tr('Idioma', 'Language'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          SegmentedButton<AppLanguage>(
            segments: const [
              ButtonSegment(value: AppLanguage.spanish, label: Text('Español')),
              ButtonSegment(value: AppLanguage.english, label: Text('English')),
            ],
            selected: {settings.language},
            onSelectionChanged: (value) => settings.setLanguage(value.first),
          ),
        ],
      ),
    );
  }
}
