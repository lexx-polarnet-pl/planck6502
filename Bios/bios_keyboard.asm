KB_RELEASE 	= %00000001
KB_SHIFT   	= %00000010
KB_CAPS		= %00000100
KB_ALT		= %00001000
;KB_ALT_L	= %00010000
KB_CTRL		= %00100000
KB_BUFFER_MASK = $3F
KB_BUFFER_CAPACITY = $40
 
.segment "BIOS_VECTORS" ; $0200
kb_wptr: .res 1
kb_rptr: .res 1
kb_flags: .res 1

.segment "KERNAL"
init_keyboard:
	lda #%00000000 ; Set all pins on port A to input
	sta VIA1_DDRA

	lda #%11111111 ; clear any pending VIA interrupt flags before enabling CA1 IRQ
	sta VIA1_IFR
	lda #%10000010 ; enable interrupts on CA1
	sta VIA1_IER

  jsr clear_kb_buffer

  lda #KB_CAPS	; we start with caps-lock enabled
  sta kb_flags
  rts

clear_kb_buffer:
  lda #$00
  sta kb_wptr
  sta kb_rptr
  rts

get_key:
  LDA MEGA_CONSOLE_PORT      ; Pobierz bajt z bufora ATmegi

  ; --- 1. Filtrowanie: odrzuć wszystko >= $80 ---
  BMI return_zero         ; Jeśli bit 7 = 1 (bajt >= $80), skocz do zwrotu zera

  ; --- 2. Konwersja na UPPERCASE (tylko dla 'a'..'z') ---
  CMP #'a'                ; Czy znak jest mniejszy niż 'a' ($61)?
  BCC get_key_done        ; Jeśli < 'a' (kody sterujące, cyfry, symbole, 'A'-'Z') -> bez zmian
  CMP #'z' + 1            ; Czy znak jest większy niż 'z' ($7A)?
  BCS get_key_done        ; Jeśli > 'z' -> bez zmian

  AND #$DF                ; Zamiana 'a'..'z' na 'A'..'Z' (zerowanie bitu 5)
  RTS                     ; Zwróć przetworzony znak ASCII ($00..$7F)

return_zero:
  LDA #$00                ; Zwróć 0 dla znaków spoza podstawowego ASCII (>= $80)

get_key_done:
  RTS

get_key_via:
	php        ; save processor status FIRST
  phx
  sei
  lda kb_rptr
  cmp kb_wptr
  bne key_pressed
	lda #$00
	jmp return_from_get_key
key_pressed:
  lda kb_rptr
  and #KB_BUFFER_MASK
  tax
  lda kb_buffer, x
  inc kb_rptr
  pha
  jsr kb_buffer_size
	cmp #KB_BUFFER_CAPACITY
  bcs return_from_get_key
  lda ACIA1_CMD
  ora #%00001000          ; ustaw bit DTR
  sta ACIA1_CMD    
  pla
return_from_get_key:
  plx
  plp  
  rts

; przerwanie klawiatury
keyboard_interrupt:
  lda VIA1_PORTB
  EOR #$FF
  sta VIA1_PORTB 

  lda kb_flags
  and #KB_RELEASE   ; check if we're releasing a key
  beq read_key   ; otherwise, read the key

  lda kb_flags
  eor #KB_RELEASE   ; flip the releasing bit
  sta kb_flags
  lda VIA1_PORTA      ; read key value that's being released
  cmp #$12       ; left shift
  beq shift_up
  cmp #$59       ; right shift
  beq shift_up
	cmp #$14       			; ctrl (both)
	beq ctrl_up	
	cmp #$11       			; alt (both)
	beq alt_up		  
  jmp exit

shift_up:
  lda kb_flags
  eor #KB_SHIFT  ; flip the shift bit
  sta kb_flags
  jmp exit

alt_up:
	lda kb_flags
	eor #KB_ALT  			; flip the alt bit
	sta kb_flags
	jmp exit

ctrl_up:
	lda kb_flags
	eor #KB_CTRL  			; flip the ctrl bit
	sta kb_flags
	jmp exit

read_key:
  lda VIA1_PORTA
  cmp #$f0        ; if releasing a key
  bne :+
  jmp key_release ; set the releasing bit
:
  cmp #$12        ; left shift
  bne :+
  jmp shift_down
:
  cmp #$59        ; right shift
  bne :+
  jmp shift_down
