# == DO NOT EDIT THE FOLLOWING LINES for the Raspberry Pi Pico VS Code Extension to work ==
if(WIN32)
    set(USERHOME $ENV{USERPROFILE})
else()
    set(USERHOME $ENV{HOME})
endif()
set(sdkVersion 2.2.0)
set(toolchainVersion 14_2_Rel1)
set(picotoolVersion 2.2.0-a4)
set(picoVscode ${USERHOME}/.pico-sdk/cmake/pico-vscode.cmake)
if (EXISTS ${picoVscode})
    include(${picoVscode})
endif()
# ====================================================================================
set(PICO_BOARD pico2 CACHE STRING "Board type")

# cmake version
cmake_minimum_required(VERSION 3.13)

# include the sdk.cmake file
include(pico_sdk_import.cmake)

# give the project a name (anything you want)
project(VGA_TEXT_MODE)

# initialize the sdk
pico_sdk_init()

add_executable(VGA_text_mode)

# must match with pio filename and executable name from above
pico_generate_pio_header(VGA_text_mode ${CMAKE_CURRENT_LIST_DIR}/hsync.pio)
pico_generate_pio_header(VGA_text_mode ${CMAKE_CURRENT_LIST_DIR}/vsync.pio)
pico_generate_pio_header(VGA_text_mode ${CMAKE_CURRENT_LIST_DIR}/rgb.pio)

# must match with executable name and source file names
target_sources(VGA_text_mode PRIVATE vga_text_mode.c vga16_graphics_v2.c)

# must match with executable name
target_link_libraries(VGA_text_mode PRIVATE pico_stdlib pico_bootsel_via_double_reset hardware_pio hardware_dma hardware_adc hardware_irq hardware_clocks)

# must match with executable name
pico_add_extra_outputs(VGA_text_mode)
