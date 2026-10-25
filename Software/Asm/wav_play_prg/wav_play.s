
; =========================================================
; TLC7226 PCM PLAYER
; CPU: 65C02 @ 8 MHz
; Format: unsigned 8-bit PCM, mono
; Target sample rate: approx. 8 kHz
; Playback: fixed number of repetitions, no interrupts
; =========================================================

; ---------------------------------------------------------
; SOUND CARD CONFIGURATION
; ---------------------------------------------------------

SOUND_CARD_ADDRESS = $FFA0

; Kanał lewy — pierwszy pin jacka
DAC_LEFT_1  = SOUND_CARD_ADDRESS + 1
DAC_LEFT_2  = SOUND_CARD_ADDRESS + 2

; Kanał prawy — drugi pin jacka
DAC_RIGHT_1 = SOUND_CARD_ADDRESS + 0
DAC_RIGHT_2 = SOUND_CARD_ADDRESS + 3

; Number of sample repetitions per stage
PLAY_COUNT = 2

; Delay calibrated for approximately 1000 cycles/sample.
DELAY_COUNT = 180

; ---------------------------------------------------------
; ZERO PAGE
; ---------------------------------------------------------

.segment "ZEROPAGE"

PTR_LO:         .res 1
PTR_HI:         .res 1
REPEAT_LEFT:    .res 1

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
; PLAYBACK MACRO
; Plays PCM_DATA PLAY_COUNT times.
; addr2 = 0 means single DAC output.
; ---------------------------------------------------------

.macro PLAY_STAGE message, addr1, addr2

        ; Display stage name
        lda #<message
        ldy #>message
        jsr bios_print_string
        ; reset DAC data
        lda #$80
        sta DAC_LEFT_1  
        sta DAC_LEFT_2
        sta DAC_RIGHT_1
        sta DAC_RIGHT_2

        ; Initialize sample pointer and repetition counter
        lda #<PCM_DATA
        sta PTR_LO
        lda #>PCM_DATA
        sta PTR_HI

        lda #PLAY_COUNT
        sta REPEAT_LEFT

.local play_next, sample_delay, check_end, stage_done

play_next:
        ldy #$00
        lda (PTR_LO),Y

        ; Write to the first DAC output
        sta addr1

        ; Write to the second DAC output if specified
        .if addr2 <> 0
            sta addr2
        .endif

        ; Sample delay
        ldx #DELAY_COUNT

sample_delay:
        dex
        bne sample_delay

        ; Advance pointer
        inc PTR_LO
        bne check_end
        inc PTR_HI

check_end:
        ; Check end of sample
        lda PTR_LO
        cmp #<PCM_DATA_END
        bne play_next

        lda PTR_HI
        cmp #>PCM_DATA_END
        bne play_next

        ; One complete playback finished
        dec REPEAT_LEFT
        beq stage_done

        ; Repeat from the beginning
        lda #<PCM_DATA
        sta PTR_LO
        lda #>PCM_DATA
        sta PTR_HI
        jmp play_next

stage_done:

.endmacro

; ---------------------------------------------------------
; CODE
; ---------------------------------------------------------

.segment "CODE"

START:
        jsr bios_clear_screen

        lda #<banner_str
        ldy #>banner_str
        jsr bios_print_string

        ; ---------------------------------------------
        ; Stage 1: Left output 1
        ; ---------------------------------------------

        PLAY_STAGE msg_left_1, DAC_LEFT_1, 0

        ; ---------------------------------------------
        ; Stage 2: Left output 2
        ; ---------------------------------------------

        PLAY_STAGE msg_left_2, DAC_LEFT_2, 0

        ; ---------------------------------------------
        ; Stage 3: Right output 1
        ; ---------------------------------------------

        PLAY_STAGE msg_right_1, DAC_RIGHT_1, 0

        ; ---------------------------------------------
        ; Stage 4: Right output 2
        ; ---------------------------------------------

        PLAY_STAGE msg_right_2, DAC_RIGHT_2, 0

        ; ---------------------------------------------
        ; Stage 5: Stereo using left output 1
        ; and right output 1
        ; ---------------------------------------------

        PLAY_STAGE msg_stereo, DAC_LEFT_1, DAC_RIGHT_1

        ; All stages complete — return to BASIC
        rts

; ---------------------------------------------------------
; BIOS API
; ---------------------------------------------------------

.include "../bios_api.inc"

; ---------------------------------------------------------
; TEXT MESSAGES
; ---------------------------------------------------------

banner_str:
        .byte "TLC7226 PCM PLAYER",$0D,$0A
        .byte "Repeats per stage: ", '0'+PLAY_COUNT,$0D,$0A,$0A,$00

msg_left_1:
        .byte "Playing LEFT output 1",$0D,$0A,$00

msg_left_2:
        .byte "Playing LEFT output 2",$0D,$0A,$00

msg_right_1:
        .byte "Playing RIGHT output 1",$0D,$0A,$00

msg_right_2:
        .byte "Playing RIGHT output 2",$0D,$0A,$00

msg_stereo:
        .byte "Playing STEREO: LEFT 1 + RIGHT 1",$0D,$0A,$00

; ---------------------------------------------------------
; PCM DATA
; Raw unsigned 8-bit PCM, no WAV header
; ---------------------------------------------------------

PCM_DATA:
        .incbin "pcm/audiotest.pcm"

PCM_DATA_END:
