#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

typedef struct {
    bool valid;
    uint16_t voltage_mv;
    uint8_t state_of_charge_percent;
} max17048_measurement_t;

/** Read battery voltage and the MAX17048 ModelGauge SOC result. */
esp_err_t max17048_read(max17048_measurement_t *measurement);
