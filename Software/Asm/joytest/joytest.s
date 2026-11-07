.setcpu "65C02"
; ---------------------------------------------------------
; ZERO PAGE
; ---------------------------------------------------------

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

; ---------------------------------------------------------
; CODE
; ---------------------------------------------------------

.segment "CODE"

START:
        jsr bios_clear_screen

        lda #<banner_str
        ldy #>banner_str
        jsr bios_print_string

        lda #<headers_str
        ldy #>headers_str
        jsr bios_print_string

; ---------------------------------------------------------
; MAIN LOOP
; ---------------------------------------------------------

MAIN_LOOP:

        lda $FFD0
        sta joy0

        lda $FFD1
        sta joy1

        ; JOYSTICK 0
        lda joy0
        sta temp

        lda #<pos_joy0
        ldy #>pos_joy0
        jsr bios_print_string

        stz joy_select
        jsr print_bits

        ; JOYSTICK 1
        lda joy1
        sta temp

        lda #<pos_joy1
        ldy #>pos_joy1
        jsr bios_print_string

        lda #1
        sta joy_select
        jsr print_bits

        bra MAIN_LOOP
        rts

; ---------------------------------------------------------
; PRINT BITS
; ---------------------------------------------------------

print_bits:

        lda #$80
        sta bit_mask

        lda #8
        sta bit_count

BIT_LOOP:

        lda temp
        and bit_mask
        beq BIT_ZERO

        lda #'1'
        bra BIT_OUTPUT

BIT_ZERO:
        lda #'0'

BIT_OUTPUT:
        jsr bios_print_char

        dec bit_count
        beq BITS_DONE

        lsr bit_mask

        jsr print_next_position

        bra BIT_LOOP

BITS_DONE:
        rts

; ---------------------------------------------------------
; PRINT NEXT POSITION
; ---------------------------------------------------------

print_next_position:

        lda joy_select
        beq JOY0_POSITION

        ; JOYSTICK 1
        lda bit_count
        cmp #7
        beq J1_R6
        cmp #6
        beq J1_R7
        cmp #5
        beq J1_R8
        cmp #4
        beq J1_R9
        cmp #3
        beq J1_R10
        cmp #2
        beq J1_R11
        bra J1_R12

JOY0_POSITION:
        lda bit_count
        cmp #7
        beq J0_R6
        cmp #6
        beq J0_R7
        cmp #5
        beq J0_R8
        cmp #4
        beq J0_R9
        cmp #3
        beq J0_R10
        cmp #2
        beq J0_R11
        bra J0_R12

; ---------------------------------------------------------
; JOYSTICK 0 POSITIONS
; ---------------------------------------------------------

J0_R6:
        lda #<p06
        ldy #>p06
        bra SEND_POSITION
J0_R7:
        lda #<p07
        ldy #>p07
        bra SEND_POSITION
J0_R8:
        lda #<p08
        ldy #>p08
        bra SEND_POSITION
J0_R9:
        lda #<p09
        ldy #>p09
        bra SEND_POSITION
J0_R10:
        lda #<p010
        ldy #>p010
        bra SEND_POSITION
J0_R11:
        lda #<p011
        ldy #>p011
        bra SEND_POSITION
J0_R12:
        lda #<p012
        ldy #>p012
        bra SEND_POSITION

; ---------------------------------------------------------
; JOYSTICK 1 POSITIONS
; ---------------------------------------------------------

J1_R6:
        lda #<p16
        ldy #>p16
        bra SEND_POSITION
J1_R7:
        lda #<p17
        ldy #>p17
        bra SEND_POSITION
J1_R8:
        lda #<p18
        ldy #>p18
        bra SEND_POSITION
J1_R9:
        lda #<p19
        ldy #>p19
        bra SEND_POSITION
J1_R10:
        lda #<p110
        ldy #>p110
        bra SEND_POSITION
J1_R11:
        lda #<p111
        ldy #>p111
        bra SEND_POSITION
J1_R12:
        lda #<p112
        ldy #>p112

SEND_POSITION:
        jmp bios_print_string

; ---------------------------------------------------------
; BIOS API
; ---------------------------------------------------------

.include "../bios_api.inc"

; ---------------------------------------------------------
; TEXT
; ---------------------------------------------------------

banner_str:
        .byte $1B,"[1;1H"
        .byte $1B,"[?25l"
        .byte "          JOYSTICK TEST"
        .byte $00

headers_str:
        .byte $1B,"[4;1H"
        .byte "PORT $FFD0"
        .byte $1B,"[4;40H"
        .byte "PORT $FFD1"
        .byte $00

pos_joy0:
        .byte $1B,"[5;12H",$00

pos_joy1:
        .byte $1B,"[5;51H",$00

; ---------------------------------------------------------
; ANSI POSITIONS
; ---------------------------------------------------------

p06:  .byte $1B,"[6;12H",0
p07:  .byte $1B,"[7;12H",0
p08:  .byte $1B,"[8;12H",0
p09:  .byte $1B,"[9;12H",0
p010: .byte $1B,"[10;12H",0
p011: .byte $1B,"[11;12H",0
p012: .byte $1B,"[12;12H",0

p16:  .byte $1B,"[6;51H",0
p17:  .byte $1B,"[7;51H",0
p18:  .byte $1B,"[8;51H",0
p19:  .byte $1B,"[9;51H",0
p110: .byte $1B,"[10;51H",0
p111: .byte $1B,"[11;51H",0
p112: .byte $1B,"[12;51H",0

joy0:       .byte 0
joy1:       .byte 0
temp:       .byte 0
bit_mask:   .byte 0
bit_count:  .byte 0
joy_select: .byte 0
