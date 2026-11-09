#include "6502bus.h"
uint row = 10;

void irq_handler(uint gpio, uint32_t events) {
    (void)gpio;
    (void)events;

    // Read all GPIOs at once
    uint32_t gpio_state = sio_hw->gpio_in;

    // 1. Adres: GPIO0-GPIO3 (4 bity) - odwrócenie kolejności
    uint8_t address = 0;              
    // GPIO3 -> bit0
    address |= ((gpio_state >> 3) & 1);
    // GPIO2 -> bit1
    address |= ((gpio_state >> 2) & 1) << 1;
    // GPIO1 -> bit2
    //address |= ((gpio_state >> 1) & 1) << 2;
    // GPIO0 -> bit3
    //address |= ((gpio_state) & 1) << 3;


    bool is_read = (gpio_state & (1u << RW_PIN)) != 0;

    // 2. Dane: GPIO4-GPIO11 (8 bitów) - odwrócenie kolejności
    uint8_t d = (gpio_state >> 4) & 0xFF;
    d = ((d & 0x55) << 1) | ((d & 0xAA) >> 1);
    d = ((d & 0x33) << 2) | ((d & 0xCC) >> 2);
    d = ((d & 0x0F) << 4) | ((d & 0xF0) >> 4);
    uint8_t data = d;

    /*char buffer[32];
    int OldPrintX, OldPrintY;

    if (address != 0x0 && !is_read) {
        OldPrintX = PrintX;
        OldPrintY = PrintY;
        snprintf(buffer, sizeof(buffer), "Addr: %02X, Data: %02X", address, data);
        PrintSetPos(60,address);
        PrintText(buffer);
        PrintSetPos(60,row);
        PrintText(buffer);
        row++;
        PrintX = OldPrintX;
        PrintY = OldPrintY;
        if (row >= 30) {
            row = 10;
        }
    }*/

    switch (address) {

        case 0x0:
            if (!is_read) {
                terminal_push_to_buffer(data);
            }
            break;

        case 0x1:
            if (is_read) {
                // TODO: Handle reads from address $1.
            } else {
                MySprite.x = data;
                // TODO: Handle writes to address $1.
            }
            break;

        case 0x2:
            if (is_read) {
                // TODO: Handle reads from address $2.
            } else {
                MySprite.y = data;
                // TODO: Handle writes to address $2.
            }
            break;

        default:
            if (is_read) {
                // TODO: Handle reads from other addresses.
            } else {
                // TODO: Handle writes to other addresses.
            }
            break;
    }
}

void setup6502bus() {
    // Configure data pins
    for (int i = 0; i < 12; i++) {
        gpio_init(i);
        gpio_set_dir(i, false); // input
    }

    // Configure the read/write signal (6502: high = read, low = write).
    gpio_init(RW_PIN);
    gpio_set_dir(RW_PIN, false);

    // Configure interrupt pin
    gpio_init(CLK_PIN);
    gpio_set_dir(CLK_PIN, false);
    //gpio_set_irq_enabled_with_callback(CLK_PIN, GPIO_IRQ_EDGE_FALL, true, &irq_handler);    // jak na razie to działa najlepiej
    gpio_set_irq_enabled_with_callback(CLK_PIN, GPIO_IRQ_EDGE_RISE, true, &irq_handler);    
}