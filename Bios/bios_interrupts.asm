.segment "KERNAL"
; check_via1_irq - sprawdza IFR VIA1 i wywołuje handler dla CA1 (keyboard_interrupt)
; Zachowuje rejestry: A, X, Y (przydatne gdy wywoływane w przerwaniu).
; Nie czyści IFR/IER — zrób to w handlerach jeśli potrzebne.

check_via1_irq:
	; --------- zachowaj A, X, Y na stosie ---------
	php
	pha                 ; push A

	; --- sprawdź CA2 (bit0) ---
	lda VIA1_IFR
	and #%00000001      ; maska bit0 = CA2
	beq chk_ca1
	; --- odkomentuj jeśli potrzebujesz ---
	; po handlerze możemy chcieć czyścić IFR/IER — tu zostawiamy to Tobie
	;jmp restore_regs   ; po obsłudze wracamy (przywracamy rejestry)

chk_ca1:
	lda VIA1_IFR
	and #%00000010      ; bit1 = CA1
	beq chk_sr
	jsr keyboard_interrupt
	lda #%00000010      ; acknowledge CA1 IRQ flag in VIA IFR
	sta VIA1_IFR
	jmp restore_regs

chk_sr:
	lda VIA1_IFR
	and #%00000100      ; bit2 = shift register
	beq chk_cb2
	; --- odkomentuj jeśli potrzebujesz ---
	; jsr cb1_interrupt_handler
	; jmp .restore_regs

chk_cb2:
	lda VIA1_IFR
	and #%00001000      ; bit3 = CB2
	beq chk_cb1
	; --- odkomentuj jeśli potrzebujesz ---
	; jsr cb2_interrupt_handler
	; jmp .restore_regs

chk_cb1:
	lda VIA1_IFR
	and #%00010000      ; bit4 = CB1
	beq chk_t2
	; --- odkomentuj jeśli potrzebujesz ---
	;jsr loader_isr
	;jmp restore_regs

chk_t2:
	lda VIA1_IFR
	and #%00100000      ; bit5 = Timer2
	beq chk_t1
	; --- odkomentuj jeśli potrzebujesz ---
	; jsr timer1_interrupt_handler
	; jmp .restore_regs

chk_t1:
	lda VIA1_IFR
	and #%01000000      ; bit6 = Timer1
	beq no_via1_irq
	; --- odkomentuj jeśli potrzebujesz ---
	; jsr timer2_interrupt_handler
	; jmp .restore_regs

no_via1_irq:
	; brak rozpoznanego/obsłużonego źródła u VIA1
	; (możesz tu dodać logowanie, czyszczenie flag lub inne działania)

restore_regs:
	pla                 ; przywróć A
	plp	
	;rti                 
	rts

; ===== przykładowe miejsca dla handlerów (zakomentowane) =====
; keyboard_interrupt:
;    ; obsługa CA1 (np. klawiatura)
;    rts
;
; ca2_interrupt_handler:
;    rts
;
; cb1_interrupt_handler:
;    rts
;
; cb2_interrupt_handler:
;    rts
;
; shift_interrupt_handler:
;    rts
;
; timer1_interrupt_handler:
;    rts
;
; timer2_interrupt_handler:
;    rts

; =====================================================
; irq_handler – wspólny IRQ dla VIA + ACIA
; =====================================================
irq_handler:
    pha
    phx
    phy

; -----------------------------------------------------
; 1. Sprawdź ACIA
; -----------------------------------------------------
    lda ACIA1_STATUS
    and #%10000000        ; bit7 = IRQ flag
    beq chk_via1
    ;jmp acia_irq          ; bit7=1 → IRQ z ACIA
	jmp (bios_vectors_acia1_irq) ; skok do wektora ACIA IRQ

; -----------------------------------------------------
; 2. Sprawdź VIA
; -----------------------------------------------------
chk_via1:
    lda VIA1_IFR
    and #%01111111        ; ignoruj bit7 (global IRQ)
    beq irq_done          ; brak źródła → wyjście
    jsr check_via1_irq    ; Twoja istniejąca logika VIA
    jmp irq_done

; -----------------------------------------------------
; ACIA IRQ
; -----------------------------------------------------
acia_irq:
    lda ACIA1_STATUS

    ; --- RX interrupt ---
    and #%00001000        ; bit3 = RX full
    beq chk_tx
    jsr acia_rx_handler ; <<< TU DOPISZESZ
    jmp irq_done

chk_tx:
    lda ACIA1_STATUS
    and #%00010000        ; bit4 = TX empty
    beq chk_ctrl
    jsr acia_tx_handler ; <<< TU DOPISZESZ
    jmp irq_done

chk_ctrl:
    lda ACIA1_STATUS
    and #%01100000        ; DCD / CTS
    beq irq_done
    ; jsr acia_ctrl_handler ; <<< OPCJONALNE

; -----------------------------------------------------
irq_done:
    ply
    plx
    pla
    rti

acia_rx_handler:
	lda ACIA1_DATA         	; read char from ACIA
	pha
	jsr kb_buffer_size
	cmp #KB_BUFFER_CAPACITY
	bcs discard_acia_char
	lda kb_wptr
	and #KB_BUFFER_MASK
	tax
	pla
	sta kb_buffer, x
	inc kb_wptr
	jsr kb_buffer_size
	cmp #KB_BUFFER_CAPACITY
	bcc not_full
buffer_full:
	lda ACIA1_CMD
  	;and #%11111110          ; skasuj bit DTR
	and #%11110111          ; skasuj bit DTR
  	sta ACIA1_CMD	
not_full:	
	rts

discard_acia_char:
	pla
	jmp buffer_full

acia_tx_handler:
	rts


nmi:
	; obsługa NMI (jeśli potrzebna)
	lda VIA1_PORTB
	EOR #$FF
	sta VIA1_PORTB 	
	rti