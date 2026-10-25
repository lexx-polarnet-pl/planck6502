#ifndef RTC_H
#define RTC_H

#include <Arduino.h>

void rtc_set_time_to_build_time();
void rtc_init();
bool rtc_read_register(uint8_t register_offset, uint8_t& value);
bool rtc_write_register(uint8_t register_offset, uint8_t value);

#endif
