;  .org $8000
;  .org $ff00

XAML  = $24                            ; Last "opened" location Low
XAMH  = $25                            ; Last "opened" location High
STL   = $26                            ; Store address Low
STH   = $27                            ; Store address High
L     = $28                            ; Hex value parsing Low
H     = $29                            ; Hex value parsing High
YSAV  = $2A                            ; Used to see if hex value is given
MODE  = $2B                            ; $00=XAM, $7F=STOR, $AE=BLOCK XAM
COUNT = $2C                            ; Bytes displayed in the current row
BLOCK_FIRST = $3D                       ; Explicit start address for a block dump

IN    = $0400                          ; Input buffer
DISPLAY_BUFFER = $2D                   ; Temporary row buffer

;ACIA_DATA   = $5000
;ACIA_STATUS = $5001
;ACIA_CMD    = $5002
;ACIA_CTRL   = $5003

WOZMON:
    lda #<wozmon_welcome
    ldy #>wozmon_welcome
    jsr print_str
                ;LDA     #$1F           ; 8-N-1, 19200 baud.
                ;STA     ACIA_CTRL
                ;LDA     #$0B           ; No parity, no echo, no interrupts.
                ;STA     ACIA_CMD
                LDA     #$1B           ; Begin with escape.

NOTCR:
                CMP     #$08           ; Backspace key?
                BEQ     BACKSPACE      ; Yes.
                CMP     #$1B           ; ESC?
                BEQ     ESCAPE         ; Yes.
                INY                    ; Advance text index.
                BPL     NEXTCHAR       ; Auto ESC if line longer than 127.

ESCAPE:
                LDA     #$5C           ; "\".
                JSR     ECHO           ; Output it.

GETLINE:
                LDA     #$0D           ; Send CR
                JSR     ECHO
                LDA     #$0A           ; LF.
                JSR     ECHO           ; Output it.						

                LDY     #$01           ; Initialize text index.
BACKSPACE:      DEY                    ; Back up text index.
                BMI     GETLINE        ; Beyond start of line, reinitialize.

NEXTCHAR:


	jsr get_key
	cmp #$00           					; nothing pressed, go back
	beq NEXTCHAR

                ;LDA     ACIA_STATUS    ; Check status.
                ;AND     #$08           ; Key ready?
                ;BEQ     NEXTCHAR       ; Loop until ready.
                ;LDA     ACIA_DATA      ; Load character. B7 will be '0'.
                STA     IN,Y           ; Add to text buffer.
                JSR     ECHO           ; Display character.
                CMP     #$0D           ; CR?
	;cmp #$0a
                BNE     NOTCR          ; No.

                LDY     #$FF           ; Reset text index.
                LDA     #$00           ; For XAM mode.
                STA     BLOCK_FIRST
                TAX                    ; X=0.
SETBLOCK:
                ASL
SETSTOR:
                ASL                    ; Leaves $7B if setting STOR mode.
                STA     MODE           ; $00 = XAM, $74 = STOR, $B8 = BLOK XAM.
BLSKIP:
                INY                    ; Advance text index.
NEXTITEM:
                LDA     IN,Y           ; Get character.
                CMP     #$0D           ; CR?
	;cmp #$0a				
                BEQ     GETLINE        ; Yes, done this line.
                CMP     #$2E           ; "."?
                BCC     BLSKIP         ; Skip delimiter.
                BEQ     SETBLOCK       ; Set BLOCK XAM mode.
                CMP     #$3A           ; ":"?
                BEQ     SETSTOR        ; Yes, set STOR mode.
                CMP     #$52           ; "R"?
                BEQ     RUNPRG         ; Yes, run user program.
                STX     L              ; $00 -> L.
                STX     H              ;    and H.
                STY     YSAV           ; Save Y for comparison

NEXTHEX:
                LDA     IN,Y           ; Get character for hex test.
                EOR     #$30           ; Map digits to $0-9.
                CMP     #$0A           ; Digit?
                BCC     DIG            ; Yes.
                ADC     #$88           ; Map letter "A"-"F" to $FA-FF.
                CMP     #$FA           ; Hex letter?
                BCC     NOTHEX         ; No, character not hex.
