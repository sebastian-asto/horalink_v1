# The following five lines of boilerplate have to be in your project's
# CMakeLists in this exact order for cmake to work correctly
cmake_minimum_required(VERSION 3.16)

# HoraLink V1 is designed specifically for the ESP32-C3. Keeping the target
# here makes command-line and container builds reproducible.
set(IDF_TARGET "esp32c3")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(horalink_V1_esp32c3)
