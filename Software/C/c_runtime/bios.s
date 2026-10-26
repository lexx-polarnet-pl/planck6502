.include "bios_api.inc"
.export _print_char
.export _print_str
.export _getch
.export _fcolor
.export _bcolor
.export _clrscr
.export _bell
.export initmainargs
.export bios_get_param_buffer

.segment "CODE"

_print_char:
        ; A = char (fastcall)
        jmp bios_print_char

_print_str:
        ; Fastcall: pointer in A (low), X (high)
        ; BIOS $FF06 expects A = low, Y = high
        pha         ; save low byte
        txa         ; A = high
        tay         ; Y = high
        pla         ; restore low in A
        jmp bios_print_string   ; bios print str (A=low, Y=high)

_getch:
        jmp bios_get_key      ; BIOS: A = klawisz lub 0, ; A wraca jako wynik funkcji

_fcolor:
        jmp bios_font_color

_bcolor:
        jmp bios_background_color

_clrscr:
        jmp bios_clear_screen
		
_bell:
		jmp bios_bell
		
; Zamiast wykonywać cokolwiek, initmainargs po prostu wraca
initmainargs:
        rts		
