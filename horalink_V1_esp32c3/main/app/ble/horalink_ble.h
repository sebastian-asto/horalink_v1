#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#define HORALINK_BLE_ADVERTISING_TIME_MS 10000U
#define HORALINK_BLE_SERVICE_UUID "7e57d004-2b97-0e7a-e511-9b9941e4a8f2"

typedef struct {
    uint64_t accumulated_seconds;
    uint16_t battery_mv;
    uint8_t battery_percent;
    bool battery_valid;
    bool channel_running;
} horalink_ble_snapshot_t;

/** Start non-connectable legacy advertising with one HoraLink snapshot. */
esp_err_t horalink_ble_start(const horalink_ble_snapshot_t *snapshot);

/** Stop advertising and release the NimBLE stack before deep sleep. */
void horalink_ble_stop(void);
