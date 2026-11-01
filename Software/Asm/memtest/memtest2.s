.setcpu "65C02"
.feature string_escapes
.debuginfo

; =========================================================
; 6502 RAM MEMORY TESTER
; =========================================================
; Requires:
;   - 65C02 CPU
;   - LexxDOS BASIC loader at $0620
;   - BIOS API from ../bios_api.inc
;   - Shadow RAM bank control register at $FFC0
;
; Memory layout:
;   $0000-$00FF  Zero page
;   $0100-$01FF  Stack
;   $0200-$05FF  System / program buffers (reserved)
;   $0600-$0FFF  This program code
;   $1000-$7FFF  Base RAM tested by this program
;   $8000-$BFFF  Banked Shadow RAM
;
; All tested ranges must start on a page boundary.
; The end page passed to test_ram_range is EXCLUSIVE.
;
; WARNING:
;   All RAM tests are destructive. Contents of tested RAM
;   will be overwritten.
; =========================================================


; ---------------------------------------------------------
; ZERO PAGE
; ---------------------------------------------------------

.segment "ZEROPAGE"

ptr:            .res 2      ; Current indirect memory pointer
tmp_val:        .res 1      ; Temporary byte / exclusive end page
range_start:    .res 2      ; Start address of current test range
test_pattern:   .res 1      ; Current test pattern / pattern modifier
bank_cnt:       .res 1      ; Number of detected RAM banks
pass_flag:      .res 1      ; 0 = PASS, nonzero = FAIL

error_addr:     .res 2      ; Address of the first detected error
error_expected: .res 1      ; Expected data value
error_actual:   .res 1      ; Actual data value
current_bank:   .res 1      ; Selected Shadow RAM bank, $FF for base RAM
current_test:   .res 1      ; 0 = fixed, 1 = address, 2 = checkerboard
current_pattern:.res 1      ; Pattern or modifier for the current test


; ---------------------------------------------------------
; BASIC LOADER: SYS 1568 ($0620)
; ---------------------------------------------------------

.segment "BASSTART"

; 10 SYS 1568
.byte $00,$0c,$06,$0A,$00,$8F,$20,$31
.byte $35,$36,$38,$00,$00,$00,$00,$00

; LexxDOS executable header, LX1 signature
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$4C,$58,$31


; ---------------------------------------------------------
; CODE
; ---------------------------------------------------------

.segment "CODE"

CTRL_REG = $FFC0            ; Shadow RAM bank control register


; =========================================================
; PROGRAM ENTRY
; =========================================================

START:
        ;jsr bios_clear_screen

        lda #<banner_str
        ldy #>banner_str
        jsr bios_print_string


; ---------------------------------------------------------
; 1. TEST BASE RAM ($1000-$7FFF)
; ---------------------------------------------------------
; Zero page, stack and program/system buffers are excluded.
; $80 is the exclusive end page, so the last tested byte
; is $7FFF.

        lda #$FF
        sta current_bank

        lda #<msg_base_ram
        ldy #>msg_base_ram
        jsr bios_print_string

        stz ptr
        lda #$10
        sta ptr+1

        lda #$80
        jsr test_ram_range

        lda pass_flag
        bne @base_error

        lda #<msg_ok
        ldy #>msg_ok
        jsr bios_print_string
        bra @check_card

@base_error:
        lda #<msg_fail
        ldy #>msg_fail
        jsr bios_print_string
        jsr print_error


; ---------------------------------------------------------
; 2. DETECT SHADOW RAM CARD
; ---------------------------------------------------------

@check_card:
        lda #<msg_card_detect
        ldy #>msg_card_detect
        jsr bios_print_string

        ; Disable Shadow RAM and expose ROM.
        stz CTRL_REG

        ; Save the ROM byte at $8000.
        lda $8000
        sta tmp_val

        ; Enable Shadow RAM bank 0 ($80).
        lda #$80
        sta CTRL_REG

        ; Write the inverted ROM byte into Shadow RAM.
        lda tmp_val
        eor #$FF
        sta $8000

        ; Disable Shadow RAM and expose ROM again.
        stz CTRL_REG

        ; ROM contents must remain unchanged.
        lda $8000
        cmp tmp_val
        bne @no_card

        ; Re-enable bank 0 and verify the RAM write.
        lda #$80
        sta CTRL_REG
        lda $8000
        eor tmp_val
        cmp #$FF
        bne @no_card

        lda #<msg_present
        ldy #>msg_present
        jsr bios_print_string
        jmp @detect_banks

