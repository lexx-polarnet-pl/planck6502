.setcpu "65C02"
.feature string_escapes
.debuginfo

PLANCK_SLOT_0 = $FF80
PLANCK_SLOT_1 = $FF90
PLANCK_SLOT_2 = $FFA0
PLANCK_SLOT_3 = $FFB0
PLANCK_SLOT_4 = $FFC0
PLANCK_SLOT_5 = $FFD0
PLANCK_SLOT_6 = $FFE0

GPU_PORT = PLANCK_SLOT_0
KEY_PORT = PLANCK_SLOT_1
SOUND_CARD_PORT = PLANCK_SLOT_2
CF_CARD_PORT = PLANCK_SLOT_3
MEM_CARD_PORT = PLANCK_SLOT_4
MEGA_CONSOLE_PORT = PLANCK_SLOT_5
SERIAL_PORT = PLANCK_SLOT_6

VIA1_PORTB = KEY_PORT
VIA1_PORTA = KEY_PORT + 1
VIA1_DDRB = KEY_PORT + 2
VIA1_DDRA = KEY_PORT + 3
VIA1_PCR = KEY_PORT + $C ; Peripheral Control Registe
VIA1_IFR = KEY_PORT + $D  ; Interrupt Flag Register
VIA1_IER = KEY_PORT + $E ; Interrupt Enable Register


ACIA1_DATA       = SERIAL_PORT
ACIA1_STATUS     = SERIAL_PORT + 1
ACIA1_CMD        = SERIAL_PORT + 2
ACIA1_CTRL       = SERIAL_PORT + 3

.zeropage
Z0:          .res 1 	; General purpose zero page locations  
Z1:          .res 1   
Z2:          .res 1
Z3:          .res 1
Z4:          .res 1
Z5:          .res 1
STROUT_LO:   .res 1		; Pointer to string output low byte
STROUT_HI:   .res 1 	; Pointer to string output high byte
;Z0 = $F3                                        ; General purpose zero page locations
;Z1 = $F4
;Z2 = $F5
;Z3 = $F6
;STROUT_LO = $F8                                 ; Pointer to string output low byte
;STROUT_HI = $F9                                 ; Pointer to string output high byte

.segment "BUFFERS"
buffers_base:
kb_buffer       = buffers_base + $00   ; $00-$3F: Bufor klawiatury
cmd_buffer      = buffers_base + $40   ; $40-$7F: Bufor poleceń dla command.com
cwd_buffer      = buffers_base + $80   ; $80-$BF: Ścieżka aktualnego katalogu (dla prompta)
parm_buffer 	= buffers_base + $C0   ; $C0-$FF: Bufor na parametry poleceń (dla command.com)

.segment "BIOS_VECTORS" ; $0200
bios_vectors_via1_irq:	.res 2
bios_vectors_acia1_irq:	.res 2
bios_mem_config:	.res 1

.segment "KERNAL"

reset:
	lda #'L'
	sta GPU_PORT
    sei         ; Disable interrupts (redundant but safe)
    cld         ; Clear decimal mode
    ldx #$ff
    txs         ; Initialize stack pointer to $01FF

	lda #'E'
	sta GPU_PORT

	jsr init_io
	lda #'X'
	sta GPU_PORT

	jsr init_vectors
	lda #'X'
	sta GPU_PORT
	
    ; Clear zero page and RAM
    lda #$00
    ldy #$00
clear_ram:
    sta $0000,y  ; Clear zero page 
	sta $0300,y  ; Clear buffers
    iny
    bne clear_ram

	cli
	;jmp loop ; for loopback tests

	jsr coursor_off
	jsr print_welcome
	jsr init_sound_card
	jsr post_mem_test
	jsr check_input_devices	
	jsr cf_init_and_mount
	jsr display_date_time
	jsr new_line
	cli
	jsr clear_kb_buffer
	jsr coursor_on
	
	jmp SHELL_INIT
	;jsr clr_scr
	;JSR LOAD
	;jmp WOZMON
	;cli
	jmp COLD_START
	;jmp endless_loader

	
; *************** MAIN LOOP
loop:
	;jsr get_key
	LDA PLANCK_SLOT_5	; bierzemy dane z nowego kontrolera klatiwatury
	cmp #$00           ; nothing pressed, go back
	beq loop
	cmp #$0a           ; enter - go to second line
	beq enter_pressed
	cmp #$1b           ; escape - clear display
	beq esc_pressed	
	jsr print_char
	jmp loop
	
enter_pressed:
	jsr new_line
	jmp loop

esc_pressed:
    jsr clr_scr
	jmp loop

; *************** END OF MAIN LOOP

endless_loader:
	jsr bios_load_program
	jsr RAMSTART2 + $20 ; run loaded program
	jmp endless_loader

; setup all IO, basically resets to defaults
init_io:

    lda #%01111111 ; first, disable all interrupts
	sta VIA1_IER
	lda #%11111111 ; clear any pending VIA interrupt flags before re-enabling
	sta VIA1_IFR

	;lda #%10100001 ; pulse output for VIA port B CB2 pin, and VIA port A CA1 positive active edge
	lda #%00000001 ; VIA port A CA1 positive active edge
	sta VIA1_PCR


	lda #%11111111 ; Set all pins on port B to output
	sta VIA1_DDRB
	sta VIA1_PORTB ; Set port B to high

	LDA     #%00011111          ; 8-N-1, 19200 bps
	;LDA    	#%00011110         	; 8-N-1, 9600 baud
	;lda 	#%00011100         	; 8-N-1, 4800 baud
	STA     ACIA1_CTRL	

	LDA     #%10001001            ; No parity, no echo, rx interrupts.
	;LDA     #%10001011            ; No parity, no echo, no rx interrupts.
	STA     ACIA1_CMD

	jsr init_keyboard
	rts

init_vectors:
	; ustaw wektory przerwań itp.
	; $0200	$02FF	Wektory systemu
	lda #<acia_irq
	sta bios_vectors_acia1_irq
	lda #>acia_irq
	sta bios_vectors_acia1_irq+1
	rts

print_welcome:
    lda #<welcome_banner
    ldy #>welcome_banner
    jsr print_str
	rts

.include "bios_console.asm"
.include "bios_utils.asm"
.include "bios_keyboard.asm"	
.include "bios_interrupts.asm"
.include "bios_filesys.asm"  
.include "bios_command.asm" 
.include "bios_mem.asm" 
.include "bios_sound.asm"
.include "bios_strings_mazovia.asm"

.include "wozmon.asm"

.include "lexxbas.asm"

.segment "BIOS_FUNCTIONS" ; FF00
bios_get_key:
	jmp get_key
bios_print_char:
	jmp print_char
bios_print_string:
	jmp print_str
bios_clear_screen:
	jmp clr_scr
bios_run_monitor:
	jmp WOZMON
bios_main_program:
	jmp loop
bios_run_basic:
	jmp COLD_START
bios_load_program:
	jmp serial_load_file
bios_return_from_irq:
	jmp irq_done
bios_font_color:
	jmp fcolor	
bios_background_color:	
	jmp bcolor
bios_get_param_buffer:
	jmp get_param_buffer
bios_cf_load:
	jmp cf_load

ret_from_irq:
	rti

; Reset/IRQ vectors
.segment "CPUINIT"
	.word nmi
	.word reset
	.word irq_handler
	;.word ret_from_irq
	;.word reset
	;.word ret_from_irq
