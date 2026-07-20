#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

typedef struct {
    uint8_t last_state;
    int64_t session_start_ms;
    uint64_t accumulated_ms;
    uint32_t transition_count;
} horometer_record_t;

/** Initialize the default NVS partition. */
esp_err_t horometer_storage_init(void);

/**
 * Load channel 1 data. `found` is false when no valid record exists yet.
 */
esp_err_t horometer_storage_load(horometer_record_t *record, bool *found);

/** Store the complete channel 1 record as one versioned NVS blob. */
esp_err_t horometer_storage_save(const horometer_record_t *record);