@no_card:
        ; Leave ROM visible.
        stz CTRL_REG

        lda #<msg_not_present
        ldy #>msg_not_present
        jsr bios_print_string
        rts


; ---------------------------------------------------------
; 3. DETECT NUMBER OF SHADOW RAM BANKS
; ---------------------------------------------------------
; Bank values are $80-$FF, allowing up to 128 banks.
; Bank 0 is marked with $AA. Each subsequent bank is
; written with a different marker. If bank 0's marker
; changes, the bank address has wrapped/aliased.

@detect_banks:
        lda #<msg_bank_count
        ldy #>msg_bank_count
        jsr bios_print_string

        ; Mark bank 0.
        lda #$80
        sta CTRL_REG
        lda #$AA
        sta $8000

        lda #$01
        sta bank_cnt

@bank_loop:
        lda bank_cnt
        cmp #128
        beq @count_done

        ; Select bank $80 + bank_cnt.
        ora #$80
        sta CTRL_REG

        ; Write a marker to the candidate bank.
        lda bank_cnt
        sta $8000

        ; Return to bank 0 and check its marker.
        lda #$80
        sta CTRL_REG
        lda $8000
        cmp #$AA
        bne @count_done

        inc bank_cnt
        jmp @bank_loop

@count_done:
        ; Print the number of detected banks.
        lda bank_cnt
        sta range_start
        stz range_start+1
        jsr print_dec3

        lda #<msg_banks_found
        ldy #>msg_banks_found
        jsr bios_print_string

        ; Calculate capacity in KB: bank_cnt * 16.
        lda bank_cnt
        sta range_start
        stz range_start+1

        asl range_start
        rol range_start+1
        asl range_start
        rol range_start+1
        asl range_start
        rol range_start+1
        asl range_start
        rol range_start+1

        jsr print_dec4

        lda #<msg_testing_shadow
        ldy #>msg_testing_shadow
        jsr bios_print_string


; ---------------------------------------------------------
; 4. TEST ALL DETECTED SHADOW RAM BANKS
; ---------------------------------------------------------

        stz pass_flag
        ldx #$00

@test_shadow_loop:
        cpx bank_cnt
        beq @shadow_done

        ; Select bank X ($80-$FF).
        txa
        ora #$80
        sta CTRL_REG
        sta current_bank

        phx
        jsr print_bank_start
        plx

        ; Test the complete bank: $8000-$BFFF.
        stz ptr
        lda #$80
        sta ptr+1

        phx
        lda #$C0                ; Exclusive end page
        jsr test_ram_range
        plx

        ; Do not let a later bank test clear an earlier error.
        lda pass_flag
        bne @shadow_done

        inx
        jmp @test_shadow_loop

@shadow_done:
        ; Always restore ROM visibility.
        stz CTRL_REG

        lda pass_flag
        bne @shadow_error

        lda #<msg_ok
        ldy #>msg_ok
        jsr bios_print_string
        rts

@shadow_error:
        lda #<msg_fail
        ldy #>msg_fail
        jsr bios_print_string
        jsr print_error
        rts


; =========================================================
; MEMORY TEST ROUTINES
; =========================================================

; ---------------------------------------------------------
; test_ram_range
;
; Input:
;   ptr     = start address (must be page-aligned)
;   A       = exclusive end page (high byte)
;
; Example:
;   ptr = $1000, A = $80 tests $1000-$7FFF.
;
; Output:
;   pass_flag = 0 (PASS), 1 (FAIL)
;
; Tests:
;   1. Fixed byte patterns: $00, $FF, $55, $AA
;   2. Walking 1: one data bit set at a time
;   3. Walking 0: one data bit cleared at a time
;   4. Address-dependent pattern and its inverse
;   5. Checkerboard pattern and its inverse
;
; Each fixed pattern is written across the entire range
; before the verification pass begins.
; ---------------------------------------------------------

test_ram_range:
        sta tmp_val             ; Exclusive end page

        lda ptr
        sta range_start
        lda ptr+1
        sta range_start+1

        stz pass_flag

        ; Run all 20 fixed data patterns.
        ldx #$00

@test_fixed_patterns:
        lda ram_test_patterns,x
        sta current_pattern
        txa
        cmp #$04
        bcc @fixed_pattern
        cmp #$0C
        bcc @walking_one
        lda #$02
        bra @save_test_type

