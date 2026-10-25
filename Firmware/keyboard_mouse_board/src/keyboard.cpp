#include <Arduino.h>

#include "keyboard.h"
#include "mouse.h"
#include "output.h"
#define PIN_PS2_KB_DATA   PB3
#define PIN_PS2_KB_CLK    PB4
#define PIN_PS2_MS_CLK    PB6

// ============================================================================
// BUFOR KLAWIATURY & STANY PS/2
// ============================================================================
static uint8_t kbd_buffer[256];
static volatile uint8_t kbd_head = 0;
static volatile uint8_t kbd_tail = 0;

static volatile uint8_t kbd_ctrl = 0x00;
static volatile uint8_t kbd_shift_state = 0;
static volatile uint8_t kbd_ctrl_state = 0;
static volatile uint8_t kbd_alt_state = 0;
static volatile bool kbd_caps_lock = false;
static volatile bool kbd_num_lock = false;
static volatile bool kbd_scroll_lock = false;
static volatile bool keyboard_leds_pending = false;
static volatile bool kbd_present = false;
static volatile bool ps2_detecting_keyboard = false;
static volatile bool ps2_keyboard_bat_passed = false;

static volatile uint8_t ps2_bit_count = 0;
static volatile uint8_t ps2_incoming_byte = 0;
static volatile bool ps2_is_release = false;
static volatile bool ps2_is_extended = false;
static volatile uint8_t ps2_pause_bytes_remaining = 0;


// ============================================================================
// MAPOWANIE SCANCODE SET 2 -> SMART ASCII
// ============================================================================
const uint8_t PROGMEM scancode_to_ascii_unshifted[128] = {
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, '\t', '`',  0,
    0,   0,   0,   0,   0,  'q', '1',  0,   0,   0,  'z', 's', 'a', 'w', '2',  0,
    0,  'c', 'x', 'd', 'e', '4', '3',  0,   0,  ' ', 'v', 'f', 't', 'r', '5',  0,
    0,   'n', 'b', 'h', 'g', 'y', '6',  0,   0,   0,  'm', 'j', 'u', '7', '8',  0,
    0,   ',', 'k', 'i', 'o', '0', '9',  0,   0,  '.', '/', 'l', ';', 'p', '-',  0,
    0,   0, '\'',  0,   '[', '=',  0,   0,   0,   0, '\r', ']',  0, '\\',  0,   0,
    0,   0,   0,   0,   0,   0, '\b',  0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,  27,   0,   0,   0,   0,   0,   0,   0,   0,   0
};

const uint8_t PROGMEM scancode_to_ascii_shifted[128] = {
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, '\t', '~',  0,
    0,   0,   0,   0,   0,  'Q', '!',  0,   0,   0,  'Z', 'S', 'A', 'W', '@',  0,
    0,  'C', 'X', 'D', 'E', '$', '#',  0,   0,  ' ', 'V', 'F', 'T', 'R', '%',  0,
    0,  'N', 'B', 'H', 'G', 'Y', '^',  0,   0,   0,  'M', 'J', 'U', '&', '*',  0,
    0,  '<', 'K', 'I', 'O', ')', '(',  0,   0,  '>', '?', 'L', ':', 'P', '_',  0,
    0,   0, '\"',  0,   '{', '+',  0,   0,   0,   0, '\r', '}',  0, '|',   0,   0,
    0,   0,   0,   0,   0,   0, '\b',  0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,  27,   0,   0,   0,   0,   0,   0,   0,   0,   0
};


// ============================================================================
// BUFOR KLAWIATURY
// ============================================================================
static inline void kbd_push(uint8_t val)
{
    uint8_t next_head = kbd_head + 1;

    if (next_head != kbd_tail) {
        kbd_buffer[kbd_head] = val;
        kbd_head = next_head;
    }
}

static inline uint8_t kbd_pop()
{
    if (kbd_head == kbd_tail) {
        return 0x00;
    }

    uint8_t val = kbd_buffer[kbd_tail];
    kbd_tail++;

    return val;
}

