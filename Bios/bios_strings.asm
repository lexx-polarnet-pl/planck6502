; ==============================================================================
; BIOS.ASM
; ==============================================================================

welcome_banner: 
	.byte 	"\x1B[0m\x1B[2J\x1B[HThe \x1B[31mW\x1B[32m6\x1B[33m5\x1B[35mC\x1B[0m (Planck/Lexx Edition) simple bios v0.4 (build {build})\r\n"
	.asciiz	"Cześć, jak się masz?\r\n"

; ==============================================================================
; BIOS_FILESYS.ASM
; ==============================================================================

cf_cwd_root_path:	    .byte 		"CF0:", $5C, $00
msg_init:               .asciiz     "Sprawdzanie CF... "
msg_cf_ok:              .byte       "OK", 13, 10, 0
msg_fat_ok:             .byte       "Partycja FAT16 załadowana pomyślnie.", 13, 10, 0
msg_dir_head:           .byte       "Zawartość katalogu: ",0
;msg_dir_end:            .byte       "----------------", 13, 10, 0
msg_dir_dir:            .byte       "<DIR>         ", 0
msg_dir_files_label:    .byte       " Plik(i)      ", 0
msg_dir_bytes_label:    .byte       " bajtów", 0
msg_dir_folders_label:  .byte       " Katalog(i)", 0
msg_loading:            .byte       "Ładowanie pliku... ", 0
msg_file_ok:            .byte       "OK", 13, 10, 0
msg_cd_root:            .byte       "ROOT", 13, 10, 0
msg_err_nocard:         .byte       "Błąd: brak karty CF!", 13, 10, 0
msg_err_read:           .byte       "Błąd odczytu z karty CF!", 13, 10, 0
msg_err_mbr:            .byte       "Błędna sygnatura MBR!", 13, 10, 0
msg_err_notfat16:       .byte       "Błąd: pierwsza partycja nie jest FAT16!", 13, 10, 0
msg_err_bpb:            .byte       "Błąd: nieprawidłowy BPB FAT16!", 13, 10, 0
msg_err_notmounted:     .byte       "Błąd: CF nie jest zamontowana!", 13, 10, 0
msg_err_notfound:       .byte       "Błąd: plik/katalog nie został znaleziony!", $07, 13, 10, 0
msg_err_notdir:         .byte       "Błąd: to nie jest katalog!", 13, 10, 0
msg_err_notfile:        .byte       "Błąd: to nie jest plik!", 13, 10, 0

awaiting_data_msg:      .asciiz     "Czekam na dane od $"
loading_complete_msg:   .asciiz     "Ładowanie zakończone na $"

; ==============================================================================
; BIOS_COMMAND.ASM
; ==============================================================================
MSG_WELCOME:  	.BYTE "DOS gotowy.", $00
;MSG_PROMPT:   	.BYTE "CF0:\\> ", $00
MSG_BAD_CMD:  	.BYTE "Zła komenda lub nazwa pliku", $07,$00
MSG_INCOMPATIBLE_PROGRAM: .BYTE "Program niezgodny z Lexx DOS", $07, $00
MSG_HELP:     	.BYTE "Dostępne komendy: HELP, CD, TYPE, CLS, DIR, VER, MON, BASIC, SLOAD", $00
MSG_VER:      	.BYTE "Lexx DOS Version 0.1 (c) 2026", $00
MSG_CD_USAGE: 	.byte "CD użycie: CD <katalog>", 0
MSG_TYPE_USAGE:	.byte "TYPE użycie: TYPE <plik>", 0	

; ---------------------------------------------------------
; BIOS_MEM.ASM
; ---------------------------------------------------------
msg_post_prefix: .byte "Test RAM: Bazowy  ", $00
msg_base_ok:     .byte $08,"OK | Rozszerzony: ", $00
msg_no_card:     .byte "Brak", $0D, $0A, $00
msg_banks:       .byte " banków (", $00
msg_kb:          .byte "KB)  ", $00
msg_ok:          .byte $08,"OK", $0D, $0A, $00
msg_fail:        .byte $08,"BŁĄD!", $0D, $0A, $00

; ==============================================================================
; BIOS_UTILS.ASM
; ==============================================================================
str_date_prefix: .byte "Jest dzisiaj: ", 0
str_time_prefix: .byte "Godzina: ", 0
str_space:		 .byte "  ", 0

; ==============================================================================
; BIOS_CONSOLE.ASM
; ==============================================================================
str_kbd_prefix:
    .byte "Klawiatura: ", 0
str_mouse_prefix:
    .byte "Mysz:       ", 0
str_ok:
    .byte "OK", 13, 10, 0          ; "OK" + Nowa linia (CR/LF)
str_missing:
    .byte "BRAK", 13, 10, 0        ; "BRAK" + Nowa linia (CR/LF)