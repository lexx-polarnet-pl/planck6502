void __fastcall__ print_char(char c);
void __fastcall__ fcolor(char color);
void __fastcall__ bcolor(char color);
void __fastcall__ clrscr(void);
void __fastcall__ print_str(const char *s);
char __fastcall__ getch(void);
void __fastcall__ bell(void);

enum colors {DEFAULT, BLACK, RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE, 
    DARK_GREEN, MED_GREEN, DARK_BLUE,  LIGHT_BLUE, DARK_ORANGE, ORANGE, PINK, LIGHT_PINK} ;

void print_number(int value) {
    char buffer[6];   
    char i = 0;
    unsigned int v;
    //print_char('0'+value);

    if (value == 0) {
        print_char('0');
        return;
    }

    if (value < 0) {
        print_char('-');
        v = (unsigned int)(-value);
    } else {
        v = (unsigned int)value;
    }

    while (v > 0) {
        //print_char('+');
        buffer[i++] = (v % 10) + '0';
        v /= 10;
    }

    while (i > 0) {
        print_char(buffer[--i]);
    }
}

void simple_printf(const char *fmt, ...) {
    va_list ap;
    const char *p;
    va_start(ap, fmt);
    for (p = fmt; *p; ++p) {
        if (*p != '%') {
            print_char(*p);
            continue;
        }
        ++p;
        if (*p == '\0') break;
        switch (*p) {
            case 'd': {
                int v = va_arg(ap, int);
                print_number(v);
                break;
            }
            case 's': {
                const char *s = va_arg(ap, const char *);
                if (s) print_str(s);
                break;
            }
            case 'c': {
                int c = va_arg(ap, int);
                print_char((char)c);
                break;
            }
            case '%': print_char('%'); break;
            default:
                print_char('%'); print_char(*p);
                break;
        }
    }
    va_end(ap);
}