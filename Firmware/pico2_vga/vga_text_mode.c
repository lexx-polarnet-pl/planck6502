/**
 * Hunter Adams (vha3@cornell.edu)
 * 
 *
 * HARDWARE CONNECTIONS
   - GPIO 16 ---> VGA Hsync 
   - GPIO 17 ---> VGA Vsync 
   - GPIO 18 ---> VGA Green lo-bit --> 470 ohm resistor --> VGA_Green
   - GPIO 19 ---> VGA Green hi_bit --> 330 ohm resistor --> VGA_Green
   - GPIO 20 ---> 330 ohm resistor ---> VGA-Blue 
   - GPIO 21 ---> 330 ohm resistor ---> VGA-Red 
   - RP2040 GND ---> VGA-GND
 *
 * RESOURCES USED
 *  - PIO state machines 0, 1, and 2 on PIO instance 0
 *  - DMA channels obtained by claim mechanism
 *  - 153.6 kBytes of RAM (for pixel color data)
 *
 */

// VGA graphics library
#include "vga16_graphics_v2.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "pico/stdlib.h"
#include "hardware/clocks.h"
#include "hardware/pio.h"
#include "hardware/dma.h"

//#define DATA_MASK 0xFF      // GP0–GP7
#define DATA_MASK 0xFF0   // bity 4–11
#define INTERRUPT_PIN 13 // na tym pinie coś się dzieje, a to jest CLK
//#define INTERRUPT_PIN 27 // RW
#define BUFFER_SIZE 256

#define TXT_SCREEN_SIZE_X  80
#define TXT_SCREEN_SIZE_Y  30 

#define TXT_SCREEN_SIZE  2400 // 80x30
#define TXT_SHIFT_BYTES 80u

unsigned char txt_chars[TXT_SCREEN_SIZE];
unsigned char txt_colors[TXT_SCREEN_SIZE];

volatile uint8_t buffer[BUFFER_SIZE];
volatile uint16_t head = 0;
uint16_t tail = 0;
bool blink = true;
bool cursorDisabled = false;

int8_t txt_cursor_x = 0;
int8_t txt_cursor_y = 0;
// uint8_t txt_fg_color = WHITE;
// uint8_t txt_bg_color = BLACK;
#define default_fg_color WHITE
#define default_bg_color DARK_BLUE
uint8_t txt_fg_color = default_fg_color;
uint8_t txt_bg_color = default_bg_color;

typedef enum {
    ANSI_STATE_NORMAL,
    ANSI_STATE_ESC,
    ANSI_STATE_CSI
} ansi_state_t;

// Setup a timer for cursor
struct repeating_timer timer;

// CSI params buffer
#define CSI_MAX_PARAMS 4
static int csi_params[CSI_MAX_PARAMS];
static int csi_param_count;
static int csi_cur_val;
static bool csi_building;
static bool csi_private = false; 

static ansi_state_t ansi_state = ANSI_STATE_NORMAL;

void echoString(char* str);

void irq_handler(uint gpio, uint32_t events) {
    // Read all GPIOs at once
    uint32_t gpio_state = sio_hw->gpio_in;    
    uint8_t data = 0;
    // GPIO4 -> bit7
    data |= ((gpio_state >> 4) & 1) << 7;
    // GPIO5 -> bit6
    data |= ((gpio_state >> 5) & 1) << 6;
    // GPIO6 -> bit5
    data |= ((gpio_state >> 6) & 1) << 5;
    // GPIO7 -> bit4
    data |= ((gpio_state >> 7) & 1) << 4;
    // GPIO8 -> bit3
    data |= ((gpio_state >> 8) & 1) << 3;
    // GPIO9 -> bit2
    data |= ((gpio_state >> 9) & 1) << 2;
    // GPIO10 -> bit1
    data |= ((gpio_state >> 10) & 1) << 1;
    // GPIO11 -> bit0
    data |= ((gpio_state >> 11) & 1);    
    buffer[head] = data;
    head = (head + 1) % BUFFER_SIZE;
}

