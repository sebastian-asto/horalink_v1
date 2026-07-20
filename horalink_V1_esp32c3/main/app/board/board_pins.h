#pragma once

#include "driver/gpio.h"

/* External 32.768 kHz crystal. These pins must not be used as GPIOs. */
#define HORALINK_PIN_XTAL_32K_P       GPIO_NUM_0
#define HORALINK_PIN_XTAL_32K_N       GPIO_NUM_1

/* Channel 1 and user-button signals. All three inputs are active high. */
#define HORALINK_PIN_CH1_WAKE_PULSE   GPIO_NUM_4
#define HORALINK_PIN_BUTTON_WAKE      GPIO_NUM_5
#define HORALINK_PIN_CH1_STATE        GPIO_NUM_6

/* MAX17048 fuel gauge (7-bit I2C address 0x36). */
#define HORALINK_PIN_I2C_SDA          GPIO_NUM_2
#define HORALINK_PIN_I2C_SCL          GPIO_NUM_8
#define HORALINK_MAX17048_ADDRESS     0x36U

#define HORALINK_WAKE_PIN_MASK \
    ((1ULL << HORALINK_PIN_CH1_WAKE_PULSE) | \
     (1ULL << HORALINK_PIN_BUTTON_WAKE))

#define HORALINK_INPUT_PIN_MASK \
    (HORALINK_WAKE_PIN_MASK | (1ULL << HORALINK_PIN_CH1_STATE))
