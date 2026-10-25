.setcpu "65C02"
; ---------------------------------------------------------
; ZERO PAGE
; ---------------------------------------------------------

.segment "ZEROPAGE"

ptr:        .res 2      ; Wskaźnik adresowania pośredniego (16-bit)
tmp_val:    .res 1      ; Zmienna pomocnicza do przechowania bajtu
range_start:.res 2      ; Początek testowanego zakresu
test_pattern: .res 1    ; Wzorzec używany podczas testu
bank_cnt:   .res 1      ; Liczba wykrytych banków RAM
pass_flag:  .res 1      ; Flaga błędu (0 = OK, >0 = Błąd)

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

CTRL_REG = $FFC0        ; Rejestr sterowania bankowaniem

START:
        jsr bios_clear_screen

        lda #<banner_str
        ldy #>banner_str
        jsr bios_print_string

        ; -------------------------------------------------
        ; 1. TEST RAM PODSTAWOWEGO ($1000 - $7FFF)
        ; (Pominiecie ZP, Stosu i bufora programu $0000-$09FF)
        ; -------------------------------------------------
        lda #<msg_base_ram
        ldy #>msg_base_ram
        jsr bios_print_string

        ; Ustawienie adresu startowego $0900
        lda #$00
        sta ptr
        lda #$10
        sta ptr+1

        lda #$80        ; Testujemy do adresu $7FFF (kończymy na stronie $80)
        jsr test_ram_range

        lda pass_flag
        bne @base_err

        lda #<msg_ok
        ldy #>msg_ok
        jsr bios_print_string
        jmp @check_card

@base_err:
        lda #<msg_fail
        ldy #>msg_fail
        jsr bios_print_string

        ; -------------------------------------------------
        ; 2. DETEKCJA OBECNOŚCI KARTY SHADOW RAM
        ; -------------------------------------------------
@check_card:
        lda #<msg_card_detect
        ldy #>msg_card_detect
        jsr bios_print_string

        ; Wyłącz rozszerzenie (włącz ROM)
        lda #$00
        sta CTRL_REG

        ; Odczytaj bajt z ROM pod $8000
        lda $8000
        sta tmp_val

        ; Włącz Bank 0 ($80)
        lda #$80
        sta CTRL_REG

        ; Zapisz inną wartość pod $8000
        lda tmp_val
        eor #$FF
        sta $8000

        ; Wyłącz RAM (włącz ROM)
        lda #$00
        sta CTRL_REG

        ; Sprawdź czy w ROM wartość się NIE zmieniła
        lda $8000
        cmp tmp_val
        bne @no_card

        ; Włącz ponownie Bank 0 i zobacz czy RAM zachował zapisaną wartość
        lda #$80
        sta CTRL_REG
        lda $8000
        eor tmp_val
        cmp #$FF
        bne @no_card

        ; Karta jest obecna
        lda #<msg_present
        ldy #>msg_present
        jsr bios_print_string
        jmp @detect_banks

@no_card:
        ; Przywróć stan ROM i zakończ
        lda #$00
        sta CTRL_REG
        lda #<msg_not_present
        ldy #>msg_not_present
        jsr bios_print_string
        rts

        ; -------------------------------------------------
        ; 3. LICZENIE Dostępnych BANKÓW (Max 128: $80..$FF)
        ; -------------------------------------------------
@detect_banks:
        lda #<msg_bank_count
        ldy #>msg_bank_count
        jsr bios_print_string

        ; Oznaczenie Banku 0 unikalną sygnaturą
        lda #$80
        sta CTRL_REG
        lda #$AA
        sta $8000

        lda #$01
        sta bank_cnt    ; Rozpoczynamy sprawdzanie od Banku 1

@bank_loop:
        lda bank_cnt
        cmp #128        ; Maksymalnie 128 banków
        beq @count_done

        ; Włącz sprawdzany bank: wartość = $80 + bank_cnt
        ora #$80
        sta CTRL_REG

        ; Zapisz inny znacznik w nowym banku
        lda bank_cnt
        sta $8000

        ; Przełącz na Bank 0 i sprawdź czy sygnatura pod $8000 przetrwała
        lda #$80
        sta CTRL_REG
        lda $8000
        cmp #$AA
        bne @count_done ; Jeśli $8000 się zmieniło, nastąpiło zawinięcie (aliasing)

        inc bank_cnt
        jmp @bank_loop

@count_done:
        ; Wyświetl liczbę banków
        lda bank_cnt
        sta range_start
        lda #$00
        sta range_start+1
        jsr print_dec3

        lda #<msg_banks_found
        ldy #>msg_banks_found
        jsr bios_print_string

        lda bank_cnt
        sta range_start
        lda #$00
        sta range_start+1
        asl range_start
        rol range_start+1
        asl range_start
        rol range_start+1
        asl range_start
        rol range_start+1
        asl range_start
        rol range_start+1
        jsr print_dec4

        ; -------------------------------------------------
        ; 4. TEST PAMIĘCI SHADOW RAM ($8000 - $BFFF)
        ; -------------------------------------------------
        lda #<msg_testing_shadow
        ldy #>msg_testing_shadow
        jsr bios_print_string

        lda #$00
        sta pass_flag
        ldx #$00        ; Indeks banku (0..bank_cnt-1)

@test_shadow_loop:
        cpx bank_cnt
        beq @shadow_done

        ; Przełącz na bank X
        txa
        ora #$80
        sta CTRL_REG

        ; Ustaw wskaźnik na start banku $8000
        lda #$00
        sta ptr
        lda #$80
        sta ptr+1

        phx             ; Zapamiętaj indeks banku na stosie
        lda #$C0        ; Testuj do adresu $BFFF (strona $C0)
        jsr test_ram_range
        plx

        inx
        jmp @test_shadow_loop

@shadow_done:
        ; Wyłącz RAM rozszerzony, przywróć ROM
        lda #$00
        sta CTRL_REG

        lda pass_flag
        bne @shadow_err

        lda #<msg_ok
        ldy #>msg_ok
        jsr bios_print_string
        rts

@shadow_err:
        lda #<msg_fail
        ldy #>msg_fail
        jsr bios_print_string
        rts

; ---------------------------------------------------------
; PROCEDURY POMOCNICZE
; ---------------------------------------------------------

; Testuje obszar RAM od adresu [ptr] do strony zawartej w A.
; Wynik: pass_flag = 0 (OK) lub 1 (FAIL)
test_ram_range:
        sta tmp_val     ; tmp_val = strona końcowa (high byte)
        lda ptr
        sta range_start
        lda ptr+1
        sta range_start+1
        lda #$00
        sta pass_flag

        ; Przebieg 1: Wzorzec $55
        lda #$55
        jsr fill_and_verify
        bcc @check_aa

        lda #$01
        sta pass_flag
        rts

@check_aa:
        ; Przebieg 2: Wzorzec $AA
        lda #$AA
        jsr fill_and_verify
        bcc @test_ok

        lda #$01
        sta pass_flag
        rts

@test_ok:
        rts

; Wypełnia obszar wzorcem w A i natychmiast go weryfikuje
fill_and_verify:
        sta test_pattern
        lda range_start
        sta ptr
        lda range_start+1
        sta ptr+1
        ldy #$00

@write_loop:
        lda test_pattern
        sta (ptr),y
        lda (ptr),y
        cmp test_pattern
        bne @verify_fail

        iny
        bne @write_loop

        inc ptr+1
        lda ptr+1
        cmp tmp_val
        bne @write_loop

        clc             ; Braki błędów (Carry flag cleared)
        rts

@verify_fail:
        sec             ; Wykryto błąd (Carry flag set)
        rts

