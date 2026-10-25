#include <Arduino.h>

#include "keyboard.h"
#include "mouse.h"
#include "nvram.h"
#include "output.h"
#include "random.h"
#include "rtc.h"

static uint8_t nvram_address = 0;
static bool message_output_enabled = false;
static bool error_output_enabled = false;

constexpr uint8_t SYS_CTRL_STAT_KEYBOARD_PRESENT = 1 << 4;
constexpr uint8_t SYS_CTRL_STAT_MOUSE_PRESENT = 1 << 5;

// Pinout ATmega328P
#define PIN_CS            PB0
#define PIN_RW            PB1
#define PIN_IRQ           PB2
#define PIN_RDY_STROBE    PB7

#define PIN_SDA           PC4
#define PIN_SCL           PC5

#define PIN_ADDR0         PC0
#define PIN_ADDR1         PC1
#define PIN_ADDR2         PC2
#define PIN_ADDR3         PC3

void show_message(const char* message)
{
    if (message_output_enabled)
    {
        kbd_push_string(message);
    }
}

void show_error(const char* message)
{
    if (error_output_enabled)
    {
        kbd_push_string(message);
    }
}

// ============================================================================
// OBSŁUGA MAGISTRALI DANYCH 6502
// ============================================================================
static inline void dataBusInput()
{
    DDRD = 0x00;
    PORTD = 0x00;
}

static inline void dataBusOutput(uint8_t value)
{
    PORTD = value;
    DDRD = 0xFF;
}

static inline bool csActive()
{
    return (PINB & _BV(PIN_CS)) == 0;
}

static inline bool isReadCycle()
{
    return (PINB & _BV(PIN_RW)) != 0;
}

static inline uint8_t getAddress()
{
    return PINC & 0x0F; // Odczyt A0-A3 z portu C (PC0-PC3)
}

static inline void rdyStrobe()
{
    PORTB &= ~_BV(PIN_RDY_STROBE);
    __asm__ __volatile__("nop\n\t");
    PORTB |= _BV(PIN_RDY_STROBE);
}

// ============================================================================
// SETUP
// ============================================================================
void setup()
{
    dataBusInput();

    // Konfiguracja linii CS, RW, RDY
    DDRB &= ~(_BV(PIN_CS) | _BV(PIN_RW));
    DDRB |= _BV(PIN_RDY_STROBE);
    PORTB |= _BV(PIN_CS) | _BV(PIN_RW) | _BV(PIN_RDY_STROBE);

    // Konfiguracja adresów A0-A3 (PC0-PC3)
    DDRC &= ~(0x0F);

    rdyStrobe();

    show_message("\x1B[0m\x1B[2J\x1B[H"); // Clear screen

    nvram_init();
    random_init();
    keyboard_init();
    mouse_init();
    // TEMPORARY: remove this call after the first successful RTC test.
    // Otherwise every reboot resets the clock to this firmware's build time.
    //rtc_set_time_to_build_time();
    rtc_init();
}

// ============================================================================
// MAIN LOOP
// ============================================================================
void loop()
{
    mouse_poll();

    if (!csActive())
    {
        keyboard_poll();
        mouse_poll();
        return;
    }

    uint8_t addr = getAddress();

    if (isReadCycle())
    {
        switch (addr)
        {
            case 0x00: // KBD_DATA (BASE + $0)
                dataBusOutput(keyboard_read_data());
                break;

            case 0x01: // KBD_CTRL (BASE + $1)
                dataBusOutput(keyboard_read_control());
                break;

            case 0x02: // KBD_STAT (BASE + $2)
                dataBusOutput(keyboard_read_status());
                break;

            case 0x06: // RTC_SEC (BASE + $6)
            case 0x07: // RTC_MIN (BASE + $7)
            case 0x08: // RTC_HOUR (BASE + $8)
            case 0x09: // RTC_DAY (BASE + $9)
            case 0x0A: // RTC_MONTH (BASE + $A)
            case 0x0B: // RTC_YEAR (BASE + $B)
            {
                uint8_t value = 0;
                if (rtc_read_register(addr - 0x06, value))
                {
                    dataBusOutput(value);
                }
                else
                {
                    dataBusOutput(0x00);
                }
                break;
            }

            case 0x0C: // NVRAM_ADDR (BASE + $C)
                dataBusOutput(nvram_address);
                break;

            case 0x0D: // NVRAM_DATA (BASE + $D)
                dataBusOutput(nvram_read(nvram_address));
                break;

            case 0x0F: // SYS_CTRL_STAT (BASE + $F)
            {
                uint8_t status = 0;
                if (keyboard_is_present())
                {
                    status |= SYS_CTRL_STAT_KEYBOARD_PRESENT;
                }
                if (mouse_is_present())
                {
                    status |= SYS_CTRL_STAT_MOUSE_PRESENT;
                }
                dataBusOutput(status);
                break;
            }

            default:
                dataBusOutput(0x00);
                break;
        }
    }
    else // Cykl zapisu 6502 -> ATmega
    {
        uint8_t data_in = PIND; // Odczyt z magistrali
        switch (addr)
        {
            case 0x01: // KBD_CTRL (BASE + $1)
                keyboard_write_control(data_in);
                break;

            case 0x06: // RTC_SEC (BASE + $6)
            case 0x07: // RTC_MIN (BASE + $7)
            case 0x08: // RTC_HOUR (BASE + $8)
            case 0x09: // RTC_DAY (BASE + $9)
            case 0x0A: // RTC_MONTH (BASE + $A)
            case 0x0B: // RTC_YEAR (BASE + $B)
                rtc_write_register(addr - 0x06, data_in);
                break;

            case 0x0C: // NVRAM_ADDR (BASE + $C)
                nvram_address = data_in;
                break;

            case 0x0D: // NVRAM_DATA (BASE + $D)
                nvram_write(nvram_address, data_in);
                break;
        }
    }

    //delayMicroseconds(100);
    rdyStrobe();
}
