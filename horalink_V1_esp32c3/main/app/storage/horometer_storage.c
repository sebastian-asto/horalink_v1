#include "app/storage/horometer_storage.h"

#include <stddef.h>
#include <string.h>

#include "esp_check.h"
#include "esp_log.h"
#include "nvs.h"
#include "nvs_flash.h"

#define HOROMETER_NVS_NAMESPACE "horometer"
#define HOROMETER_NVS_KEY       "channel_1"
#define HOROMETER_RECORD_MAGIC  0x484C4E4BU /* "HLNK" */
#define HOROMETER_RECORD_VERSION 1U

typedef struct {
    uint32_t magic;
    uint16_t version;
    uint8_t last_state;
    uint8_t reserved_0;
    int64_t session_start_ms;
    uint64_t accumulated_ms;
    uint32_t transition_count;
    uint32_t reserved_1;
} stored_record_t;

_Static_assert(sizeof(stored_record_t) == 32, "Unexpected NVS record layout");

static const char *TAG = "HOROMETER_NVS";

esp_err_t horometer_storage_init(void)
{
    esp_err_t err = nvs_flash_init();

    if ((err == ESP_ERR_NVS_NO_FREE_PAGES) ||
        (err == ESP_ERR_NVS_NEW_VERSION_FOUND)) {
        ESP_LOGW(TAG, "NVS necesita reinicializacion: %s", esp_err_to_name(err));
        ESP_RETURN_ON_ERROR(nvs_flash_erase(), TAG, "No se pudo borrar NVS");
        err = nvs_flash_init();
    }

    return err;
}

esp_err_t horometer_storage_load(horometer_record_t *record, bool *found)
{
    ESP_RETURN_ON_FALSE(record != NULL, ESP_ERR_INVALID_ARG, TAG,
                        "record es NULL");
    ESP_RETURN_ON_FALSE(found != NULL, ESP_ERR_INVALID_ARG, TAG,
                        "found es NULL");

    *found = false;
    nvs_handle_t handle;
    esp_err_t err = nvs_open(HOROMETER_NVS_NAMESPACE, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    ESP_RETURN_ON_ERROR(err, TAG, "No se pudo abrir NVS");

    stored_record_t stored = {0};
    size_t stored_size = sizeof(stored);
    err = nvs_get_blob(handle, HOROMETER_NVS_KEY, &stored, &stored_size);
    nvs_close(handle);

    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    ESP_RETURN_ON_ERROR(err, TAG, "No se pudo leer el registro");

    if ((stored_size != sizeof(stored)) ||
        (stored.magic != HOROMETER_RECORD_MAGIC) ||
        (stored.version != HOROMETER_RECORD_VERSION) ||
        (stored.last_state > 1U)) {
        ESP_LOGW(TAG, "Registro ausente, incompatible o invalido; se inicializara nuevamente");
        return ESP_OK;
    }

    record->last_state = stored.last_state;
    record->session_start_ms = stored.session_start_ms;
    record->accumulated_ms = stored.accumulated_ms;
    record->transition_count = stored.transition_count;
    *found = true;
    return ESP_OK;
}

esp_err_t horometer_storage_save(const horometer_record_t *record)
{
    ESP_RETURN_ON_FALSE(record != NULL, ESP_ERR_INVALID_ARG, TAG,
                        "record es NULL");
    ESP_RETURN_ON_FALSE(record->last_state <= 1U, ESP_ERR_INVALID_ARG, TAG,
                        "Estado de canal invalido");

    const stored_record_t stored = {
        .magic = HOROMETER_RECORD_MAGIC,
        .version = HOROMETER_RECORD_VERSION,
        .last_state = record->last_state,
        .session_start_ms = record->session_start_ms,
        .accumulated_ms = record->accumulated_ms,
        .transition_count = record->transition_count,
    };

    nvs_handle_t handle;
    ESP_RETURN_ON_ERROR(
        nvs_open(HOROMETER_NVS_NAMESPACE, NVS_READWRITE, &handle),
        TAG,
        "No se pudo abrir NVS para escritura");

    esp_err_t err = nvs_set_blob(handle, HOROMETER_NVS_KEY, &stored, sizeof(stored));
    if (err == ESP_OK) {
        err = nvs_commit(handle);
    }
    nvs_close(handle);

    ESP_RETURN_ON_ERROR(err, TAG, "No se pudo guardar el registro");
    return ESP_OK;
}
