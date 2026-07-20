#include "app/drivers/max17048/max17048.h"

#include <stddef.h>

#include "app/board/board_pins.h"
#include "driver/i2c_master.h"
#include "esp_check.h"
#include "esp_log.h"

#define MAX17048_REG_VCELL 0x02U
#define MAX17048_REG_SOC   0x04U
#define MAX17048_I2C_HZ    100000U
#define MAX17048_TIMEOUT_MS 100

static const char *TAG = "MAX17048";

static esp_err_t read_register(i2c_master_dev_handle_t device,
                               uint8_t address,
                               uint16_t *value)
{
    uint8_t bytes[2] = {0};
    ESP_RETURN_ON_ERROR(
        i2c_master_transmit_receive(device,
                                    &address,
                                    sizeof(address),
                                    bytes,
                                    sizeof(bytes),
                                    MAX17048_TIMEOUT_MS),
        TAG,
        "No se pudo leer el registro 0x%02x",
        address);

    *value = ((uint16_t)bytes[0] << 8) | bytes[1];
    return ESP_OK;
}

esp_err_t max17048_read(max17048_measurement_t *measurement)
{
    ESP_RETURN_ON_FALSE(measurement != NULL, ESP_ERR_INVALID_ARG, TAG,
                        "measurement es NULL");
    *measurement = (max17048_measurement_t) {0};

    const i2c_master_bus_config_t bus_config = {
        .i2c_port = I2C_NUM_0,
        .sda_io_num = HORALINK_PIN_I2C_SDA,
        .scl_io_num = HORALINK_PIN_I2C_SCL,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = false,
    };

    i2c_master_bus_handle_t bus = NULL;
    esp_err_t err = i2c_new_master_bus(&bus_config, &bus);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "No se pudo iniciar I2C: %s", esp_err_to_name(err));
        return err;
    }

    const i2c_device_config_t device_config = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = HORALINK_MAX17048_ADDRESS,
        .scl_speed_hz = MAX17048_I2C_HZ,
    };

    i2c_master_dev_handle_t device = NULL;
    err = i2c_master_bus_add_device(bus, &device_config, &device);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "No se pudo registrar 0x36: %s", esp_err_to_name(err));
        i2c_del_master_bus(bus);
        return err;
    }

    uint16_t raw_vcell = 0;
    uint16_t raw_soc = 0;
    err = read_register(device, MAX17048_REG_VCELL, &raw_vcell);
    if (err == ESP_OK) {
        err = read_register(device, MAX17048_REG_SOC, &raw_soc);
    }

    const esp_err_t remove_err = i2c_master_bus_rm_device(device);
    const esp_err_t delete_err = i2c_del_master_bus(bus);
    if (err == ESP_OK) {
        err = (remove_err != ESP_OK) ? remove_err : delete_err;
    }
    if (err != ESP_OK) {
        return err;
    }

    /* VCELL is a 12-bit value with 1.25 mV per shifted LSB. SOC uses
     * 1/256 percent per LSB. Both registers arrive MSB first. */
    measurement->voltage_mv =
        (uint16_t)((((uint32_t)raw_vcell >> 4U) * 1250U + 500U) / 1000U);
    uint32_t rounded_soc = ((uint32_t)raw_soc + 128U) / 256U;
    if (rounded_soc > 100U) {
        rounded_soc = 100U;
    }
    measurement->state_of_charge_percent = (uint8_t)rounded_soc;
    measurement->valid = true;

    ESP_LOGI(TAG, "Bateria: %u%%, %u mV",
             measurement->state_of_charge_percent,
             measurement->voltage_mv);
    return ESP_OK;
}
