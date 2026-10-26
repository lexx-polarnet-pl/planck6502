; ==============================================================================
; PROSTY SHELL / COMMAND.COM DLA KOMPUTERA 6502
; ==============================================================================

; --- DEFINICJE ADRESÓW STRONY ZERO I I/O ---
.segment "ZEROPAGE"
BUF_PTR: .res 2 ;     = $FC       ; Wskaźnik pomocniczy w Stronie Zero ($FC-$FD)
CMD_PTR: .res 2 ;     = $FE       ; Wskaźnik pomocniczy w Stronie Zero ($FE-$FF)

.segment "BIOS_VECTORS"
cmd_filename_83: .res 11

INPUT_BUF   = cmd_buffer ; Bufor poleceń: 64 bajty w segmencie BUFFERS
INPUT_BUF_END = $3F      ; Ostatni bajt zarezerwowany na terminator $00

; --- ZNAKI ASCII ---
CHAR_CR     = $0D       ; Enter / Return
CHAR_BS     = $08       ; Backspace
CHAR_SPACE  = $20       ; Spacja
CHAR_NULL   = $00       ; Koniec ciągu znaków

; ==============================================================================
; SEKCJA STARTOWA / GLÓWNA PĘTLA REPL
; ==============================================================================
.segment "KERNAL"

SHELL_INIT:
    LDA #<MSG_WELCOME
    LDY #>MSG_WELCOME
    JSR print_str

SHELL_LOOP:
    JSR new_line
    LDA #<cwd_buffer
    LDY #>cwd_buffer
    JSR print_str
    LDA #'>'
    JSR print_char
    LDA #' '
    JSR print_char

    JSR READ_LINE       ; Wczytaj linię tekstu z klawiatury do INPUT_BUF
    
    LDA INPUT_BUF
    BEQ SHELL_LOOP      ; Jeśli linia jest pusta (użytkownik wcisnął tylko Enter), powtórz

    JSR EVAL_COMMAND    ; Przeanalizuj i wykonaj polecenie
    JMP SHELL_LOOP

; ==============================================================================
; PARSER I INTERPRETER POLECEŃ
; ==============================================================================
EVAL_COMMAND:
    LDA #<CMD_TABLE
    STA CMD_PTR
    LDA #>CMD_TABLE
    STA CMD_PTR+1

SEARCH_LOOP:
    ; Sprawdź czy nie doszliśmy do końca tabeli poleceń ($00)
    LDY #0
    LDA (CMD_PTR), Y
    BEQ CMD_NOT_FOUND   ; Jeśli 0, oznacza to brak dopasowania w tabeli

    ; Porównaj słowo w buforze ze słowem w tabeli
    LDY #0
COMPARE_CHAR:
    LDA (CMD_PTR), Y
    BEQ MATCH_FOUND     ; Dośliśmy do końca nazwy komendy w tabeli (bajt $00) -> DOPASOWANO!
    
    CMP INPUT_BUF, Y
    BNE NEXT_COMMAND    ; Różnica znaków -> przejdź do następnej komendy
    
    INY
    JMP COMPARE_CHAR

NEXT_COMMAND:
    ; Przesuń CMD_PTR za nazwę komendy (do bajtu $00)
    LDY #0
FIND_NULL:
    LDA (CMD_PTR), Y
    BEQ NULL_FOUND
    INY
    JMP FIND_NULL

NULL_FOUND:
    ; Pomiń bajt $00 i 2 bajty adresu procedury (+3 bajty łącznie)
    TYA
    CLC
    ADC #3
    ADC CMD_PTR
    STA CMD_PTR
    BCC SEARCH_LOOP
    INC CMD_PTR+1
    JMP SEARCH_LOOP

MATCH_FOUND:
    ; Sprawdź czy po nazwie w buforze jest spacja lub CR/NULL
    LDA INPUT_BUF, Y
    CMP #CHAR_SPACE
    BEQ EXECUTE
    CMP #CHAR_CR
    BEQ EXECUTE
    CMP #CHAR_NULL
    BEQ EXECUTE
    JMP NEXT_COMMAND    ; Np. wpisano "HELPME", a w tabeli było "HELP" -> szukaj dalej

