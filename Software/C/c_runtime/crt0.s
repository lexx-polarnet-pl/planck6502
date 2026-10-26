.export _start
.import __STARTUP__
.import _main
.import   __RAM_START__, __RAM_SIZE__       ; Linker generated
.import    copydata, zerobss, initlib, donelib

.include  "zeropage.inc"

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

_start:

; ---------------------------------------------------------------------------
; Set cc65 argument stack pointer

        LDA     #<(__RAM_START__ + __RAM_SIZE__)
        STA     sp
        LDA     #>(__RAM_START__ + __RAM_SIZE__)
        STA     sp+1

; ---------------------------------------------------------------------------
; Initialize memory storage

        JSR     zerobss              ; Clear BSS segment
        JSR     copydata             ; Initialize DATA segment
        JSR     initlib              ; Run constructors

        JSR 	_main

        RTS 						 ; Return to system

hang:
        JMP hang