static inline bool kbd_has_data()
{
    return (kbd_head != kbd_tail);
}


// ============================================================================
// POMOCNICZE FUNKCJE PS/2
// ============================================================================

static bool ps2_wait_clock_low(uint32_t timeout)
{
    while ((PINB & _BV(PIN_PS2_KB_CLK)) && --timeout) {
    }

    return timeout > 0;
}


static bool ps2_wait_clock_high(uint32_t timeout)
{
    while (!(PINB & _BV(PIN_PS2_KB_CLK)) && --timeout) {
    }

    return timeout > 0;
}


// ============================================================================
// ODBIÓR JEDNEJ RAMKI PS/2 - W TRYBIE SYNCHRONICZNYM
//
// Format:
//
// START  D0 D1 D2 D3 D4 D5 D6 D7 PARITY STOP
//   0                                  1
//
// Wywoływane z wyłączonymi przerwaniami.
// ============================================================================
static bool ps2_receive_byte_blocking(uint8_t *result)
{
    uint8_t data = 0;
    uint8_t parity = 0;

    // Czekamy na początek ramki - opadające CLK.
    if (!ps2_wait_clock_low(10000)) {
        return false;
    }

    // Bit START
    uint8_t bit = (PINB & _BV(PIN_PS2_KB_DATA)) ? 1 : 0;

    if (bit != 0) {
        return false;
    }

    if (!ps2_wait_clock_high(10000)) {
        return false;
    }


    // 8 bitów danych
    for (uint8_t i = 0; i < 8; i++) {

        if (!ps2_wait_clock_low(10000)) {
            return false;
        }

        bit = (PINB & _BV(PIN_PS2_KB_DATA)) ? 1 : 0;

        if (bit) {
            data |= _BV(i);
            parity ^= 1;
        }

        if (!ps2_wait_clock_high(10000)) {
            return false;
        }
    }


    // Bit PARITY
    if (!ps2_wait_clock_low(10000)) {
        return false;
    }

    bit = (PINB & _BV(PIN_PS2_KB_DATA)) ? 1 : 0;

    if (bit) {
        parity ^= 1;
    }

    // PS/2 używa nieparzystej parzystości.
    // Po uwzględnieniu bitu parity liczba jedynek
    // musi być nieparzysta.
    if (parity != 1) {
        return false;
    }

    if (!ps2_wait_clock_high(10000)) {
        return false;
    }


    // Bit STOP
    if (!ps2_wait_clock_low(10000)) {
        return false;
    }

    bit = (PINB & _BV(PIN_PS2_KB_DATA)) ? 1 : 0;

    if (bit != 1) {
        return false;
    }

    if (!ps2_wait_clock_high(10000)) {
        return false;
    }

    *result = data;

    return true;
}