/*void irq_handler(uint gpio, uint32_t events) {
    // Read all GPIOs at once
    uint32_t gpio_state = sio_hw->gpio_in;

    // Example data read
    //uint8_t data = (gpio_state & DATA_MASK) >> 4;

    // Store in circular buffer
    uint8_t data = 0;

    // GPIO4 -> bit7
    data |= ((gpio_state >> 4) & 1) << 7;

    // GPIO5 -> bit6
    data |= ((gpio_state >> 5) & 1) << 6;

    // GPIO6 -> bit5
    data |= ((gpio_state >> 6) & 1) << 5;

    // GPIO7 -> bit4
    data |= ((gpio_state >> 7) & 1) << 4;

    // GPIO8 -> bit3
    data |= ((gpio_state >> 8) & 1) << 3;

    // GPIO9 -> bit2
    data |= ((gpio_state >> 9) & 1) << 2;

    // GPIO10 -> bit1
    data |= ((gpio_state >> 10) & 1) << 1;

    // GPIO11 -> bit0
    data |= ((gpio_state >> 11) & 1);    
    buffer[head] = data;
    head = (head + 1) % BUFFER_SIZE;

    // ===== DEBUG GPIO DUMP =====

    char gpio_debug[32 + 2]; // 30 bitów + \n + \0
    int pos = 0;

    // Od najwyższego GPIO do najniższego
    for (int i = 29; i >= 0; i--) {
        gpio_debug[pos++] = (gpio_state & (1u << i)) ? '1' : '0';
    }

    gpio_debug[pos++] = '\n';
    gpio_debug[pos++] = '\r';
    gpio_debug[pos] = '\0';

    echoString(gpio_debug);
}*/


void putChar(short x, short y, unsigned char c, char color, char bg) {
  txt_chars[x+y*80] = c ;
  //txt_colors[x+y*80] = ( (bg & 0x0F) << 4) | (color & 0x0F) ;
  txt_colors[x+y*80] = color;
}

// zwraca kolor tekstu (foreground) dla znaku w pozycji x,y
unsigned char getCharFColor(short x, short y) {
        unsigned char v = txt_colors[x + y * TXT_SCREEN_SIZE_X];
        return v & 0x0F;
}

// zwraca kolor tła (background) dla znaku w pozycji x,y
unsigned char getCharBColor(short x, short y) {
        unsigned char v = txt_colors[x + y * TXT_SCREEN_SIZE_X];
        return (v >> 4) & 0x0F;
}

void shift_left_txt_80_memmove(char color) {
    if (TXT_SCREEN_SIZE == 0) return;

    if (TXT_SCREEN_SIZE <= TXT_SHIFT_BYTES) {
        // jeśli mniejsza lub równa przesunięciu — wyzeruj całość
        memset(txt_chars,  0, TXT_SCREEN_SIZE);
        memset(txt_colors, txt_bg_color, TXT_SCREEN_SIZE);
        return;
    }

    size_t remaining = TXT_SCREEN_SIZE - TXT_SHIFT_BYTES;

    // kopiuj znaki i kolory (memmove obsługuje overlap)
    memmove(txt_chars,  txt_chars  + TXT_SHIFT_BYTES, remaining);
    memmove(txt_colors, txt_colors + TXT_SHIFT_BYTES, remaining);

    // wyzeruj ogony
    memset(txt_chars  + remaining, 0, TXT_SHIFT_BYTES);
    memset(txt_colors + remaining, color, TXT_SHIFT_BYTES);
}

void moveScreenUp(void) {
    shift_left_5120_fast(txt_bg_color);   
    shift_left_txt_80_memmove(txt_bg_color);
}