; Drukuje liczbę 2-cyfrową w systemie dziesiętnym (dla A <= 99)
print_dec2:
        ldy #$00
@div10:
        cmp #10
        bcc @print_digits
        sbc #10
        iny
        bne @div10

@print_digits:
        pha             ; Zapisz jednostki
        tya             ; Dziesiątki do A
        ora #'0'
        jsr bios_print_char
        pla             ; Jednostki do A
        ora #'0'
        jsr bios_print_char
        rts

; Drukuje 16-bitową liczbę 3-cyfrową w systemie dziesiętnym (do 999)
print_dec3:
        lda #$00
        sta tmp_val
@div100:
        lda range_start+1
        bne @subtract100
        lda range_start
        cmp #100
        bcc @div10_start
@subtract100:
        sec
        lda range_start
        sbc #100
        sta range_start
        lda range_start+1
        sbc #$00
        sta range_start+1
        inc tmp_val
        jmp @div100

@div10_start:
        lda #$00
        sta test_pattern
@div10:
        lda range_start
        cmp #10
        bcc @print_digits
        sec
        sbc #10
        sta range_start
        inc test_pattern
        jmp @div10

@print_digits:
        lda tmp_val
        ora #'0'
        jsr bios_print_char
        lda test_pattern
        ora #'0'
        jsr bios_print_char
        lda range_start
        ora #'0'
        jsr bios_print_char
        rts

; Drukuje 16-bitową liczbę 4-cyfrową w systemie dziesiętnym (do 9999)
print_dec4:
        lda #$00
        sta pass_flag
@div1000:
        lda range_start+1
        cmp #$03
        bcc @div100
        bne @subtract1000
        lda range_start
        cmp #$E8
        bcc @div100
@subtract1000:
        sec
        lda range_start
        sbc #$E8
        sta range_start
        lda range_start+1
        sbc #$03
        sta range_start+1
        inc pass_flag
        jmp @div1000

@div100:
        lda #$00
        sta tmp_val
@div100_loop:
        lda range_start+1
        bne @subtract100
        lda range_start
        cmp #100
        bcc @div10_start
@subtract100:
        sec
        lda range_start
        sbc #100
        sta range_start
        lda range_start+1
        sbc #$00
        sta range_start+1
        inc tmp_val
        jmp @div100_loop

@div10_start:
        lda #$00
        sta test_pattern
@div10:
        lda range_start
        cmp #10
        bcc @print_digits
        sec
        sbc #10
        sta range_start
        inc test_pattern
        jmp @div10

@print_digits:
        lda pass_flag
        ora #'0'
        jsr bios_print_char
        lda tmp_val
        ora #'0'
        jsr bios_print_char
        lda test_pattern
        ora #'0'
        jsr bios_print_char
        lda range_start
        ora #'0'
        jsr bios_print_char
        rts

; ---------------------------------------------------------
; BIOS API
; ---------------------------------------------------------

.include "../bios_api.inc"

; ---------------------------------------------------------
; TEXT MESSAGES
; ---------------------------------------------------------

banner_str:
        .byte "=== TESTER PAMIECI RAM 6502 ===", $0D, $0A, $00

msg_base_ram:
        .byte "Test RAM podstawowego ($1000-$7FFF): ", $00

msg_card_detect:
        .byte "Detekcja karty Shadow RAM: ", $00

msg_present:
        .byte "OBECNA", $0D, $0A, $00

msg_not_present:
        .byte "BRAK KARTY", $0D, $0A, $00

msg_bank_count:
        .byte "Liczba wykrytych bankow: ", $00

msg_banks_found:
        .byte " bank(ow) (", $00

msg_testing_shadow:
        .byte " KB)", $0D, $0A, "Testowanie bankow Shadow RAM: ", $00

msg_ok:
        .byte "OK", $0D, $0A, $00

msg_fail:
        .byte "BLAD!", $0D, $0A, $00	