#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

#define HORALINK_BLE_ADVERTISING_TIME_MS 10000U
#define HORALINK_BLE_CONNECTED_TIME_MS   60000U
#define HORALINK_RESET_CONFIRM_TIME_MS   15000U

#define HORALINK_BLE_SERVICE_UUID \
    "7e57d004-2b97-0e7a-e511-9b9941e4a8f2"
#define HORALINK_BLE_NAME_UUID \
    "7e57d005-2b97-0e7a-e511-9b9941e4a8f2"
#define HORALINK_BLE_RESET_UUID \
    "7e57d006-2b97-0e7a-e511-9b9941e4a8f2"

typedef enum {
    HORALINK_RESET_IDLE = 0,
    HORALINK_RESET_WAITING_PHYSICAL_CONFIRMATION = 1,
    HORALINK_RESET_COMPLETED = 2,
    HORALINK_RESET_EXPIRED = 3,
} horalink_reset_status_t;

typedef struct {
    uint64_t accumulated_seconds;
    uint16_t battery_mv;
    uint8_t battery_percent;
    bool battery_valid;
    bool channel_running;
} horalink_ble_snapshot_t;

/** Start connectable advertising and expose the temporary GATT service. */
esp_err_t horalink_ble_start(const horalink_ble_snapshot_t *snapshot,
                             const char *device_name);

bool horalink_ble_is_connected(void);

/** Consume a friendly-name update received through GATT. */
bool horalink_ble_take_name_update(char *name, size_t capacity);

/** Consume a reset request received through GATT. */
bool horalink_ble_take_reset_request(void);

/** Update the value read from the reset-status GATT characteristic. */
void horalink_ble_set_reset_status(horalink_reset_status_t status);

/** Stop advertising/connections and release NimBLE before deep sleep. */
void horalink_ble_stop(void);
