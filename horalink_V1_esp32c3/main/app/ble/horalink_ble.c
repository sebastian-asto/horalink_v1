#include "app/ble/horalink_ble.h"

#include <string.h>

#include "app/storage/device_config_storage.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "host/ble_att.h"
#include "host/ble_gap.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "host/ble_hs_id.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "os/os_mbuf.h"

#define HORALINK_ADV_LENGTH 31U
#define HORALINK_DATA_VERSION 1U
#define HORALINK_FLAG_CHANNEL_RUNNING (1U << 0)
#define HORALINK_FLAG_BATTERY_VALID   (1U << 1)
#define HORALINK_RESET_COMMAND        0xa5U

static const char *TAG = "HORALINK_BLE";
static SemaphoreHandle_t sync_sem;
static esp_err_t sync_result;
static uint8_t advertising_data[HORALINK_ADV_LENGTH];
static bool nimble_started;
static bool keep_advertising;
static volatile bool connected;
static uint16_t connection_handle = BLE_HS_CONN_HANDLE_NONE;
static uint8_t own_addr_type;

static portMUX_TYPE state_lock = portMUX_INITIALIZER_UNLOCKED;
static char current_name[HORALINK_DEVICE_NAME_MAX_BYTES + 1U];
static char pending_name[HORALINK_DEVICE_NAME_MAX_BYTES + 1U];
static bool name_update_pending;
static bool reset_request_pending;
static volatile horalink_reset_status_t reset_status = HORALINK_RESET_IDLE;

static const ble_uuid128_t service_uuid = BLE_UUID128_INIT(
    0xf2, 0xa8, 0xe4, 0x41, 0x99, 0x9b, 0x11, 0xe5,
    0x7a, 0x0e, 0x97, 0x2b, 0x04, 0xd0, 0x57, 0x7e);
static const ble_uuid128_t name_uuid = BLE_UUID128_INIT(
    0xf2, 0xa8, 0xe4, 0x41, 0x99, 0x9b, 0x11, 0xe5,
    0x7a, 0x0e, 0x97, 0x2b, 0x05, 0xd0, 0x57, 0x7e);
static const ble_uuid128_t reset_uuid = BLE_UUID128_INIT(
    0xf2, 0xa8, 0xe4, 0x41, 0x99, 0x9b, 0x11, 0xe5,
    0x7a, 0x0e, 0x97, 0x2b, 0x06, 0xd0, 0x57, 0x7e);

static int name_access(uint16_t conn_handle, uint16_t attr_handle,
                       struct ble_gatt_access_ctxt *ctxt, void *arg);
static int reset_access(uint16_t conn_handle, uint16_t attr_handle,
                        struct ble_gatt_access_ctxt *ctxt, void *arg);

static const struct ble_gatt_svc_def gatt_services[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &service_uuid.u,
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                .uuid = &name_uuid.u,
                .access_cb = name_access,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_WRITE,
            },
            {
                .uuid = &reset_uuid.u,
                .access_cb = reset_access,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_WRITE,
            },
            {0},
        },
    },
    {0},
};

static void build_advertising_data(const horalink_ble_snapshot_t *snapshot)
{
    static const uint8_t service_uuid_le[16] = {
        0xf2, 0xa8, 0xe4, 0x41, 0x99, 0x9b, 0x11, 0xe5,
        0x7a, 0x0e, 0x97, 0x2b, 0x04, 0xd0, 0x57, 0x7e,
    };

    uint8_t *cursor = advertising_data;
    *cursor++ = 0x02;
    *cursor++ = BLE_HS_ADV_TYPE_FLAGS;
    *cursor++ = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    *cursor++ = 0x1b;
    *cursor++ = BLE_HS_ADV_TYPE_SVC_DATA_UUID128;
    memcpy(cursor, service_uuid_le, sizeof(service_uuid_le));
    cursor += sizeof(service_uuid_le);

    *cursor++ = HORALINK_DATA_VERSION;
    *cursor++ = (snapshot->channel_running ? HORALINK_FLAG_CHANNEL_RUNNING : 0U) |
                (snapshot->battery_valid ? HORALINK_FLAG_BATTERY_VALID : 0U);
    *cursor++ = snapshot->battery_valid ? snapshot->battery_percent : 0xffU;
    *cursor++ = (uint8_t)snapshot->battery_mv;
    *cursor++ = (uint8_t)(snapshot->battery_mv >> 8U);

    for (size_t index = 0; index < 5U; ++index) {
        *cursor++ = (uint8_t)(snapshot->accumulated_seconds >> (index * 8U));
    }
}

static int append_value(struct os_mbuf *om, const void *data, size_t length)
{
    return os_mbuf_append(om, data, length) == 0
        ? 0
        : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static int name_access(uint16_t conn_handle_arg, uint16_t attr_handle,
                       struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle_arg;
    (void)attr_handle;
    (void)arg;

    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
        char name_copy[sizeof(current_name)];
        taskENTER_CRITICAL(&state_lock);
        strlcpy(name_copy, current_name, sizeof(name_copy));
        taskEXIT_CRITICAL(&state_lock);
        return append_value(ctxt->om, name_copy, strlen(name_copy));
    }

    if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
        const uint16_t length = OS_MBUF_PKTLEN(ctxt->om);
        if ((length == 0U) || (length > HORALINK_DEVICE_NAME_MAX_BYTES)) {
            return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        }

        char received[sizeof(current_name)] = {0};
        uint16_t copied = 0;
        if (ble_hs_mbuf_to_flat(ctxt->om, received, length, &copied) != 0) {
            return BLE_ATT_ERR_UNLIKELY;
        }
        received[copied] = '\0';

        taskENTER_CRITICAL(&state_lock);
        strlcpy(current_name, received, sizeof(current_name));
        strlcpy(pending_name, received, sizeof(pending_name));
        name_update_pending = true;
        taskEXIT_CRITICAL(&state_lock);
        ESP_LOGI(TAG, "Nuevo nombre recibido por GATT: %s", received);
        return 0;
    }

    return BLE_ATT_ERR_UNLIKELY;
}

