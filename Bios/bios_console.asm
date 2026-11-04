SYS_CTRL_STAT     = MEGA_CONSOLE_PORT + $F   ; System Status & Control Register
RNG_DATA          = MEGA_CONSOLE_PORT + $E   ; Random Number Generator Data Register

; Maski bitowe dla odczytu statusu
MASK_KBD_PRESENT   = %00100000   ; Bit 5: Klawiatura podłączona
MASK_MOUSE_PRESENT = %01000000   ; Bit 6: Mysz podłączona
KB_BUFFER_MASK = $3F
KB_BUFFER_CAPACITY = $40
 
.segment "BIOS_VECTORS" ; $0200
kb_wptr: .res 1
kb_rptr: .res 1

.segment "KERNAL"

get_key:
        php
        jsr get_key_standard
        ; to jest fragment z getkey simple
        ; --- 1. Filtrowanie: odrzuć wszystko >= $80 ---
        CMP #$80
        BCS return_zero         ; Jeśli bajt >= $80, skocz do zwrotu zera
        ; --- 2. Konwersja na UPPERCASE (tylko dla 'a'..'z') ---
        CMP #'a'                ; Czy znak jest mniejszy niż 'a' ($61)?
        BCC get_key_done        ; Jeśli < 'a' (kody sterujące, cyfry, symbole, 'A'-'Z') -> bez zmian
        CMP #'z' + 1            ; Czy znak jest większy niż 'z' ($7A)?
        BCS get_key_done        ; Jeśli > 'z' -> bez zmian
        AND #$DF                ; Zamiana 'a'..'z' na 'A'..'Z' (zerowanie bitu 5)
        jmp get_key_done        ; Zwróć przetworzony znak ASCII ($00..$7F)

return_zero:
        LDA #$00                ; Zwróć 0 dla znaków spoza podstawowego ASCII (>= $80)

get_key_done:
        plp
        RTS

get_key_standard:
	php        ; save processor status FIRST
        phx
        sei
        lda kb_rptr
        cmp kb_wptr
        bne key_pressed
	lda #$00
	jmp return_from_get_key
key_pressed:
        lda kb_rptr
        and #KB_BUFFER_MASK
        tax
        lda kb_buffer, x
        inc kb_rptr
        pha
        jsr kb_buffer_size
        cmp #KB_BUFFER_CAPACITY
        bcs return_from_get_key
        lda ACIA1_CMD
        ora #%00001000          ; ustaw bit DTR
        sta ACIA1_CMD    
        pla
return_from_get_key:
        plx
        plp  
        rts

clear_kb_buffer:
        lda #$00
        sta kb_wptr
        sta kb_rptr
        rts


mega_console_keyboard_irq:
        ;LDA #'M'
        ;STA GPU_PORT
        LDA MEGA_CONSOLE_PORT

	pha
	jsr kb_buffer_size
	cmp #KB_BUFFER_CAPACITY
	bcs discard_mega_console_char
	lda kb_wptr
	and #KB_BUFFER_MASK
	tax
	pla
	sta kb_buffer, x
	inc kb_wptr
	jsr kb_buffer_size
	cmp #KB_BUFFER_CAPACITY
	bcc bfr_not_full
bfr_buffer_full:
	lda ACIA1_CMD
  	;and #%11111110          ; skasuj bit DTR
	and #%11110111          ; skasuj bit DTR
  	sta ACIA1_CMD	
bfr_not_full:	
	rts

discard_mega_console_char:
	pla
	jmp bfr_buffer_full

kb_buffer_size:
	lda kb_wptr
	sec
	sbc kb_rptr
	rts

print_char:
        cmp #7                  ; Sprawdź, czy znak w akumulatorze (A) to ASCII 7 (BEL)
        bne not_bell           ; Jeśli NIE jest to 7, przejdź do reszty procedury
        jsr opl_error_gong      ; jeśli to bell (gong), wywołaj funkcję dźwięku i wyjdź z procedury
        rts
not_bell:        
        sta GPU_PORT

        ; acia part starts here
        pha
wait_tdre:
        lda ACIA1_STATUS
        and #$10
        beq wait_tdre

        pla
        sta ACIA1_DATA
        ; acia end

        ; delay for picoVGA
;        pha
;	txa
;	ldx #20 ; delay potrzebny dla picoVGA
;delay:
;	dex          
;	bne  delay 
;	tax
;	pla
        ; delay end

	rts
	
; print_str - drukuje łańcuch ASCII zakończony zerem
; Wymaganie przed wywołaniem:
; strptr_lo/strptr_hi zawierają adres 16-bit początku łańcucha (low, high)

print_str:
STRING_ADDRESS_PTR = STROUT_LO
    sta STRING_ADDRESS_PTR                      ; load t_string lsb
    sty STRING_ADDRESS_PTR+1                    ; load t_string msb
    ldy #0               ; offset = 0
