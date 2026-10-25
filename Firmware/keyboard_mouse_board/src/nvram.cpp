#include <EEPROM.h>

#include "nvram.h"

void nvram_init()
{
}

uint8_t nvram_read(uint8_t address)
{
    return EEPROM.read(address);
}

void nvram_write(uint8_t address, uint8_t value)
{
    EEPROM.update(address, value);
}