// ============================================================================
// NISKOPOZIOMOWE WYSYŁANIE KOMEND PS/2
// HOST -> DEVICE
//
// Funkcja:
//   1. blokuje PCINT klawiatury
//   2. wysyła pełną ramkę PS/2
//   3. zwalnia magistralę
//   4. synchronicznie odbiera ACK = 0xFA
//
// Dzięki temu ACK NIE trafia do ISR jako scancode.
// ============================================================================
static bool ps2_send_byte(uint8_t pin_clk, uint8_t pin_data, uint8_t data)
{
    uint8_t parity = 1;
    uint8_t received;

    // Zapamiętujemy stan SREG.
    uint8_t saved_sreg = SREG;

    cli();

    // ------------------------------------------------------------------------
    // Wyłączamy PCINT dla portu B.
    //
    // Podczas transmisji host -> keyboard ISR nie powinien próbować
    // dekodować zegara tej transmisji jako normalnego scancode.
    // ------------------------------------------------------------------------
    PCICR &= ~_BV(PCIE0);

    // Czyścimy ewentualną oczekującą flagę PCINT.
    PCIFR |= _BV(PCIF0);

    // Resetujemy odbiornik PS/2.
    ps2_bit_count = 0;
    ps2_incoming_byte = 0;


    // ------------------------------------------------------------------------
    // HOST REQUEST
    //
    // CLK LOW przez minimum 100 us.
    // ------------------------------------------------------------------------
    DDRB |= _BV(pin_clk);
    PORTB &= ~_BV(pin_clk);

    delayMicroseconds(120);


    // ------------------------------------------------------------------------
    // START BIT
    //
    // DATA LOW.
    // ------------------------------------------------------------------------
    DDRB |= _BV(pin_data);
    PORTB &= ~_BV(pin_data);


    // ------------------------------------------------------------------------
    // Zwalniamy CLK.
    //
    // Klawiatura od tego momentu generuje zegar.
    // ------------------------------------------------------------------------
    DDRB &= ~_BV(pin_clk);
    PORTB |= _BV(pin_clk);


    // ------------------------------------------------------------------------
    // RAMKA:
    //
    // START
    // D0
    // D1
    // D2
    // D3
    // D4
    // D5
    // D6
    // D7
    // PARITY
    // STOP
    //
    // START jest już ustawiony przed zwolnieniem CLK.
    // Po każdym falling edge ustawiamy DATA dla kolejnego bitu,
    // podczas gdy CLK jest HIGH.
    // ------------------------------------------------------------------------

    for (uint8_t frame_pos = 0; frame_pos < 11; frame_pos++) {

        // Czekamy na opadające zbocze CLK.
        // To zbocze zatwierdza aktualny bit.
        if (!ps2_wait_clock_low(10000)) {
            goto ps2_send_error;
        }


        // Po ostatnim bicie nie przygotowujemy już następnego bitu.
        if (frame_pos == 10) {
            break;
        }


        // Czekamy aż CLK wróci HIGH.
        if (!ps2_wait_clock_high(10000)) {
            goto ps2_send_error;
        }


        // ------------------------------------------------------------
        // Przygotowanie kolejnego bitu
        // ------------------------------------------------------------

        if (frame_pos < 8) {

            // frame_pos = 0 -> D0
            // frame_pos = 1 -> D1
            // ...
            // frame_pos = 7 -> D7

            uint8_t bit = (data >> frame_pos) & 0x01;

            if (bit) {
                PORTB |= _BV(pin_data);
                parity ^= 1;
            }
            else {
                PORTB &= ~_BV(pin_data);
            }
        }
        else if (frame_pos == 8) {

            // PARITY

            if (parity) {
                PORTB |= _BV(pin_data);
            }
            else {
                PORTB &= ~_BV(pin_data);
            }
        }
        else if (frame_pos == 9) {

            // STOP = HIGH

            PORTB |= _BV(pin_data);
        }
    }


    // ------------------------------------------------------------------------
    // STOP został odebrany przez klawiaturę.
    //
    // Czekamy na HIGH CLK, a następnie zwalniamy DATA.
    // ------------------------------------------------------------------------
    if (!ps2_wait_clock_high(10000)) {
        goto ps2_send_error;
    }

    DDRB &= ~_BV(pin_data);
    PORTB |= _BV(pin_data);


    // ------------------------------------------------------------------------
    // TERAZ KLawiatura powinna rozpocząć ACK.
    //
    // Odbieramy synchronicznie całą ramkę.
    // ------------------------------------------------------------------------
    if (!ps2_receive_byte_blocking(&received)) {
        goto ps2_send_error;
    }


    // ------------------------------------------------------------------------
    // Ponownie włączamy PCINT.
    // ------------------------------------------------------------------------
    ps2_bit_count = 0;
    ps2_incoming_byte = 0;
    ps2_is_release = false;
    ps2_is_extended = false;

    PCIFR |= _BV(PCIF0);
    PCICR |= _BV(PCIE0);

    SREG = saved_sreg;


    // ACK klawiatury = 0xFA
    return (received == 0xFA);


ps2_send_error:

    // W przypadku błędu również zwalniamy magistralę.
    DDRB &= ~_BV(pin_data);
    PORTB |= _BV(pin_data);

    DDRB &= ~_BV(pin_clk);
    PORTB |= _BV(pin_clk);

    ps2_bit_count = 0;
    ps2_incoming_byte = 0;
    ps2_is_release = false;
    ps2_is_extended = false;

    PCIFR |= _BV(PCIF0);
    PCICR |= _BV(PCIE0);

    SREG = saved_sreg;

    return false;
}


