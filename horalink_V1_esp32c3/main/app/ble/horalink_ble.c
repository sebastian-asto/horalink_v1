#include "app/ble/horalink_ble.h"

#include <string.h>

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "host/ble_gap.h"
#include "host/ble_hs.h"
#include "host/ble_hs_id.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"

#define HORALINK_ADV_LENGTH 31U
#define HORALINK_DATA_LENGTH 10U
#define HORALINK_DATA_VERSION 1U
#define HORALINK_FLAG_CHANNEL_RUNNING (1U << 0)
#define HORALINK_FLAG_BATTERY_VALID   (1U << 1)

static const char *TAG = "HORALINK_BLE";
static SemaphoreHandle_t sync_sem;
static esp_err_t sync_result;
static uint8_t advertising_data[HORALINK_ADV_LENGTH];
static bool nimble_started;
static uint8_t own_addr_type;

/* UUID 7e57d004-2b97-0e7a-e511-9b9941e4a8f2 in BLE little-endian order. */
static const uint8_t service_uuid_le[16] = {
    0xf2, 0xa8, 0xe4, 0x41, 0x99, 0x9b, 0x11, 0xe5,
    0x7a, 0x0e, 0x97, 0x2b, 0x04, 0xd0, 0x57, 0x7e,
};

static void build_advertising_data(const horalink_ble_snapshot_t *snapshot)
{
    uint8_t *cursor = advertising_data;
    *cursor++ = 0x02;
    *cursor++ = BLE_HS_ADV_TYPE_FLAGS;
    *cursor++ = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;

    *cursor++ = 0x1b; /* type + 128-bit UUID + 10-byte payload */
    *cursor++ = BLE_HS_ADV_TYPE_SVC_DATA_UUID128;
    memcpy(cursor, service_uuid_le, sizeof(service_uuid_le));
    cursor += sizeof(service_uuid_le);

    *cursor++ = HORALINK_DATA_VERSION;
    *cursor++ = (snapshot->channel_running ? HORALINK_FLAG_CHANNEL_RUNNING : 0U) |
                (snapshot->battery_valid ? HORALINK_FLAG_BATTERY_VALID : 0U);
    *cursor++ = snapshot->battery_valid ? snapshot->battery_percent : 0xffU;
    *cursor++ = (uint8_t)snapshot->battery_mv;
    *cursor++ = (uint8_t)(snapshot->battery_mv >> 8U);

    uint64_t seconds = snapshot->accumulated_seconds;
    for (size_t index = 0; index < 5U; ++index) {
        *cursor++ = (uint8_t)(seconds >> (index * 8U));
    }
}

static int gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;
    if (event->type == BLE_GAP_EVENT_ADV_COMPLETE) {
        ESP_LOGI(TAG, "Publicidad BLE finalizada (razon=%d).",
                 event->adv_complete.reason);
    }
    return 0;
}

static void on_reset(int reason)
{
    ESP_LOGE(TAG, "NimBLE reiniciado (razon=%d).", reason);
}

static void on_sync(void)
{
    int rc = ble_hs_util_ensure_addr(0);
    if (rc == 0) {
        rc = ble_hs_id_infer_auto(0, &own_addr_type);
    }
    if (rc == 0) {
        rc = ble_gap_adv_set_data(advertising_data,
                                  sizeof(advertising_data));
    }
    if (rc == 0) {
        const struct ble_gap_adv_params params = {
            .conn_mode = BLE_GAP_CONN_MODE_NON,
            .disc_mode = BLE_GAP_DISC_MODE_GEN,
            .itvl_min = 160, /* 100 ms */
            .itvl_max = 192, /* 120 ms */
        };
        rc = ble_gap_adv_start(own_addr_type,
                               NULL,
                               BLE_HS_FOREVER,
                               &params,
                               gap_event,
                               NULL);
    }

    sync_result = (rc == 0) ? ESP_OK : ESP_FAIL;
    if (rc != 0) {
        ESP_LOGE(TAG, "No se pudo iniciar la publicidad (rc=%d).", rc);
    }
    xSemaphoreGive(sync_sem);
}

static void host_task(void *param)
{
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

esp_err_t horalink_ble_start(const horalink_ble_snapshot_t *snapshot)
{
    if (snapshot == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    if (nimble_started) {
        return ESP_ERR_INVALID_STATE;
    }

    build_advertising_data(snapshot);
    sync_sem = xSemaphoreCreateBinary();
    if (sync_sem == NULL) {
        return ESP_ERR_NO_MEM;
    }

    esp_err_t err = nimble_port_init();
    if (err != ESP_OK) {
        vSemaphoreDelete(sync_sem);
        sync_sem = NULL;
        return err;
    }

    nimble_started = true;
    sync_result = ESP_FAIL;
    ble_hs_cfg.reset_cb = on_reset;
    ble_hs_cfg.sync_cb = on_sync;
    nimble_port_freertos_init(host_task);

    if (xSemaphoreTake(sync_sem, pdMS_TO_TICKS(2000)) != pdTRUE) {
        ESP_LOGE(TAG, "Tiempo agotado esperando la sincronizacion BLE.");
        horalink_ble_stop();
        return ESP_ERR_TIMEOUT;
    }
    if (sync_result != ESP_OK) {
        horalink_ble_stop();
        return sync_result;
    }

    ESP_LOGI(TAG,
             "Publicidad no conectable activa por 10 s; UUID %s.",
             HORALINK_BLE_SERVICE_UUID);
    return ESP_OK;
}

void horalink_ble_stop(void)
{
    if (!nimble_started) {
        return;
    }

    if (ble_gap_adv_active()) {
        const int rc = ble_gap_adv_stop();
        if (rc != 0) {
            ESP_LOGW(TAG, "No se pudo detener advertising (rc=%d).", rc);
        }
    }
    const int stop_rc = nimble_port_stop();
    if (stop_rc != 0) {
        ESP_LOGW(TAG, "No se pudo detener NimBLE (rc=%d).", stop_rc);
    }
    const esp_err_t deinit_err = nimble_port_deinit();
    if (deinit_err != ESP_OK) {
        ESP_LOGW(TAG, "No se pudo liberar NimBLE: %s",
                 esp_err_to_name(deinit_err));
    }

    nimble_started = false;
    if (sync_sem != NULL) {
        vSemaphoreDelete(sync_sem);
        sync_sem = NULL;
    }
}