// apply SGR parameter (only the ones requested)
static void ansi_apply_sgr(int param) {

    // those are the colors 
    /* {BLACK, DARK_GREEN, MED_GREEN, GREEN,
            DARK_BLUE, BLUE, LIGHT_BLUE, CYAN,
            RED, DARK_ORANGE, ORANGE, YELLOW, 
            MAGENTA, PINK, LIGHT_PINK, WHITE} ;*/
    switch(param) {
        case 0:
            // reset attributes
            txt_fg_color = default_fg_color;
            txt_bg_color = default_bg_color;
            break;
        case 39:
            // reset foreground to default
            txt_fg_color = default_fg_color;
            break;       
        case 49:
            // reset background to default
            txt_bg_color = default_bg_color;
            break;
            // foreground colors                 
        case 30:
            txt_fg_color = BLACK;
            break;
        case 31:
            txt_fg_color = RED;
            break;
        case 32:
            txt_fg_color = GREEN;
            break;
        case 33:
            txt_fg_color = YELLOW;
            break;
        case 34:
            txt_fg_color = BLUE;
            break;
        case 35:    
            txt_fg_color = MAGENTA;
            break;
        case 36:
            txt_fg_color = CYAN;
            break;
        case 37:
            txt_fg_color = WHITE;
            break;
        case 90: 
            txt_fg_color = DARK_GREEN;
            break;
        case 91:
            txt_fg_color = MED_GREEN;
            break;
        case 92:
            txt_fg_color = DARK_BLUE;
            break;
        case 93:
            txt_fg_color = LIGHT_BLUE;
            break;
        case 94:
            txt_fg_color = DARK_ORANGE;
            break;
        case 95:
            txt_fg_color = ORANGE;
            break;
        case 96:
            txt_fg_color = PINK;
            break;
        case 97:
            txt_fg_color = LIGHT_PINK;
            break;            
            // background colors
        case 40:
            txt_bg_color = BLACK;
            break;
        case 41:
            txt_bg_color = RED;
            break;
        case 42:
            txt_bg_color = GREEN;
            break;
        case 43:
            txt_bg_color = YELLOW;
            break;
        case 44:
            txt_bg_color = BLUE;
            break;
        case 45:
            txt_bg_color = MAGENTA;
            break;
        case 46:
            txt_bg_color = CYAN;
            break;
        case 47:
            txt_bg_color = WHITE;
            break;
        case 100:
            txt_bg_color = DARK_GREEN;
            break;
        case 101:
            txt_bg_color = MED_GREEN;
            break;
        case 102:
            txt_bg_color = DARK_BLUE;
            break;
        case 103:
            txt_bg_color = LIGHT_BLUE;
            break;
        case 104:
            txt_bg_color = DARK_ORANGE;
            break;
        case 105:
            txt_bg_color = ORANGE;
            break;
        case 106:
            txt_bg_color = PINK;
            break;
        case 107:
            txt_bg_color = LIGHT_PINK;
            break;
    }

    // PLACEHOLDER: if you need to propagate attribute change to hardware, do it here
}

// Timer interrupt (cursor)
bool repeating_timer_callback(struct repeating_timer *t) {
    if (blink) {
        drawCharBig(txt_cursor_x*8, txt_cursor_y*16, txt_chars[txt_cursor_x+txt_cursor_y*80], txt_fg_color, txt_bg_color);
    } else {
        drawCharBig(txt_cursor_x*8, txt_cursor_y*16, txt_chars[txt_cursor_x+txt_cursor_y*80], txt_bg_color, txt_fg_color);
    }
    blink = !blink;
    return true;
}

void cursor_enable(void) {
    // start timer for cursor blinking
    blink = true;
    add_repeating_timer_ms(300, repeating_timer_callback, NULL, &timer);
    drawCharBig(txt_cursor_x*8, txt_cursor_y*16, txt_chars[txt_cursor_x+txt_cursor_y*80], txt_bg_color, txt_fg_color);
}

