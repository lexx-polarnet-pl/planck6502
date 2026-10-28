#include <Arduino.h>

#include <stdio.h>

#include "mouse.h"
#include "output.h"
#include "ps2.h"

namespace
{
constexpr uint16_t PS2_TIMEOUT_MS = 50;


// ============================================================================
// STAN MYSZY
// ============================================================================
volatile int16_t mouse_x = 0;
volatile int16_t mouse_y = 0;
volatile uint8_t mouse_buttons = 0;
volatile uint16_t mouse_packet_count = 0;
volatile uint16_t mouse_clock_edge_count = 0;
volatile uint16_t mouse_clock_change_count = 0;
volatile uint16_t mouse_valid_frame_count = 0;
volatile uint16_t mouse_bad_frame_count = 0;
bool mouse_present = false;


// ============================================================================
// DEBUG / BŁĘDY
// ============================================================================
Ps2ReceiveError receive_error = Ps2ReceiveError::None;
uint8_t receive_error_bit = 0;
uint16_t receive_error_frame = 0;


// ============================================================================
// ODBIÓR PAKIETU MYSZY
// ============================================================================
uint8_t packet_bytes[3];
uint8_t packet_byte_count = 0;

uint8_t receive_bit_count = 0;
uint8_t receive_byte = 0;
bool receive_parity = false;
bool receive_frame_valid = true;

uint32_t last_report_ms = 0;


// ============================================================================
// ODBIÓR JEDNEJ RAMKI PS/2 DEVICE -> HOST
//
// Format:
//   START D0 D1 D2 D3 D4 D5 D6 D7 PARITY STOP
//
// Dane próbkowane na FALLING EDGE CLK.
// ============================================================================

bool receive_device_byte(uint8_t& value,
                         uint16_t timeout_ms = PS2_TIMEOUT_MS)
{
    Ps2ReceiveStatus status;
    const bool success = ps2_receive_byte(
        PIN_PS2_MS_CLK,
        PIN_PS2_MS_DATA,
        value,
        timeout_ms,
        Ps2TimeoutMode::Milliseconds,
        true,
        status
    );

    switch (status.error)
    {
        case Ps2ReceiveError::ClockTimeout:
            receive_error = Ps2ReceiveError::ClockTimeout;
            break;
        case Ps2ReceiveError::BadFrame:
            receive_error = Ps2ReceiveError::BadFrame;
            break;
        case Ps2ReceiveError::BadParity:
            receive_error = Ps2ReceiveError::BadParity;
            break;
        case Ps2ReceiveError::None:
        default:
            receive_error = Ps2ReceiveError::None;
            break;
    }

    receive_error_bit = status.bit;
    receive_error_frame = status.frame;
    return success;
}

// ============================================================================
// FORMATOWANIE BŁĘDU
// ============================================================================
void format_receive_error(const char* stage,
                          char* message,
                          size_t message_size)
{
    switch (receive_error)
    {
        case Ps2ReceiveError::ClockTimeout:

            snprintf(
                message,
                message_size,
                "MOUSE: %s timeout bit=%u frame=%03X CLK=%u DATA=%u\r\n",
                stage,
                receive_error_bit,
                receive_error_frame,
                (PINB & _BV(PIN_PS2_MS_CLK)) ? 1U : 0U,
                (PINB & _BV(PIN_PS2_MS_DATA)) ? 1U : 0U
            );

            break;


        case Ps2ReceiveError::BadFrame:

            snprintf(
                message,
                message_size,
                "MOUSE: %s frame=%03X\r\n",
                stage,
                receive_error_frame
            );

            break;


        case Ps2ReceiveError::BadParity:

            snprintf(
                message,
                message_size,
                "MOUSE: %s parity=%03X\r\n",
                stage,
                receive_error_frame
            );

            break;


        case Ps2ReceiveError::None:
        default:

            snprintf(
                message,
                message_size,
                "MOUSE: %s read failed\r\n",
                stage
            );

            break;
    }
}

// ============================================================================
// RESET + SELF TEST + ID + ENABLE
// ============================================================================
bool send_reset_and_enable(const char*& error)
{
    uint8_t response;

    static char response_error[32];

    // =========================================================================
    // RESET = FF
    // =========================================================================
    for (uint8_t attempt = 0; attempt < 3; ++attempt)
    {
        if (!ps2_send_byte(
                PIN_PS2_MS_CLK, PIN_PS2_MS_DATA, 0xFF, response))
        {
            error = "MOUSE: reset transmit or ACK failed\r\n";
            return false;
        }

        if (response == 0xFA)
            break;

        if (response != 0xFE || attempt == 2)
        {
            static char msg[64];

            snprintf(
                msg,
                sizeof(msg),
                "MOUSE: reset response=0x%02X\r\n",
                response
            );

            error = msg;
            return false;
        }

        // RESEND - powtórz FF.
        delay(20);

    }

    if (response != 0xFA)
    {
        error = "MOUSE: reset ACK failed\r\n";
        return false;
    }

    char msg[48];
    snprintf(msg, sizeof(msg),
            "MOUSE: first response=0x%02X\r\n", response);
    show_message(msg);

    // =========================================================================
    // SELF TEST = AA
    // =========================================================================
    if (!receive_device_byte(response, 1000))
    {
        static char receive_message[64];

        format_receive_error(
            "self-test",
            receive_message,
            sizeof(receive_message)
        );

        error = receive_message;
        return false;
    }


    if (response != 0xAA)
    {
        snprintf(
            response_error,
            sizeof(response_error),
            "MOUSE: self-test=0x%02X\r\n",
            response
        );

        error = response_error;
        return false;
    }


    // =========================================================================
    // DEVICE ID
    // =========================================================================
    if (!receive_device_byte(response))
    {
        static char receive_message[64];

        format_receive_error(
            "device ID",
            receive_message,
            sizeof(receive_message)
        );

        error = receive_message;
        return false;
    }


    if (response != 0x00)
    {
        snprintf(
            response_error,
            sizeof(response_error),
            "MOUSE: device ID=0x%02X\r\n",
            response
        );

        error = response_error;
        return false;
    }


    // =========================================================================
    // ENABLE DATA REPORTING = F4
    // =========================================================================
    for (uint8_t attempt = 0; ; ++attempt)
    {
        if (!ps2_send_byte(
                PIN_PS2_MS_CLK, PIN_PS2_MS_DATA, 0xF4, response))
        {
            error = "MOUSE: enable transmit or ACK failed\r\n";
            return false;
        }

        if (response != 0xFE || attempt == 2)
            break;
    }


    if (response != 0xFA)
    {
        snprintf(
            response_error,
            sizeof(response_error),
            "MOUSE: enable ACK=0x%02X\r\n",
            response
        );

        error = response_error;
        return false;
    }


    return true;
}


// ============================================================================
// DODANIE DELTY Z SATURACJĄ
// ============================================================================
void add_delta(volatile int16_t& position,
               int16_t delta)
{
    int32_t updated =
        static_cast<int32_t>(position) + delta;


    if (updated > 32767)
    {
        updated = 32767;
    }
    else if (updated < -32768)
    {
        updated = -32768;
    }


    position =
        static_cast<int16_t>(updated);
}


// ============================================================================
// PRZETWARZANIE PAKIETU 3-BITOWEGO
// ============================================================================
void process_packet()
{
    const uint8_t status =
        packet_bytes[0];

    const uint8_t buttons =
        status & 0x07;


    // Overflow X/Y.
    //
    // Jeżeli wystąpi overflow, ignorujemy deltę,
    // ale zachowujemy stan przycisków.
    if (status & 0xC0)
    {
        mouse_buttons = buttons;

        ++mouse_packet_count;

        return;
    }


    // X
    add_delta(
        mouse_x,
        static_cast<int8_t>(packet_bytes[1])
    );


    // Y
    //
    // PS/2: Y rośnie do góry.
    // Dla układu współrzędnych ekranu odwracamy znak.
    add_delta(
        mouse_y,
        -static_cast<int16_t>(
            static_cast<int8_t>(packet_bytes[2])
        )
    );


    mouse_buttons = buttons;

    ++mouse_packet_count;
}

} // namespace


