#include <Arduino.h>

#include "mouse.h"
#include "ps2.h"

namespace
{
volatile uint8_t keyboard_bit_count = 0;
volatile uint8_t keyboard_incoming_byte = 0;
volatile uint8_t ps2_last_pins =
    _BV(PIN_PS2_KB_CLK) | _BV(PIN_PS2_MS_CLK);

void restore_clock_interrupt(uint8_t clock_pin, bool was_enabled)
{
    const uint8_t saved_sreg = SREG;
    cli();

    const uint8_t clock_mask = _BV(clock_pin);
    ps2_last_pins =
        (ps2_last_pins & static_cast<uint8_t>(~clock_mask))
        | (PINB & clock_mask);

    if (was_enabled)
    {
        PCMSK0 |= clock_mask;
    }

    if (clock_pin == PIN_PS2_KB_CLK)
    {
        keyboard_bit_count = 0;
        keyboard_incoming_byte = 0;
    }

    SREG = saved_sreg;
}

bool decode_received_frame(const uint8_t* bits,
                           uint8_t& value,
                           Ps2ReceiveStatus& status)
{
    status = {Ps2ReceiveError::None, 0, 0};

    for (uint8_t i = 0; i < 11; ++i)
    {
        status.frame |= static_cast<uint16_t>(bits[i]) << i;
    }

    if (bits[0] != 0)
    {
        status.error = Ps2ReceiveError::BadFrame;
        status.bit = 0;
        return false;
    }

    if (bits[10] != 1)
    {
        status.error = Ps2ReceiveError::BadFrame;
        status.bit = 10;
        return false;
    }

    uint8_t parity = 0;
    value = 0;

    for (uint8_t i = 0; i < 8; ++i)
    {
        value |= static_cast<uint8_t>(bits[i + 1] << i);
        parity ^= bits[i + 1];
    }

    if ((parity ^ bits[9]) != 1)
    {
        status.error = Ps2ReceiveError::BadParity;
        return false;
    }

    return true;
}
}

void ps2_release_line(uint8_t pin)
{
    PORTB |= _BV(pin);
    DDRB &= ~_BV(pin);
}

void ps2_pull_line_low(uint8_t pin)
{
    PORTB &= ~_BV(pin);
    DDRB |= _BV(pin);
}

bool ps2_wait_clock_level(uint8_t clock_pin,
                          bool high,
                          uint32_t timeout,
                          Ps2TimeoutMode timeout_mode)
{
    if (timeout_mode == Ps2TimeoutMode::Milliseconds)
    {
        const uint32_t start = millis();

        while (((PINB & _BV(clock_pin)) != 0) != high)
        {
            if (millis() - start >= timeout)
            {
                return false;
            }
        }
    }
    else
    {
        while (((PINB & _BV(clock_pin)) != 0) != high)
        {
            if (timeout == 0 || --timeout == 0)
            {
                return false;
            }
        }

        return true;
    }

    return true;
}

