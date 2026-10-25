SOUND_CARD_ADDRESS = $FFA0

; ---------------------------------------------------------
; BIOS API
; ---------------------------------------------------------

.include "../bios_api.inc"

OPL_ADDR    = SOUND_CARD_ADDRESS + 8
OPL_DATA    = SOUND_CARD_ADDRESS + 9

.segment "ZEROPAGE"
PTR_LO:         .res 1
PTR_HI:         .res 1
FILE_BASE_LO:   .res 1
FILE_BASE_HI:   .res 1
LOOP_PTR_LO:    .res 1
LOOP_PTR_HI:    .res 1
LOOP_ENABLED:   .res 1

TMP1:           .res 1
TMP2:           .res 1

WAIT_LO:        .res 1
WAIT_HI:        .res 1
STROUT_LO:      .res 2   ; Pointer to string output low byte

; ---------------------------------------------------------
; BASIC LOADER: SYS 1568 ($0620)
; ---------------------------------------------------------

.segment "BASSTART"

; 10 SYS 1568 
.byte $00,$0c,$06,$0A,$00,$8F,$20,$31
.byte $35,$36,$38,$00,$00,$00,$00,$00
; We continue with program header here, since we have 20 bytes reserved for this purpose. 
; We end with LX1 signature, indicating that this program is LexxDOS 1.0 executable.
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$4C,$58,$31

.segment "CODE"

        ;jsr bios_clear_screen
        jsr bios_get_param_buffer
        sta PTR_LO                 ; Zapisz wskaźnik do Zero Page
        sty PTR_HI
        ldy #0
        lda (PTR_LO),y             ; Odczytaj bajt [0] (długość bufora)
        beq cmd_buffer_is_empty    ; Jeśli A == 0, bufor jest pusty!

cmd_buffer_has_data:
        lda #<baner_str
        ldy #>baner_str
        jsr bios_print_string  
        lda PTR_LO
        ldy PTR_HI
        jsr bios_print_string          

        rts

cmd_buffer_is_empty:
        ; wyświetl pomoc
        lda #<usage_str
        ldy #>usage_str
        jsr bios_print_string     
        rts


        jsr bios_print_string
        rts
        lda $0D
        jsr bios_print_char
        lda $0A
        jsr bios_print_char
        rts
   
START:
        
; ---------------------------------------------------------
; Ustaw wskaźnik na dane VGM
; ---------------------------------------------------------

        lda #<VGM_DATA
        sta PTR_LO

        lda #>VGM_DATA
        sta PTR_HI

        lda PTR_LO
        sta FILE_BASE_LO
        lda PTR_HI
        sta FILE_BASE_HI

        ldy #$1C
        lda (PTR_LO),Y
        sta LOOP_PTR_LO

        iny
        lda (PTR_LO),Y
        sta LOOP_PTR_HI

        lda LOOP_PTR_LO
        ora LOOP_PTR_HI
        beq NO_LOOP_OFFSET

        clc
        lda FILE_BASE_LO
        adc LOOP_PTR_LO
        sta LOOP_PTR_LO

        lda FILE_BASE_HI
        adc LOOP_PTR_HI
        sta LOOP_PTR_HI

        lda #$01
        sta LOOP_ENABLED
        jmp READ_VGM_DATA_OFFSET

NO_LOOP_OFFSET:
        lda #$00
        sta LOOP_ENABLED

READ_VGM_DATA_OFFSET:
; ---------------------------------------------------------
; Dodaj offset danych z VGM header ($34-$37)
; ---------------------------------------------------------

; low
        ldy #$34
        lda (PTR_LO),Y
        clc
        adc #$40
        sta TMP1

; high
        iny
        lda (PTR_LO),Y
        adc #$00
        sta TMP2

; dodaj do bazowego adresu pliku
        clc
        lda PTR_LO
        adc TMP1
        sta PTR_LO

        lda PTR_HI
        adc TMP2
        sta PTR_HI

; =========================================================
; MAIN LOOP
; =========================================================

NEXT_CMD:

        ldy #0
        lda (PTR_LO),Y

; ---------------------------------------------------------
; 5A = OPL2 write
; ---------------------------------------------------------

        cmp #$5A
        beq CMD_OPL

; ---------------------------------------------------------
; 61 = wait n samples
; ---------------------------------------------------------

        cmp #$61
        beq CMD_WAIT

; ---------------------------------------------------------
; 62 = wait 735
; ---------------------------------------------------------

        cmp #$62
        beq CMD_WAIT_60HZ

; ---------------------------------------------------------
; 63 = wait 882
; ---------------------------------------------------------

        cmp #$63
        beq CMD_WAIT_50HZ

; ---------------------------------------------------------
; 66 = end
; ---------------------------------------------------------

        cmp #$66
        beq CMD_END_SHORT

; ---------------------------------------------------------
; 70-7F = short wait (1-16 samples)
; ---------------------------------------------------------

        cmp #$70
        bcc CMD_UNKNOWN
        cmp #$80
        bcc CMD_WAIT_SHORT
        jmp CMD_UNKNOWN