// ============================================================================
// INIT MYSZY
// ============================================================================
void mouse_init()
{
    mouse_present = false;

    // ------------------------------------------------------------------------
    // CLK + DATA jako wejścia z pull-up.
    // ------------------------------------------------------------------------
    ps2_release_line(PIN_PS2_MS_CLK);
    ps2_release_line(PIN_PS2_MS_DATA);


    // ------------------------------------------------------------------------
    // RESET / SELF TEST / ID / ENABLE
    // ------------------------------------------------------------------------
    const char* error = nullptr;


    if (!send_reset_and_enable(error))
    {
        ps2_release_line(PIN_PS2_MS_CLK);
        ps2_release_line(PIN_PS2_MS_DATA);

        show_error(error);

        return;
    }


    // ------------------------------------------------------------------------
    // Zerowanie stanu myszy
    // ------------------------------------------------------------------------
    packet_byte_count = 0;
    receive_bit_count = 0;
    receive_byte = 0;
    receive_parity = false;
    receive_frame_valid = true;

    mouse_x = 0;
    mouse_y = 0;
    mouse_buttons = 0;
    mouse_packet_count = 0;
    mouse_clock_edge_count = 0;
    mouse_clock_change_count = 0;
    mouse_valid_frame_count = 0;
    mouse_bad_frame_count = 0;

    last_report_ms = millis();


    // ------------------------------------------------------------------------
    // Enable pin-change interrupt on the mouse clock pin.
    //
    // Mysz generuje dane na falling edge CLK.
    // ------------------------------------------------------------------------
    PCMSK0 |= _BV(PIN_PS2_MS_CLK);

    PCICR |= _BV(PCIE0);


    show_message(
        "MOUSE: PS/2 OK\r\n"
    );
    mouse_present = true;
}

