; =========================================================
; 6502 Compact Flash Diagnostic
; =========================================================
;
; Diagnostyka:
; - status interface
; - reset / ready
; - IDENTIFY DEVICE
; - READ SECTOR
; - dump pierwszego sektora
;
; Mapowanie:
;
; FFD0 DATA
; FFD1 ERROR / FEATURES
; FFD2 SECTOR COUNT
; FFD3 LBA0
; FFD4 LBA1
; FFD5 LBA2
; FFD6 DRIVE/HEAD
; FFD7 STATUS / COMMAND
;
;
; =========================================================
CF_BASE         = $FFB0
CF_DATA         = CF_BASE + 0
CF_ERROR        = CF_BASE + 1
CF_SECCNT       = CF_BASE + 2
CF_LBA0         = CF_BASE + 3
CF_LBA1         = CF_BASE + 4
CF_LBA2         = CF_BASE + 5
CF_DRIVE        = CF_BASE + 6
CF_STATUS       = CF_BASE + 7
CF_COMMAND      = CF_BASE + 7

.segment "ZEROPAGE"
PTR_LO:         .res 1
PTR_HI:         .res 1
TMP1:           .res 1
TMP2:           .res 1
TMP3:           .res 1
OFFSET_LO:      .res 1
OFFSET_HI:      .res 1
STATUS_TMP:     .res 1

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
; =========================================================
; START
; =========================================================

START:
        jsr bios_clear_screen
        lda #<title_str
        ldy #>title_str
        jsr bios_print_string

; =========================================================
; BASIC STATUS TEST
; =========================================================

        lda #<msg_status
        ldy #>msg_status
        jsr bios_print_string
        lda CF_STATUS
        jsr PRINT_HEX
        lda #$0D
        jsr bios_print_char
        lda #$0A
        jsr bios_print_char

; =========================================================
; WAIT READY
; =========================================================

        lda #<msg_wait
        ldy #>msg_wait
        jsr bios_print_string
        ldx #0

WAIT_READY:

        lda CF_STATUS
        sta STATUS_TMP
        jsr PRINT_HEX
        lda #' '
        jsr bios_print_char
        lda STATUS_TMP
        and #$C0
        cmp #$40
        beq READY_OK
        inx
        cpx #100
        bne WAIT_READY
        lda #<msg_timeout
        ldy #>msg_timeout
        jsr bios_print_string
        jmp ENDLESS

READY_OK:

        lda #<msg_ready_ok
        ldy #>msg_ready_ok
        jsr bios_print_string

; =========================================================
; SELECT DRIVE
; =========================================================

        lda #<msg_select
        ldy #>msg_select
        jsr bios_print_string
        lda #$E0
        sta CF_DRIVE

; 400ns delay

        lda CF_STATUS
        lda CF_STATUS
        lda CF_STATUS
        lda CF_STATUS
                    
        jsr PRINT_HEX
        lda #$0D
        jsr bios_print_char
        lda #$0A
        jsr bios_print_char

; =========================================================
; ENABLE 8-BIT DATA TRANSFERS
;
; ATA SET FEATURES (EFh), feature 01h.
; This is supported only by CF cards that implement 8-bit PIO.
; =========================================================

        lda #<msg_features
        ldy #>msg_features
        jsr bios_print_string
        lda #$01
        sta CF_ERROR          ; FEATURES register

        lda #$EF
        sta CF_COMMAND        ; SET FEATURES

        lda #0
        sta TMP1
        ldx #0
        ldy #0

WAIT_FEATURES:
        lda CF_STATUS
        and #$80              ; BSY set?
        beq CHECK_FEATURES

        inx
        bne WAIT_FEATURES
        iny
        bne WAIT_FEATURES
        inc TMP1
        lda TMP1
        cmp #8
        bne WAIT_FEATURES

        lda #<msg_timeout
        ldy #>msg_timeout
        jsr bios_print_string
        jmp ENDLESS

CHECK_FEATURES:
        lda CF_STATUS
        and #$01              ; ERR set?
        beq FEATURES_OK

        lda #<msg_features_error
        ldy #>msg_features_error
        jsr bios_print_string
        lda CF_ERROR
        jsr PRINT_HEX
        jmp ENDLESS

