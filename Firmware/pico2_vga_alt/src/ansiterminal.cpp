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

    // ANSI color codes follow the order of the Planck 16-color palette.
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
            txt_bg_color = DEFAULT_BG_COLOR;
            break;
            // foreground colors                 
        case 30:
            txt_fg_color = PLANCK_BLACK;
            break;
        case 31:
            txt_fg_color = PLANCK_DARK_RED;
            break;
        case 32:
            txt_fg_color = PLANCK_RED;
            break;
        case 33:
            txt_fg_color = PLANCK_ORANGE;
            break;
        case 34:
            txt_fg_color = PLANCK_DARK_BLUE;
            break;
        case 35:    
            txt_fg_color = PLANCK_BLUE;
            break;
        case 36:
            txt_fg_color = PLANCK_CYAN;
            break;
        case 37:
            txt_fg_color = PLANCK_WHITE;
            break;
        case 90: 
            txt_fg_color = PLANCK_NAVY;
            break;
        case 91:
            txt_fg_color = PLANCK_LIGHT_BLUE;
            break;
        case 92:
            txt_fg_color = PLANCK_PINK_TINT;
            break;
        case 93:
            txt_fg_color = PLANCK_PINK;
            break;
        case 94:
            txt_fg_color = PLANCK_LIGHT_CYAN;
            break;
        case 95:
            txt_fg_color = PLANCK_SKY_BLUE;
            break;
        case 96:
            txt_fg_color = PLANCK_ICE_BLUE;
            break;
        case 97:
            txt_fg_color = PLANCK_BRIGHT_WHITE;
            break;            
            // background colors
        case 40:
            txt_bg_color = PLANCK_BLACK;
            break;
        case 41:
            txt_bg_color = PLANCK_DARK_RED;
            break;
        case 42:
            txt_bg_color = PLANCK_RED;
            break;
        case 43:
            txt_bg_color = PLANCK_ORANGE;
            break;
        case 44:
            txt_bg_color = PLANCK_DARK_BLUE;
            break;
        case 45:
            txt_bg_color = PLANCK_BLUE;
            break;
        case 46:
            txt_bg_color = PLANCK_CYAN;
            break;
        case 47:
            txt_bg_color = PLANCK_WHITE;
            break;
        case 100:
            txt_bg_color = PLANCK_NAVY;
            break;
        case 101:
            txt_bg_color = PLANCK_LIGHT_BLUE;
            break;
        case 102:
            txt_bg_color = PLANCK_PINK_TINT;
            break;
        case 103:
            txt_bg_color = PLANCK_PINK;
            break;
        case 104:
            txt_bg_color = PLANCK_LIGHT_CYAN;
            break;
        case 105:
            txt_bg_color = PLANCK_SKY_BLUE;
            break;
        case 106:
            txt_bg_color = PLANCK_ICE_BLUE;
            break;
        case 107:
            txt_bg_color = PLANCK_BRIGHT_WHITE;
            break;
    }
    PrintSetCol(PC_COLOR(txt_bg_color, txt_fg_color));
    // PLACEHOLDER: if you need to propagate attribute change to hardware, do it here
}


static void ansi_process_csi_final(char final_ch) {

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
            }
        } break;

        case 'H': {
            // Cursor position: ESC [ r ; c H  (1-based). If omitted, go to home.
            int r = 1, c = 1;
            if (csi_param_count >= 1 && csi_params[0] > 0) r = csi_params[0];
            if (csi_param_count >= 2 && csi_params[1] > 0) c = csi_params[1];
            // convert to 0-based indices used by your code
            PrintSetPos(c - 1, r - 1);
        } break;

        case 'h': {
            // DEC private mode set: ESC [ ? 25 h -> show cursor
            if (csi_private) {
                int p = (csi_param_count >= 1) ? csi_params[0] : 0;
                if (p == 25) {
                    terminal_cursor_enable();
                    terminal_cursor_disabled = false;
                }
            }
        } break;

        case 'l': {
            // DEC private mode reset: ESC [ ? 25 l -> hide cursor
            if (csi_private) {
                int p = (csi_param_count >= 1) ? csi_params[0] : 0;
                if (p == 25) {
                    terminal_cursor_disable();
                    terminal_cursor_disabled = true;
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