EXECUTE:
    ; Pobierz adres procedury (znajduje się zaraz za bajtem $00 w tabeli)
    INY                 ; Przejdź za bajt $00
    LDA (CMD_PTR), Y
    STA BUF_PTR         ; Młodszy bajt adresu
    INY
    LDA (CMD_PTR), Y
    STA BUF_PTR+1       ; Starszy bajt adresu

    JSR PARSE_PARAMETERS

    ; Wywołaj procedurę za pomocą podwójnego skoku
    JSR INDIRECT_JMP
    RTS

INDIRECT_JMP:
    JMP (BUF_PTR)       ; Skok pod adres zapisany w BUF_PTR ($FC)

CMD_NOT_FOUND:
    JSR PARSE_PARAMETERS
    JSR BUILD_PROGRAM_FILENAME
    BCS UNKNOWN_COMMAND

    JSR new_line
    LDA #<cmd_filename_83
    STA ptr_filename
    LDA #>cmd_filename_83
    STA ptr_filename+1
    LDA #<RAMSTART2
    STA ptr_dest_buf
    LDA #>RAMSTART2
    STA ptr_dest_buf+1
    JSR cf_load
    BCS EXTERNAL_PROGRAM_NOT_LOADED
    JSR run_lexxdos_program
EXTERNAL_PROGRAM_NOT_LOADED:
    RTS

run_lexxdos_program:
    LDA RAMSTART2 + $1D
    CMP #'L'
    BNE @incompatible
    LDA RAMSTART2 + $1E
    CMP #'X'
    BNE @incompatible
    LDA RAMSTART2 + $1F
    CMP #'1'
    BNE @incompatible

    JSR RAMSTART2 + $20
    RTS

@incompatible:
    JSR new_line
    LDA #<MSG_INCOMPATIBLE_PROGRAM
    LDY #>MSG_INCOMPATIBLE_PROGRAM
    JSR print_str
    RTS

UNKNOWN_COMMAND:
    JSR new_line
    LDA #<MSG_BAD_CMD
    LDY #>MSG_BAD_CMD
    JSR print_str
    RTS

BUILD_PROGRAM_FILENAME:
    LDX #0
    LDA #' '
@clear_filename:
    STA cmd_filename_83,x
    INX
    CPX #11
    BNE @clear_filename

    LDX #0
    LDY #0
@copy_command:
    LDA INPUT_BUF,x
    CMP #CHAR_NULL
    BEQ @command_end
    CMP #CHAR_SPACE
    BEQ @command_end
    CPY #8
    BCS @invalid
    CMP #'a'
    BCC @store_command_char
    CMP #'z'+1
    BCS @store_command_char
    AND #$DF
@store_command_char:
    STA cmd_filename_83,y
    INX
    INY
    BRA @copy_command

@command_end:
    CPY #0
    BEQ @invalid
    LDA #'P'
    STA cmd_filename_83+8
    LDA #'R'
    STA cmd_filename_83+9
    LDA #'G'
    STA cmd_filename_83+10
    CLC
    RTS

@invalid:
    SEC
    RTS

; ==============================================================================
; TABELA POLECEŃ (TUTAJ DODAJESZ WŁASNE KOMENDY!)
; Format: .BYTE "NAZWA", $00, .WORD ADRES_PROCEDURY
; Tabela MUSI kończyć się bajtem $00
; ==============================================================================
CMD_TABLE:
    .BYTE "HELP", $00
    .WORD CMD_HELP_ROUTINE

    .BYTE "CLS", $00
    .WORD CMD_CLS_ROUTINE

    .BYTE "DIR", $00
    .WORD CMD_DIR_ROUTINE

    .BYTE "VER", $00
    .WORD CMD_VER_ROUTINE

    .BYTE "MON", $00
    .WORD CMD_MON_ROUTINE

    .BYTE "BASIC", $00
    .WORD CMD_BASIC_ROUTINE

    .BYTE "SLOAD", $00
    .WORD CMD_SLOAD_ROUTINE

    .BYTE "CD", $00
    .WORD CMD_CD_ROUTINE

    .BYTE "TYPE", $00
    .WORD CMD_TYPE_ROUTINE

    ; --- MIEJSCE NA TWOJE NOWE POLECENIA ---
    ; .BYTE "MYCMD", $00
    ; .WORD MY_CUSTOM_JMP_ADDRESS

    .BYTE $00           ; Znacznik końca tabeli!

