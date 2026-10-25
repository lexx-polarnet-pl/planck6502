#ifndef KEYBOARD_H
#define KEYBOARD_H

#include <Arduino.h>

void keyboard_init();
void keyboard_poll();
bool keyboard_is_present();
void kbd_push_string(const char* str);
uint8_t keyboard_read_data();
uint8_t keyboard_read_control();
uint8_t keyboard_read_status();
void keyboard_write_control(uint8_t value);

#endif