@walking_one:
        lda #$01
        bra @save_test_type

@fixed_pattern:
        lda #$00

@save_test_type:
        sta current_test

        phx
        jsr print_test_start
        plx

        lda current_pattern
        jsr fill_and_verify
        bcs @range_failed

        phx
        jsr print_test_pass
        plx

        inx
        cpx #20
        bne @test_fixed_patterns

        ; Address-dependent pattern.
        ; Expected byte = low address XOR high address.
        lda #$03
        sta current_test
        lda #$00
        sta current_pattern
        phx
        jsr print_test_start
        plx
        lda current_pattern
        jsr address_pattern_pass
        bcs @range_failed
        phx
        jsr print_test_pass
        plx

        ; Inverted address-dependent pattern.
        lda #$03
        sta current_test
        lda #$FF
        sta current_pattern
        phx
        jsr print_test_start
        plx
        lda current_pattern
        jsr address_pattern_pass
        bcs @range_failed
        phx
        jsr print_test_pass
        plx

        ; Checkerboard: $55 at even offsets, $AA at odd.
        lda #$04
        sta current_test
        lda #$00
        sta current_pattern
        phx
        jsr print_test_start
        plx
        lda current_pattern
        jsr checkerboard_pass
        bcs @range_failed
        phx
        jsr print_test_pass
        plx

        ; Inverted checkerboard.
        lda #$04
        sta current_test
        lda #$FF
        sta current_pattern
        phx
        jsr print_test_start
        plx
        lda current_pattern
        jsr checkerboard_pass
        bcs @range_failed
        phx
        jsr print_test_pass
        plx

        lda #<msg_crlf
        ldy #>msg_crlf
        jsr bios_print_string
        rts

@range_failed:
        lda #<msg_test_fail
        ldy #>msg_test_fail
        jsr bios_print_string
        lda #$01
        sta pass_flag
        rts


; ---------------------------------------------------------
; fill_and_verify
;
; Input:
;   A = fixed byte pattern
;
; Output:
;   Carry clear = PASS
;   Carry set   = FAIL
;
; The complete range is written first and verified second.
; ---------------------------------------------------------

fill_and_verify:
        sta test_pattern

        ; Restore the beginning of the range.
        lda range_start
        sta ptr
        lda range_start+1
        sta ptr+1

        ; PASS 1: write the complete range.
        ldy #$00

@write_loop:
        lda test_pattern
        sta (ptr),y

        iny
        bne @write_loop

        inc ptr+1
        lda ptr+1
        cmp tmp_val
        bne @write_loop

        ; PASS 2: verify the complete range.
        lda range_start
        sta ptr
        lda range_start+1
        sta ptr+1

        lda test_pattern
        sta error_expected

        ldy #$00

@verify_loop:
        lda (ptr),y
        cmp error_expected
        beq @verify_ok
        jmp memory_test_fail

@verify_ok:
        iny
        bne @verify_loop

        inc ptr+1
        lda ptr+1
        cmp tmp_val
        bne @verify_loop

        clc
        rts


; ---------------------------------------------------------
; address_pattern_pass
;
; Input:
;   A = $00 for normal pattern, $FF for inverted pattern
;
; Pattern:
;   expected = low_address XOR high_address XOR modifier
;
; The tested ranges start on page boundaries, so ptr's
; low byte is zero and Y is the low address byte.
; ---------------------------------------------------------

address_pattern_pass:
        sta test_pattern

        lda range_start
        sta ptr
        lda range_start+1
        sta ptr+1

        ; PASS 1: write address-dependent values.
        ldy #$00

@write_loop:
        tya
        eor ptr+1
        eor test_pattern
        sta (ptr),y

        iny
        bne @write_loop

        inc ptr+1
        lda ptr+1
        cmp tmp_val
        bne @write_loop

        ; PASS 2: verify address-dependent values.
        lda range_start
        sta ptr
        lda range_start+1
        sta ptr+1

        ldy #$00

@verify_loop:
        tya
        eor ptr+1
        eor test_pattern
        sta error_expected

        lda (ptr),y
        cmp error_expected
        beq @verify_ok
        jmp memory_test_fail

@verify_ok:
        iny
        bne @verify_loop

        inc ptr+1
        lda ptr+1
        cmp tmp_val
        bne @verify_loop

        clc
        rts


