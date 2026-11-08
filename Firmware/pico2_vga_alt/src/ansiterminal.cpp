#include "ansiterminal.h"


// ansi terminal support
typedef enum {
    ANSI_STATE_NORMAL,
    ANSI_STATE_ESC,
    ANSI_STATE_CSI
} ansi_state_t;

static int csi_params[CSI_MAX_PARAMS];
static int csi_param_count;
static int csi_cur_val;
static bool csi_building;
static bool csi_private = false; 

static ansi_state_t ansi_state = ANSI_STATE_NORMAL;

static void ansi_apply_sgr(int param);
static void ansi_process_csi_final(char final_ch);

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
            txt_fg_color = DEFAULT_FG_COLOR;
            txt_bg_color = DEFAULT_BG_COLOR;
            break;
        case 39:
            // reset foreground to default
            txt_fg_color = DEFAULT_FG_COLOR;
            break;       
        case 49:
            // reset background to default
            txt_bg_color = DEFAULT_BG_COLOR;;
            break;
            // foreground colors                 
        case 30:
            txt_fg_color = PC_BLACK;
            break;
        case 31:
            txt_fg_color = PC_RED;
            break;
        case 32:
            txt_fg_color = PC_GREEN;
            break;
        case 33:
            txt_fg_color = PC_YELLOW;
            break;
        case 34:
            txt_fg_color = PC_BLUE;
            break;
        case 35:    
            txt_fg_color = PC_MAGENTA;
            break;
        case 36:
            txt_fg_color = PC_CYAN;
            break;
        case 37:
            txt_fg_color = PC_WHITE;
            break;
        case 90: 
            //txt_fg_color = PC_DARK_GREEN;
            break;
        case 91:
            //txt_fg_color = PC_MED_GREEN;
            break;
        case 92:
            //txt_fg_color = PC_DARK_BLUE;
            break;
        case 93:
            //txt_fg_color = PC_LIGHT_BLUE;
            break;
        case 94:
            //txt_fg_color = PC_DARK_ORANGE;
            break;
        case 95:
            //txt_fg_color = PC_ORANGE;
            break;
        case 96:
            //txt_fg_color = PC_PINK;
            break;
        case 97:
            //txt_fg_color = PC_LIGHT_PINK;
            break;            
            // background colors
        case 40:
            txt_bg_color = PC_BLACK;
            break;
        case 41:
            txt_bg_color = PC_RED;
            break;
        case 42:
            txt_bg_color = PC_GREEN;
            break;
        case 43:
            txt_bg_color = PC_YELLOW;
            break;
        case 44:
            txt_bg_color = PC_BLUE;
            break;
        case 45:
            txt_bg_color = PC_MAGENTA;
            break;
        case 46:
            txt_bg_color = PC_CYAN;
            break;
        case 47:
            txt_bg_color = PC_WHITE;
            break;
        case 100:
            //txt_bg_color = PC_DARK_GREEN;
            break;
        case 101:
            //txt_bg_color = PC_MED_GREEN;
            break;
        case 102:
            //txt_bg_color = PC_DARK_BLUE;
            break;
        case 103:
            //txt_bg_color = PC_LIGHT_BLUE;
            break;
        case 104:
            //txt_bg_color = PC_DARK_ORANGE;
            break;
        case 105:
            //txt_bg_color = PC_ORANGE;
            break;
        case 106:
            //txt_bg_color = PC_PINK;
            break;
        case 107:
            //txt_bg_color = PC_LIGHT_PINK;
            break;
    }

    // PLACEHOLDER: if you need to propagate attribute change to hardware, do it here
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
                PrintClear();
                //clear_screen(txt_bg_color);
                //memset(txt_chars, 0, TXT_SCREEN_SIZE);
                //memset(txt_colors, txt_bg_color, TXT_SCREEN_SIZE);
                // PLACEHOLDER: full-screen refresh after clear
            }
        } break;

        case 'H': {
            // Cursor position: ESC [ r ; c H  (1-based). If omitted, go to home.
            int r = 1, c = 1;
            if (csi_param_count >= 1 && csi_params[0] > 0) r = csi_params[0];
            if (csi_param_count >= 2 && csi_params[1] > 0) c = csi_params[1];
            // convert to 0-based indices used by your code
            PrintSetPos(c - 1, r - 1);
            //txt_cursor_y = r - 1;
            //txt_cursor_x = c - 1;
            //ansi_clamp_cursor(&txt_cursor_x, &txt_cursor_y);
            // PLACEHOLDER: move hardware cursor if necessary*/
        } break;

        case 'h': {
            // DEC private mode set: ESC [ ? 25 h -> show cursor
            if (csi_private) {
                int p = (csi_param_count >= 1) ? csi_params[0] : 0;
                if (p == 25) {
                    terminal_cursor_enable();
                    //cursorDisabled = false;
                }
            }
        } break;

        case 'l': {
            // DEC private mode reset: ESC [ ? 25 l -> hide cursor
            if (csi_private) {
                int p = (csi_param_count >= 1) ? csi_params[0] : 0;
                if (p == 25) {
                    terminal_cursor_disable();
                    //cursorDisabled = true;
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

bool ansi_terminal_process_char(char ch) {
    if (ansi_state == ANSI_STATE_NORMAL) {
        if (ch != 0x1B) {
            return false;
        }

        ansi_state = ANSI_STATE_ESC;
        csi_param_count = 0;
        csi_cur_val = 0;
        csi_building = false;
        return true;
    }

    if (ansi_state == ANSI_STATE_ESC) {
        if (ch == '[') {
            ansi_state = ANSI_STATE_CSI;
            csi_param_count = 0;
            csi_cur_val = 0;
            csi_building = false;
            csi_private = false;
        } else {
            ansi_state = ANSI_STATE_NORMAL;
        }
        return true;
    }

    if (ch == '?') {
        csi_private = true;
        return true;
    }

    if (ch >= '0' && ch <= '9') {
        csi_building = true;
        csi_cur_val = csi_cur_val * 10 + (ch - '0');
        return true;
    }

    if (ch == ';') {
        if (csi_param_count < CSI_MAX_PARAMS) {
            csi_params[csi_param_count++] = csi_building ? csi_cur_val : 0;
        }
        csi_cur_val = 0;
        csi_building = false;
        return true;
    }

    if (csi_building) {
        if (csi_param_count < CSI_MAX_PARAMS) {
            csi_params[csi_param_count++] = csi_cur_val;
        }
        csi_building = false;
    }
    ansi_process_csi_final(ch);
    ansi_state = ANSI_STATE_NORMAL;
    return true;
}