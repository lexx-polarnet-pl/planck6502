#define DATA_MASK 0xFF0   // bity 4–11
#define INTERRUPT_PIN 13 // na tym pinie coś się dzieje, a to jest CLK

void irq_handler(uint gpio, uint32_t events);
void setup6502bus();