bool mouse_is_present()
{
    return mouse_present;
}


// ============================================================================
// ODBIÓR BITU MYSZY
//
// UWAGA:
//
// PS/2 DATA jest próbkowane na FALLING EDGE CLK.
//
// Zmieniamy więc funkcję z:
//
//     mouse_on_clock_rising()
//
// na:
//
//     mouse_on_clock_falling()
//
// ============================================================================
void mouse_on_clock_falling()
{
    ++mouse_clock_edge_count;
    ++mouse_clock_change_count;

    const uint8_t data_bit =
        (PINB & _BV(PIN_PS2_MS_DATA)) ? 1 : 0;


    // =========================================================================
    // BIT 0 = START
    // =========================================================================
    if (receive_bit_count == 0)
    {
        receive_frame_valid =
            (data_bit == 0);

        receive_byte = 0;
        receive_parity = false;
    }


    // =========================================================================
    // BITY 1..8 = DATA
    // =========================================================================
    else if (receive_bit_count <= 8)
    {
        receive_byte |=
            data_bit << (receive_bit_count - 1);

        receive_parity ^=
            data_bit != 0;
    }


    // =========================================================================
    // BIT 9 = PARITY
    // =========================================================================
    else if (receive_bit_count == 9)
    {
        receive_parity ^=
            data_bit != 0;
    }


    // =========================================================================
    // BIT 10 = STOP
    // =========================================================================
    else
    {
        if (data_bit != 1 || !receive_parity)
        {
            receive_frame_valid = false;
        }

        if (receive_frame_valid)
        {
            ++mouse_valid_frame_count;
        }
        else
        {
            ++mouse_bad_frame_count;
        }

        if (receive_frame_valid)
        {
            // -----------------------------------------------------------------
            // Pierwszy bajt musi mieć bit 3 ustawiony.
            //
            // To jest bit Always 1 w standardowym pakiecie myszy PS/2.
            // -----------------------------------------------------------------
            if (packet_byte_count == 0)
            {
                if (receive_byte & 0x08)
                {
                    packet_bytes[
                        packet_byte_count++
                    ] = receive_byte;
                }
            }
            else
            {
                packet_bytes[
                    packet_byte_count++
                ] = receive_byte;


                // -------------------------------------------------------------
                // Mamy pełne 3 bajty.
                // -------------------------------------------------------------
                if (packet_byte_count == 3)
                {
                    process_packet();

                    packet_byte_count = 0;
                }
            }
        }


        // ---------------------------------------------------------------------
        // Następna ramka.
        // ---------------------------------------------------------------------
        receive_bit_count = 0;

        return;
    }


    ++receive_bit_count;
}

void mouse_on_clock_rising()
{
    ++mouse_clock_change_count;
}


// ============================================================================
// POLLING / DEBUG
// ============================================================================
void mouse_poll()
{
    const uint32_t now = millis();


    if (now - last_report_ms < 3000)
    {
        return;
    }


    last_report_ms = now;


    int16_t x;
    int16_t y;
    uint8_t buttons;
    uint16_t packets;
    uint16_t clock_edges;
    uint16_t clock_changes;
    uint16_t valid_frames;
    uint16_t bad_frames;
    uint8_t pinb;
    uint8_t pcmsk0;
    uint8_t pcicr;


    const uint8_t saved_sreg = SREG;

    cli();


    x = mouse_x;
    y = mouse_y;
    buttons = mouse_buttons;
    packets = mouse_packet_count;
    clock_edges = mouse_clock_edge_count;
    clock_changes = mouse_clock_change_count;
    valid_frames = mouse_valid_frame_count;
    bad_frames = mouse_bad_frame_count;
    pinb = PINB;
    pcmsk0 = PCMSK0;
    pcicr = PCICR;


    SREG = saved_sreg;


    char message[112];


    snprintf(
        message,
        sizeof(message),
        "MOUSE X=%d Y=%d L=%u R=%u M=%u PKT=%u EDGE=%u CHG=%u FRM=%u BAD=%u PB6=%u MSK=%02X PCICR=%02X\r\n",
        static_cast<int>(x),
        static_cast<int>(y),

        (buttons & 0x01) ? 1U : 0U,
        (buttons & 0x02) ? 1U : 0U,
        (buttons & 0x04) ? 1U : 0U,

        static_cast<unsigned int>(packets),
        static_cast<unsigned int>(clock_edges),
        static_cast<unsigned int>(clock_changes),
        static_cast<unsigned int>(valid_frames),
        static_cast<unsigned int>(bad_frames),
        (pinb & _BV(PIN_PS2_MS_CLK)) ? 1U : 0U,
        pcmsk0,
        pcicr
    );


    show_message(message);
}