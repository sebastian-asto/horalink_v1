#pragma once

/**
 * @brief Run one wake-up cycle and return the device to deep sleep.
 *
 * Deep sleep resets the CPU, so this function is entered again through
 * app_main() after every GPIO wake-up.
 */
void horometer_app_run(void);
