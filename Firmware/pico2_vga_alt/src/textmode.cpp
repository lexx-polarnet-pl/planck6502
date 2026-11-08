#include "textmode.h"
#include "font_lexx.h"
#include "ansiterminal.cpp"

#define TEXT_WIDTH  80 // Szerokość ekranu w znakach
#define TEXT_HEIGHT 30 // Wysokość ekranu w wierszach

// 640x480, font 8x16 = 80x30 characters (+colors)
ALIGNED u8 TextFramebuffer[TEXT_WIDTH * TEXT_HEIGHT * 2];

// 256 characters x 8 pixels x 16 lines = 4096 bytes
ALIGNED u8 TextFontBuffer[4096];

bool terminal_cursor_blink = true;
bool terminal_cursor_disabled = false;



/*
// text colors (if using PC CGA colors)
#define PC_BLACK	0
#define PC_BLUE		1
#define PC_GREEN	2
#define PC_CYAN		3
#define PC_RED		4
#define PC_MAGENTA	5
#define PC_BROWN	6
#define PC_LTGRAY	7
#define PC_GRAY		8
#define PC_LTBLUE	9
#define PC_LTGREEN	10
#define PC_LTCYAN	11
#define PC_LTRED	12
#define PC_LTMAGENTA	13
#define PC_YELLOW	14
#define PC_WHITE	15
*/

// Setup a timer for cursor
struct repeating_timer timer;

void terminal_setup_text_mode() {
    // Copy font from Flash to RAM
    memcpy(TextFontBuffer, FontBoldB8x16, sizeof(TextFontBuffer));
    //memcpy(TextFontBuffer, fontLexx, sizeof(TextFontBuffer));

    // Initialize monochrome text mode
    Video(DEV_VGA, RES_VGA, FORM_TEXT16, TextFramebuffer, TextFontBuffer);

    PrintSetCol(PC_COLOR(txt_fg_color, txt_bg_color));
    PrintClear();
    PrintHome();

    // Print some text
    //PrintSetPos(0, 0);
    PrintText("HELLO FROM PICOVGA!");

    terminal_cursor_enable();

}

void termial_push_to_buffer(uint8_t data) {
    terminal_buffer[terminal_buffer_head] = data;
    terminal_buffer_head = (terminal_buffer_head + 1) % TERMINAL_BUFFER_SIZE;
}

/*void terminal_print_char(char ch) {
    terminal_cursor_disable();
    if (ch == '\b') {
        TextFramebuffer[(PrintY * TEXT_WIDTH + PrintX) * 2 ] = ' '; // put space in the old place
        PrintX--;               
        if (PrintX < 0) {
            PrintX = 0;
        }
    } else {
        PrintChar(ch);
    }
    if (PrintX >= TEXT_WIDTH) {
        PrintX = 0;
        PrintY++;
    }
    if (PrintY >= TEXT_HEIGHT) {
        terminal_scroll_up(PrintCol);
        PrintY = TEXT_HEIGHT - 1;
    }
    terminal_cursor_enable();
}*/

void terminal_print_char(char ch) {
    if (!ansi_terminal_process_char(ch)) {
        terminal_cursor_disable();
        if (ch == '\b') {
            TextFramebuffer[(PrintY * TEXT_WIDTH + PrintX) * 2] = ' ';
            PrintX--;
            if (PrintX < 0) {
                PrintX = 0;
            }
        } else {
            PrintChar(ch);
        }
        if (PrintX >= TEXT_WIDTH) {
            PrintX = 0;
            PrintY++;
        }
        if (PrintY >= TEXT_HEIGHT) {
            terminal_scroll_up(PrintCol);
            PrintY = TEXT_HEIGHT - 1;
        }    
        terminal_cursor_enable();        
    }
}    

void terminal_process_queue() {
    if (terminal_buffer_head != terminal_buffer_tail) {
        //char znak = terminal_buffer[terminal_buffer_tail];
        terminal_print_char(terminal_buffer[terminal_buffer_tail]);
        terminal_buffer_tail = (terminal_buffer_tail + 1) % TERMINAL_BUFFER_SIZE;
    }
}

void terminal_scroll_up(uint8_t attr) {
    int line_bytes = TEXT_WIDTH * 2;

    // 1. Przesuń wiersze 1..TEXT_HEIGHT-1 w miejsce wierszy 0..TEXT_HEIGHT-2
    memmove(
        &TextFramebuffer[0], 
        &TextFramebuffer[line_bytes], 
        line_bytes * (TEXT_HEIGHT - 1)
    );

    // 2. Wyczyść ostatni wiersz (spacje + ustawienie koloru)
    u8 *last_line = &TextFramebuffer[line_bytes * (TEXT_HEIGHT - 1)];
    for (int i = 0; i < TEXT_WIDTH; i++) {
        last_line[i * 2]     = ' ';  // Znak spacji
        last_line[i * 2 + 1] = attr; // Atrybut koloru
    }
}

// Timer interrupt (cursor)
bool terminal_cursor_timer_callback(struct repeating_timer *t) {
    TextFramebuffer[(PrintY * TEXT_WIDTH + PrintX) * 2 + 1] ^= 0xFF; // Invert color attribute
    if (terminal_cursor_blink) {
        TextFramebuffer[(PrintY * TEXT_WIDTH + PrintX) * 2 + 1] = PC_COLOR(txt_bg_color, txt_fg_color);
        
        //drawCharBig(txt_cursor_x*8, txt_cursor_y*16, txt_chars[txt_cursor_x+txt_cursor_y*80], txt_fg_color, txt_bg_color);
    } else {
        TextFramebuffer[(PrintY * TEXT_WIDTH + PrintX) * 2 + 1] = PC_COLOR(txt_fg_color, txt_bg_color);
        //drawCharBig(txt_cursor_x*8, txt_cursor_y*16, txt_chars[txt_cursor_x+txt_cursor_y*80], txt_bg_color, txt_fg_color);
    }
    terminal_cursor_blink = !terminal_cursor_blink;
    return true;
}

void terminal_cursor_enable(void) {
    // cancel any existing timer first
    cancel_repeating_timer(&timer);
    // start timer for cursor blinking
    terminal_cursor_blink = false;
    TextFramebuffer[(PrintY * TEXT_WIDTH + PrintX) * 2 + 1] = PC_COLOR(txt_bg_color, txt_fg_color);
    add_repeating_timer_ms(300, terminal_cursor_timer_callback, NULL, &timer);
}

void terminal_cursor_disable(void) {
    // stop timer for cursor blinking
    cancel_repeating_timer(&timer);
    TextFramebuffer[(PrintY * TEXT_WIDTH + PrintX) * 2 + 1] = PC_COLOR(txt_fg_color, txt_bg_color);
}