; ---------------------------------------------------------
; unknown command -> skip
; ---------------------------------------------------------

CMD_UNKNOWN:
        lda #'?'
        jsr bios_print_char
        jsr INC_PTR
        jmp NEXT_CMD

CMD_END_SHORT:
        jmp CMD_END

; =========================================================
; COMMAND: OPL WRITE
; =========================================================

CMD_OPL:

        ;lda #'.'
        ;jsr print_char
; byte 1 = register
        ldy #1
        lda (PTR_LO),Y
        sta OPL_ADDR

        jsr OPL_DELAY

; byte 2 = data
        iny
        lda (PTR_LO),Y
        sta OPL_DATA

        jsr OPL_DELAY

; skip 3 bytes
        jsr INC_PTR
        jsr INC_PTR
        jsr INC_PTR

        jmp NEXT_CMD

; =========================================================
; COMMAND: WAIT N SAMPLES
; =========================================================

CMD_WAIT:
        ;lda #'W'
        ;jsr print_char
        ldy #1
        lda (PTR_LO),Y
        sta WAIT_LO

        iny
        lda (PTR_LO),Y
        sta WAIT_HI

        jsr WAIT_ROUTINE

; skip command + 2 bytes
        jsr INC_PTR
        jsr INC_PTR
        jsr INC_PTR

        jmp NEXT_CMD

; =========================================================
; COMMAND: SHORT WAIT
; =========================================================

CMD_WAIT_SHORT:
        ;lda #'s'
        ;jsr print_char
        sec
        sbc #$70          ; opcode 0x70..0x7F -> 0..15
        clc
        adc #1            ; convert to 1..16 samples
        sta WAIT_LO

        lda #0
        sta WAIT_HI

        jsr WAIT_ROUTINE

        jsr INC_PTR

        jmp NEXT_CMD

; =========================================================
; WAIT 735
; =========================================================

CMD_WAIT_60HZ:

        ;lda #'6'
        ;jsr print_char
        lda #<735
        sta WAIT_LO

        lda #>735
        sta WAIT_HI

        jsr WAIT_ROUTINE

        jsr INC_PTR

        jmp NEXT_CMD

; =========================================================
; WAIT 882
; =========================================================

CMD_WAIT_50HZ:

        ;lda #'5'
        ;jsr print_char
        lda #<882
        sta WAIT_LO

        lda #>882
        sta WAIT_HI

        jsr WAIT_ROUTINE

        jsr INC_PTR

        jmp NEXT_CMD

; =========================================================
; END
; =========================================================

CMD_END:
        lda LOOP_ENABLED
        beq CMD_END_NO_LOOP
        lda #<end_str_loop
        ldy #>end_str_loop
        jsr bios_print_string  
        lda LOOP_PTR_LO
        sta PTR_LO
        lda LOOP_PTR_HI
        sta PTR_HI
        jmp NEXT_CMD

CMD_END_NO_LOOP:
        lda #<end_str
        ldy #>end_str
        jsr bios_print_string  
        jmp START

; =========================================================
; INCREMENT POINTER
; =========================================================

INC_PTR:

        inc PTR_LO
        bne done

        inc PTR_HI

done:
        rts

; =========================================================
; OPL SHORT DELAY
; =========================================================

; YM3812 potrzebuje krótkich opóźnień

OPL_DELAY:

        ldx #20
loop:
        dex
        bne loop

        rts

; =========================================================
; WAIT ROUTINE
; =========================================================

; To NIE jest dokładny timing VGM.
; To tylko proste opóźnienie zależne od samples.

WAIT_ROUTINE:

outer:

        ldx #30

inner:
        dex
        bne inner

        sec
        lda WAIT_LO
        sbc #1
        sta WAIT_LO

        lda WAIT_HI
        sbc #0
        sta WAIT_HI

        lda WAIT_LO
        ora WAIT_HI
        bne outer

        rts

baner_str: .byte "Playing file: ",$0
usage_str: .byte $0D,$0A,"Usage: VGM_PLAY <FILE.VGM>",$0D,$0A,$0
end_str: .byte $0D,$0A,"End of file. Playing from the beginning.",$0D,$0A,$0
end_str_loop: .byte $0D,$0A,"End of file. Offset jump.",$0D,$0A,$0

; =========================================================
; VGM DATA, that will be loaded into memory and played by the program. 
; =========================================================

VGM_DATA:

    ;.incbin "vgm/James Lord Pierpont - Jingle Bells.vgm"
    ;.incbin "vgm/Leisure Suit Larry - Theme.vgm"
    ;.incbin "vgm/Mission Impossible - Theme.vgm"    
    ;.incbin "vgm/Star Wars - Main Title.vgm"
    ;'.incbin "vgm/001 Highways.vgm"
    ;.incbin "vgm/Twin Cobra - Break A Leg! (Stage 1, 6).vgm"
    ;.incbin "vgm/Indiana Jones.vgm"
    ;.incbin "vgm/Simon & Garfunkel - The Sound of Silence.vgm"

