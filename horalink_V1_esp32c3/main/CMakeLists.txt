idf_component_register(
    SRCS 
    "main.c"
    "app/ble/horalink_ble.c"
    "app/drivers/max17048/max17048.c"
    "app/horometer/horometer_app.c"
    "app/storage/device_config_storage.c"
    "app/storage/horometer_storage.c"
    INCLUDE_DIRS "."
    REQUIRES
    esp_driver_gpio
    esp_driver_i2c
    esp_hw_support
    bt
    freertos
    log
    nvs_flash)
    