:
	cmp #$14       			; ctrl (both)
	bne :+
	jmp ctrl_down
:
	cmp #$11       			; alt (both)
	bne :+
	jmp alt_down
:
	cmp #$58       			; caps lock
	bne :+
	jmp caps_down
:

  tax
  ; If Ctrl is held (or was pressed) and this scancode is 'C' ($21), return ASCII $03 (Ctrl-C)
	lda kb_flags
	and #KB_CTRL
	beq no_ctrl_check
	txa                     ; A = scancode (X was set by TAX)
	cmp #$21                ; scancode for 'c' key
	beq ctrl_c_found
no_ctrl_check:  
  lda kb_flags
  and #KB_SHIFT
  bne shifted_key

  lda keymap, x   ; map to character code
  jmp push_key

shifted_key:
  lda keymap_shifted, x   ; map to character code
  ;lda keymap, x   ; map to character code

push_key:
  ; sprawdz czy nie jest wcisniety caps lock
  pha             ; zachowaj oryginał
	lda kb_flags
  and #KB_CAPS
  beq not_letter_or_caps    ; jeśli caps nie wciśnięty -> przywróć i przejdz dalej

  pla             ; restore A do rejestru (teraz wykonamy test i ewentualne odwrócenie)
  pha             ; ponownie zapisz oryginał na stosie (jak w poprzedniej wersji)	
  and #$DF        ; A = uppercase wersja (czyli dla liter A-Z, dla innych zmienia się inaczej)
  cmp #'A'
  bcc not_letter_or_caps ; jeśli A < 'A' -> nie litera
  cmp #'Z'+1
  bcc is_letter_and_caps  ; jeśli A <= 'Z' -> litera

not_letter_or_caps:
  pla             ; przywróć oryginał
	jmp push_key_final

is_letter_and_caps:
  pla             ; przywróć oryginał (oryginalny ASCII, może być a..z lub A..Z)
  eor #$20        ; toggle bit 5 -> zamienia małe<->duże tylko dla liter
	jmp push_key_final	

ctrl_c_found:
	lda #$03
push_key_final:
  pha
  jsr kb_buffer_size
  cmp #KB_BUFFER_CAPACITY
  bcs key_buffer_full
  lda kb_wptr
  and #KB_BUFFER_MASK
  tax
  pla
  sta kb_buffer, x
  inc kb_wptr
  jmp exit
key_buffer_full:
  pla
  jmp exit

shift_down:
  lda kb_flags
  ora #KB_SHIFT
  sta kb_flags
  jmp exit

alt_down:
	lda kb_flags
	ora #KB_ALT
	sta kb_flags
	jmp exit

ctrl_down:
	lda kb_flags
	ora #KB_CTRL
	sta kb_flags
	jmp exit

caps_down:
	lda kb_flags
	;ora #KB_CAPS
	eor #KB_CAPS
	sta kb_flags
	jmp exit

  
key_release:
  lda kb_flags
  ora #KB_RELEASE
  sta kb_flags

exit:
  ;lda #%00000010      ; acknowledge CA1 interrupt before leaving ISR
  ;sta VIA1_IFR
  rts

kb_buffer_size:
	lda kb_wptr
	sec
	sbc kb_rptr
	rts

.segment "KEYMAP"

keymap:
	.byte "????????????? `?" ; 00-0F
	.byte "?????q1???zsaw2?" ; 10-1F
	.byte "?cxde43?? vftr5?" ; 20-2F
	.byte "?nbhgy6???mju78?" ; 30-3F
	.byte "?,kio09??./l;p-?" ; 40-4F
	.byte "??'?[=????",$0a,"]?",$5C,"??" ; 50-5F
	.byte "??????",$08,"??1?47???" ; 60-6F
	.byte "0.2568",$1b,"??+3-*9??" ; 70-7F
keymap_shifted:
	.byte "????????????? ~?" ; 00-0F
	.byte "?????Q!???ZSAW@?" ; 10-1F
	.byte "?CXDE#$?? VFTR%?" ; 20-2F
	.byte "?NBHGY^???MJU&*?" ; 30-3F
	.byte "?<KIO)(??>?L:P_?" ; 40-4F
	.byte "??",$22,"?{+?????}?|??" ; 50-5F
	.byte "?????????1?47???" ; 60-6F
	.byte "0.2568???+3-*9??" ; 70-7F
