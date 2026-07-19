#include <stdio.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_sleep.h"
#include "esp_log.h"

#include "app/button/isr_button.h"
//--------------------

static const char* TAG = "MAIN";

void app_main(void)
{
    init_isr_button();

    uint8_t counter = 0;
    TickType_t time_minute =  pdMS_TO_TICKS(60000);

    while(1){
        esp_light_sleep_start();
        //vTaskDelay(time_minute);
        counter++;
        //ESP_LOGI(TAG,"Han Pasado %d %s",counter,counter==1?"minuto":"minutos");
    }
}

