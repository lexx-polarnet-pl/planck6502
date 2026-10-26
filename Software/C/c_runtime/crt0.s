.export _start
.import __STARTUP__
.import _main
.import   __RAM_START__, __RAM_SIZE__       ; Linker generated
.import    copydata, zerobss, initlib, donelib

.include  "zeropage.inc"

.segment "ZEROPAGE"
; Upewnij się, że tmp1 i tmp2 są dostępne w zeropage.inc lub zadeklaruj komórki:
arg_count:  .res 1     ; Licznik argc (1 bajt wystarczy, max 255)

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

.segment "BSS"

MAX_ARGS = 16
argv_table: .res (MAX_ARGS + 1) * 2  ; Tablica wskaźników
empty_str:  .byte $00               ; Pusty string dla argv[0]

.segment "CODE"

.import pushax          ; Standardowa funkcja cc65 do wrzucania AX na stos sp
.import bios_get_param_buffer ; funkcja BIOS

_start:

; ---------------------------------------------------------------------------
; Set cc65 argument stack pointer

        LDA     #<(__RAM_START__ + __RAM_SIZE__)
        STA     c_sp
        LDA     #>(__RAM_START__ + __RAM_SIZE__)
        STA     c_sp+1

; ---------------------------------------------------------------------------
; Initialize memory storage

        JSR     zerobss              ; Clear BSS segment
        JSR     copydata             ; Initialize DATA segment
        JSR     initlib              ; Run constructors

; ---------------------------------------------------------------------------
; PARSER ARGUMENTÓW
; ---------------------------------------------------------------------------

        ; BIOS zwraca wskaźnik w A (LSB) i Y (MSB).
        JSR     bios_get_param_buffer
        STA     ptr1
        STY     ptr1+1

        ; 2. Ustawienie argv[0] = &empty_str
        LDA     #<empty_str
        STA     argv_table
        LDA     #>empty_str
        STA     argv_table+1

        LDA     #1
        STA     arg_count           ; argc = 1 (mamy argv[0])

        LDY     #0                  ; Indeks w buforze wejściowym (ptr1)

parse_loop:
        ; Pomijanie spacji
skip_spaces:
        LDA     (ptr1),Y
        BEQ     done_parsing        ; Kod 0 = koniec ciągu
        CMP     #' '
        BNE     found_arg
        INY
        JMP     skip_spaces

found_arg:
        ; Sprawdzenie limitu MAX_ARGS
        LDA     arg_count
        CMP     #MAX_ARGS
        BCS     done_parsing

        ; Zapisanie adresu początku argumentu: ptr1 + Y
        TYA
        CLC
        ADC     ptr1
        STA     tmp1
        LDA     ptr1+1
        ADC     #0
        STA     tmp2                ; tmp1/tmp2 = adres argumentu

        ; Wyliczenie offsetu w argv_table = arg_count * 2
        LDA     arg_count
        ASL A
        TAX                         ; X = offset w bajtach w argv_table

        LDA     tmp1
        STA     argv_table,X        ; LSB
        LDA     tmp2
        STA     argv_table+1,X      ; MSB

        INC     arg_count           ; argc++

; Szukanie końca słowa (spacja lub \0)
scan_arg_end:
        LDA     (ptr1),Y
        BEQ     done_parsing
        CMP     #' '
        BEQ     null_terminate
        INY
        JMP     scan_arg_end

null_terminate:
        ; Zamiana spacji na zerowy bajt terminator (\0)
        LDA     #$00
        STA     (ptr1),Y
        INY
        JMP     parse_loop

done_parsing:
        ; Wpisanie NULL na końcu tablicy argv[argc] = NULL
        LDA     arg_count
        ASL A
        TAX
        LDA     #$00
        STA     argv_table,X
        STA     argv_table+1,X

; ---------------------------------------------------------------------------
; WYWOŁANIE MAIN(ARGC, ARGV)
; ---------------------------------------------------------------------------

        ; cc65 układa argumenty od lewej do prawej. Najpierw argc, potem argv.
        LDA     arg_count
        LDX     #$00
        JSR     pushax

        ; Push argv (wskaźnik 16-bitowy) na stos cc65 (sp)
        LDA     #<argv_table
        LDX     #>argv_table
        JSR     pushax              ; cc65 zapisuje AX na sp

        ; Wywołanie C main(argc, argv)
        JSR     _main

        ; Destruktory / wyjście
        JSR     donelib

        RTS 						 ; Return to system

hang:
        JMP hang