void cursor_disable(void) {
    // stop timer for cursor blinking
    cancel_repeating_timer(&timer);
    // redraw character at cursor position in normal colors
    drawCharBig(txt_cursor_x*8, txt_cursor_y*16, txt_chars[txt_cursor_x+txt_cursor_y*80], txt_fg_color, txt_bg_color);
}

static void ansi_process_csi_final(char final_ch) {
    //cursor_disable();
    //extern int txt_cursor_x;
    //extern int txt_cursor_y;

    // if any number still being built, commit it
    if (csi_building) {
        if (csi_param_count < CSI_MAX_PARAMS) csi_params[csi_param_count++] = csi_cur_val;
        csi_building = false;
    }

    switch (final_ch) {
        case 'J': {
            // Only support ESC [ 2 J -> erase entire screen
            int p = (csi_param_count >= 1) ? csi_params[0] : 0;
            if (p == 2) {
                clear_screen(txt_bg_color);
                memset(txt_chars, 0, TXT_SCREEN_SIZE);
                memset(txt_colors, txt_bg_color, TXT_SCREEN_SIZE);
                // PLACEHOLDER: full-screen refresh after clear
            }
        } break;

        case 'H': {
            // Cursor position: ESC [ r ; c H  (1-based). If omitted, go to home.
            int r = 1, c = 1;
            if (csi_param_count >= 1 && csi_params[0] > 0) r = csi_params[0];
            if (csi_param_count >= 2 && csi_params[1] > 0) c = csi_params[1];
            // convert to 0-based indices used by your code
            txt_cursor_y = r - 1;
            txt_cursor_x = c - 1;
            //ansi_clamp_cursor(&txt_cursor_x, &txt_cursor_y);
            // PLACEHOLDER: move hardware cursor if necessary*/
        } break;

        case 'h': {
            // DEC private mode set: ESC [ ? 25 h -> show cursor
            if (csi_private) {
                int p = (csi_param_count >= 1) ? csi_params[0] : 0;
                if (p == 25) {
                    cursor_enable();
                    cursorDisabled = false;
                }
            }
        } break;

        case 'l': {
            // DEC private mode reset: ESC [ ? 25 l -> hide cursor
            if (csi_private) {
                int p = (csi_param_count >= 1) ? csi_params[0] : 0;
                if (p == 25) {
                    cursor_disable();
                    cursorDisabled = true;
                }
            }
        } break;

        case 'm': {
            if (csi_param_count == 0) {
                ansi_apply_sgr(0);
            } else {
                for (int i = 0; i < csi_param_count; ++i) {
                    ansi_apply_sgr(csi_params[i]);
                }
            }
        } break;


        default:
            // unsupported CSI final - ignore
            break;
    }

    // reset CSI buffer
    csi_param_count = 0;
    csi_cur_val = 0;
    csi_building = false;
    csi_private = false;
    //cursor_enable();    
}

