#include "app/horometer/horometer_app.h"

#include <stdbool.h>
#include <inttypes.h>
#include <limits.h>
#include <stdint.h>
#include <sys/time.h>

#include "app/ble/horalink_ble.h"
#include "app/board/board_pins.h"
#include "app/drivers/max17048/max17048.h"
#include "app/storage/device_config_storage.h"
#include "app/storage/horometer_storage.h"
#include "driver/gpio.h"
#include "esp_check.h"
#include "esp_log.h"
#include "esp_sleep.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "HOROMETER";

static int64_t get_rtc_time_ms(void)
{
    struct timeval now;
    ESP_ERROR_CHECK(gettimeofday(&now, NULL) == 0 ? ESP_OK : ESP_FAIL);
    return ((int64_t)now.tv_sec * 1000LL) + (now.tv_usec / 1000LL);
}

static uint64_t get_session_duration_ms(const horometer_record_t *record,
                                        int64_t now_ms)
{
    if ((record->last_state == 0U) || (now_ms < record->session_start_ms)) {
        return 0U;
    }

    return (uint64_t)(now_ms - record->session_start_ms);
}

static uint64_t saturating_add_u64(uint64_t left, uint64_t right)
{
    return (UINT64_MAX - left < right) ? UINT64_MAX : left + right;
}

static uint64_t get_effective_total_ms(const horometer_record_t *record,
                                       int64_t now_ms)
{
    return saturating_add_u64(record->accumulated_ms,
                              get_session_duration_ms(record, now_ms));
}

static void log_duration(const char *label, uint64_t duration_ms)
{
    const uint64_t total_seconds = duration_ms / 1000U;
    const uint64_t days = total_seconds / 86400U;
    const uint64_t hours = (total_seconds / 3600U) % 24U;
    const uint64_t minutes = (total_seconds / 60U) % 60U;
    const uint64_t seconds = total_seconds % 60U;

    ESP_LOGI(TAG,
             "%s: %" PRIu64 " ms (%" PRIu64 " dias, %02" PRIu64
             ":%02" PRIu64 ":%02" PRIu64 ")",
             label,
             duration_ms,
             days,
             hours,
             minutes,
             seconds);
}

static void configure_inputs(void)
{
    const gpio_config_t input_config = {
        .pin_bit_mask = HORALINK_INPUT_PIN_MASK,
        .mode = GPIO_MODE_INPUT,
        /* The PCB drives these signals LOW or HIGH. */
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };

    ESP_ERROR_CHECK(gpio_config(&input_config));
}

static uint64_t report_wakeup(void)
{
    const esp_sleep_wakeup_cause_t cause = esp_sleep_get_wakeup_cause();

    if (cause != ESP_SLEEP_WAKEUP_GPIO) {
        ESP_LOGI(TAG, "Arranque inicial; preparando el horometro.");
        return 0U;
    }

    const uint64_t wake_mask = esp_sleep_get_gpio_wakeup_status();

    if ((wake_mask & (1ULL << HORALINK_PIN_BUTTON_WAKE)) != 0) {
        ESP_LOGI(TAG, "ESP32-C3 despertado: se pulso el boton en GPIO5.");
    }

    if ((wake_mask & (1ULL << HORALINK_PIN_CH1_WAKE_PULSE)) != 0) {
        ESP_LOGI(TAG, "Pulso de cambio del canal 1 detectado en GPIO4.");
    }

    if ((wake_mask & HORALINK_WAKE_PIN_MASK) == 0) {
        ESP_LOGW(TAG, "Despertar GPIO sin pin reconocido (mascara: 0x%llx).",
                 (unsigned long long)wake_mask);
    }

    return wake_mask;
}

static void initialize_record(horometer_record_t *record,
                              uint8_t current_state,
                              int64_t now_ms)
{
    *record = (horometer_record_t) {
        .last_state = current_state,
        .session_start_ms = (current_state != 0U) ? now_ms : 0,
        .accumulated_ms = 0U,
        .transition_count = 0U,
    };

    ESP_ERROR_CHECK(horometer_storage_save(record));
    ESP_LOGI(TAG, "Primer registro del canal 1 creado en NVS (estado: %u).",
             current_state);
}

static bool update_channel_state(horometer_record_t *record,
                                 uint8_t current_state,
                                 int64_t now_ms)
{
    if (record->last_state == current_state) {
        ESP_LOGI(TAG, "GPIO6 conserva el estado %u; no se escribe NVS.",
                 current_state);
        return false;
    }

    if (current_state != 0U) {
        record->session_start_ms = now_ms;
        ESP_LOGI(TAG, "Canal 1 encendido; instante inicial guardado: %" PRId64 " ms.",
                 now_ms);
    } else {
        const uint64_t session_ms = get_session_duration_ms(record, now_ms);
        record->accumulated_ms = saturating_add_u64(record->accumulated_ms,
                                                    session_ms);
        record->session_start_ms = 0;
        log_duration("Duracion de la sesion finalizada", session_ms);
        log_duration("Tiempo acumulado guardado", record->accumulated_ms);
    }

    record->last_state = current_state;
    if (record->transition_count != UINT32_MAX) {
        record->transition_count++;
    }
    ESP_ERROR_CHECK(horometer_storage_save(record));
    ESP_LOGI(TAG, "Nuevo estado %u confirmado en NVS; transiciones: %" PRIu32 ".",
             current_state,
             record->transition_count);
    return true;
}