; ==============================================================================
; PROCEDURY OBSŁUGI POLECEŃ (TUTAJ WSTAWIASZ SWOJE JMP / JSR)
; ==============================================================================

CMD_HELP_ROUTINE:
    JSR new_line
    LDA #<MSG_HELP
    LDY #>MSG_HELP
    JSR print_str
    RTS

CMD_CLS_ROUTINE:
    jmp clr_scr

CMD_DIR_ROUTINE:
    JSR new_line
    jmp cf_dir

CMD_CD_ROUTINE:
    ldx #0
    lda #' '
@clear_cd_filename:
    sta cmd_filename_83,x
    inx
    cpx #11
    bne @clear_cd_filename

    lda parm_buffer
    cmp #CHAR_NULL
    bne @check_dot
    jmp @usage

@check_dot:
    cmp #'.'
    bne @normal_name
    lda parm_buffer+1
    cmp #CHAR_NULL
    beq @single_dot
    cmp #CHAR_SPACE
    beq @single_dot
    cmp #'.'
    bne @normal_name
    lda parm_buffer+2
    cmp #CHAR_NULL
    beq @double_dot
    cmp #CHAR_SPACE
    beq @double_dot
    bra @normal_name

@single_dot:
    lda #'.'
    sta cmd_filename_83
    bra @execute

@double_dot:
    lda #'.'
    sta cmd_filename_83
    sta cmd_filename_83+1
    bra @execute

@normal_name:
    jsr PARSE_FILENAME_83
    bcc @execute
    jmp @usage

@execute:
    lda #<cmd_filename_83
    sta ptr_filename
    lda #>cmd_filename_83
    sta ptr_filename+1
    jmp cf_cd

@usage:
    lda #<MSG_CD_USAGE
    ldy #>MSG_CD_USAGE
    jsr print_str
    rts



CMD_TYPE_ROUTINE:
    lda parm_buffer
    cmp #CHAR_NULL
    beq @usage
    jsr PARSE_FILENAME_83
    bcs @usage
    lda #<cmd_filename_83
    sta ptr_filename
    lda #>cmd_filename_83
    sta ptr_filename+1
    jsr new_line
    jmp cf_type

@usage:
    lda #<MSG_TYPE_USAGE
    ldy #>MSG_TYPE_USAGE
    jsr print_str
    rts

PARSE_FILENAME_83:
    ldx #0
    lda #' '
@clear_filename:
    sta cmd_filename_83,x
    inx
    cpx #11
    bne @clear_filename

    ldx #0
    ldy #0
@base_name:
    lda parm_buffer,x
    cmp #CHAR_NULL
    beq @base_done
    cmp #CHAR_SPACE
    beq @base_done
    cmp #'.'
    beq @extension
    cpy #8
    bcs @invalid
    cmp #'a'
    bcc @store_base
    cmp #'z'+1
    bcs @store_base
    and #$DF
@store_base:
    sta cmd_filename_83,y
    iny
    inx
    bra @base_name

@base_done:
    cpy #0
    beq @invalid
    clc
    rts

@extension:
    cpy #0
    beq @invalid
    inx
    ldy #8
@extension_char:
    lda parm_buffer,x
    cmp #CHAR_NULL
    beq @valid
    cmp #CHAR_SPACE
    beq @valid
    cmp #'.'
    beq @invalid
    cpy #11
    bcs @invalid
    cmp #'a'
    bcc @store_extension
    cmp #'z'+1
    bcs @store_extension
    and #$DF
