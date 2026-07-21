#pragma once

#include <stddef.h>

#include "esp_err.h"

#define HORALINK_DEVICE_NAME_MAX_BYTES 40U
#define HORALINK_DEFAULT_DEVICE_NAME "HoraLink"

/** Load the persistent friendly name, or the default when none exists. */
esp_err_t device_config_load_name(char *name, size_t capacity);

/** Save a non-empty UTF-8 friendly name. */
esp_err_t device_config_save_name(const char *name);
