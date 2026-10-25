/**
 * Hunter Adams (vha3@cornell.edu)
 * modified for 8-bit color (256 colors) by user
 * 
 *
 * HARDWARE CONNECTIONS
 *  - GPIO 16 ---> VGA Hsync
 *  - GPIO 17 ---> VGA Vsync
 *  - GPIO 18 ---> 470 ohm resistor ---> VGA Green 
 *  - GPIO 19 ---> 330 ohm resistor ---> VGA Green
 *  - GPIO 20 ---> 330 ohm resistor ---> VGA Blue
 *  - GPIO 21 ---> 330 ohm resistor ---> VGA Red
 *  - GPIO 22 ---> 330 ohm resistor ---> VGA Green/Blue/Red (additional bits)
 *  - GPIO 23 ---> 330 ohm resistor ---> VGA Green/Blue/Red (additional bits)
 *  - RP2040 GND ---> VGA GND
 *
 * RESOURCES USED
 *  - PIO state machines 0, 1, and 2 on PIO instance 0
 *  - DMA channels 0, 1, 2, and 3
 *  - 307.2 kBytes of RAM (for pixel color data)
 *
 * NOTE
 *  - This is a translation of the display primitives
 *    for the PIC32 written by Bruce Land and students
 *
 */

// Give the I/O pins that we're using some names that make sense - usable in main()
//enum vga_pins {HSYNC=16, VSYNC, LO_GRN, HI_GRN, BLUE_PIN, RED_PIN} ;
// we do pinout according to the Planck layout
//enum vga_pins {HSYNC=31, VSYNC=32, LO_GRN=21, HI_GRN=22, BLUE_PIN=19, RED_PIN=25} ; //those are physical pins, but GPIO moust be provided
enum vga_pins {BLUE_PIN=14, LO_GRN=16, HI_GRN=17, RED_PIN=19, HSYNC=22, VSYNC=26} ;
//enum vga_pins {BLUE_PIN=18, LO_GRN=16, HI_GRN=17, RED_PIN=19, HSYNC=26, VSYNC=27} ;

// We can produce 256 (8-bit) colors, so let's give the basic 16 readable names - usable in main()
enum colors {
    BLACK       = 0b00000000,

    DARK_GREEN  = 0b00010000,
    MED_GREEN   = 0b00101000,
    GREEN       = 0b00111000,

    DARK_BLUE   = 0b01000000,
    BLUE        = 0b10000000,
    LIGHT_BLUE  = 0b10100100,
    CYAN        = 0b10111100,

    RED         = 0b00000111,
    DARK_ORANGE = 0b00010110,
    ORANGE      = 0b00100111,
    YELLOW      = 0b00111111,

    MAGENTA     = 0b10000111,
    PINK        = 0b10010111,
    LIGHT_PINK  = 0b11011111,

    WHITE       = 0b11111111
};

// VGA primitives - usable in main
void initVGA(void) ;
void drawPixel(short x, short y, char color) ;
void drawVLine(short x, short y, short h, char color) ;
void drawHLine(int x, int y, int w, char color) ; // faster mod 5/11/2025
void drawLine(short x0, short y0, short x1, short y1, char color) ;
void drawRect(short x, short y, short w, short h, char color);
void drawCircle(short x0, short y0, short r, char color) ;
void drawCircleHelper( short x0, short y0, short r, unsigned char cornername, char color) ;
void fillCircle(short x0, short y0, short r, char color) ;
void fillCircleHelper(short x0, short y0, short r, unsigned char cornername, short delta, char color) ;
void drawRoundRect(short x, short y, short w, short h, short r, char color) ;
void fillRoundRect(short x, short y, short w, short h, short r, char color) ;
void fillRect(short x, short y, short w, short h, char color) ;
void drawChar(short x, short y, unsigned char c, char color, char bg, unsigned char size) ;
void setCursor(short x, short y);
void setTextColor(char c);
void setTextColor2(char c, char bg);
void setTextSize(unsigned char s);
void setTextWrap(char w);
void tft_write(unsigned char c) ;
void writeString(char* str) ;
// ===  strings added 10/11/2023 brl4
void drawCharBig(short x, short y, unsigned char c, char color, char bg) ;
void writeStringBig(char* str) ;
void setTextColorBig(char, char); //works, but can use usual setTextColor2
// 5x7 font
void writeStringBold(char* str);
// === added by brl4 5/11/2025
// fast clear -- x1 and x2 must be EVEN numbered pixels
void clearRect(short x1, short y1, short x2, short y2, short c) ;
// clears the whole frame below top value
void clearLowFrame(short, short) ;
// === get the color of apixel from the frame buffer
short readPixel(short, short) ;
// draw a little cross
void crosshair(short x, short y, short c) ;


void shift_left_5120_fast(char color);
void clear_screen(char color);