static void log_current_summary(const horometer_record_t *record, int64_t now_ms)
{
    const uint64_t active_session_ms = get_session_duration_ms(record, now_ms);
    const uint64_t effective_total_ms = get_effective_total_ms(record, now_ms);

    ESP_LOGI(TAG, "Resumen del canal 1: estado=%s, transiciones=%" PRIu32 ".",
             record->last_state != 0U ? "ENCENDIDO" : "APAGADO",
             record->transition_count);
    log_duration("Tiempo total de funcionamiento", effective_total_ms);
    if (record->last_state != 0U) {
        log_duration("Duracion de la sesion activa", active_session_ms);
    }
}

static void reset_hour_counter(horometer_record_t *record)
{
    const uint8_t current_state =
        (uint8_t)(gpio_get_level(HORALINK_PIN_CH1_STATE) != 0);
    const int64_t now_ms = get_rtc_time_ms();

    *record = (horometer_record_t) {
        .last_state = current_state,
        .session_start_ms = current_state != 0U ? now_ms : 0,
        .accumulated_ms = 0U,
        .transition_count = 0U,
    };
    ESP_ERROR_CHECK(horometer_storage_save(record));
    ESP_LOGW(TAG,
             "Contador reiniciado por confirmacion fisica; estado inicial=%u.",
             current_state);
}

static void run_button_advertising(horometer_record_t *record,
                                   const char *device_name)
{
    max17048_measurement_t battery = {0};
    const esp_err_t battery_err = max17048_read(&battery);
    if (battery_err != ESP_OK) {
        ESP_LOGW(TAG,
                 "MAX17048 no disponible (%s); se publicara bateria no valida.",
                 esp_err_to_name(battery_err));
    }

    const int64_t snapshot_time_ms = get_rtc_time_ms();
    uint64_t total_seconds = get_effective_total_ms(record, snapshot_time_ms) / 1000U;
    const uint64_t max_advertised_seconds = (1ULL << 40U) - 1U;
    if (total_seconds > max_advertised_seconds) {
        total_seconds = max_advertised_seconds;
    }

    const horalink_ble_snapshot_t snapshot = {
        .accumulated_seconds = total_seconds,
        .battery_mv = battery.voltage_mv,
        .battery_percent = battery.state_of_charge_percent,
        .battery_valid = battery.valid,
        .channel_running = record->last_state != 0U,
    };

    ESP_LOGI(TAG,
             "Publicando HoraLink: tiempo=%" PRIu64 " s, bateria=%s, canal=%s.",
             snapshot.accumulated_seconds,
             snapshot.battery_valid ? "valida" : "no disponible",
             snapshot.channel_running ? "ENCENDIDO" : "APAGADO");

    const esp_err_t ble_err = horalink_ble_start(&snapshot, device_name);
    if (ble_err != ESP_OK) {
        ESP_LOGE(TAG, "No se pudo iniciar BLE: %s", esp_err_to_name(ble_err));
        return;
    }

    /* GPIO6 is monitored while the radio is awake. Requiring three equal
     * samples rejects short disturbances without losing a real stable state. */
    uint8_t candidate_state = record->last_state;
    uint8_t stable_samples = 0U;
    int64_t session_deadline_us = esp_timer_get_time() +
        ((int64_t)HORALINK_BLE_ADVERTISING_TIME_MS * 1000LL);
    int64_t reset_deadline_us = 0;
    bool connection_extended = false;
    bool button_armed = gpio_get_level(HORALINK_PIN_BUTTON_WAKE) == 0;
    bool previous_button_level =
        gpio_get_level(HORALINK_PIN_BUTTON_WAKE) != 0;

    while (esp_timer_get_time() < session_deadline_us) {
        const int64_t loop_time_us = esp_timer_get_time();
        if (horalink_ble_is_connected() && !connection_extended) {
            connection_extended = true;
            session_deadline_us = loop_time_us +
                ((int64_t)HORALINK_BLE_CONNECTED_TIME_MS * 1000LL);
            ESP_LOGI(TAG, "Configuracion extendida por 60 segundos.");
        }

        char updated_name[HORALINK_DEVICE_NAME_MAX_BYTES + 1U] = {0};
        if (horalink_ble_take_name_update(updated_name,
                                          sizeof(updated_name))) {
            ESP_ERROR_CHECK(device_config_save_name(updated_name));
        }

        if (horalink_ble_take_reset_request()) {
            reset_deadline_us = loop_time_us +
                ((int64_t)HORALINK_RESET_CONFIRM_TIME_MS * 1000LL);
            if (session_deadline_us < reset_deadline_us) {
                session_deadline_us = reset_deadline_us;
            }
            button_armed = gpio_get_level(HORALINK_PIN_BUTTON_WAKE) == 0;
            ESP_LOGW(TAG,
                     "Pulse nuevamente GPIO5 antes de 15 s para confirmar el reinicio.");
        }

        const bool button_level =
            gpio_get_level(HORALINK_PIN_BUTTON_WAKE) != 0;
        if (!button_level) {
            button_armed = true;
        }
        if ((reset_deadline_us != 0) && button_armed && button_level &&
            !previous_button_level) {
            reset_hour_counter(record);
            horalink_ble_set_reset_status(HORALINK_RESET_COMPLETED);
            reset_deadline_us = 0;
            button_armed = false;
        } else if ((reset_deadline_us != 0) &&
                   (loop_time_us >= reset_deadline_us)) {
            ESP_LOGW(TAG, "Reinicio cancelado: no hubo confirmacion fisica.");
            horalink_ble_set_reset_status(HORALINK_RESET_EXPIRED);
            reset_deadline_us = 0;
        }
        previous_button_level = button_level;

        const uint8_t sampled_state =
            (uint8_t)(gpio_get_level(HORALINK_PIN_CH1_STATE) != 0);
        if (sampled_state == record->last_state) {
            candidate_state = sampled_state;
            stable_samples = 0U;
        } else if (sampled_state != candidate_state) {
            candidate_state = sampled_state;
            stable_samples = 1U;
        } else if (stable_samples < 3U) {
            stable_samples++;
            if (stable_samples == 3U) {
                ESP_LOGI(TAG,
                         "Cambio de GPIO6 detectado durante publicidad BLE.");
                update_channel_state(record,
                                     candidate_state,
                                     get_rtc_time_ms());
                stable_samples = 0U;
            }
        }
        vTaskDelay(pdMS_TO_TICKS(20));
    }

    horalink_ble_stop();
    ESP_LOGI(TAG, "Sesion BLE terminada; regresando a bajo consumo.");
}