void echoChar(unsigned char znak) {
    cursor_disable();
    // state machine handling: normal, ESC, CSI
    if (ansi_state == ANSI_STATE_NORMAL) {
        if (znak == 0x1B) { // ESC
            ansi_state = ANSI_STATE_ESC;
            // init CSI buffers in case next is '['
            csi_param_count = 0;
            csi_cur_val = 0;
            csi_building = false;
            return;
        }    
        if (znak == '\n') {          
            txt_cursor_x = 0;  
        } else if (znak == '\r') {
            txt_cursor_y++;
            if (txt_cursor_y >= TXT_SCREEN_SIZE_Y) {
                moveScreenUp();
                txt_cursor_y = TXT_SCREEN_SIZE_Y-1;
            }
        } else if (znak == '\b') {
            putChar(txt_cursor_x, txt_cursor_y, 32, txt_fg_color, txt_bg_color); // put space in old place
            drawCharBig(txt_cursor_x*8, txt_cursor_y*16, 32, txt_fg_color, txt_bg_color); // put space in old place
                       
            txt_cursor_x--;
            if (txt_cursor_x < 0) {
                txt_cursor_x =0;
                //txt_cursor_y--;
            }
        } else if (znak == '\t'){
            int new_x = txt_cursor_x + 4;
            if (new_x < TXT_SCREEN_SIZE_X){
                txt_cursor_x = new_x;
            }
        } else {
            putChar(txt_cursor_x, txt_cursor_y, znak, txt_fg_color, txt_bg_color);
            drawCharBig(txt_cursor_x*8, txt_cursor_y*16, znak, txt_fg_color, txt_bg_color);
            txt_cursor_x++;
            if (txt_cursor_x >= TXT_SCREEN_SIZE_X) {
                txt_cursor_x = 0;
                txt_cursor_y++;
                if (txt_cursor_y >= TXT_SCREEN_SIZE_Y) {
                    moveScreenUp();
                    txt_cursor_y = TXT_SCREEN_SIZE_Y-1;
                }
            }
        }
    } else if (ansi_state == ANSI_STATE_ESC) {
        // expect '[' for CSI or treat as unsupported single-letter escape
        if (znak == '[') {
            ansi_state = ANSI_STATE_CSI;
            // initialize CSI parsing
            csi_param_count = 0;
            csi_cur_val = 0;
            csi_building = false;
            csi_private = false;
            return;
        } else {
            // unsupported escape sequence -> return to normal
            ansi_state = ANSI_STATE_NORMAL;
            return;
        }
    }
    else if (ansi_state == ANSI_STATE_CSI) {
        // parse digits and separators ';' or final byte
        // handle '?' private-mode indicator (e.g. "?25h" / "?25l")
        if (znak == '?') {
            csi_private = true;
            return;
        }
        if (znak >= '0' && znak <= '9') {
            csi_building = true;
            csi_cur_val = csi_cur_val * 10 + (znak - '0');
            return;
        } else if (znak == ';') {
            if (csi_building) {
                if (csi_param_count < CSI_MAX_PARAMS) csi_params[csi_param_count++] = csi_cur_val;
            } else {
                if (csi_param_count < CSI_MAX_PARAMS) csi_params[csi_param_count++] = 0;
            }
            csi_cur_val = 0;
            csi_building = false;
            return;
        } else {
            // final byte arrived
            if (csi_building) {
                if (csi_param_count < CSI_MAX_PARAMS) csi_params[csi_param_count++] = csi_cur_val;
                csi_building = false;
            }
            char final_ch = (char)znak;
            ansi_process_csi_final(final_ch);
            ansi_state = ANSI_STATE_NORMAL;
            return;
        }
    }
    if (!cursorDisabled)cursor_enable();
}

void echoString(char* str) {
    while (*str){
      char c = *str++;
      echoChar(c);
    }
}

void drawGradient(void) {
    for (int y = 10; y < 460; y++) {
        for (int x = 10; x < 630; x++) {

            // Składowe RGB dopasowane do palety:
            // RRR GGG BB
            //
            // R: 3 bity (0-7)
            // G: 3 bity (0-7)
            // B: 2 bity (0-3)

            uint8_t r = (x * 8) / 640;          // poziomy gradient czerwieni
            uint8_t g = (y * 8) / 480;          // pionowy gradient zieleni

            // niebieski jako mieszanka X i Y
            uint8_t b = ((x + y) * 4) / (640 + 480);

            // Złożenie koloru:
            // bits: RRR GGG BB
            uint8_t color =
                ((r & 0x07) << 5) |
                ((g & 0x07) << 2) |
                (b & 0x03);

            drawPixel(x, y, color);
        }
    }
}

#include <math.h>