// ============================================================================
// LED KLAWIATURY
//
// UWAGA:
//
// Bity maski PS/2: Scroll Lock=0, Num Lock=1, Caps Lock=2.
// ============================================================================
static bool ps2_update_keyboard_leds(uint8_t leds)
{
    if (!ps2_send_byte(PIN_PS2_KB_CLK, PIN_PS2_KB_DATA, 0xED)) {
        return false;
    }

    delay(20);

    return ps2_send_byte(
        PIN_PS2_KB_CLK,
        PIN_PS2_KB_DATA,
        leds & 0x07
    );
}


// ============================================================================
// INICJALIZACJA / DETEKCJA KLAWIATURY
// ============================================================================
static void ps2_kb_init_and_detect()
{
    kbd_present = false;
    ps2_keyboard_bat_passed = false;
    ps2_detecting_keyboard = true;

    // RESET keyboard
    //
    // ps2_send_byte() wyśle FF i odbierze ACK=FA.
    //
    // Następnie klawiatura powinna wysłać BAT = AA.
    //
    if (ps2_send_byte(PIN_PS2_KB_CLK, PIN_PS2_KB_DATA, 0xFF)) {

        uint32_t start_time = millis();

        while (millis() - start_time < 1000 &&
               !ps2_keyboard_bat_passed) {
        }
    }

    ps2_detecting_keyboard = false;
    kbd_present = ps2_keyboard_bat_passed;
    keyboard_leds_pending = kbd_present;
}


// ============================================================================
// WSTAWIENIE TEKSTU DO BUFORA
// ============================================================================
void kbd_push_string(const char* str)
{
    while (*str) {

        uint8_t saved_sreg = SREG;

        cli();

        kbd_push((uint8_t)*str);

        str++;

        SREG = saved_sreg;
    }
}


// ============================================================================
// INTERPRETACJA SCANCODE
// ============================================================================
static uint8_t map_altgr(uint8_t code, bool shifted)
{
    if (code == 0x1C) return shifted ? 0x8F : 0x86; // A: Ą, ą
    if (code == 0x21) return shifted ? 0x95 : 0x8D; // C: Ć, ć
    if (code == 0x24) return shifted ? 0x90 : 0x91; // E: Ę, ę
    if (code == 0x4B) return shifted ? 0x9C : 0x92; // L: Ł, ł
    if (code == 0x31) return shifted ? 0xA5 : 0xA4; // N: Ń, ń
    if (code == 0x44) return shifted ? 0xA3 : 0xA2; // O: Ó, ó
    if (code == 0x1B) return shifted ? 0x98 : 0x9E; // S: Ś, ś
    if (code == 0x22) return shifted ? 0xA0 : 0xA6; // X: Ź, ź
    if (code == 0x1A) return shifted ? 0xA1 : 0xA7; // Z: Ż, ż
    return 0;
}

static uint8_t map_function_key(uint8_t code)
{
    if (code == 0x05) return 0xEA; // F1
    if (code == 0x06) return 0xEB; // F2
    if (code == 0x04) return 0xEC; // F3
    if (code == 0x0C) return 0xED; // F4
    if (code == 0x03) return 0xEE; // F5
    if (code == 0x0B) return 0xEF; // F6
    if (code == 0x83) return 0xF0; // F7
    if (code == 0x0A) return 0xF1; // F8
    if (code == 0x01) return 0xF2; // F9
    if (code == 0x09) return 0xF3; // F10
    if (code == 0x78) return 0xF4; // F11
    if (code == 0x07) return 0xF5; // F12
    return 0;
}