bool ps2_receive_byte(uint8_t clock_pin,
                      uint8_t data_pin,
                      uint8_t& value,
                      uint32_t timeout,
                      Ps2TimeoutMode timeout_mode,
                      bool wait_for_idle_high,
                      Ps2ReceiveStatus& status)
{
    value = 0;
    status = {Ps2ReceiveError::None, 0, 0};

    uint8_t bits[11];
    uint8_t received_value = 0;
    uint8_t first_bit = 0;

    if (wait_for_idle_high)
    {
        const bool clock_is_low = (PINB & _BV(clock_pin)) == 0;
        const bool data_is_low = (PINB & _BV(data_pin)) == 0;

        if (clock_is_low && data_is_low)
        {
            bits[0] = 0;
            first_bit = 1;

            if (!ps2_wait_clock_level(
                    clock_pin, true, timeout, timeout_mode))
            {
                status.error = Ps2ReceiveError::ClockTimeout;
                status.bit = 0;
                return false;
            }
        }
        else if (!ps2_wait_clock_level(
                     clock_pin, true, timeout, timeout_mode))
        {
            status.error = Ps2ReceiveError::ClockTimeout;
            return false;
        }
    }

    for (uint8_t i = first_bit; i < 11; ++i)
    {
        if (!ps2_wait_clock_level(clock_pin, false, timeout, timeout_mode))
        {
            status.error = Ps2ReceiveError::ClockTimeout;
            status.bit = i;
            return false;
        }

        bits[i] = (PINB & _BV(data_pin)) ? 1 : 0;
        status.frame |= static_cast<uint16_t>(bits[i]) << i;
        if (!ps2_wait_clock_level(clock_pin, true, timeout, timeout_mode))
        {
            status.error = Ps2ReceiveError::ClockTimeout;
            status.bit = i;
            return false;
        }

        if (i < 10)
        {
            continue;
        }

        if (decode_received_frame(bits, received_value, status))
        {
            value = received_value;
            return true;
        }
    }

    return false;
}

namespace
{
constexpr uint16_t PS2_RESPONSE_INTERBIT_TIMEOUT_US = 300;

bool ps2_wait_clock_falling_for_us(uint8_t clock_pin, uint16_t timeout_us)
{
    const uint32_t start = micros();

    while (PINB & _BV(clock_pin))
    {
        if (micros() - start >= timeout_us)
        {
            return false;
        }
    }

    return true;
}

bool ps2_receive_command_response(uint8_t clock_pin,
                                  uint8_t data_pin,
                                  uint8_t& value,
                                  Ps2ReceiveStatus& status)
{
    uint8_t bits[11];
    status = {Ps2ReceiveError::None, 0, 0};

    if (!ps2_wait_clock_level(
            clock_pin, false, 10000, Ps2TimeoutMode::PollIterations))
    {
        status.error = Ps2ReceiveError::ClockTimeout;
        status.bit = 0;
        return false;
    }

    bits[0] = (PINB & _BV(data_pin)) ? 1 : 0;

    if (bits[0] != 0)
    {
        status.error = Ps2ReceiveError::BadFrame;
        status.bit = 0;
        return false;
    }

    if (!ps2_wait_clock_level(
            clock_pin, true, 10000, Ps2TimeoutMode::PollIterations))
    {
        status.error = Ps2ReceiveError::ClockTimeout;
        status.bit = 0;
        return false;
    }

    if (!ps2_wait_clock_falling_for_us(
            clock_pin, PS2_RESPONSE_INTERBIT_TIMEOUT_US))
    {
        // A lone low pulse is the device's physical ACK, preceding its reply byte.
        return ps2_receive_byte(
            clock_pin,
            data_pin,
            value,
            10000,
            Ps2TimeoutMode::PollIterations,
            false,
            status
        );
    }

    for (uint8_t i = 1; i < 11; ++i)
    {
        bits[i] = (PINB & _BV(data_pin)) ? 1 : 0;

        if (!ps2_wait_clock_level(
                clock_pin, true, 10000, Ps2TimeoutMode::PollIterations))
        {
            status.error = Ps2ReceiveError::ClockTimeout;
            status.bit = i;
            return false;
        }

        if (i < 10
            && !ps2_wait_clock_level(
                clock_pin, false, 10000, Ps2TimeoutMode::PollIterations))
        {
            status.error = Ps2ReceiveError::ClockTimeout;
            status.bit = i + 1;
            return false;
        }
    }

    if (!decode_received_frame(bits, value, status))
    {
        return false;
    }

    return true;
}
}

