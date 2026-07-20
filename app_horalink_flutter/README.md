# Aplicación móvil HoraLink

Aplicación Flutter para Android que recibe la instantánea del horómetro desde
la publicidad BLE del ESP32-C3. No establece una conexión, no requiere
emparejamiento y no modifica la información del dispositivo.

## Información mostrada

- Tiempo acumulado en formato `días HH:MM:SS`.
- Porcentaje de batería calculado por el MAX17048.
- Voltaje de batería.
- Estado del canal 1: activo o apagado.
- RSSI del paquete recibido.
- Hora de la última actualización.

## Funcionamiento

La app abre una búsqueda BLE de 15 segundos. El código Android nativo utiliza
`BluetoothLeScanner`, extrae Service Data del UUID HoraLink y entrega el
payload a Dart mediante canales de plataforma.

UUID reconocido:

```text
7e57d004-2b97-0e7a-e511-9b9941e4a8f2
```

La publicidad del ESP32-C3 dura 10 segundos después de pulsar GPIO5. Para
evitar perderla, primero inicia la búsqueda en la aplicación y después pulsa
el botón físico.

## Permisos Android

El manifiesto incluye:

- `BLUETOOTH` y `BLUETOOTH_ADMIN` hasta Android 11.
- `ACCESS_FINE_LOCATION` para búsqueda BLE en Android antiguos.
- `BLUETOOTH_SCAN` y `BLUETOOTH_CONNECT` en Android 12 o posterior.
- Característica obligatoria `android.hardware.bluetooth_le`.

En Android 12+ el usuario debe autorizar **Dispositivos cercanos**. En versiones
anteriores puede solicitarse ubicación debido al modelo de permisos BLE de
Android, aunque HoraLink no utiliza la ubicación del teléfono.

## Estructura principal

```text
lib/
├── main.dart
├── models/horalink_measurement.dart
└── services/horalink_scanner.dart

android/app/src/main/kotlin/com/example/app_horalink_flutter/
└── MainActivity.kt
```

- `main.dart`: interfaz y tablero de mediciones.
- `horalink_measurement.dart`: validación y decodificación de los 10 bytes.
- `horalink_scanner.dart`: permisos, ventana de búsqueda y estado de la UI.
- `MainActivity.kt`: escáner BLE Android y canales hacia Flutter.

## Requisitos de desarrollo

- Flutter con Dart compatible con SDK `^3.12.2`.
- Android SDK y un teléfono Android con BLE.
- Android 5.0/API 21 como versión mínima.

Instalar dependencias:

```text
flutter pub get
```

Ejecutar en un teléfono conectado:

```text
flutter devices
flutter run
```

Generar un APK de depuración:

```text
flutter build apk --debug
```

El APK queda en:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## Calidad y pruebas

Ejecutar el análisis estático:

```text
flutter analyze
```

Ejecutar las pruebas:

```text
flutter test
```

Las pruebas incluidas verifican el formato del tiempo y la decodificación byte
por byte de la trama BLE HoraLink.

## Secuencia de uso

1. Instala y abre la aplicación.
2. Activa Bluetooth.
3. Pulsa **Buscar HoraLink**.
4. Autoriza dispositivos cercanos o el permiso solicitado por Android.
5. Pulsa el botón físico GPIO5 de la PCB.
6. Espera a que aparezca **Datos recibidos**.
7. Verifica tiempo acumulado, batería, voltaje y estado del canal.

Si no se recibe una lectura, repite la búsqueda y pulsa GPIO5 dentro de la
ventana de 15 segundos. También comprueba que Bluetooth esté encendido y que el
teléfono se encuentre próximo a la PCB.
