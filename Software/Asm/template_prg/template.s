.setcpu "65C02"
; ---------------------------------------------------------
; ZERO PAGE
; ---------------------------------------------------------

.segment "ZEROPAGE"

; zp variables here

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
		
        rts

; ---------------------------------------------------------
; BIOS API
; ---------------------------------------------------------

.include "../bios_api.inc"

; ---------------------------------------------------------
; TEXT MESSAGES
; ---------------------------------------------------------

banner_str:
        .byte "PROGRAM TEMPLATE",$0D,$0A,$00