; ---------------------------------------------------------
; checkerboard_pass
;
; Input:
;   A = $00 for normal pattern, $FF for inverted pattern
;
; Pattern:
;   even offsets = $55
;   odd offsets  = $AA
;   modifier $FF inverts both values.
;
; The tested ranges start on page boundaries.
; ---------------------------------------------------------

checkerboard_pass:
        sta test_pattern

        lda range_start
        sta ptr
        lda range_start+1
        sta ptr+1

        ; PASS 1: write checkerboard.
        ldy #$00

@write_loop:
        tya
        and #$01
        beq @write_even

        lda #$AA
        bra @write_value

@write_even:
        lda #$55

@write_value:
        eor test_pattern
        sta (ptr),y

        iny
        bne @write_loop

        inc ptr+1
        lda ptr+1
        cmp tmp_val
        bne @write_loop

        ; PASS 2: verify checkerboard.
        lda range_start
        sta ptr
        lda range_start+1
        sta ptr+1

        ldy #$00

@verify_loop:
        tya
        and #$01
        beq @verify_even

        lda #$AA
        bra @verify_value

@verify_even:
        lda #$55

@verify_value:
        eor test_pattern
        sta error_expected

        lda (ptr),y
        cmp error_expected
        beq @verify_ok
        jmp memory_test_fail

@verify_ok:
        iny
        bne @verify_loop

        inc ptr+1
        lda ptr+1
        cmp tmp_val
        bne @verify_loop

        clc
        rts


; ---------------------------------------------------------
; memory_test_fail
;
; Called when a verification read does not match the
; expected value.
;
; error_expected must already contain the expected byte.
; ---------------------------------------------------------

memory_test_fail:
        lda (ptr),y
        sta error_actual

        ; Calculate failing address: ptr + Y.
        tya
        clc
        adc ptr
        sta error_addr

        lda ptr+1
        adc #$00
        sta error_addr+1

        sec
        rts


; =========================================================
; NUMBER FORMATTING
; =========================================================

; ---------------------------------------------------------
; Progress reporting
; ---------------------------------------------------------

print_bank_start:
        lda #<msg_bank_start
        ldy #>msg_bank_start
        jsr bios_print_string

        lda current_bank
        jsr print_hex_byte

        lda #<msg_bank_range
        ldy #>msg_bank_range
        jsr bios_print_string
        rts

print_test_start:
print_test_details:
        lda current_test
        beq @fixed
        cmp #$01
        beq @walking_one
        cmp #$02
        beq @walking_zero
        cmp #$03
        beq @address

        lda #<msg_test_checkerboard
        ldy #>msg_test_checkerboard
        bra @print_label

@walking_one:
        lda #<msg_test_walking_one
        ldy #>msg_test_walking_one
        bra @print_label

@walking_zero:
        lda #<msg_test_walking_zero
        ldy #>msg_test_walking_zero
        bra @print_label

@address:
        lda #<msg_test_address
        ldy #>msg_test_address
        bra @print_label

@fixed:
        lda #<msg_test_fixed
        ldy #>msg_test_fixed

@print_label:
        jsr bios_print_string
        lda current_pattern
        jsr print_hex_byte

        lda #<msg_test_suffix
        ldy #>msg_test_suffix
        jmp bios_print_string

print_test_pass:
        lda #<msg_test_pass
        ldy #>msg_test_pass
        jmp bios_print_string

; ---------------------------------------------------------
; print_dec2
; Prints an unsigned decimal value from 0 to 99.
; Input: A
; ---------------------------------------------------------

print_dec2:
        ldy #$00

@div10:
        cmp #10
        bcc @print_digits
        sec
        sbc #10
        iny
        bne @div10

@print_digits:
        pha
        tya
        ora #'0'
        jsr bios_print_char

        pla
        ora #'0'
        jsr bios_print_char
        rts


; ---------------------------------------------------------
; print_dec3
; Prints a 16-bit decimal value from 0 to 999.
; Input: range_start
; ---------------------------------------------------------

print_dec3:
        stz tmp_val

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
        stz test_pattern

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


; ---------------------------------------------------------
; print_dec4
; Prints a 16-bit decimal value from 0 to 9999.
; Input: range_start
; ---------------------------------------------------------

print_dec4:
        stz pass_flag

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
        stz tmp_val

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
        stz test_pattern

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


; =========================================================
; ERROR REPORTING
; =========================================================

; Prints:
;   Error at $AAAA expected $EE got $AA

