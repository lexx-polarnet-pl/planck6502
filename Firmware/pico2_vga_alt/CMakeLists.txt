# == DO NOT EDIT THE FOLLOWING LINES for the Raspberry Pi Pico VS Code Extension to work ==
if(WIN32)
    set(USERHOME $ENV{USERPROFILE})
else()
    set(USERHOME $ENV{HOME})
endif()
set(sdkVersion 2.3.1)
set(toolchainVersion 15_2_Rel1)
set(picotoolVersion 2.3.1)
set(picoVscode ${USERHOME}/.pico-sdk/cmake/pico-vscode.cmake)
if (EXISTS ${picoVscode})
    include(${picoVscode})
endif()
# ====================================================================================
set(PICO_BOARD pico2 CACHE STRING "Board type")

cmake_minimum_required(VERSION 3.12)

include(pico_sdk_import.cmake)  # Include Pico SDK

if (NOT PICOVGA_PATH)
    set(PICOVGA_PATH "${CMAKE_CURRENT_LIST_DIR}/lib/picovga")
endif ()
include(picovga_import.cmake)

project(planckvga C CXX ASM)   # planckvga project

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

pico_sdk_init()                 # Initialize Pico SDK

add_compile_options(-Wall -Wno-format -Wno-unused-function -Wno-maybe-uninitialized)

# Create planckvga executable with specified source files
add_executable(planckvga
    src/main.cpp
)

# If monitor requires vsync uncomment to set the vsync pin
#add_compile_definitions(VGA_GPIO_VSYNC=9)

# Add PicoVGA to the target
add_picovga(planckvga)

# for vga_config.h include
target_include_directories(planckvga PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}/src
)

# Generate the uf2 output
pico_add_extra_outputs(planckvga)
