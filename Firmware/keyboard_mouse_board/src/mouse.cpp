#include <Arduino.h>

#include <stdio.h>

#include "mouse.h"
#include "output.h"

#define PIN_PS2_MS_DATA   PB5
#define PIN_PS2_MS_CLK    PB6

namespace
{
constexpr uint8_t MOUSE_ADDRESS_MASK =
    _BV(PIN_PS2_MS_CLK) | _BV(PIN_PS2_MS_DATA);

constexpr uint16_t PS2_TIMEOUT_MS = 50;


// ============================================================================
// BŁĘDY ODBIORU
// ============================================================================
enum class ReceiveError : uint8_t
{
    None,
    ClockTimeout,
    BadFrame,
    BadParity
};


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
ReceiveError receive_error = ReceiveError::None;
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
// ZWOLNIENIE LINII PS/2
//
// PS/2 jest typu open collector/open drain.
//
// HIGH = zwolnienie linii
// LOW  = aktywne ściągnięcie do GND
// ============================================================================
void release_line(uint8_t pin)
{
    PORTB |= _BV(pin);
    DDRB &= ~_BV(pin);
}


// ============================================================================
// ŚCIĄGNIĘCIE LINII DO LOW
// ============================================================================
void pull_line_low(uint8_t pin)
{
    PORTB &= ~_BV(pin);
    DDRB |= _BV(pin);
}


// ============================================================================
// OCZEKIWANIE NA POZIOM CLK
// ============================================================================
bool wait_clock_level(bool high,
                      uint16_t timeout_ms = PS2_TIMEOUT_MS)
{
    const uint32_t start = millis();

    while (((PINB & _BV(PIN_PS2_MS_CLK)) != 0) != high)
    {
        if (millis() - start >= timeout_ms)
        {
            return false;
        }
    }

    return true;
}

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
    value = 0;

    receive_error = ReceiveError::None;
    receive_error_bit = 0;
    receive_error_frame = 0;

    uint8_t bits[11];

    // ------------------------------------------------------------------------
    // Synchronizacja z początkiem nowej ramki.
    //
    // Po zakończeniu transmisji host -> device CLK powinien być HIGH.
    // Najpierw doprowadzamy się do tego stanu, a następnie czekamy na
    // pierwsze falling edge nowej ramki.
    // ------------------------------------------------------------------------

    if (!wait_clock_level(true, timeout_ms))
    {
        receive_error = ReceiveError::ClockTimeout;
        receive_error_bit = 0;
        return false;
    }

    // ------------------------------------------------------------------------
    // Odbiór 11 bitów
    // ------------------------------------------------------------------------

    for (uint8_t i = 0; i < 11; ++i)
    {
        // Czekamy na falling edge.
        if (!wait_clock_level(false, timeout_ms))
        {
            receive_error = ReceiveError::ClockTimeout;
            receive_error_bit = i;
            return false;
        }

        // DATA jest ważne na falling edge.
        bits[i] =
            (PINB & _BV(PIN_PS2_MS_DATA)) ? 1 : 0;

        receive_error_frame |=
            static_cast<uint16_t>(bits[i]) << i;

        // Czekamy na koniec cyklu.
        if (!wait_clock_level(true, timeout_ms))
        {
            receive_error = ReceiveError::ClockTimeout;
            receive_error_bit = i;
            return false;
        }
    }

    // ------------------------------------------------------------------------
    // START
    // ------------------------------------------------------------------------

    if (bits[0] != 0)
    {
        receive_error = ReceiveError::BadFrame;
        receive_error_bit = 0;
        return false;
    }

    // ------------------------------------------------------------------------
    // STOP
    // ------------------------------------------------------------------------

    if (bits[10] != 1)
    {
        receive_error = ReceiveError::BadFrame;
        receive_error_bit = 10;
        return false;
    }

    // ------------------------------------------------------------------------
    // DATA
    // ------------------------------------------------------------------------

    uint8_t parity = 0;

    value = 0;

    for (uint8_t i = 0; i < 8; ++i)
    {
        value |=
            static_cast<uint8_t>(bits[i + 1] << i);

        parity ^= bits[i + 1];
    }

    // ------------------------------------------------------------------------
    // PARITY - odd parity
    // ------------------------------------------------------------------------

    if ((parity ^ bits[9]) != 1)
    {
        receive_error = ReceiveError::BadParity;
        return false;
    }

