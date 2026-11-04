.segment "KERNAL"

; =====================================================
; irq_handler – wspólny IRQ wszystkich urządzeń
; =====================================================
irq_handler:
    pha
    phx
    phy

; -----------------------------------------------------
; 1. Sprawdź ACIA (jest najszybsza)
; -----------------------------------------------------
    lda ACIA1_STATUS
    and #%10000000        ; bit7 = IRQ flag
    beq chk_mega_console
    ;jmp acia_irq          ; bit7=1 → IRQ z ACIA
	jmp (bios_vectors_acia1_irq) ; skok do wektora ACIA IRQ

; -----------------------------------------------------
; 2. Sprawdź Mega console
; -----------------------------------------------------
chk_mega_console:
    lda SYS_CTRL_STAT
    and #%00000001        ; bit0 = Keyboard IRQ flag
    beq irq_done          ; brak źródła → wyjście
    jsr mega_console_keyboard_irq
    jmp irq_done

irq_done:
    ply
    plx
    pla
    rti

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
    jmp irq_done

; -----------------------------------------------------


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
	rti