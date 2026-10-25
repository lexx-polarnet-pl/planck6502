SPINNER_START_CHAR = $EC        ; Pierwszy znak spinnera w foncie
SPINNER_FRAMES     = 4          ; Liczba klatek (zmień na 8 dla 8 znaków)

RTC_SEC   = MEGA_CONSOLE_PORT + $6   ; Sekundy (00-59, BCD)
RTC_MIN   = MEGA_CONSOLE_PORT + $7   ; Minuty (00-59, BCD)
RTC_HOUR  = MEGA_CONSOLE_PORT + $8   ; Godziny (00-23, BCD)
RTC_DAY   = MEGA_CONSOLE_PORT + $9   ; Dzień miesiąca (1-31, Binarnie)
RTC_MONTH = MEGA_CONSOLE_PORT + $A   ; Miesiąc (1-12, Binarnie)
RTC_YEAR  = MEGA_CONSOLE_PORT + $B   ; Rok (00-99, Binarnie)

.segment "BIOS_VECTORS"
spinner_state:     .res 1       ; Alokacja 1 bajtu na stan spinnera w RAM

.segment "KERNAL"

print_a_hex:
;---------------------------------------------------
; print_a_hex (wozmon version)
; Input:  A = value 0–255
; Output: prints hex (e.g. 00, 1A, FF)
; Destroys: A
; Requires: JSR print_char (A = ASCII, prints one char)
;---------------------------------------------------
	PHA                    ; Save A for LSD.
	LSR
	LSR
	LSR                    ; MSD to LSD position.
	LSR
	JSR     print_a_hex_2  ; Output hex digit.
	PLA                    ; Restore A.

print_a_hex_2:
	AND     #$0F           ; Mask LSD for hex print.
	ORA     #$30           ; Add "0".
	CMP     #$3A           ; Digit?
	BCC     print_a_hex_echo    ; Yes, output it.
	ADC     #$06           ; Add offset for letter.
print_a_hex_echo:
	jsr print_char	
	rts
				
;---------------------------------------------------
; print_a_decimal
; Input:  A = value 0–255
; Output: prints decimal (e.g. 0, 5, 42, 255)
; Destroys: A,X,Y
; Requires: JSR print_char (A = ASCII, prints one char)
;---------------------------------------------------

print_a_decimal:
    pha                 ; save original value
    lda #0
    sta Z1          ; clear temporary counters
    sta Z0

    pla
    tay                ; Y = number

;---- compute hundreds
hund_loop:
    cpy #100
    bcc got_hundreds
    iny                ; Y -= 100 (using INC/DEC trick)
    dey                ; nope this is incorrect: need real subtract
    ; Let's do real subtract:
hund_sub:
    cpy #100
    bcc got_hundreds
    sec
    tya
    sbc #100
    tay
    inc Z0
    bne hund_sub

got_hundreds:

;---- compute tens
ten_sub:
    cpy #10
    bcc got_tens
    sec
    tya
    sbc #10
    tay
    inc Z1
    bne ten_sub

got_tens:
    tya                 ; remainder = ones

;---- Now print digits
    lda Z0
    beq skip_hundreds
    clc
    adc #'0'
    jsr print_char

skip_hundreds:
    lda Z0
    bne print_tens     ; if hundreds>0, print tens even if zero
    lda Z1
    beq print_ones     ; no hundreds, tens=0 → skip tens

print_tens:
    lda Z1
    clc
    adc #'0'
    jsr print_char

print_ones:
    tya                ; ones
    clc
    adc #'0'
    jsr print_char
    rts

;---------------------------------------------------

; ==============================================================================
; PROCEDURA: spinner_update
; Adresowanie bezwzględne (Absolute) zamiast Zero Page.
; Modyfikuje: A, X (Rejestr Y pozostaje nienaruszony)
; ==============================================================================
.proc spinner_update
    ; 1. Wysyłamy BACKSPACE ($08), aby cofnąć kursor na pozycję spinnera
    lda #$08
    jsr print_char

    ; 2. Obliczamy kod znaku: SPINNER_START_CHAR + spinner_state
    ; Przyjmujemy adresowanie bezwzględne z pamięci RAM (BIOS_VECTORS)
    lda spinner_state
    clc
    adc #SPINNER_START_CHAR
    jsr print_char                ; Wypisujemy nowy znak (nadpisuje stary)

    ; 3. Inkrementacja stanu i zapętlenie (modulo SPINNER_FRAMES)
    ldx spinner_state
    inx
    cpx #SPINNER_FRAMES
    bcc @save_state             ; Jeśli X < SPINNER_FRAMES, przejdź do zapisu
    ldx #0                      ; Rezetujemy licznik do 0

@save_state:
    stx spinner_state           ; Absolute store (3 bajty, 4 cykle)
    rts
.endproc


; ==============================================================================
; MAIN ENTRY POINT: Display Full Date and Time
; ==============================================================================
display_date_time:
    ; Wyświetlenie etykiety daty
    LDA #<str_date_prefix
    LDY #>str_date_prefix
    JSR print_str

    ; Wyświetlenie daty 
    JSR print_date

    ; Wyświetlenie separatora
    LDA #<str_space
    LDY #>str_space
    JSR print_str

    ; Wyświetlenie etykiety czasu
    LDA #<str_time_prefix
    LDY #>str_time_prefix
    JSR print_str

    ; Wyświetlenie czasu (HH:MM:SS)
    JSR print_time

    RTS

; ==============================================================================
; SUBROUTINE: print_date
; Formatuje i wyświetla datę w formacie: YYYY-MM-DD (np. 2026-10-24)
; ==============================================================================
print_date:
    ; DZIEŃ (BCD 01-31)
    LDA RTC_DAY
    JSR print_bcd2

    LDA #'.'
    JSR print_char

    ; MIESIĄC (BCD 01-12)
    LDA RTC_MONTH
    JSR print_bcd2

    LDA #'.'
    JSR print_char

    ; Prefiks stulecia "20"
    LDA #'2'
    JSR print_char
    LDA #'0'
    JSR print_char

    ; ROK (BCD 00-99)
    LDA RTC_YEAR
    JSR print_bcd2

    RTS

; ==============================================================================
; SUBROUTINE: print_time
; Formatuje i wyświetla czas w formacie: HH:MM:SS (np. 14:30:00)
; ==============================================================================
print_time:
    ; GODZINY (BCD 00-23)
    LDA RTC_HOUR
    JSR print_bcd2

    LDA #':'
    JSR print_char

    ; MINUTY (BCD 00-59)
    LDA RTC_MIN
    JSR print_bcd2

    LDA #':'
    JSR print_char

    ; SEKUNDY (BCD 00-59)
    LDA RTC_SEC
    JSR print_bcd2

    RTS

; ==============================================================================
; HELPER: print_bcd2
; Drukuje dwucyfrową liczbę zapisaną w formacie BCD (0x00 - 0x99)
; ==============================================================================
print_bcd2:
    PHA                 ; Zapisz oryginalną wartość BCD na stosie
    LSR
    LSR
    LSR
    LSR                 ; Przesuń 4 bity w prawo -> wyciągnij cyfrę dziesiątek
    ORA #'0'            ; Konwersja cyfry na ASCII ('0'-'9')
    JSR print_char

    PLA                 ; Odzyskaj oryginalną wartość BCD
    AND #$0F            ; Maska na cyfrę jednostek (młodsze 4 bity)
    ORA #'0'            ; Konwersja cyfry na ASCII
    JSR print_char
    RTS