DIG:
                ASL
                ASL                    ; Hex digit to MSD of A.
                ASL
                ASL

                LDX     #$04           ; Shift count.
HEXSHIFT:
                ASL                    ; Hex digit left, MSB to carry.
                ROL     L              ; Rotate into LSD.
                ROL     H              ; Rotate into MSD's.
                DEX                    ; Done 4 shifts?
                BNE     HEXSHIFT       ; No, loop.
                INY                    ; Advance text index.
                BNE     NEXTHEX        ; Always taken. Check next character for hex.

NOTHEX:
                CPY     YSAV           ; Check if L, H empty (no hex digits).
                BEQ     ESCAPE         ; Yes, generate ESC sequence.

                LDA     IN,Y
                CMP     #$2E           ; Is this the start of a block range?
                BNE     NOTHEX_MODE
                LDA     L
                STA     XAML
                STA     STL
                LDA     H
                STA     XAMH
                STA     STH
                LDA     #$01
                STA     BLOCK_FIRST
                JMP     TONEXTITEM

NOTHEX_MODE:
                BIT     MODE           ; Test MODE byte.
                BVC     NOTSTOR        ; B6=0 is STOR, 1 is XAM and BLOCK XAM.

                LDA     L              ; LSD's of hex data.
                STA     (STL,X)        ; Store current 'store index'.
                INC     STL            ; Increment store index.
                BNE     NEXTITEM       ; Get next item (no carry).
                INC     STH            ; Add carry to 'store index' high order.
TONEXTITEM:     JMP     NEXTITEM       ; Get next command item.

RUNPRG:
                JMP     (XAML)         ; Run at current XAM index.

NOTSTOR:
                BMI     XAMNEXT        ; B7 = 0 for XAM, 1 for BLOCK XAM.

                LDX     #$02           ; Byte count.
SETADR:         LDA     L-1,X          ; Copy hex data to
                STA     STL-1,X        ;  'store index'.
                STA     XAML-1,X       ; And to 'XAM index'.
                DEX                    ; Next of 2 bytes.
                BNE     SETADR         ; Loop unless X = 0.

NXTPRNT:
                LDA     #$0D           ; CR.
                JSR     ECHO           ; Output it.
                LDA     #$0A           ; LF.
                JSR     ECHO           ; Output it.				
                LDA     XAMH           ; 'Examine index' high-order byte.
                JSR     PRBYTE         ; Output it in hex format.
                LDA     XAML           ; Low-order 'examine index' byte.
                JSR     PRBYTE         ; Output it in hex format.
                LDA     #$3A           ; ":".
                JSR     ECHO           ; Output it.
                LDA     #$20
                JSR     ECHO
                LDA     #$00
                STA     COUNT

PRDATA:
                LDA     (XAML,X)       ; Get data byte at 'examine index'.
                LDX     COUNT
                STA     DISPLAY_BUFFER,X ; Keep it for the ASCII preview.
                JSR     PRBYTE         ; Output it in hex format.
                INC     COUNT
                LDA     COUNT
                CMP     #$08
                BNE     PRDATA_NOGROUP
                LDA     #$20           ; Extra space between groups.
                JSR     ECHO
PRDATA_NOGROUP:
                LDA     COUNT
                CMP     #$10
                BNE     PRDATA_SEPARATOR
                LDX     #$00
                JMP     XAMADVANCE
PRDATA_SEPARATOR:
                LDA     #$20           ; Blank.
                JSR     ECHO           ; Separate hex bytes.
                LDX     #$00
                JMP     XAMADVANCE

XAMNEXT:        STX     MODE           ; Start block examine after current XAML.
                LDA     BLOCK_FIRST
                BEQ     XAMNEXT_CONTINUE
                LDA     #$00
                STA     BLOCK_FIRST
                LDA     XAML
                CMP     L
                LDA     XAMH
                SBC     H
                BCC     XAMNEXT_DISPLAY
                BEQ     XAMNEXT_DISPLAY
                JMP     TONEXTITEM
XAMNEXT_DISPLAY:
                JMP     NXTPRNT
XAMNEXT_CONTINUE:
                LDA     XAML
                CMP     L              ; Compare 'examine index' to hex data.
                LDA     XAMH
                SBC     H
                BCC     XAMNEXT_ADVANCE
                JMP     TONEXTITEM