print_str_next:
    lda (STRING_ADDRESS_PTR),y    ; wczytaj znak
    beq print_str_done            ; jeśli 0 -> koniec
    jsr print_char       ; drukuj znak (oczekuje: znak w A)
    iny                  ; offset++
    jmp print_str_next
print_str_done:
    rts	

clr_scr:
	; ansi code for clear screen is \033[2J
	; and \033[H – home the cursor
    lda #<clr_scr_str
    ldy #>clr_scr_str
    jsr print_str
	rts
clr_scr_str: .byte "\x1B[2J\x1B[H",0

new_line:
	lda #$0D ; CR
	jsr print_char
	lda #$0A ; LF
	jsr print_char   
	rts    

fcolor:
        pha
        lda #$1B        ; ESC
        jsr print_char
        lda #'['
        jsr print_char
        pla 
        ; Check accumulator and convert color number to ANSI SGR codes:
        ; A = 0 -> set to 39 (default foreground)
        ; A = 1-8 -> add 29 -> 30-37 (standard colors)
        ; A = 9-16 -> add 81 -> 90-97 (bright colors)
        beq FCOLOR_SET_39
        cmp #$09
        bcc FCOLOR_ADD_29      ; A < 9 => 1-8
        cmp #$11
        bcc FCOLOR_ADD_81      ; A < 17 => 9-16
        ; other values: ignore (do not print number)
        jmp FCOLOR_SKIP_PRINT
FCOLOR_SET_39:
        lda #$27
        jsr print_a_decimal
        jmp FCOLOR_AFTER_PRINT
FCOLOR_ADD_29:
        clc
        adc #$1D
        jsr print_a_decimal
        jmp FCOLOR_AFTER_PRINT
FCOLOR_ADD_81:
        clc
        adc #$51
        jsr print_a_decimal
        jmp FCOLOR_AFTER_PRINT
FCOLOR_SKIP_PRINT:
        ; fall through to print 'm'
FCOLOR_AFTER_PRINT:
        lda #'m'
        jsr print_char
        rts

bcolor:
        pha
        lda #$1B        ; ESC
        jsr print_char
        lda #'['
        jsr print_char
        pla 
        ; Check accumulator and convert background color number to ANSI SGR codes:
        ; A = 0 -> set to 49 (reset background)
        ; A = 1-8 -> add 39 -> 40-47 (basic colors)
        ; A = 9-16 -> add 91 -> 100-107 (extended/bright backgrounds)
        beq BCOLOR_SET_49
        cmp #$09
        bcc BCOLOR_ADD_39     ; A < 9 => 1-8
        cmp #$11
        bcc BCOLOR_ADD_91     ; A < 17 => 9-16
        ; other values: ignore (do not print number)
        jmp BCOLOR_SKIP_PRINT
BCOLOR_SET_49:
        lda #$31
        jsr print_a_decimal
        jmp BCOLOR_AFTER_PRINT
BCOLOR_ADD_39:
        clc
        adc #$27
        jsr print_a_decimal
        jmp BCOLOR_AFTER_PRINT
BCOLOR_ADD_91:
        clc
        adc #$5B
        jsr print_a_decimal
        jmp BCOLOR_AFTER_PRINT
BCOLOR_SKIP_PRINT:
        ; fall through to print 'm'
BCOLOR_AFTER_PRINT:
        lda #'m'
        jsr print_char
        rts       

coursor_off:
        lda #<csroff_str
        ldy #>csroff_str
        jsr print_str
        rts
csroff_str: 
        .asciiz "\x1B[?25l"

coursor_on:
        lda #<csron_str
        ldy #>csron_str
        jsr print_str
        rts
csron_str: 
        .asciiz "\x1B[?25h"        


; ==============================================================================
; MAIN ENTRY POINT: Display Input Devices Status
; ==============================================================================
check_input_devices:
    ; --- 1. SPRAWDZENIE KLAWIATURY ---
    LDA #<str_kbd_prefix
    LDY #>str_kbd_prefix
    JSR print_str

    LDA SYS_CTRL_STAT
    AND #MASK_KBD_PRESENT
    BEQ kbd_not_found

    ; Klawiatura obecna
    LDA #<str_ok
    LDY #>str_ok
    JSR print_str
    JMP check_mouse

kbd_not_found:
    ; Klawiatura nieobecna
    LDA #<str_missing
    LDY #>str_missing
    JSR print_str

    ; --- 2. SPRAWDZENIE MYSZY ---
check_mouse:
    LDA #<str_mouse_prefix
    LDY #>str_mouse_prefix
    JSR print_str

    LDA SYS_CTRL_STAT
    AND #MASK_MOUSE_PRESENT
    BEQ mouse_not_found

    ; Mysz obecna
    LDA #<str_ok
    LDY #>str_ok
    JSR print_str
    RTS

mouse_not_found:
    ; Mysz nieobecna
    LDA #<str_missing
    LDY #>str_missing
    JSR print_str
    RTS

GET_RANDOM:
    LDA RNG_DATA        ; Wracaj natychmiast z nową wartością 0-255 w akumulatorze
    RTS