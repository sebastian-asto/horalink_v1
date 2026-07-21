import 'package:flutter/services.dart';

import '../models/horalink_product.dart';

class ProductPreferences {
  static const _channel = MethodChannel('horalink/preferences');

  static Future<HoraLinkProduct?> load() async {
    try {
      final value = await _channel.invokeMethod<String>('getSelectedProduct');
      return HoraLinkProduct.fromStorage(value);
    } on PlatformException {
      return null;
    }
  }

  static Future<void> save(HoraLinkProduct product) async {
    await _channel.invokeMethod<void>('setSelectedProduct', {
      'product': product.storageValue,
    });
  }

  static Future<void> clear() async {
    await _channel.invokeMethod<void>('clearSelectedProduct');
  }

  static Future<int?> loadUsageLimitHours(String deviceId) async {
    return _channel.invokeMethod<int>('getUsageLimitHours', {
      'deviceId': deviceId,
    });
  }

  static Future<void> saveUsageLimitHours(String deviceId, int hours) async {
    await _channel.invokeMethod<void>('setUsageLimitHours', {
      'deviceId': deviceId,
      'hours': hours,
    });
  }

  static Future<String?> loadTheme() =>
      _channel.invokeMethod<String>('getTheme');

  static Future<void> saveTheme(String theme) =>
      _channel.invokeMethod<void>('setTheme', {'theme': theme});

  static Future<String?> loadLanguage() =>
      _channel.invokeMethod<String>('getLanguage');

  static Future<void> saveLanguage(String language) =>
      _channel.invokeMethod<void>('setLanguage', {'language': language});
}