XAMNEXT_ADVANCE:
                INC     XAML
                BEQ     XAMNEXT_WRAP
                JMP     NXTPRNT
XAMNEXT_WRAP:
                INC     XAMH
                JMP     NXTPRNT

XAMADVANCE:     STX     MODE           ; 0 -> MODE (XAM mode).
                LDA     XAML
                CMP     L              ; Compare 'examine index' to hex data.
                LDA     XAMH
                SBC     H
                BCC     XAMADVANCE_CONTINUE
                JMP     PRDATA_LAST
XAMADVANCE_CONTINUE:
                INC     XAML           ; Advance only when another byte remains.
                BNE     XAMADVANCE_MORE
                INC     XAMH
XAMADVANCE_MORE:
                LDA     COUNT
                CMP     #$10
                BEQ     PRDATA_NEXTROW
                JMP     PRDATA

PRDATA_LAST:
                JSR     PRDATA_ASCII
                JMP     TONEXTITEM

PRDATA_NEXTROW:
                JSR     PRDATA_ASCII
                JMP     NXTPRNT

PRDATA_ASCII:
                LDA     COUNT
                STA     YSAV
PRDATA_PAD_HEX:
                LDA     YSAV
                CMP     #$10
                BEQ     PRDATA_ASCII_START
                CMP     #$0F
                BEQ     PRDATA_PAD_LAST
                LDA     #$20
                JSR     ECHO
                JSR     ECHO
                JSR     ECHO
                INC     YSAV
                LDA     YSAV
                CMP     #$08
                BNE     PRDATA_PAD_HEX
                LDA     #$20           ; Group separator after byte eight.
                JSR     ECHO
                JMP     PRDATA_PAD_HEX
PRDATA_PAD_LAST:
                LDA     #$20
                JSR     ECHO
                JSR     ECHO
                INC     YSAV
                JMP     PRDATA_PAD_HEX

PRDATA_ASCII_START:
                LDA     #$20
                JSR     ECHO
                JSR     ECHO
                JSR     ECHO
                LDA     #$7C           ; "|"
                JSR     ECHO
                LDX     #$00
PRDATA_ASCII_LOOP:
                CPX     COUNT
                BEQ     PRDATA_ASCII_PAD
                LDA     DISPLAY_BUFFER,X
                CMP     #$20
                BCC     PRDATA_ASCII_DOT
                CMP     #$7F
                BCS     PRDATA_ASCII_DOT
                JSR     ECHO
                INX
                JMP     PRDATA_ASCII_LOOP
PRDATA_ASCII_DOT:
                LDA     #$2E           ; Replace non-printable bytes with ".".
                JSR     ECHO
                INX
                JMP     PRDATA_ASCII_LOOP
PRDATA_ASCII_PAD:
                CPX     #$10
                BEQ     PRDATA_ASCII_END
                LDA     #$20
                JSR     ECHO
                INX
                JMP     PRDATA_ASCII_PAD
PRDATA_ASCII_END:
                LDA     #$7C           ; "|"
                JSR     ECHO
                LDX     #$00
                RTS

PRBYTE:
                PHA                    ; Save A for LSD.
                LSR
                LSR
                LSR                    ; MSD to LSD position.
                LSR
                JSR     PRHEX          ; Output hex digit.
                PLA                    ; Restore A.

PRHEX:
                AND     #$0F           ; Mask LSD for hex print.
                ORA     #$30           ; Add "0".
                CMP     #$3A           ; Digit?
                BCC     ECHO           ; Yes, output it.
                ADC     #$06           ; Add offset for letter.

ECHO:
	jsr print_char
;                PHA                    ; Save A.
;                STA     ACIA_DATA      ; Output character.
;                LDA     #$FF           ; Initialize delay loop.
;TXDELAY:        DEC                    ; Decrement A.
;                BNE     TXDELAY        ; Until A gets to 0.
;                PLA                    ; Restore A.
                RTS                    ; Return.

;  .org $FFFA
;
;                .word   $0F00          ; NMI vector
;                .word   RESET          ; RESET vector
;                .word   $0000          ; IRQ vector
wozmon_welcome: .byte  "WOZMON gotowy.",$0D,$0A,0