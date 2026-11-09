#define DATA_MASK 0xFF0   // bity 4–11
#define CLK_PIN 13 // na tym pinie coś się dzieje, a to jest CLK
#define SSEL_PIN 12 // slot select
#define RW_PIN 27 // read write

void irq_handler(uint gpio, uint32_t events);
void setup6502bus();