print_error:
        lda #<msg_error_context
        ldy #>msg_error_context
        jsr bios_print_string

        lda current_bank
        cmp #$FF
        bne @shadow_bank

        lda #<msg_base_bank
        ldy #>msg_base_bank
        jsr bios_print_string
        bra @test_context

@shadow_bank:
        lda #<msg_bank_label
        ldy #>msg_bank_label
        jsr bios_print_string
        lda current_bank
        jsr print_hex_byte

@test_context:
        lda #<msg_crlf
        ldy #>msg_crlf
        jsr bios_print_string
        lda #<msg_error_test
        ldy #>msg_error_test
        jsr bios_print_string
        jsr print_test_details

        lda #<msg_crlf
        ldy #>msg_crlf
        jsr bios_print_string

        lda #<msg_error_at
        ldy #>msg_error_at
        jsr bios_print_string

        lda error_addr+1
        jsr print_hex_byte

        lda error_addr
        jsr print_hex_byte

        lda #<msg_expected
        ldy #>msg_expected
        jsr bios_print_string

        lda error_expected
        jsr print_hex_byte

        lda #<msg_got
        ldy #>msg_got
        jsr bios_print_string

        lda error_actual
        jsr print_hex_byte

        lda #<msg_crlf
        ldy #>msg_crlf
        jsr bios_print_string
        rts


; Prints A as two hexadecimal digits.
print_hex_byte:
        pha

        lsr a
        lsr a
        lsr a
        lsr a
        jsr print_hex_nibble

        pla
        and #$0F
        jmp print_hex_nibble


; Prints the low nibble in A as one hexadecimal digit.
print_hex_nibble:
        cmp #10
        bcc @decimal_digit

        clc
        adc #('A' - 10)
        bra @emit

@decimal_digit:
        clc
        adc #'0'

@emit:
        jmp bios_print_char


; =========================================================
; BIOS API
; =========================================================

.include "../bios_api.inc"


; =========================================================
; TEST PATTERNS
; =========================================================

ram_test_patterns:
        ; Fixed patterns
        .byte $00,$FF,$55,$AA

        ; Walking 1
        .byte $01,$02,$04,$08,$10,$20,$40,$80

        ; Walking 0
        .byte $FE,$FD,$FB,$F7,$EF,$DF,$BF,$7F


; =========================================================
; TEXT MESSAGES
; =========================================================

banner_str:
        .byte "=== Planck W65C02 RAM TESTER v2 ===", $0D, $0A, $00

msg_base_ram:
        .byte "Base RAM test ($1000-$7FFF): ", $00

msg_card_detect:
        .byte "Shadow RAM card detection: ", $00

msg_present:
        .byte "PRESENT", $0D, $0A, $00

msg_not_present:
        .byte "NOT PRESENT", $0D, $0A, $00

msg_bank_count:
        .byte "Detected memory banks: ", $00

msg_banks_found:
        .byte " bank(s) (", $00

msg_testing_shadow:
        .byte " KB)", $0D, $0A, "Testing Shadow RAM banks: ", $00

msg_bank_start:
        .byte "Bank $", $00

msg_bank_range:
        .byte " ($8000-$BFFF)", $0D, $0A, $00

msg_test_fixed:
        .byte "F$", $00

msg_test_walking_one:
        .byte "W1$", $00

msg_test_walking_zero:
        .byte "W0$", $00

msg_test_address:
        .byte "A$", $00

msg_test_checkerboard:
        .byte "C$", $00

msg_test_suffix:
        .byte " ", $00

msg_test_pass:
        .byte "\x1B[32mOK\x1B[0m ", $00 

msg_test_fail:
        .byte " \x1B[31mFAIL\x1B[0m ", $00

msg_error_context:
        .byte "Failure context: ", $00

msg_base_bank:
        .byte "base RAM ($1000-$7FFF)", $00

msg_bank_label:
        .byte "Shadow RAM bank $", $00

msg_error_test:
        .byte "Test: ", $00

msg_ok:
        .byte "\x1B[32mPASS\x1B[0m", $0D, $0A, $00

msg_fail:
        .byte "\x1B[31mFAIL\x1B[0m", $0D, $0A, $00

msg_error_at:
        .byte "Error at $", $00

msg_expected:
        .byte " expected $", $00

msg_got:
        .byte " got $", $00

msg_crlf:
        .byte $0D, $0A, $00
program_end:
