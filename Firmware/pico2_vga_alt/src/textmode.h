#define DEFAULT_FG_COLOR PC_WHITE
#define DEFAULT_BG_COLOR PC_BLUE
#define TERMINAL_BUFFER_SIZE 256 // bufor terminala wejściowego


volatile uint8_t terminal_buffer[TERMINAL_BUFFER_SIZE];
volatile uint16_t terminal_buffer_head = 0;
uint16_t terminal_buffer_tail = 0;

uint8_t txt_fg_color = DEFAULT_FG_COLOR;
uint8_t txt_bg_color = DEFAULT_BG_COLOR;

void terminal_setup_text_mode();
void terminal_push_to_buffer(uint8_t data);
void terminal_process_queue();
void terminal_print_char(char ch);
void terminal_scroll_up(uint8_t attr);
bool terminal_cursor_timer_callback(struct repeating_timer *t);
void terminal_cursor_enable(void);
void terminal_cursor_disable(void);