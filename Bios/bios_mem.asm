; ---------------------------------------------------------
; KOD POST BIOS
; ---------------------------------------------------------
;.segment "BIOS_VECTORS" ; $0200


.segment "KERNAL"

post_mem_test:
        php                 ; Zachowaj stan przerwań przed destrukcyjnym testem RAM
        sei

        ; Inicjalizacja bajtu konfiguracji na 0
        stz bios_mem_config

        ; Wyświetlenie prefiksu na ekranie POST
        lda #<msg_post_prefix
        ldy #>msg_post_prefix
        jsr print_str

        ; -------------------------------------------------
        ; 1. TEST RAM PODSTAWOWEGO ($0300 - $7FFF)
        ; (Pomięcie strony zerowej, stosu i wektorów BIOS-u)
        ; -------------------------------------------------
        lda #$00
        sta Z0
        lda #$03            ; Start od strony $03 (omijamy stronę zerową, stos i wektory systemu)
        sta Z1

        lda #$80            ; Koniec na stronie $80 ($7FFF)
        jsr test_ram_range

        lda Z4              ; pass_flag
        beq @base_ok

        ; Błąd RAM podstawowego
        lda #<msg_fail
        ldy #>msg_fail
        jsr print_str
        plp
        rts

@base_ok:
        lda #<msg_base_ok
        ldy #>msg_base_ok
        jsr print_str

        ; -------------------------------------------------
        ; 2. DETEKCJA KARTY SHADOW RAM
        ; -------------------------------------------------
        stz MEM_CARD_PORT        ; Włącz ROM

        lda $8000
        sta Z2              ; Zapamiętaj bajt z ROM

        lda #$80            ; Włącz Bank 0
        sta MEM_CARD_PORT

        lda Z2
        eor #$FF
        sta $8000           ; Zapisz zanegowany bajt do RAM

        stz MEM_CARD_PORT        ; Wyłącz RAM (ROM)

        lda $8000           ; Sprawdź czy ROM się NIE zmienił
        cmp Z2
        bne @no_card

        lda #$80            ; Sprawdź czy RAM zachował wartość
        sta MEM_CARD_PORT
        lda $8000
        eor Z2
        cmp #$FF
        bne @no_card

        ; Karta wykryta -> ustaw Bit 7 w bios_mem_config
        lda #$80
        sta bios_mem_config
        bra @detect_banks

@no_card:
        stz MEM_CARD_PORT
        lda #<msg_no_card
        ldy #>msg_no_card
        jsr print_str
        plp
        rts

        ; -------------------------------------------------
        ; 3. LICZENIE BANKÓW (Max 128: $80..$FF)
        ; -------------------------------------------------
@detect_banks:
        lda #$80            ; Sygnatura Banku 0
        sta MEM_CARD_PORT
        lda #$AA
        sta $8000

        lda #$01
        sta Z3              ; bank_cnt = 1

@bank_loop:
        lda Z3
        cmp #128            ; Max 128 banków
        beq @count_done

        ora #$80            ; Włącz sprawdzany bank ($80 + Z3)
        sta MEM_CARD_PORT

        lda Z3
        sta $8000           ; Zapisz znacznik w sprawdzanym banku

        lda #$80            ; Wróć do Banku 0
        sta MEM_CARD_PORT
        lda $8000
        cmp #$AA            ; Sprawdź nadpisanie (aliasing)
        bne @count_done

        inc Z3              ; bank_cnt++
        bra @bank_loop

@count_done:
        ; Dołącz liczbę banków do najmłodszych 7 bitów bios_mem_config
        lda bios_mem_config
        ora Z3
        sta bios_mem_config

        ; Wyświetl informację o liczbie banków i pojemności KB
        lda Z3
        jsr print_dec3

        lda #<msg_banks
        ldy #>msg_banks
        jsr print_str

        ; Przeliczenie banków na KB (bank_cnt * 16)
        lda Z3
        sta Z0
        stz Z1
        asl Z0
        rol Z1
        asl Z0
        rol Z1
        asl Z0
        rol Z1
        asl Z0
        rol Z1              ; Z0:Z1 = KB
        
        lda Z0
        sta Z3              ; Ustawienie pod test/wydruk
        lda Z1
        sta Z4
        jsr print_dec4

        lda #<msg_kb
        ldy #>msg_kb
        jsr print_str

        ; -------------------------------------------------
        ; 4. TEST PAMIĘCI SHADOW RAM ($8000 - $BFFF)
        ; -------------------------------------------------
        stz Z4              ; pass_flag = 0
        ldx #$00            ; Indeks banku

