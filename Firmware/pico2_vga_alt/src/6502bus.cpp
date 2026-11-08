#include "6502bus.h"

void irq_handler(uint gpio, uint32_t events) {
    // Read all GPIOs at once
    uint32_t gpio_state = sio_hw->gpio_in;    
    uint8_t data = 0;
    // GPIO4 -> bit7
    data |= ((gpio_state >> 4) & 1) << 7;
    // GPIO5 -> bit6
    data |= ((gpio_state >> 5) & 1) << 6;
    // GPIO6 -> bit5
    data |= ((gpio_state >> 6) & 1) << 5;
    // GPIO7 -> bit4
    data |= ((gpio_state >> 7) & 1) << 4;
    // GPIO8 -> bit3
    data |= ((gpio_state >> 8) & 1) << 3;
    // GPIO9 -> bit2
    data |= ((gpio_state >> 9) & 1) << 2;
    // GPIO10 -> bit1
    data |= ((gpio_state >> 10) & 1) << 1;
    // GPIO11 -> bit0
    data |= ((gpio_state >> 11) & 1);   
    termial_push_to_buffer(data); 
    //terminal_buffer[terminal_buffer_head] = data;
    //terminal_buffer_head = (terminal_buffer_head + 1) % TERMINAL_BUFFER_SIZE;
}

void setup6502bus() {
    // Configure data pins
    for (int i = 0; i < 12; i++) {
        gpio_init(i);
        gpio_set_dir(i, false); // input
    }


    // Configure interrupt pin
    gpio_init(INTERRUPT_PIN);
    gpio_set_dir(INTERRUPT_PIN, false);
    gpio_set_irq_enabled_with_callback(INTERRUPT_PIN, GPIO_IRQ_EDGE_FALL, true, &irq_handler);    
}