bool ps2_send_byte(uint8_t clock_pin,
                   uint8_t data_pin,
                   uint8_t value,
                   uint8_t& response)
{
    uint8_t parity = 1;
    Ps2ReceiveStatus receive_status;
    response = 0;
    const uint8_t saved_sreg = SREG;
    const uint8_t clock_mask = _BV(clock_pin);

    cli();
    const bool pin_change_was_enabled = (PCMSK0 & clock_mask) != 0;
    PCMSK0 &= static_cast<uint8_t>(~clock_mask);

    if (clock_pin == PIN_PS2_KB_CLK)
    {
        keyboard_bit_count = 0;
        keyboard_incoming_byte = 0;
    }

    SREG = saved_sreg;

    DDRB |= _BV(clock_pin);
    PORTB &= ~_BV(clock_pin);
    delayMicroseconds(120);

    DDRB |= _BV(data_pin);
    PORTB &= ~_BV(data_pin);

    DDRB &= ~_BV(clock_pin);
    PORTB |= _BV(clock_pin);

    for (uint8_t frame_pos = 0; frame_pos < 11; ++frame_pos)
    {
        if (!ps2_wait_clock_level(
                clock_pin, false, 10000, Ps2TimeoutMode::PollIterations))
        {
            goto send_error;
        }

        if (frame_pos == 10)
        {
            break;
        }

        if (frame_pos < 8)
        {
            if ((value >> frame_pos) & 0x01)
            {
                PORTB |= _BV(data_pin);
                parity ^= 1;
            }
            else
            {
                PORTB &= ~_BV(data_pin);
            }
        }
        else if (frame_pos == 8)
        {
            if (parity)
            {
                PORTB |= _BV(data_pin);
            }
            else
            {
                PORTB &= ~_BV(data_pin);
            }
        }
        else
        {
            PORTB |= _BV(data_pin);
        }

        if (!ps2_wait_clock_level(
                clock_pin, true, 10000, Ps2TimeoutMode::PollIterations))
        {
            goto send_error;
        }
    }

    if (!ps2_wait_clock_level(
            clock_pin, true, 10000, Ps2TimeoutMode::PollIterations))
    {
        goto send_error;
    }

    ps2_release_line(data_pin);

    if (!ps2_receive_command_response(
            clock_pin, data_pin, response, receive_status))
    {
        goto send_error;
    }

    restore_clock_interrupt(clock_pin, pin_change_was_enabled);
    SREG = saved_sreg;
    return true;

send_error:
    ps2_release_line(data_pin);
    ps2_release_line(clock_pin);
    restore_clock_interrupt(clock_pin, pin_change_was_enabled);
    SREG = saved_sreg;
    return false;
}

ISR(PCINT0_vect)
{
    const uint8_t current_pins = PINB;
    const uint8_t enabled_pins = PCMSK0;

    if ((enabled_pins & _BV(PIN_PS2_KB_CLK))
        && (ps2_last_pins & _BV(PIN_PS2_KB_CLK))
        && !(current_pins & _BV(PIN_PS2_KB_CLK)))
    {
        const uint8_t data_bit =
            (current_pins & _BV(PIN_PS2_KB_DATA)) ? 1 : 0;

        if (keyboard_bit_count >= 1 && keyboard_bit_count <= 8)
        {
            keyboard_incoming_byte >>= 1;
            if (data_bit)
            {
                keyboard_incoming_byte |= 0x80;
            }
        }

        ++keyboard_bit_count;

        if (keyboard_bit_count == 11)
        {
            keyboard_process_ps2_scancode(keyboard_incoming_byte);
            keyboard_bit_count = 0;
            keyboard_incoming_byte = 0;
        }
    }

    if ((enabled_pins & _BV(PIN_PS2_MS_CLK))
        && !(ps2_last_pins & _BV(PIN_PS2_MS_CLK))
        && (current_pins & _BV(PIN_PS2_MS_CLK)))
    {
        mouse_on_clock_rising();
    }

    if ((enabled_pins & _BV(PIN_PS2_MS_CLK))
        && (ps2_last_pins & _BV(PIN_PS2_MS_CLK))
        && !(current_pins & _BV(PIN_PS2_MS_CLK)))
    {
        mouse_on_clock_falling();
    }

    ps2_last_pins = current_pins;
}
