#include "textmode.h"
#include "fonts/font_lexx.h"
#include "ansiterminal.cpp"
#include <cstdio>
#include <hardware/clocks.h>

#define TEXT_WIDTH  80 // Szerokość ekranu w znakach
#define TEXT_HEIGHT 30 // Wysokość ekranu w wierszach

// 640x480, font 8x16 = 80x30 characters (+colors)
ALIGNED u8 TextFramebuffer[TEXT_WIDTH * TEXT_HEIGHT * 2];

// 256 characters x 8 pixels x 16 lines = 4096 bytes
ALIGNED u8 TextFontBuffer[4096];

bool terminal_cursor_blink = true;


// Setup a timer for cursor
struct repeating_timer timer;

void terminal_setup_text_mode(sSprite** sprites, u16 sprite_count) {
    // Copy font from Flash to RAM
    //memcpy(TextFontBuffer, FontBoldB8x16, sizeof(TextFontBuffer));
    memcpy(TextFontBuffer, fontLexx, sizeof(TextFontBuffer));

    StartVgaCore();

    VgaCfgDef(&Cfg);
    Cfg.mode[1] = LAYERMODE_SPRITEBLACK;
    VgaCfg(&Cfg, &Vmode);

    ScreenClear(pScreen);
    sStrip* strip = ScreenAddStrip(pScreen, TEXT_HEIGHT * 16);
    sSegm* segment = ScreenAddSegm(strip, TEXT_WIDTH * 8);
    ScreenSegmAText(segment, TextFramebuffer, TextFontBuffer, 16, DefPal16, TEXT_WIDTH * 2);
    PrintSetup(TextFramebuffer, TEXT_WIDTH, TEXT_HEIGHT, TEXT_WIDTH * 2);
    PrintSetCol(PC_COLOR(txt_bg_color, txt_fg_color));
    PrintClear();

    LayerSpriteSetup(1, sprites, sprite_count, &Vmode, 0, 0, TEXT_WIDTH * 8, TEXT_HEIGHT * 16, 0);
    LayerOn(1);

    set_sys_clock_pll(Vmode.vco * 1000, Vmode.pd1, Vmode.pd2);
    VgaInitReq(&Vmode);

    PrintHome();

    // Print some text
    //PrintSetPos(0, 0);
    PrintText("HELLO FROM PICOVGA!\n\n");

    char buffer[32];

    for (u8 i=0; i<16; i++) {
        PrintSetCol(PC_COLOR(PC_BLACK,i));
        snprintf(buffer, sizeof(buffer), " Color %d test on BLACK ", i);
        PrintText(buffer);
        PrintSetCol(PC_COLOR(PC_WHITE,i));
        snprintf(buffer, sizeof(buffer), " Color %d test on WHITE \n", i);
        PrintText(buffer);
    }

    PrintSetCol(PC_COLOR(txt_bg_color, txt_fg_color));   

    terminal_cursor_enable();

}

void terminal_push_to_buffer(uint8_t data) {
    terminal_buffer[terminal_buffer_head] = data;
    terminal_buffer_head = (terminal_buffer_head + 1) % TERMINAL_BUFFER_SIZE;
}

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
        if (!terminal_cursor_disabled) terminal_cursor_enable();        
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
        TextFramebuffer[(PrintY * TEXT_WIDTH + PrintX) * 2 + 1] = PC_COLOR(txt_fg_color, txt_bg_color);
    } else {
        TextFramebuffer[(PrintY * TEXT_WIDTH + PrintX) * 2 + 1] = PC_COLOR(txt_bg_color, txt_fg_color);
    }
    terminal_cursor_blink = !terminal_cursor_blink;
    return true;
}

void terminal_cursor_enable(void) {
    // cancel any existing timer first
    cancel_repeating_timer(&timer);
    // start timer for cursor blinking
    terminal_cursor_blink = false;
    TextFramebuffer[(PrintY * TEXT_WIDTH + PrintX) * 2 + 1] = PC_COLOR(txt_fg_color, txt_bg_color);
    add_repeating_timer_ms(300, terminal_cursor_timer_callback, NULL, &timer);
}

void terminal_cursor_disable(void) {
    // stop timer for cursor blinking
    cancel_repeating_timer(&timer);
    TextFramebuffer[(PrintY * TEXT_WIDTH + PrintX) * 2 + 1] = PC_COLOR(txt_bg_color, txt_fg_color);
}