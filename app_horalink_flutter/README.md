# Aplicación móvil HoraLink

Aplicación Flutter para Android que recibe la instantánea del horómetro desde
la publicidad BLE del ESP32-C3. También abre una conexión GATT temporal para
asignar un nombre o reiniciar el contador con autorización física.

## Selección de producto

En el primer inicio, la aplicación pregunta qué producto posee el usuario y
muestra las imágenes de las dos variantes:

- **HoraLink BLE:** disponible; abre el tablero BLE actual.
- **HoraLink LoRa:** visible como **Próximamente**, sin permitir todavía el
  ingreso a una función incompleta.

La elección BLE se guarda en las preferencias nativas de Android, por lo que
los siguientes inicios abren directamente el tablero. El icono de cuadrícula
en la barra superior permite volver a **Cambiar producto** cuando sea necesario.

## Apariencia e idioma

El botón de ajustes está disponible en el selector de producto y en el tablero.
Permite cambiar inmediatamente entre tema **Claro** y **Oscuro**, y entre
**Español** e **English**. Ambas preferencias se guardan localmente y se
restauran al abrir nuevamente la aplicación.

## Identidad visual

El launcher Android utiliza un icono propio basado en la silueta frontal del
dispositivo HoraLink BLE, con fondo verde azulado y distintivo Bluetooth. La
fuente maestra se conserva en `assets/branding/horalink_launcher_icon.png` y
los recursos optimizados para Android están en las carpetas `mipmap-*`.

## Información mostrada

- Tiempo acumulado separado en meses, días, horas, minutos y segundos. Para
  programación de mantenimiento, cada mes equivale a 30 días.
- Porcentaje de batería calculado por el MAX17048.
- Voltaje de batería.
- Estado del canal 1: activo o apagado.
- RSSI del paquete recibido.
- Hora de la última actualización.
- Progreso circular de vida útil o mantenimiento cuando se configura un límite
  de horas para el equipo.

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

Después de recibir los datos aparece **Configurar HoraLink**. Si la conexión se
establece dentro de la ventana inicial, el firmware mantiene la sesión hasta 60
segundos. No se guarda un emparejamiento permanente.

## Configuración disponible

- Nombre UTF-8 persistente, por ejemplo `HoraLink - Lámpara UV`.
- Reinicio exclusivo de horas y transiciones; el nombre se conserva.
- Diálogo de advertencia antes de solicitar el reinicio.
- Segunda pulsación física de GPIO5, con 15 segundos de plazo, para efectuar el
  borrado.
- Límite de uso configurable entre 1 y 10 000 000 horas. La app lo guarda
  localmente por dirección BLE y muestra porcentaje utilizado y horas restantes.

El nombre leído del dispositivo también se guarda localmente asociado a su
dirección BLE para mostrarlo en futuras búsquedas.

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
├── models/
│   ├── horalink_measurement.dart
│   └── horalink_product.dart
├── screens/product_selection_screen.dart
└── services/
    ├── horalink_scanner.dart
    └── product_preferences.dart

assets/products/
├── horalink_ble.png
└── horalink_lora.png

android/app/src/main/kotlin/com/example/app_horalink_flutter/
└── MainActivity.kt
```

- `main.dart`: interfaz y tablero de mediciones.
- `horalink_measurement.dart`: validación y decodificación de los 10 bytes.
- `horalink_product.dart`: modelo de las variantes BLE y LoRa.
- `product_selection_screen.dart`: selector inicial y aviso de LoRa.
- `horalink_scanner.dart`: búsqueda, conexión y operaciones de configuración.
- `product_preferences.dart`: persistencia de la variante elegida en Android.
- `MainActivity.kt`: escáner, cliente GATT Android y canales hacia Flutter.

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
2. En el primer inicio, elige **HoraLink BLE**.
3. Activa Bluetooth.
4. Pulsa **Buscar HoraLink**.
5. Autoriza dispositivos cercanos o el permiso solicitado por Android.
6. Pulsa el botón físico GPIO5 de la PCB.
7. Espera a que aparezca **Datos recibidos**.
8. Verifica tiempo acumulado, batería, voltaje y estado del canal.
9. Para cambiar el nombre, abre **Configurar HoraLink** y guarda el nuevo texto.
10. Para reiniciar horas, confirma el diálogo y pulsa GPIO5 otra vez antes de 15
   segundos.

Si no se recibe una lectura, repite la búsqueda y pulsa GPIO5 dentro de la
ventana de 15 segundos. También comprueba que Bluetooth esté encendido y que el
teléfono se encuentre próximo a la PCB.