static uint8_t map_numpad_navigation(uint8_t code)
{
    if (code == 0x75) return 0xE0; // Up
    if (code == 0x72) return 0xE1; // Down
    if (code == 0x6B) return 0xE2; // Left
    if (code == 0x74) return 0xE3; // Right
    if (code == 0x6C) return 0xE4; // Home
    if (code == 0x69) return 0xE5; // End
    if (code == 0x7D) return 0xE6; // Page Up
    if (code == 0x7A) return 0xE7; // Page Down
    if (code == 0x70) return 0xE8; // Insert
    if (code == 0x71) return 0xE9; // Delete
    return 0;
}

static uint8_t map_numpad_ascii(uint8_t code)
{
    if (code == 0x70) return '0';
    if (code == 0x69) return '1';
    if (code == 0x72) return '2';
    if (code == 0x7A) return '3';
    if (code == 0x6B) return '4';
    if (code == 0x73) return '5';
    if (code == 0x74) return '6';
    if (code == 0x6C) return '7';
    if (code == 0x75) return '8';
    if (code == 0x7D) return '9';
    if (code == 0x71) return '.';
    if (code == 0x79) return '+';
    if (code == 0x7B) return '-';
    if (code == 0x7C) return '*';
    return 0;
}

static uint8_t map_extended_key(uint8_t code)
{
    if (code == 0x75) return 0xE0; // Up
    if (code == 0x72) return 0xE1; // Down
    if (code == 0x6B) return 0xE2; // Left
    if (code == 0x74) return 0xE3; // Right
    if (code == 0x6C) return 0xE4; // Home
    if (code == 0x69) return 0xE5; // End
    if (code == 0x7D) return 0xE6; // Page Up
    if (code == 0x7A) return 0xE7; // Page Down
    if (code == 0x70) return 0xE8; // Insert
    if (code == 0x71) return 0xE9; // Delete
    if (code == 0x7C) return 0xF6; // Print Screen
    if (code == 0x2F) return 0xF9; // Menu
    if (code == 0x1F) return 0xFA; // Left GUI
    if (code == 0x27) return 0xFB; // Right GUI
    if (code == 0x5A) return 0xFC; // Numpad Enter
    if (code == 0x4A) return '/';  // Numpad divide
    return 0;
}

