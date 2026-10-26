#include <stdio.h>
#include <stdarg.h>
#include <lexx.h>

int counter;

void main(void) {
    print_str("===========================================================\r\n");
    print_str("  _  _  ___  _    _     ___     _  _  ___  ___  _    ___  \r\n");
    print_str(" | || || __|| |  | |   / _ \\   | || |/ _ \\| _ \\| |  |   \\ \r\n");
    print_str(" | __ || _| | |__| |__| (_) |  | __ | (_) |   /| |__| |) |\r\n");
    print_str(" |_||_||___||____|____|\\___/   |_||_|\\___/|_|_\\|____|___/\r\n");
    print_str("===========================================================\r\n");
    print_str("      Compiled with C (Cross-built on Win64 for 6502)      \r\n"); 
    print_str("  CPU: WDC 65C02 @ 8 MHz | RAM: 32KB | Status: IT LIVES!   \r\n");
    print_str("===========================================================\r\n");

    for (counter = 0; counter < 10; counter++)
    {
        simple_printf("Counter value: %d\r\n", counter);
    }
}
