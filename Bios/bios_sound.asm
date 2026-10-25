; Kanał lewy — pierwszy pin jacka
DAC_LEFT_1  = SOUND_CARD_PORT + 1
DAC_LEFT_2  = SOUND_CARD_PORT + 2

; Kanał prawy — drugi pin jacka
DAC_RIGHT_1 = SOUND_CARD_PORT + 0
DAC_RIGHT_2 = SOUND_CARD_PORT + 3

; Rejestry OPL (Yamaha YM3812) — adres i dane
OPL_ADDR = SOUND_CARD_PORT + 8
OPL_DATA = SOUND_CARD_PORT + 9

init_sound_card:
    ; reset DAC data
    lda #$80
    sta DAC_LEFT_1  
    sta DAC_LEFT_2
    sta DAC_RIGHT_1
    sta DAC_RIGHT_2
    jsr opl_startup_chime
    rts

; ============================================================
; OPL2 WRITE
;
; A = numer rejestru
; X = wartość
;
; Przyjmujemy, że dostęp do OPL odbywa się przy 2 MHz.
;
; YM3812:
;   po adresie  >= ~3.3 us
;   po danych   >= ~23 us
;
; 6502 @ 2 MHz:
;   1 cykl = 0.5 us
;
; dlatego:
;   adres -> 8 cykli
;   dane   -> 46 cykli
;
; ============================================================

opl_write:
    sta OPL_ADDR

    ; ----------------------------------------------------
    ; ~8 cykli
    ; ----------------------------------------------------

    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2


    stx OPL_DATA

    ; ----------------------------------------------------
    ; ~46 cykli
    ;
    ; 23 x NOP = 46 cykli
    ; ----------------------------------------------------

    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2
    nop             ; 2

    rts


; ============================================================
; ERROR SOUND
; ============================================================

opl_error_gong:

    ; ----------------------------------------------------
    ; Najpierw wyłączamy kanał 0.
    ;
    ; B0 bit 5 = KEY ON
    ;
    ; ----------------------------------------------------

    lda #$B0
    ldx #$00
    jsr opl_write


    ; ====================================================
    ; MODULATOR
    ; ====================================================

    ; ----------------------------------------------------
    ; $20
    ;
    ; AM   = 0
    ; VIB  = 0
    ; EGT  = 0  <-- BARDZO WAŻNE
    ; KSR  = 0
    ; MULT = 2
    ;
    ; 00000010
    ; ----------------------------------------------------

    lda #$20
    ldx #$02
    jsr opl_write


    ; ----------------------------------------------------
    ; $40
    ;
    ; KSL = 0
    ; TL  = 24
    ;
    ; Modulator nie jest zbyt mocny.
    ; ----------------------------------------------------

    lda #$40
    ldx #$18
    jsr opl_write


    ; ----------------------------------------------------
    ; $60
    ;
    ; AR = 15  szybki attack
    ; DR = 5   powolniejszy decay
    ;
    ; ----------------------------------------------------

    lda #$60
    ldx #$F5
    jsr opl_write


    ; ----------------------------------------------------
    ; $80
    ;
    ; SL = 15
    ; RR = 8
    ;
    ; Przy EGT=0 obwiednia nie zatrzyma się na sustain.
    ; ----------------------------------------------------

    lda #$80
    ldx #$F8
    jsr opl_write


    ; ----------------------------------------------------
    ; $E0
    ;
    ; waveform = 0 = sine
    ; ----------------------------------------------------

    lda #$E0
    ldx #$00
    jsr opl_write


    ; ====================================================
    ; CARRIER
    ; ====================================================

    ; ----------------------------------------------------
    ; $23
    ;
    ; EGT = 0
    ; MULT = 1
    ;
    ; ----------------------------------------------------

    lda #$23
    ldx #$01
    jsr opl_write


    ; ----------------------------------------------------
    ; $43
    ;
    ; KSL = 0
    ; TL = 0
    ;
    ; carrier pełna głośność
    ; ----------------------------------------------------

    lda #$43
    ldx #$00
    jsr opl_write


    ; ----------------------------------------------------
    ; $63
    ;
    ; AR = 15
    ; DR = 5
    ; ----------------------------------------------------

    lda #$63
    ldx #$F5
    jsr opl_write


    ; ----------------------------------------------------
    ; $83
    ;
    ; SL = 15
    ; RR = 8
    ;
    ; EGT jest ustawione w $23 = 0
    ; więc dźwięk sam zejdzie do zera.
    ; ----------------------------------------------------

    lda #$83
    ldx #$F8
    jsr opl_write


    ; ----------------------------------------------------
    ; $E3
    ;
    ; waveform = sine
    ; ----------------------------------------------------

    lda #$E3
    ldx #$00
    jsr opl_write


    ; ====================================================
    ; CHANNEL 0
    ; ====================================================

    ; ----------------------------------------------------
    ; $C0
    ;
    ; FB = 3
    ; C  = 0 -> FM
    ;
    ; Trochę feedbacku daje bardziej "gongowe"
    ; brzmienie niż czysty sinus.
    ;
    ; ----------------------------------------------------

    lda #$C0
    ldx #$06
    jsr opl_write


    ; ----------------------------------------------------
    ; $A0
    ;
    ; F-NUMBER low 8 bitów
    ;
    ; FNUM = $240
    ; ----------------------------------------------------

    lda #$A0
    ldx #$40
    jsr opl_write


    ; ----------------------------------------------------
    ; $B0
    ;
    ; bit 5 = KEY ON
    ;
    ; BLOCK = 4
    ; FNUM high = 2
    ;
    ; %00110010 = $32
    ;
    ; ----------------------------------------------------

    lda #$B0
    ldx #$32
    jsr opl_write


    ; ----------------------------------------------------
    ; GOTOWE
    ;
    ; YM3812 właśnie rozpoczął generowanie dźwięku.
    ;
    ; Nie robimy KEY-OFF.
    ; Nie czekamy.
    ; Nie używamy IRQ.
    ; Nie używamy VIA.
    ;
    ; EGT=0 powoduje samoczynne wygaszenie obwiedni.
    ;
    ; ----------------------------------------------------

    rts