    return true;
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
        case ReceiveError::ClockTimeout:

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


        case ReceiveError::BadFrame:

            snprintf(
                message,
                message_size,
                "MOUSE: %s frame=%03X\r\n",
                stage,
                receive_error_frame
            );

            break;


        case ReceiveError::BadParity:

            snprintf(
                message,
                message_size,
                "MOUSE: %s parity=%03X\r\n",
                stage,
                receive_error_frame
            );

            break;


        case ReceiveError::None:
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
// WYSYŁANIE JEDNEJ RAMKI HOST -> DEVICE
// ============================================================================

bool send_device_byte(uint8_t value)
{
    uint8_t parity = 1;

    // ------------------------------------------------------------------------
    // HOST REQUEST TO SEND
    // ------------------------------------------------------------------------

    pull_line_low(PIN_PS2_MS_CLK);
    delayMicroseconds(120);

    // START = 0
    pull_line_low(PIN_PS2_MS_DATA);

    // Zwolnij CLK.
    release_line(PIN_PS2_MS_CLK);

    // Pierwszy falling edge = START.
    if (!wait_clock_level(false, PS2_TIMEOUT_MS))
        return false;

    if (!wait_clock_level(true, PS2_TIMEOUT_MS))
        return false;

    // ------------------------------------------------------------------------
    // DATA
    // ------------------------------------------------------------------------

    for (uint8_t i = 0; i < 8; ++i)
    {
        const uint8_t bit = value & 0x01;

        if (!wait_clock_level(false, PS2_TIMEOUT_MS))
            return false;

        if (bit)
            release_line(PIN_PS2_MS_DATA);
        else
            pull_line_low(PIN_PS2_MS_DATA);

        parity ^= bit;

        if (!wait_clock_level(true, PS2_TIMEOUT_MS))
            return false;

        value >>= 1;
    }

    // ------------------------------------------------------------------------
    // PARITY
    // ------------------------------------------------------------------------

    if (!wait_clock_level(false, PS2_TIMEOUT_MS))
        return false;

    if (parity)
        release_line(PIN_PS2_MS_DATA);
    else
        pull_line_low(PIN_PS2_MS_DATA);

    if (!wait_clock_level(true, PS2_TIMEOUT_MS))
        return false;

    // ------------------------------------------------------------------------
    // STOP
    // ------------------------------------------------------------------------

    if (!wait_clock_level(false, PS2_TIMEOUT_MS))
        return false;

    release_line(PIN_PS2_MS_DATA);

    if (!wait_clock_level(true, PS2_TIMEOUT_MS))
        return false;

    release_line(PIN_PS2_MS_DATA);

    return true;
}

// ============================================================================
// WYSŁANIE KOMENDY
// ============================================================================
bool send_command(uint8_t command)
{
    return send_device_byte(command);
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
    if (!send_device_byte(0xFF))
    {
        error = "MOUSE: reset transmit failed\r\n";
        return false;
    }

    // =========================================================================
    // ACK / RESEND
    //
    // Odpowiedź myszy jest pełną ramką PS/2:
    //   FA = ACK
    //   FE = RESEND
    // =========================================================================
    for (uint8_t attempt = 0; attempt < 3; ++attempt)
    {
        if (!receive_device_byte(response, 1000))
        {
            static char msg[64];

            format_receive_error(
                "reset ACK",
                msg,
                sizeof(msg)
            );

            error = msg;
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

        if (!send_device_byte(0xFF))
        {
            error = "MOUSE: reset retry transmit failed\r\n";
            return false;
        }
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
        if (!send_command(0xF4))
        {
            error = "MOUSE: enable transmit failed\r\n";
            return false;
        }

        if (!receive_device_byte(response))
        {
            static char receive_message[64];

            format_receive_error(
                "enable ACK",
                receive_message,
                sizeof(receive_message)
            );

            error = receive_message;
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
    DDRB &= ~MOUSE_ADDRESS_MASK;

    PORTB |= MOUSE_ADDRESS_MASK;


    // ------------------------------------------------------------------------
    // RESET / SELF TEST / ID / ENABLE
    // ------------------------------------------------------------------------
    const char* error = nullptr;


    if (!send_reset_and_enable(error))
    {
        release_line(PIN_PS2_MS_CLK);
        release_line(PIN_PS2_MS_DATA);

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