static void process_ps2_scancode(uint8_t code)
{
    // ------------------------------------------------------------------------
    // DETEKCJA BAT
    // ------------------------------------------------------------------------
    if (ps2_detecting_keyboard) {

        if (code == 0xAA) {
            ps2_keyboard_bat_passed = true;
        }

        return;
    }

    if (ps2_pause_bytes_remaining > 0) {
        --ps2_pause_bytes_remaining;
        return;
    }

    if (code == 0xE1) {
        if (kbd_ctrl & 0x01) {
            kbd_push(code);
        }
        else {
            ps2_pause_bytes_remaining = 7;
            kbd_push(0xF8);
        }
        return;
    }

    // ------------------------------------------------------------------------
    // PREFIX E0
    // ------------------------------------------------------------------------
    if (code == 0xE0) {
        ps2_is_extended = true;
        return;
    }


    // ------------------------------------------------------------------------
    // PREFIX F0 = RELEASE
    // ------------------------------------------------------------------------
    if (code == 0xF0) {
        ps2_is_release = true;
        return;
    }


    // ------------------------------------------------------------------------
    // Modyfikatory i blokady
    // ------------------------------------------------------------------------
    if (!ps2_is_extended && code == 0x12) {
        if (ps2_is_release) {
            kbd_shift_state &= static_cast<uint8_t>(~0x01);
        }
        else {
            kbd_shift_state |= 0x01;
        }
    }
    else if (!ps2_is_extended && code == 0x59) {
        if (ps2_is_release) {
            kbd_shift_state &= static_cast<uint8_t>(~0x02);
        }
        else {
            kbd_shift_state |= 0x02;
        }
    }
    else if (code == 0x14) {
        const uint8_t mask = ps2_is_extended ? 0x02 : 0x01;
        if (ps2_is_release) {
            kbd_ctrl_state &= static_cast<uint8_t>(~mask);
        }
        else {
            kbd_ctrl_state |= mask;
        }
    }
    else if (code == 0x11) {
        const uint8_t mask = ps2_is_extended ? 0x02 : 0x01;
        if (ps2_is_release) {
            kbd_alt_state &= static_cast<uint8_t>(~mask);
        }
        else {
            kbd_alt_state |= mask;
        }
    }
    else if (!ps2_is_extended && !ps2_is_release
             && (code == 0x58 || code == 0x77 || code == 0x7E)) {
        if (code == 0x58) {
            kbd_caps_lock = !kbd_caps_lock;
        }
        else if (code == 0x77) {
            kbd_num_lock = !kbd_num_lock;
        }
        else {
            kbd_scroll_lock = !kbd_scroll_lock;
        }
        keyboard_leds_pending = true;
    }


    // ------------------------------------------------------------------------
    // TRYB RAW
    // ------------------------------------------------------------------------
    if (kbd_ctrl & 0x01) {

        if (!ps2_is_release) {
            kbd_push(code);
        }
    }

    // ------------------------------------------------------------------------
    // TRYB ASCII
    // ------------------------------------------------------------------------
    else {

        if (!ps2_is_release) {
            const bool shifted = kbd_shift_state != 0;
            uint8_t output = 0;

            if (ps2_is_extended) {
                output = map_extended_key(code);
            }
            else if (code == 0x7E) {
                output = 0xF7; // Scroll Lock
            }
            else if (map_function_key(code) != 0) {
                output = map_function_key(code);
            }
            else if ((code == 0x70 || code == 0x69 || code == 0x72
                      || code == 0x7A || code == 0x6B || code == 0x73
                      || code == 0x74 || code == 0x6C || code == 0x75
                      || code == 0x7D || code == 0x71)
                     && (kbd_num_lock != shifted)) {
                output = map_numpad_ascii(code);
            }
            else if (code == 0x79 || code == 0x7B || code == 0x7C) {
                output = map_numpad_ascii(code);
            }
            else if (!kbd_num_lock || shifted) {
                output = map_numpad_navigation(code);
            }

            if (output == 0 && !ps2_is_extended && code < 128) {
                const uint8_t plain =
                    pgm_read_byte(&scancode_to_ascii_unshifted[code]);
                const bool letter = plain >= 'a' && plain <= 'z';

                if (kbd_alt_state & 0x02) {
                    output = map_altgr(code, shifted != kbd_caps_lock);
                }

                if (output == 0 && (kbd_ctrl_state != 0) && letter) {
                    output = plain - 'a' + 1;
                }
                else if (output == 0) {
                    const bool use_shifted = letter
                        ? (shifted != kbd_caps_lock)
                        : shifted;
                    output = use_shifted
                        ? pgm_read_byte(&scancode_to_ascii_shifted[code])
                        : plain;
                }
            }

            if (output != 0) {
                kbd_push(output);
            }
        }
    }


    // ------------------------------------------------------------------------
    // KONIEC SEKWENCJI
    // ------------------------------------------------------------------------
    ps2_is_release = false;
    ps2_is_extended = false;
}


// ============================================================================
// ISR PS/2 + MOUSE
// ============================================================================
ISR(PCINT0_vect)
{
    static uint8_t last_pins =
        _BV(PIN_PS2_KB_CLK) | _BV(PIN_PS2_MS_CLK);

    const uint8_t current_pins = PINB;


    // =========================================================================
    // KLAWIATURA - FALLING EDGE CLK
    // =========================================================================
    if ((last_pins & _BV(PIN_PS2_KB_CLK))
        && !(current_pins & _BV(PIN_PS2_KB_CLK))) {

        uint8_t data_bit =
            (PINB & _BV(PIN_PS2_KB_DATA)) ? 1 : 0;


        // ---------------------------------------------------------------------
        // Odbieramy bity D0..D7.
        //
        // Bit START jest pomijany.
        // ---------------------------------------------------------------------
        if (ps2_bit_count >= 1 &&
            ps2_bit_count <= 8) {

            ps2_incoming_byte >>= 1;

            if (data_bit) {
                ps2_incoming_byte |= 0x80;
            }
        }


        ps2_bit_count++;


        // ---------------------------------------------------------------------
        // 11 bitów:
        //
        // 0 = START
        // 1..8 = DATA
        // 9 = PARITY
        // 10 = STOP
        // ---------------------------------------------------------------------
        if (ps2_bit_count == 11) {

            process_ps2_scancode(ps2_incoming_byte);

            ps2_bit_count = 0;
            ps2_incoming_byte = 0;
        }
    }


    // =========================================================================
    // MOUSE - RISING EDGE
    // =========================================================================
    if (!(last_pins & _BV(PIN_PS2_MS_CLK))
        && (current_pins & _BV(PIN_PS2_MS_CLK))) {

        mouse_on_clock_rising();
    }
    // =========================================================================
    // MOUSE - FALLING EDGE
    // =========================================================================
    if ((last_pins & _BV(PIN_PS2_MS_CLK))
        && !(current_pins & _BV(PIN_PS2_MS_CLK))) {

        mouse_on_clock_falling();
    }

    last_pins = current_pins;
}