FEATURES_OK:

; =========================================================
; IDENTIFY DEVICE
; =========================================================

        lda #<msg_identify
        ldy #>msg_identify
        jsr bios_print_string
        lda #$EC
        sta CF_COMMAND
        ldx #0

WAIT_IDENTIFY:
        lda CF_STATUS
        sta STATUS_TMP
        jsr PRINT_HEX
        lda #' '
        jsr bios_print_char
        lda STATUS_TMP
        and #$88
        cmp #$08
        beq IDENTIFY_OK
        lda STATUS_TMP
        and #$01
        bne IDENTIFY_ERROR
        inx
        cpx #100
        bne WAIT_IDENTIFY
        lda #<msg_timeout
        ldy #>msg_timeout
        jsr bios_print_string
        jmp ENDLESS

IDENTIFY_ERROR:

        lda #<msg_identify_error
        ldy #>msg_identify_error
        jsr bios_print_string
        lda CF_ERROR
        jsr PRINT_HEX
        jmp ENDLESS

IDENTIFY_OK:

        lda #<msg_identify_ok
        ldy #>msg_identify_ok
        jsr bios_print_string

; =========================================================
; READ IDENTIFY DATA
; =========================================================

        lda #<SECTOR_BUFFER
        sta PTR_LO
        lda #>SECTOR_BUFFER
        sta PTR_HI
        ldx #2

READ_IDENTIFY_PAGE:

        ldy #0

READ_IDENTIFY_LOOP:

        lda CF_DATA
        sta (PTR_LO),Y
        iny
        bne READ_IDENTIFY_LOOP
        inc PTR_HI
        dex
        bne READ_IDENTIFY_PAGE
        lda #<msg_identify_done
        ldy #>msg_identify_done
        jsr bios_print_string

; =========================================================
; READ SECTOR 0
; =========================================================

        lda #<msg_read
        ldy #>msg_read
        jsr bios_print_string

        lda #0
        sta TMP1
        ldx #0
        ldy #0

WAIT_READY2:

        lda CF_STATUS
        and #$C0
        cmp #$40
        beq READ_READY2
        inx
        bne WAIT_READY2
        iny
        bne WAIT_READY2
        inc TMP1
        lda TMP1
        cmp #8
        bne WAIT_READY2
        lda #<msg_timeout
        ldy #>msg_timeout
        jsr bios_print_string
        jmp ENDLESS

READ_READY2:
        lda #1
        sta CF_SECCNT
        lda #0
        sta CF_LBA0
        sta CF_LBA1
        sta CF_LBA2
        lda #$E0
        sta CF_DRIVE
        lda CF_STATUS
        lda CF_STATUS
        lda CF_STATUS
        lda CF_STATUS
        lda #$20
        sta CF_COMMAND
        ldx #0

WAIT_DRQ:

        lda CF_STATUS
        sta STATUS_TMP
        jsr PRINT_HEX
        lda #' '
        jsr bios_print_char
        lda STATUS_TMP
        and #$88
        cmp #$08
        beq DRQ_OK
        lda STATUS_TMP
        and #$01
        bne READ_ERROR
        inx
        cpx #100
        bne WAIT_DRQ
        lda #<msg_timeout
        ldy #>msg_timeout
        jsr bios_print_string
        jmp ENDLESS

READ_ERROR:

        lda #<msg_read_error
        ldy #>msg_read_error
        jsr bios_print_string
        lda CF_ERROR
        jsr PRINT_HEX
        jmp ENDLESS

DRQ_OK:

        lda #<msg_read_ok
        ldy #>msg_read_ok
        jsr bios_print_string

; =========================================================
; READ 512 BYTES
; =========================================================

        lda #<SECTOR_BUFFER
        sta PTR_LO
        lda #>SECTOR_BUFFER
        sta PTR_HI
        ldx #2

READ_PAGE:

        ldy #0

READ_LOOP:

        lda CF_DATA
        sta (PTR_LO),Y
        iny
        bne READ_LOOP
        inc PTR_HI
        dex
        bne READ_PAGE

