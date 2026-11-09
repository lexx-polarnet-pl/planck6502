#define PLANCK_BLACK        0
#define PLANCK_DARK_RED     1
#define PLANCK_RED          2
#define PLANCK_ORANGE       3
#define PLANCK_DARK_BLUE    4
#define PLANCK_BLUE         5
#define PLANCK_CYAN         6
#define PLANCK_WHITE        7

#define PLANCK_NAVY         8
#define PLANCK_LIGHT_BLUE   9
#define PLANCK_PINK_TINT    10
#define PLANCK_PINK         11
#define PLANCK_LIGHT_CYAN   12
#define PLANCK_SKY_BLUE     13
#define PLANCK_ICE_BLUE     14
#define PLANCK_BRIGHT_WHITE 15

#define DEFAULT_FG_COLOR PLANCK_WHITE
#define DEFAULT_BG_COLOR PLANCK_NAVY

#define TERMINAL_BUFFER_SIZE 256 // bufor terminala wejściowego


volatile uint8_t terminal_buffer[TERMINAL_BUFFER_SIZE];
volatile uint16_t terminal_buffer_head = 0;
uint16_t terminal_buffer_tail = 0;
bool terminal_cursor_disabled = false;

uint8_t txt_fg_color = DEFAULT_FG_COLOR;
uint8_t txt_bg_color = DEFAULT_BG_COLOR;

void terminal_setup_text_mode(sSprite** sprites, u16 sprite_count);
void terminal_push_to_buffer(uint8_t data);
void terminal_process_queue();
void terminal_print_char(char ch);
void terminal_scroll_up(uint8_t attr);
bool terminal_cursor_timer_callback(struct repeating_timer *t);
void terminal_cursor_enable(void);
void terminal_cursor_disable(void);