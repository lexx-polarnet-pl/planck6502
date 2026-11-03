#include <Arduino.h>
#include <avr/interrupt.h>

#include "random.h"
#include "rtc.h"

namespace
{
uint32_t random_state = 0x6D2B79F5UL;
volatile uint32_t interrupt_entropy = 0;

uint32_t mix_seed_byte(uint32_t state, uint8_t value)
{
    state ^= value;
    state *= 0x01000193UL;
    return state;
}
}

void random_init()
{
    uint32_t seed = 0x811C9DC5UL;
    bool rtc_seed_available = true;

    for (uint8_t register_offset = 0; register_offset < 6; ++register_offset)
    {
        uint8_t value = 0;
        if (!rtc_read_register(register_offset, value))
        {
            rtc_seed_available = false;
            break;
        }

        seed = mix_seed_byte(seed, value);
    }

    if (!rtc_seed_available)
    {
        seed = mix_seed_byte(seed, static_cast<uint8_t>(micros()));
        seed = mix_seed_byte(seed, static_cast<uint8_t>(micros() >> 8));
        seed = mix_seed_byte(seed, static_cast<uint8_t>(TCNT0));
    }

    if (seed == 0)
    {
        seed = 0x6D2B79F5UL;
    }

    random_state = seed;
    interrupt_entropy = seed ^ 0x9E3779B9UL;
}

uint8_t random_byte()
{
    const uint8_t saved_sreg = SREG;
    cli();
    random_state ^= interrupt_entropy;
    interrupt_entropy = 0;
    SREG = saved_sreg;

    random_state ^= random_state << 13;
    random_state ^= random_state >> 17;
    random_state ^= random_state << 5;

    return static_cast<uint8_t>(random_state);
}

void random_add_entropy(uint8_t sample)
{
    uint32_t entropy = interrupt_entropy;
    entropy ^= sample;
    entropy = (entropy << 7) | (entropy >> 25);
    entropy += 0x9E3779B9UL;
    interrupt_entropy = entropy;
}