@test_shadow_loop:
        lda bios_mem_config
        and #$7F
        sta Z2              ; Tymczasowo przechowywana liczba banków
        cpx Z2
        beq @shadow_done

        txa
        ora #$80
        sta MEM_CARD_PORT        ; Przełącz bank

        stz Z0              ; Adres startowy $8000
        lda #$80
        sta Z1

        phx
        lda #$C0            ; Test do strony $BFFF (koniec przed $C0)
        jsr test_ram_range
        plx

        lda Z4              ; Jeśli wykryto błąd, natychmiast przerwij
        bne @shadow_done

        inx
        bra @test_shadow_loop

@shadow_done:
        stz MEM_CARD_PORT        ; Przywróć ROM

        lda Z4
        beq @shadow_ok

        lda #<msg_fail
        ldy #>msg_fail
        jsr print_str
        plp
        rts

@shadow_ok:
        lda #<msg_ok
        ldy #>msg_ok
        jsr print_str
        plp
        rts

; ---------------------------------------------------------
; PROCEDURY POMOCNICZE
; ---------------------------------------------------------

; Testuje obszar RAM od [Z0:Z1] do strony w rejestrze A
test_ram_range:
        sta Z5              ; Strona końcowa
        stz Z4              ; pass_flag = 0
        lda Z1
        sta Z3              ; Zachowaj stronę początkową

        lda #$55
        jsr fill_and_verify
        bcc @check_aa

        inc Z4
        rts

@check_aa:
        lda Z3
        sta Z1              ; Drugi wzorzec testuje ten sam zakres
        lda #$AA
        jsr fill_and_verify
        bcc @test_ok

        inc Z4
@test_ok:
        jsr spinner_update
        rts

fill_and_verify:
        sta Z2              ; Wzorzec testowy
        ldy #$00

@fill_loop:
        lda Z2
        sta (Z0),y
        lda (Z0),y
        cmp Z2
        bne @verify_fail

        iny
        bne @fill_loop

        inc Z1              ; Kolejna strona
        lda Z1
        cmp Z5              ; Czy osiągnięto stronę docelową?
        bne @fill_loop

        clc
        rts

@verify_fail:
        sec
        rts

; ---------------------------------------------------------
; PROCEDURY FORMATOWANIA TEKSTU
; ---------------------------------------------------------

print_dec3:
        stz Z5              ; Setki
@div100:
        cmp #100
        bcc @div10_prep
        sec
        sbc #100
        inc Z5
        bra @div100

@div10_prep:
        stz Z2              ; Dziesiątki
@div10:
        cmp #10
        bcc @print
        sec
        sbc #10
        inc Z2
        bra @div10

@print:
        pha
        lda Z5
        beq @skip_hundreds  ; Pomijaj wygaszone zero setek
        ora #'0'
        jsr print_char
@skip_hundreds:
        lda Z2
        ora #'0'
        jsr print_char
        pla
        ora #'0'
        jsr print_char
        rts

print_dec4:
        stz Z5              ; Tysiące
@div1000:
        lda Z4              ; High byte
        cmp #$03
        bcc @div100_prep
        bne @sub1000
        lda Z3              ; Low byte
        cmp #$E8
        bcc @div100_prep
@sub1000:
        sec
        lda Z3
        sbc #$E8
        sta Z3
        lda Z4
        sbc #$03
        sta Z4
        inc Z5
        bra @div1000

@div100_prep:
        phx
        ldx #$00            ; Setki
@div100:
        lda Z4
        bne @sub100
        lda Z3
        cmp #100
        bcc @div10_prep_4
@sub100:
        sec
        lda Z3
        sbc #100
        sta Z3
        lda Z4
        sbc #$00
        sta Z4
        inx
        bra @div100

@div10_prep_4:
        ldy #$00            ; Dziesiątki
@div10_4:
        lda Z3
        cmp #10
        bcc @print_4
        sec
        sbc #10
        sta Z3
        iny
        bra @div10_4

@print_4:
        lda Z5
        beq @skip_th
        ora #'0'
        jsr print_char
@skip_th:
        txa
        ora #'0'
        jsr print_char
        tya
        ora #'0'
        jsr print_char
        lda Z3
        ora #'0'
        jsr print_char
        plx
        rts