; =========================================================
; DUMP SECTOR
; =========================================================

        lda #<dump_str
        ldy #>dump_str
        jsr bios_print_string
        lda #<SECTOR_BUFFER
        sta PTR_LO
        lda #>SECTOR_BUFFER
        sta PTR_HI
        lda #0
        sta OFFSET_LO
        sta OFFSET_HI
        ldx #32

NEXT_LINE:

; offset
        lda OFFSET_HI
        jsr PRINT_HEX
        lda OFFSET_LO
        jsr PRINT_HEX
        lda #':'
        jsr bios_print_char
        lda #' '
        jsr bios_print_char

; hex

        ldy #0

HEX_LOOP:

        lda (PTR_LO),Y
        jsr PRINT_HEX
        lda #' '
        jsr bios_print_char
        iny
        cpy #16
        bne HEX_LOOP

; gap

        lda #' '
        jsr bios_print_char
        lda #' '
        jsr bios_print_char

; ascii

        ldy #0

ASCII_LOOP:

        lda (PTR_LO),Y
        cmp #32
        bcc NOT_PRINTABLE
        cmp #127
        bcs NOT_PRINTABLE
        jsr bios_print_char
        jmp ASCII_NEXT

NOT_PRINTABLE:

        lda #'.'
        jsr bios_print_char

ASCII_NEXT:

        iny
        cpy #16
        bne ASCII_LOOP
        lda #$0D
        jsr bios_print_char
        lda #$0A
        jsr bios_print_char

; next line

        clc
        lda PTR_LO
        adc #16
        sta PTR_LO
        lda PTR_HI
        adc #0
        sta PTR_HI
        clc
        lda OFFSET_LO
        adc #16
        sta OFFSET_LO
        lda OFFSET_HI
        adc #0
        sta OFFSET_HI
        dex
        bne NEXT_LINE

; =========================================================

DONE:

        lda #<done_str
        ldy #>done_str
        jsr bios_print_string

ENDLESS:

        ; return to basic
        rts
        jmp ENDLESS

; =========================================================
; PRINT HEX
; =========================================================

PRINT_HEX:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr PRINT_NIBBLE
        pla
        and #$0F

PRINT_NIBBLE:
        cmp #10
        bcc DIGIT
        clc
        adc #'A' - 10
        jmp bios_print_char

DIGIT:
        clc
        adc #'0'
        jmp bios_print_char

; ---------------------------------------------------------
; BIOS API
; ---------------------------------------------------------

.include "../bios_api.inc"

; =========================================================
; STRINGS
; =========================================================

title_str:

.byte "6502 Compact Flash Diagnostic",$0D,$0A,$0D,$0A,$0

msg_status:

.byte "Initial status: ",0

msg_wait:

.byte "Waiting ready: ",0

msg_timeout:

.byte $0D,$0A,"TIMEOUT",$0D,$0A,0

msg_ready_ok:

.byte $0D,$0A,"READY OK",$0D,$0A,$0D,$0A,0

msg_select:

.byte "Selecting drive: ",0

msg_features:

.byte "SET FEATURES: ",0

msg_identify:

.byte $0D,$0A,"IDENTIFY DEVICE: ",0

msg_identify_ok:

.byte $0D,$0A,"IDENTIFY OK",$0D,$0A,0

msg_features_error:

.byte $0D,$0A,"SET FEATURES ERROR: ",0

msg_identify_error:

.byte $0D,$0A,"IDENTIFY ERROR: ",0

msg_identify_done:

.byte $0D,$0A,"IDENTIFY DATA READ",$0D,$0A,0

msg_read:

.byte $0D,$0A,"READ SECTOR 0: ",0

msg_read_ok:

.byte $0D,$0A,"READ OK",$0D,$0A,0

msg_read_error:

.byte $0D,$0A,"READ ERROR: ",0

dump_str:

.byte $0D,$0A,"SECTOR DUMP",$0D,$0A,$0D,$0A,0

done_str:

.byte $0D,$0A,"DONE",$0D,$0A,0

; =========================================================

; BUFFER

; =========================================================

SECTOR_BUFFER:

.res 512