void drawColorWheel(void) {
    const int cx = 320;
    const int cy = 240;
    const int radius = 220;

    for (int y = 0; y < 480; y++) {
        for (int x = 0; x < 640; x++) {

            float dx = (float)(x - cx);
            float dy = (float)(y - cy);

            float dist = sqrtf(dx * dx + dy * dy);

            // Poza kołem -> czarne tło
            if (dist > radius) {
                drawPixel(x, y, 0);
                continue;
            }

            // Kąt 0..2PI
            float angle = atan2f(dy, dx);
            if (angle < 0)
                angle += 2.0f * 3.1415926f;

            // Hue 0..1
            float h = angle / (2.0f * 3.1415926f);

            // Saturation 0..1
            float s = dist / radius;

            // Value = 1
            float v = 1.0f;

            float r, g, b;

            // HSV -> RGB
            float hh = h * 6.0f;
            int i = (int)hh;
            float f = hh - i;

            float p = v * (1.0f - s);
            float q = v * (1.0f - s * f);
            float t = v * (1.0f - s * (1.0f - f));

            switch (i % 6) {
                case 0: r = v; g = t; b = p; break;
                case 1: r = q; g = v; b = p; break;
                case 2: r = p; g = v; b = t; break;
                case 3: r = p; g = q; b = v; break;
                case 4: r = t; g = p; b = v; break;
                default:r = v; g = p; b = q; break;
            }

            // Konwersja do:
            // BB GGG RRR

            uint8_t rr = (uint8_t)(r * 7.0f);
            uint8_t gg = (uint8_t)(g * 7.0f);
            uint8_t bb = (uint8_t)(b * 3.0f);

            uint8_t color =
                (rr & 0x07) |
                ((gg & 0x07) << 3) |
                ((bb & 0x03) << 6);

            drawPixel(x, y, color);
        }
    }
}

void drawPaletteGrid(void) {
    for (int c = 0; c < 256; c++) {

        int gx = c & 15;
        int gy = c >> 4;

        int startX = gx * 10;
        int startY = gy * 10;

        for (int y = 0; y < 10; y++) {
            for (int x = 0; x < 10; x++) {
                drawPixel(startX + x, startY + y, c);
            }
        }
    }
}

void drawRGBCube(
    short startX,
    short startY,
    short boxWidth,
    short boxHeight
) {
    // 8 poziomów czerwieni
    // 8 poziomów zieleni
    // 4 poziomy niebieskiego

    for (int b = 0; b < 4; b++) {

        for (int g = 0; g < 8; g++) {

            for (int r = 0; r < 8; r++) {

                // Pozycja boxa

                int px = startX + (r * boxWidth);

                // Każdy poziom blue to osobny blok 8 wierszy
                int py = startY + ((b * 8 + g) * boxHeight);

                // Format:
                // BB GGG RRR

                uint8_t color =
                    (r & 0x07) |
                    ((g & 0x07) << 3) |
                    ((b & 0x03) << 6);

                // Wypełnienie boxa

                for (int y = 0; y < boxHeight; y++) {
                    for (int x = 0; x < boxWidth; x++) {

                        drawPixel(
                            px + x,
                            py + y,
                            color
                        );
                    }
                }
            }
        }
    }
}