static void wait_until_wakeup_inputs_are_low(void)
{
    bool announced = false;

    while ((gpio_get_level(HORALINK_PIN_BUTTON_WAKE) != 0) ||
           (gpio_get_level(HORALINK_PIN_CH1_WAKE_PULSE) != 0)) {
        if (!announced) {
            ESP_LOGI(TAG, "Esperando que las entradas de despertar regresen a LOW.");
            announced = true;
        }
        vTaskDelay(pdMS_TO_TICKS(5));
    }
}

static void enter_deep_sleep(void)
{
    /*
     * ESP32-C3 has no classic RTC IO block. Its supported deep-sleep GPIO
     * controller is the correct wake source for GPIO4 and GPIO5.
     */
    ESP_ERROR_CHECK(esp_deep_sleep_enable_gpio_wakeup(
        HORALINK_WAKE_PIN_MASK,
        ESP_GPIO_WAKEUP_GPIO_HIGH));

    ESP_LOGI(TAG, "Entrando en sueno profundo; GPIO4 y GPIO5 pueden despertar el equipo.");
    esp_deep_sleep_start();
}

void horometer_app_run(void)
{
    configure_inputs();
    const uint64_t wake_mask = report_wakeup();
    const uint8_t current_state =
        (uint8_t)(gpio_get_level(HORALINK_PIN_CH1_STATE) != 0);
    const int64_t now_ms = get_rtc_time_ms();

    ESP_LOGI(TAG, "Estado actual del canal 1 (GPIO6): %u", current_state);

    ESP_ERROR_CHECK(horometer_storage_init());
    horometer_record_t record = {0};
    bool record_found = false;
    ESP_ERROR_CHECK(horometer_storage_load(&record, &record_found));

    if (!record_found) {
        initialize_record(&record, current_state, now_ms);
    } else {
        if ((record.last_state != 0U) &&
            (now_ms < record.session_start_ms)) {
            ESP_LOGW(TAG,
                     "El reloj RTC se reinicio durante una sesion activa; "
                     "la sesion continuara desde este arranque.");
            record.session_start_ms = now_ms;
            ESP_ERROR_CHECK(horometer_storage_save(&record));
        }
        update_channel_state(&record, current_state, now_ms);
    }

    if ((wake_mask & (1ULL << HORALINK_PIN_BUTTON_WAKE)) != 0) {
        char device_name[HORALINK_DEVICE_NAME_MAX_BYTES + 1U] = {0};
        ESP_ERROR_CHECK(device_config_load_name(device_name,
                                                 sizeof(device_name)));
        log_current_summary(&record, now_ms);
        run_button_advertising(&record, device_name);
    }

    /* A HIGH level is the wake condition. Sleeping before it returns LOW
     * would immediately wake and reboot the ESP32-C3 again. */
    wait_until_wakeup_inputs_are_low();
    enter_deep_sleep();
}
