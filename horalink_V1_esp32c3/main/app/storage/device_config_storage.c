#include "app/storage/device_config_storage.h"

#include <string.h>

#include "esp_check.h"
#include "esp_log.h"
#include "nvs.h"

#define DEVICE_CONFIG_NAMESPACE "device_cfg"
#define DEVICE_NAME_KEY         "name"

static const char *TAG = "DEVICE_CONFIG";

esp_err_t device_config_load_name(char *name, size_t capacity)
{
    ESP_RETURN_ON_FALSE(name != NULL, ESP_ERR_INVALID_ARG, TAG,
                        "name es NULL");
    ESP_RETURN_ON_FALSE(capacity > strlen(HORALINK_DEFAULT_DEVICE_NAME),
                        ESP_ERR_INVALID_SIZE, TAG, "buffer insuficiente");

    strlcpy(name, HORALINK_DEFAULT_DEVICE_NAME, capacity);

    nvs_handle_t handle;
    esp_err_t err = nvs_open(DEVICE_CONFIG_NAMESPACE, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    ESP_RETURN_ON_ERROR(err, TAG, "No se pudo abrir configuracion");

    size_t required = capacity;
    err = nvs_get_str(handle, DEVICE_NAME_KEY, name, &required);
    nvs_close(handle);

    if (err == ESP_ERR_NVS_NOT_FOUND) {
        strlcpy(name, HORALINK_DEFAULT_DEVICE_NAME, capacity);
        return ESP_OK;
    }
    if ((err == ESP_ERR_NVS_INVALID_LENGTH) || (required > capacity)) {
        ESP_LOGW(TAG, "Nombre guardado demasiado largo; se usara el predeterminado");
        strlcpy(name, HORALINK_DEFAULT_DEVICE_NAME, capacity);
        return ESP_OK;
    }
    ESP_RETURN_ON_ERROR(err, TAG, "No se pudo leer el nombre");
    return ESP_OK;
}

esp_err_t device_config_save_name(const char *name)
{
    ESP_RETURN_ON_FALSE(name != NULL, ESP_ERR_INVALID_ARG, TAG,
                        "name es NULL");
    const size_t length = strnlen(name, HORALINK_DEVICE_NAME_MAX_BYTES + 1U);
    ESP_RETURN_ON_FALSE((length > 0U) &&
                        (length <= HORALINK_DEVICE_NAME_MAX_BYTES),
                        ESP_ERR_INVALID_SIZE, TAG, "Longitud de nombre invalida");

    nvs_handle_t handle;
    ESP_RETURN_ON_ERROR(
        nvs_open(DEVICE_CONFIG_NAMESPACE, NVS_READWRITE, &handle),
        TAG,
        "No se pudo abrir configuracion para escritura");

    esp_err_t err = nvs_set_str(handle, DEVICE_NAME_KEY, name);
    if (err == ESP_OK) {
        err = nvs_commit(handle);
    }
    nvs_close(handle);
    ESP_RETURN_ON_ERROR(err, TAG, "No se pudo guardar el nombre");

    ESP_LOGI(TAG, "Nombre persistente actualizado: %s", name);
    return ESP_OK;
}
