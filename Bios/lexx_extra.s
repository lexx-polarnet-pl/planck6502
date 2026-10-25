.segment "EXTRA"

MON:
        jmp     WOZMON
        ;rts

CLS:
        jsr    clr_scr
        rts
		
INK:
        jsr GETBYT
        txa 
        jmp fcolor

PAPER:
        jsr GETBYT
        txa 
        jmp bcolor

CURSOR:
        jsr GETBYT      ; column
        txa
        sta Z2  ; columns

        jsr CHKCOM

        jsr GETBYT      ; row
        txa
        sta Z3  ; rows

        lda #$1B
        jsr print_char
        lda #'['
        jsr print_char
        lda Z3
        jsr print_a_decimal
        lda #';'
        jsr print_char
        lda Z2
        jsr print_a_decimal
        lda #'H'
        jsr print_char
        rts

CSROFF = coursor_off

CSRON = coursor_on

SYS_LEXX:
        ; ---- pobierz adres z BASIC ----
        ;jsr GETADR            ; LINNUM / LINNUM+1 zawiera integer
        ;jsr GTNUM
        jsr FRMNUM
        jsr GETADR        
        lda #<sys_str
        ldy #>sys_str
        jsr print_str
        lda LINNUM+1
        jsr print_a_hex
        lda LINNUM  
        jsr print_a_hex
        jsr new_line
        ; ---- wywołanie programu maszynowego ----
        ; wciśnij adres powrotu = (adres etykiety after_sys_call) - 1
        ;lda #<after_sys_call - 1
        ;pha
        ;lda #>after_sys_call - 1
        ;pha

        ; skocz do docelowego kodu przez wskaźnik w ZP
        ; jako że nie musimy już nic przywracać, możemy zrobić jmp a rts wróci poziom wyżej
        jmp (LINNUM)

;after_sys_call:

        ;rts

        ;rts
sys_str: 
        .asciiz "Executing machine code at $"