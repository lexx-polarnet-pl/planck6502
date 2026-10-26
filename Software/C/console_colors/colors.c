#include <stdio.h>
#include <stdarg.h>
#include <lexx.h>

int x, y;

void main(void) {
    fcolor(WHITE);
    bcolor(DARK_BLUE);
    clrscr();
    print_str("All colors for the console\r\n");
    for (x = 1; x <= 16; x++) {
        bcolor(x);
        print_str("BG:");
        print_number(x);
        print_str("\t");
        for (y = 0; y <= 16; y++) {        
            fcolor(y);
            print_str("FG");
            print_number(y);
        }
        print_str("\r\n");
    }
    fcolor(DEFAULT);
    bcolor(DEFAULT);
    print_str("End of color test");    
}
