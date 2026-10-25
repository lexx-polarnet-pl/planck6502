#ifndef NVRAM_H
#define NVRAM_H

#include <Arduino.h>

void nvram_init();
uint8_t nvram_read(uint8_t address);
void nvram_write(uint8_t address, uint8_t value);

#endif