@store_extension:
    sta cmd_filename_83,y
    iny
    inx
    bra @extension_char

@valid:
    clc
    rts

@invalid:
    sec
    rts

CMD_VER_ROUTINE:
    JSR new_line
    LDA #<MSG_VER
    LDY #>MSG_VER
    JSR print_str
    RTS

CMD_MON_ROUTINE:
    JSR new_line
    jmp WOZMON

CMD_BASIC_ROUTINE:
    ; Clear zero page for Basic
    lda #$00
    ldy #$00
bas_clear_ram:
    sta $0000,y  ; Clear zero page 
    iny
    bne bas_clear_ram
    jmp COLD_START

CMD_SLOAD_ROUTINE:
    JSR new_line
	jsr serial_load_file
	JSR run_lexxdos_program
    rts


; ==============================================================================
; PROCEDURY POMOCNICZE (WEJŚCIE / WYJŚCIE)
; ==============================================================================

; --- WCZYTYWANIE LINII TEKSTU DO INPUT_BUF ---
READ_LINE:
    STZ parm_buffer
    LDX #0
READ_LOOP:
    JSR get_key    ; Pobierz znak z I/O do akumulatora A
    
    CMP #CHAR_NULL
    BEQ READ_LOOP       ; Jeśli brak znaku (0), czekaj dalej

    CMP #CHAR_CR        ; Czy naciśnięto ENTER?
    BEQ READ_DONE

    CMP #CHAR_BS        ; Czy naciśnięto BACKSPACE?
    BEQ HANDLE_BS

    CPX #INPUT_BUF_END  ; Zostaw miejsce na terminator w 64-bajtowym buforze
    BCS READ_LOOP
    
    JSR print_char    ; Wyświetl znak (ECHO)
    STA INPUT_BUF, X    ; Zapisz znak w buforze
    INX
    
    JMP READ_LOOP

HANDLE_BS:
    CPX #0
    BEQ READ_LOOP       ; Jeśli bufor jest pusty, ignoruj Backspace
    DEX
    JSR print_char    ; Wyślij Backspace do terminala
    LDA #CHAR_SPACE
    JSR print_char    ; Nadpisz spacją
    LDA #CHAR_BS
    JSR print_char    ; Cofa kursor
    JMP READ_LOOP

READ_DONE:
    LDA #CHAR_NULL
    STA INPUT_BUF, X    ; Zakończ ciąg znaków bajtem $00
    RTS

PARSE_PARAMETERS:
    LDX #0
@find_separator:
    LDA INPUT_BUF, X
    BEQ @done
    CMP #CHAR_SPACE
    BEQ @skip_separator
    INX
    BRA @find_separator

@skip_separator:
    INX
    LDA INPUT_BUF, X
    CMP #CHAR_SPACE
    BEQ @skip_separator
    LDY #0
@copy_parameter:
    LDA INPUT_BUF, X
    STA parm_buffer, Y
    BEQ @done
    INX
    INY
    BRA @copy_parameter

@done:
    RTS

; --- WYŚWIETLANIE CIĄGU ZNAKÓW ZAKOŃCZONEGO $00 ---
; Adres przekazywany w A (młodszy bajt) i Y (starszy bajt)
PRINT_STRING:
    STA BUF_PTR
    STY BUF_PTR+1
    LDY #0
PSTR_LOOP:
    LDA (BUF_PTR), Y
    BEQ PSTR_DONE
    JSR print_char
    INY
    JMP PSTR_LOOP
PSTR_DONE:
    RTS

; ==============================================================================
; BIOS API: GET_PARAM_BUFFER
; Zwraca adres bufora parametrów.
; Wyjście: A = LSB adresu, Y = MSB adresu
; ==============================================================================
get_param_buffer:
    lda #<parm_buffer   ; Pobierz młodszy bajt adresu ($C0)
    ldy #>parm_buffer   ; Pobierz starszy bajt adresu ($03)
    rts
