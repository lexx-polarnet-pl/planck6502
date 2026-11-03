#ifndef RANDOM_H
#define RANDOM_H

#include <Arduino.h>

void random_init();
uint8_t random_byte();
void random_add_entropy(uint8_t sample);

#endif