void drawAsciiTable(int startX, int startY,
                    uint16_t fgColor, uint16_t bgColor)
{
    const int cellW = 11;
    const int cellH = 19;

    // Dodatkowe miejsce na opisy wierszy i kolumn
    const int offsetX = 24;
    const int offsetY = 20;

    int tableX = startX + offsetX;
    int tableY = startY + offsetY;

    // =========================
    // Opisy kolumn (0-F)
    // =========================
    for (int x = 0; x < 16; x++) {
        char label;

        if (x < 10)
            label = '0' + x;
        else
            label = 'A' + (x - 10);

        drawCharBig(
            tableX + x * cellW,
            startY,
            label,
            fgColor,
            bgColor
        );
    }

    // =========================
    // Opisy wierszy (0x-Fx)
    // =========================
    for (int y = 0; y < 16; y++) {

        char hi;

        if (y < 10)
            hi = '0' + y;
        else
            hi = 'A' + (y - 10);

        drawCharBig(startX, tableY + y * cellH, hi, fgColor, bgColor);
        drawCharBig(startX + 8, tableY + y * cellH, 'x', fgColor, bgColor);
    }

    // =========================
    // Siatka + znaki ASCII
    // =========================
    for (int x = 0; x < 16; x++) {

        // pionowe linie
        drawVLine(
            tableX + x * cellW - 2,
            tableY - 2,
            16 * cellH,
            fgColor
        );

        // poziome linie
        drawHLine(
            tableX - 2,
            tableY + x * cellH - 2,
            16 * cellW,
            fgColor
        );

        for (int y = 0; y < 16; y++) {

            unsigned char c = x + y * 16;

            drawCharBig(
                tableX + x * cellW,
                tableY + y * cellH,
                c,
                fgColor,
                bgColor
            );
        }
    }

    // Ostatnia pionowa linia
    drawVLine(
        tableX + 16 * cellW - 2,
        tableY - 2,
        16 * cellH + 1,
        fgColor
    );

    // Ostatnia pozioma linia
    drawHLine(
        tableX - 2,
        tableY + 16 * cellH - 2,
        16 * cellW + 1,
        fgColor
    );
}

int main() {
    // overclock
    set_sys_clock_khz(150000, true) ;
    
    // Initialize stdio
    stdio_init_all();

    // Enable cursor
    cursor_enable();

    // Configure data pins
    for (int i = 0; i < 12; i++) {
        gpio_init(i);
        gpio_set_dir(i, false); // input
    }


    // Configure interrupt pin
    gpio_init(INTERRUPT_PIN);
    gpio_set_dir(INTERRUPT_PIN, false);
    gpio_set_irq_enabled_with_callback(INTERRUPT_PIN, GPIO_IRQ_EDGE_FALL, true, &irq_handler);    

    // Initialize the VGA screen
    initVGA() ;
    clear_screen(txt_bg_color);
    //drawColorWheel();
    //drawGradient();
    //drawPaletteGrid();
    
    /*for (int x=0;x<639;x++) {
        for (int y=0;y<50;y++) {
            drawPixel(x,y+0,  0b00000001);
            drawPixel(x,y+50, 0b00000010);
            drawPixel(x,y+100,0b00000100);
            drawPixel(x,y+150,0b00001000);
            drawPixel(x,y+200,0b00010000);
            drawPixel(x,y+250,0b00100000);
            drawPixel(x,y+300,0b01000000);
            drawPixel(x,y+350,0b10000000);
        }
    }*/

    echoString("Lexx/Planck VGA BIOS v0.3\r\n");

    /*for (int i=10;i<630;i++) {
        for (int j=400;j<450;j++) {
            drawPixel(i,j,i%256);
        }
    }*/
    /*for (int x=0;x<16;x++) {
        drawVLine(x*11+200-2, 48, 16*19, txt_fg_color) ;
        drawHLine(198, x*19+50-2, 16*11, txt_fg_color) ;
        for (int y=0;y<16;y++) {
            unsigned char c = x + y *16;
            drawCharBig(x*11+200, y*19+50, c, txt_fg_color, txt_bg_color);
        }
    }
    drawVLine(16*11+200-2, 48, 16*19+1, txt_fg_color) ;
    drawHLine(198, 16*19+50-2, 16*11+1, txt_fg_color) ;   */
    
    drawAsciiTable(50, 50, txt_fg_color, txt_bg_color);
    drawRGBCube(350, 55, 25, 10);
    //drawGradient();
    

    while(true) {
        if (head != tail) {
            char znak = buffer[tail];
            echoChar(buffer[tail]);
            tail = (tail + 1) % BUFFER_SIZE;
        }
    }
}
