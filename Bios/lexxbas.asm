;definitions for BASIC

LEXX := 1

CONFIG_2A := 1

;CONFIG_NO_POKE := 0

CONFIG_NO_LINE_EDITING := 1

CONFIG_SCRTCH_ORDER := 2

ZP_START1 = $00
ZP_START2 = $0A
ZP_START3 = $60
ZP_START4 = $6B

EXTRA_TABLE_FLAG = $EF

USR := GORESTART

SPACE_FOR_GOSUB := $3E
STACK_TOP		:= $FA
WIDTH       := 40
WIDTH2      := 30
RAMSTART2   := $0600

.segment "KERNAL"
MONCOUT := bios_print_char
MONRDKEY:
mon_loop:
    jsr get_key
    cmp #$00         ; nic nie wciśnięte, czekaj
    beq mon_loop
	jsr print_char
    cmp #$0A         ; jeśli LF (Enter z keymap)
    bne not_lf
    lda #$0D         ; zamień na CR
not_lf:
    rts

; ISCNTC:
; 	rts

LOAD := bios_load_program

SAVE:
print_not_supported:
    lda #<not_supported_msg
    ldy #>not_supported_msg
    jsr print_str
	rts

not_supported_msg: .asciiz   "Not implemented\r\n"


.include "msbasic.s"