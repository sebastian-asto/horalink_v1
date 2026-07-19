#include <stdint.h>
#include <inttypes.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "driver/gpio.h"
#include "esp_sleep.h"
#include "esp_log.h"

#include "app/button/isr_button.h"

//----------------------------------

#define PIN_BUTTON  GPIO_NUM_5

static const char* TAG = "ISR_BUTTON";
static QueueSetHandle_t button_Queue = NULL;

//-----declarando funciones----
static void button_ISR_handler(void *arg);
static void button_Task_Funtion(void *arg);
//---------------

void init_isr_button(void) {

    //opcion -> GPIO_INTR_POSEDGE  

    //inicializando la cola 
    button_Queue = xQueueCreate(1,sizeof(uint32_t));
    //creando la tarea
    xTaskCreate(button_Task_Funtion, "TASK_BUTTON_ISR", 2048, NULL, 10, NULL);

    gpio_config_t button = {
        .pin_bit_mask = 1ULL << PIN_BUTTON,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_POSEDGE
    };

    //gpio_config(&button);
    ESP_LOGI(
        TAG,"Button ISR Configured %s",
        (gpio_config(&button)==ESP_OK?"Successfully":"Incorrectly")
    );

    //Configurar el pin y el nivel de despertar
    gpio_wakeup_enable(PIN_BUTTON,GPIO_INTR_HIGH_LEVEL);

    //Habilitar globalmente el wake-up por GPIO
    esp_sleep_enable_gpio_wakeup();

    //instalando el servicio general de interrupciones
    gpio_install_isr_service(0);
    
    //asociando el pin button con la funcion ISR
 
    gpio_isr_handler_add(
        PIN_BUTTON,
        button_ISR_handler,
        (void*)PIN_BUTTON
    );
}

//funcion de la ISR 

static void IRAM_ATTR button_ISR_handler(void *arg)
{
    // Recupera el número de GPIO enviado al registrar la ISR.
    uint32_t pin_number = (uint32_t)arg;

    // Inicialmente suponemos que ninguna tarea de mayor prioridad
    // será despertada.
    BaseType_t task_woken = pdFALSE;

    // Envía el número del GPIO a la cola.
    // Si esto desbloquea una tarea de mayor prioridad,
    // task_woken será cambiado a pdTRUE.
    xQueueSendFromISR(
        button_Queue,
        &pin_number,
        &task_woken
    );

    // Si task_woken es pdTRUE, solicita que al terminar la ISR
    // se ejecute inmediatamente la tarea de mayor prioridad.
    portYIELD_FROM_ISR(task_woken);
}

//tarea creada

static void button_Task_Funtion(void *arg)
{
    uint32_t pin_number;

    while(1){
        ESP_LOGI(TAG,"tarea bloqueada");
        if(xQueueReceive(button_Queue,&pin_number,portMAX_DELAY) == pdTRUE){
            ESP_LOGI(TAG,"Interrupción recibida del GPIO %"PRIu32, pin_number);
        }
    }
}


