#ifndef PS2_H
#define PS2_H

#include <Arduino.h>

constexpr uint8_t PIN_PS2_KB_DATA = PB3;
constexpr uint8_t PIN_PS2_KB_CLK = PB4;
constexpr uint8_t PIN_PS2_MS_DATA = PB5;
constexpr uint8_t PIN_PS2_MS_CLK = PB6;

enum class Ps2TimeoutMode : uint8_t
{
    PollIterations,
    Milliseconds
};

enum class Ps2ReceiveError : uint8_t
{
    None,
    ClockTimeout,
    BadFrame,
    BadParity
};

struct Ps2ReceiveStatus
{
    Ps2ReceiveError error;
    uint8_t bit;
    uint16_t frame;
};

void ps2_release_line(uint8_t pin);
void ps2_pull_line_low(uint8_t pin);
bool ps2_wait_clock_level(uint8_t clock_pin,
                          bool high,
                          uint32_t timeout,
                          Ps2TimeoutMode timeout_mode);
bool ps2_receive_byte(uint8_t clock_pin,
                      uint8_t data_pin,
                      uint8_t& value,
                      uint32_t timeout,
                      Ps2TimeoutMode timeout_mode,
                      bool wait_for_idle_high,
                      Ps2ReceiveStatus& status);
bool ps2_send_byte(uint8_t clock_pin,
                   uint8_t data_pin,
                   uint8_t value,
                   uint8_t& response);
void keyboard_process_ps2_scancode(uint8_t code);

#endif
