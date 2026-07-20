# Firmware HoraLink V1 para ESP32-C3

Firmware desarrollado con ESP-IDF 5.5.4 para un horómetro de un canal de bajo
consumo. Mantiene el ESP32-C3 en deep sleep, conserva el tiempo mediante el RTC
con cristal externo, guarda las transiciones en NVS y transmite una instantánea
por publicidad BLE cuando se pulsa el botón.

## Mapa de pines

| Señal de la PCB | Pin | Dirección | Función |
|---|---:|---|---|
| `XTAL-32K_P` | GPIO0 | Cristal | Oscilador RTC externo de 32.768 kHz |
| `XTAL-32K_N` | GPIO1 | Cristal | Oscilador RTC externo de 32.768 kHz |
| `SDA/I2C` | GPIO2 | Bidireccional | Datos del MAX17048 |
| `CH1/RTC` | GPIO4 | Entrada | Pulso HIGH de 36 ms; despierta por cambio de canal |
| `BUTTON/RTC` | GPIO5 | Entrada | Botón activo en HIGH; inicia la consulta BLE |
| `STATE-CH1` | GPIO6 | Entrada | Estado estable: `0` apagado, `1` funcionando |
| `SCL/I2C` | GPIO8 | Salida | Reloj I2C del MAX17048 |

GPIO4, GPIO5 y GPIO6 son manejados por la electrónica de la PCB, por lo que el
firmware no habilita resistencias internas. El bus I2C utiliza los pull-up
externos de SDA y SCL a 3.3 V.

ESP-IDF muestra el siguiente aviso siempre que
`enable_internal_pullup = false`:

```text
i2c.master: Please check pull-up resistances whether be connected properly.
```

Es informativo; no indica una falla cuando los pull-up externos están montados
y el MAX17048 responde correctamente.

## Secuencia del horómetro

### Arranque inicial

El firmware configura las entradas, inicializa NVS, lee GPIO6 y crea el primer
registro si todavía no existe. Luego configura GPIO4 y GPIO5 como fuentes de
despertar por nivel alto y entra en deep sleep.

### Canal apagado a encendido

1. GPIO6 cambia de `0` a `1`.
2. GPIO4 genera un pulso HIGH y despierta al ESP32-C3.
3. El firmware compara GPIO6 con el último estado almacenado.
4. Guarda en NVS el instante inicial de la sesión y el nuevo estado.
5. Regresa a deep sleep.

### Canal encendido a apagado

1. GPIO6 cambia de `1` a `0`.
2. GPIO4 despierta al ESP32-C3.
3. Se calcula la duración desde el instante inicial de la sesión.
4. La duración se suma al tiempo acumulado.
5. Se guardan el estado apagado, el acumulado y el contador de transiciones.
6. El equipo regresa a deep sleep.

### Pulsación del botón

1. GPIO5 despierta al ESP32-C3.
2. Se calcula el tiempo efectivo, incluyendo una sesión actualmente activa.
3. Se leen `VCELL` y `SOC` del MAX17048 en la dirección I2C `0x36`.
4. NimBLE inicia publicidad legacy no conectable durante 10 segundos.
5. GPIO6 se muestrea cada 20 ms; un cambio requiere tres muestras iguales para
   ser aceptado y guardado.
6. Se detiene la publicidad, se libera NimBLE y se espera que GPIO4/GPIO5
   regresen a LOW.
7. El ESP32-C3 entra nuevamente en deep sleep.

## Registro NVS

El namespace `horometer` contiene un único blob versionado con:

| Campo | Tipo | Descripción |
|---|---|---|
| `last_state` | `uint8_t` | Último estado confirmado de GPIO6 |
| `session_start_ms` | `int64_t` | Instante RTC de inicio de la sesión activa |
| `accumulated_ms` | `uint64_t` | Tiempo finalizado acumulado en milisegundos |
| `transition_count` | `uint32_t` | Número de transiciones confirmadas |

La flash solamente se escribe al crear el registro, corregir una sesión cuyo
RTC se haya reiniciado o confirmar una transición. Consultar con el botón no
escribe NVS si GPIO6 permanece sin cambios.

## MAX17048

El driver usa la API I2C master de ESP-IDF a 100 kHz:

| Registro | Dirección | Conversión |
|---|---:|---|
| `VCELL` | `0x02` | Valor de 12 bits, 1.25 mV por LSB desplazado |
| `SOC` | `0x04` | Porcentaje ModelGauge, 1/256 % por LSB |

El porcentaje publicado proviene del cálculo SOC interno del MAX17048. También
se transmite el voltaje para diagnóstico. Si falla la lectura I2C, la
publicidad continúa con la bandera de batería no válida.

## Trama de publicidad BLE

UUID de Service Data:

```text
7e57d004-2b97-0e7a-e511-9b9941e4a8f2
```

Payload HoraLink de 10 bytes:

| Byte(s) | Campo | Formato |
|---:|---|---|
| 0 | Versión | Actualmente `1` |
| 1 | Banderas | Bit 0: canal activo; bit 1: batería válida |
| 2 | Batería | Porcentaje `0..100`; `0xFF` si no es válido |
| 3–4 | Voltaje | Milivoltios, `uint16` little-endian |
| 5–9 | Horómetro | Segundos acumulados, entero de 40 bits little-endian |

La publicidad se repite aproximadamente cada 100–120 ms. Se usa
`BLE_GAP_CONN_MODE_NON`, por lo que HoraLink no acepta conexiones ni
emparejamiento.

## Estructura del código

```text
main/
├── main.c
└── app/
    ├── ble/horalink_ble.c
    ├── board/board_pins.h
    ├── drivers/max17048/max17048.c
    ├── horometer/horometer_app.c
    └── storage/horometer_storage.c
```

## Configuración y compilación

Requisitos:

- ESP-IDF 5.5.4.
- Target `esp32c3`.
- Flash de 4 MB.
- Cristal RTC externo de 32.768 kHz.

Compilar:

```text
idf.py build
```

Grabar y abrir el monitor, sustituyendo el puerto cuando sea necesario:

```text
idf.py -p COM10 flash monitor
```

La compilación verificada genera `build/horalink_V1_esp32c3.bin`. La tabla de
particiones contiene NVS, `otadata`, dos slots OTA de 1856 KiB, `phy_init` y
una partición SPIFFS de 256 KiB.

## Mediciones de referencia

En la PCB probada, alimentada a 4.2 V y medida después de entrar en deep sleep,
se observaron aproximadamente 47 µA con el canal apagado y 110 µA con el canal
encendido. Son valores experimentales de referencia; pueden variar con la
placa, temperatura, instrumento, estado del MAX17048 y componentes externos.

## Prueba recomendada

1. Enciende la PCB con GPIO6 en LOW y confirma la entrada a deep sleep.
2. Activa el canal y verifica el registro del instante inicial.
3. Desactiva el canal y verifica la duración y el acumulado.
4. En la aplicación móvil pulsa **Buscar HoraLink**.
5. Pulsa el botón físico GPIO5.
6. Confirma en consola la lectura del MAX17048, el inicio de publicidad y el
   mensaje de finalización después de 10 segundos.
7. Comprueba en la app que tiempo, batería, voltaje y estado coinciden.