static int reset_access(uint16_t conn_handle_arg, uint16_t attr_handle,
                        struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle_arg;
    (void)attr_handle;
    (void)arg;

    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
        const uint8_t status = (uint8_t)reset_status;
        return append_value(ctxt->om, &status, sizeof(status));
    }

    if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
        uint8_t command = 0;
        uint16_t copied = 0;
        if ((OS_MBUF_PKTLEN(ctxt->om) != 1U) ||
            (ble_hs_mbuf_to_flat(ctxt->om, &command, sizeof(command),
                                 &copied) != 0) ||
            (command != HORALINK_RESET_COMMAND)) {
            return BLE_ATT_ERR_VALUE_NOT_ALLOWED;
        }

        taskENTER_CRITICAL(&state_lock);
        reset_request_pending = true;
        reset_status = HORALINK_RESET_WAITING_PHYSICAL_CONFIRMATION;
        taskEXIT_CRITICAL(&state_lock);
        ESP_LOGW(TAG, "Reinicio solicitado; esperando segunda pulsacion fisica.");
        return 0;
    }

    return BLE_ATT_ERR_UNLIKELY;
}

static int start_advertising(void);

static int gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            connection_handle = event->connect.conn_handle;
            connected = true;
            ESP_LOGI(TAG, "Aplicacion conectada; sesion de configuracion activa.");
        } else if (keep_advertising) {
            start_advertising();
        }
        return 0;

    case BLE_GAP_EVENT_DISCONNECT:
        connected = false;
        connection_handle = BLE_HS_CONN_HANDLE_NONE;
        ESP_LOGI(TAG, "Aplicacion desconectada (razon=%d).",
                 event->disconnect.reason);
        if (keep_advertising) {
            start_advertising();
        }
        return 0;

    case BLE_GAP_EVENT_ADV_COMPLETE:
        if (keep_advertising && !connected) {
            start_advertising();
        }
        return 0;

    default:
        return 0;
    }
}

static int start_advertising(void)
{
    int rc = ble_gap_adv_set_data(advertising_data, sizeof(advertising_data));
    if (rc != 0) {
        return rc;
    }

    const struct ble_gap_adv_params params = {
        .conn_mode = BLE_GAP_CONN_MODE_UND,
        .disc_mode = BLE_GAP_DISC_MODE_GEN,
        .itvl_min = 160,
        .itvl_max = 192,
    };
    return ble_gap_adv_start(own_addr_type, NULL, BLE_HS_FOREVER,
                             &params, gap_event, NULL);
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
        rc = start_advertising();
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

esp_err_t horalink_ble_start(const horalink_ble_snapshot_t *snapshot,
                             const char *device_name)
{
    if ((snapshot == NULL) || (device_name == NULL)) {
        return ESP_ERR_INVALID_ARG;
    }
    if (nimble_started) {
        return ESP_ERR_INVALID_STATE;
    }

    build_advertising_data(snapshot);
    strlcpy(current_name, device_name, sizeof(current_name));
    name_update_pending = false;
    reset_request_pending = false;
    reset_status = HORALINK_RESET_IDLE;
    connected = false;
    keep_advertising = true;

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

    int rc = ble_gatts_count_cfg(gatt_services);
    if (rc == 0) {
        rc = ble_gatts_add_svcs(gatt_services);
    }
    if (rc != 0) {
        ESP_LOGE(TAG, "No se pudo registrar el servicio GATT (rc=%d).", rc);
        horalink_ble_stop();
        return ESP_FAIL;
    }

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

    ESP_LOGI(TAG, "Publicidad conectable activa por 10 s; nombre=%s.",
             current_name);
    return ESP_OK;
}

bool horalink_ble_is_connected(void)
{
    return connected;
}

bool horalink_ble_take_name_update(char *name, size_t capacity)
{
    if ((name == NULL) || (capacity == 0U)) {
        return false;
    }

    bool available;
    taskENTER_CRITICAL(&state_lock);
    available = name_update_pending;
    if (available) {
        strlcpy(name, pending_name, capacity);
        name_update_pending = false;
    }
    taskEXIT_CRITICAL(&state_lock);
    return available;
}

bool horalink_ble_take_reset_request(void)
{
    bool requested;
    taskENTER_CRITICAL(&state_lock);
    requested = reset_request_pending;
    reset_request_pending = false;
    taskEXIT_CRITICAL(&state_lock);
    return requested;
}

void horalink_ble_set_reset_status(horalink_reset_status_t status)
{
    reset_status = status;
}

void horalink_ble_stop(void)
{
    if (!nimble_started) {
        return;
    }

    keep_advertising = false;
    if (ble_gap_adv_active()) {
        const int rc = ble_gap_adv_stop();
        if (rc != 0) {
            ESP_LOGW(TAG, "No se pudo detener advertising (rc=%d).", rc);
        }
    }
    if (connected && (connection_handle != BLE_HS_CONN_HANDLE_NONE)) {
        ble_gap_terminate(connection_handle, BLE_ERR_REM_USER_CONN_TERM);
        vTaskDelay(pdMS_TO_TICKS(50));
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
    connected = false;
    connection_handle = BLE_HS_CONN_HANDLE_NONE;
    if (sync_sem != NULL) {
        vSemaphoreDelete(sync_sem);
        sync_sem = NULL;
    }
}
