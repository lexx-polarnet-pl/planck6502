#include <stdio.h>
#include <stdarg.h>
#include <lexx.h>

int counter;

void main(void) {
    printf("===========================================================\r\n");
    printf("  _  _  ___  _    _     ___     _  _  ___  ___  _    ___  \r\n");
    printf(" | || || __|| |  | |   / _ \\   | || |/ _ \\| _ \\| |  |   \\ \r\n");
    printf(" | __ || _| | |__| |__| (_) |  | __ | (_) |   /| |__| |) |\r\n");
    printf(" |_||_||___||____|____|\\___/   |_||_|\\___/|_|_\\|____|___/\r\n");
    printf("===========================================================\r\n");
    printf("      Compiled with C (Cross-built on Win64 for 6502)      \r\n"); 
    printf("  CPU: WDC 65C02 @ 8 MHz | RAM: 32KB | Status: IT LIVES!   \r\n");
    printf("===========================================================\r\n");

    for (counter = 0; counter < 10; counter++)
    {
        printf("Counter value: %d\r\n", counter);
    }
}