; ============================================================
; STARTUP CHIME
; ============================================================

opl_startup_chime:

    ; ----------------------------------------------------
    ; CHANNEL 0 - wyższy ton
    ; ----------------------------------------------------

    ; Modulator: MULT=2, EGT=0
    lda #$20
    ldx #$02
    jsr opl_write

    ; Modulator: poziom
    lda #$40
    ldx #$20
    jsr opl_write

    ; Modulator: szybki attack, średni decay
    lda #$60
    ldx #$F6
    jsr opl_write

    ; Modulator: sustain/release
    lda #$80
    ldx #$F9
    jsr opl_write

    ; Modulator: sinus
    lda #$E0
    ldx #$00
    jsr opl_write


    ; Carrier: MULT=1, EGT=0
    lda #$23
    ldx #$01
    jsr opl_write

    ; Carrier: głośność
    lda #$43
    ldx #$04
    jsr opl_write

    ; Carrier: szybki attack, średni decay
    lda #$63
    ldx #$F6
    jsr opl_write

    ; Carrier: sustain/release
    lda #$83
    ldx #$F9
    jsr opl_write

    ; Carrier: sinus
    lda #$E3
    ldx #$00
    jsr opl_write

    ; Feedback
    lda #$C0
    ldx #$04
    jsr opl_write

    ; Częstotliwość CH0: FNUM=$1C0
    lda #$A0
    ldx #$C0
    jsr opl_write

    ; KEY-ON, BLOCK=4, FNUM high=1
    lda #$B0
    ldx #$31
    jsr opl_write


    ; ----------------------------------------------------
    ; CHANNEL 1 - niższy, cieplejszy ton
    ; ----------------------------------------------------

    ; Modulator: MULT=1, EGT=0
    lda #$21
    ldx #$01
    jsr opl_write

    ; Modulator: poziom
    lda #$41
    ldx #$24
    jsr opl_write

    ; Modulator: attack/decay
    lda #$61
    ldx #$F4
    jsr opl_write

    ; Modulator: sustain/release
    lda #$81
    ldx #$FA
    jsr opl_write

    ; Modulator: sinus
    lda #$E1
    ldx #$00
    jsr opl_write


    ; Carrier: MULT=1, EGT=0
    lda #$24
    ldx #$01
    jsr opl_write

    ; Carrier: nieco ciszej
    lda #$44
    ldx #$0C
    jsr opl_write

    ; Carrier: attack/decay
    lda #$64
    ldx #$F3
    jsr opl_write

    ; Carrier: sustain/release
    lda #$84
    ldx #$FA
    jsr opl_write

    ; Carrier: sinus
    lda #$E4
    ldx #$00
    jsr opl_write

    ; Feedback
    lda #$C1
    ldx #$03
    jsr opl_write

    ; Częstotliwość CH1: FNUM=$190
    lda #$A1
    ldx #$90
    jsr opl_write

    ; KEY-ON, BLOCK=4, FNUM high=1
    lda #$B1
    ldx #$31
    jsr opl_write


    ; ----------------------------------------------------
    ; Koniec - OPL2 generuje dźwięk samodzielnie.
    ; Nie potrzeba IRQ, VIA, timera ani KEY-OFF.
    ; ----------------------------------------------------
    rts