// ============================================================================
// INIT
// ============================================================================
void keyboard_init()
{
    // PS/2 CLK + DATA jako wejścia z pull-up
    DDRB &= ~(_BV(PIN_PS2_KB_CLK) |
              _BV(PIN_PS2_KB_DATA));

    PORTB |= _BV(PIN_PS2_KB_CLK) |
             _BV(PIN_PS2_KB_DATA);


    // ------------------------------------------------------------------------
    // PCINT0 / PORTB
    // ------------------------------------------------------------------------
    PCICR |= _BV(PCIE0);

    // Keyboard clock is PB6 = PCINT6.
    PCMSK0 |= _BV(PIN_PS2_KB_CLK);


    sei();


    // ------------------------------------------------------------------------
    // RESET + DETEKCJA KLAWIATURY
    // ------------------------------------------------------------------------
    ps2_kb_init_and_detect();

    kbd_ctrl = 0;
    kbd_shift_state = 0;
    kbd_ctrl_state = 0;
    kbd_alt_state = 0;
    kbd_caps_lock = false;
    kbd_num_lock = false;
    kbd_scroll_lock = false;


    // ------------------------------------------------------------------------
    // Komunikaty startowe
    // ------------------------------------------------------------------------
    if (kbd_present) {
        show_message("Klawiatura OK.\r\n");
    }
    else {
        show_message("Ojojoj nie ma klawiatury!!!!!\r\n");
    }
}

bool keyboard_is_present()
{
    return kbd_present;
}

void keyboard_poll()
{
    if (!keyboard_leds_pending || !kbd_present) {
        return;
    }

    const uint8_t saved_sreg = SREG;
    cli();

    const uint8_t leds =
        (kbd_scroll_lock ? 0x01 : 0)
        | (kbd_num_lock ? 0x02 : 0)
        | (kbd_caps_lock ? 0x04 : 0);
    keyboard_leds_pending = false;

    SREG = saved_sreg;

    if (!ps2_update_keyboard_leds(leds)) {
        show_error("Keyboard: LED update failed\r\n");
    }
}


// ============================================================================
// INTERFEJS DLA 6502
// ============================================================================
uint8_t keyboard_read_data()
{
    return kbd_pop();
}


uint8_t keyboard_read_control()
{
    return (kbd_ctrl & 0x03)
        | (kbd_caps_lock ? 0x04 : 0)
        | (kbd_num_lock ? 0x08 : 0)
        | (kbd_scroll_lock ? 0x10 : 0);
}


uint8_t keyboard_read_status()
{
    uint8_t stat = 0;

    if (kbd_ctrl & 0x01) stat |= 0x01;
    if (kbd_shift_state) stat |= 0x02;
    if (kbd_ctrl_state) stat |= 0x04;
    if (kbd_alt_state) stat |= 0x08;
    if (kbd_caps_lock) stat |= 0x10;
    if (kbd_has_data()) stat |= 0x80;

    return stat;
}


void keyboard_write_control(uint8_t value)
{
    kbd_ctrl = value & 0x03;
}
