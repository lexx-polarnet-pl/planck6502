; ==============================================================================
; SYSTEM REJESTRÓW COMPACTFLASH (Mapowanie od $FFD0 - tryb 8-bit)
; ==============================================================================
CF_DATA       = CF_CARD_PORT        ; Rejestr danych
CF_ERROR      = CF_CARD_PORT + 1    ; Rejestr błędów (odczyt)
CF_FEATURES   = CF_CARD_PORT + 1    ; Rejestr cech (zapis)
CF_SEC_CNT    = CF_CARD_PORT + 2    ; Liczba sektorów
CF_LBA_LOW    = CF_CARD_PORT + 3    ; LBA 0..7
CF_LBA_MID    = CF_CARD_PORT + 4    ; LBA 8..15
CF_LBA_HIGH   = CF_CARD_PORT + 5    ; LBA 16..23
CF_HEAD       = CF_CARD_PORT + 6    ; LBA 24..27 + rejestr Head/Device
CF_STATUS     = CF_CARD_PORT + 7    ; Rejestr stanu (odczyt)
CF_COMMAND    = CF_CARD_PORT + 7    ; Rejestr komend (zapis)

; Komendy CF
CF_CMD_READ   = $20      ; Read Sectors
CF_CMD_FEAT   = $EF      ; Set Features
CF_FEAT_8BIT  = $01      ; Enable 8-bit transfer

; Bity rejestru CF_STATUS

CF_BUSY       = $80
CF_READY      = $40
CF_ERR        = $01

; ==============================================================================
; ZMIENNE ZEROPAGE I PAMIĘĆ (Pojemniki na dane struktury FAT16)
; ==============================================================================
.zeropage
;ptr_l:          .res 1   ; Wskaźnik pomocniczy (Low)
;ptr_h:          .res 1   ; Wskaźnik pomocniczy (High)
; Strona zerowa - wskaźniki dla wpisów katalogu
;dir_ptr_l:      .res 1   ; Wskaźnik na bieżący wpis 32B (Low)
;dir_ptr_h:      .res 1   ; Wskaźnik na bieżący wpis 32B (High)
;cur_lba_l:      .res 1   ; Kopia bieżącego LBA (Low)
;cur_lba_h:      .res 1   ; Kopia bieżącego LBA (Mid-Low)
ptr_l = Z0             ; Wskaźnik pomocniczy (Low)
ptr_h = Z1            ; Wskaźnik pomocniczy (High)
; Strona zerowa - wskaźniki dla wpisów katalogu
dir_ptr_l = Z2        ; Wskaźnik na bieżący wpis 32B (Low)
dir_ptr_h = Z3         ; Wskaźnik na bieżący wpis 32B (High)
cur_lba_l = Z4         ; Kopia bieżącego LBA (Low)
cur_lba_h = Z5         ; Kopia bieżącego LBA (Mid-Low)

ptr_filename:   .res 2   ; Wskaźnik na 11-bajtową bufor z nazwą pliku (np. "TEST    TXT")
ptr_dest_buf:   .res 2   ; Wskaźnik gdzie w RAM zapisać wczytywany plik
; Wskaźniki pomocnicze
;dir_ptr_l:      .res 1
;dir_ptr_h:      .res 1


.segment "BIOS_VECTORS" ; $0200
; Parametry FAT16 wyciągnięte z Boot Sektora:
fat_part_lba:   .res 4   ; LBA początkowe partycji (4 bajty)
fat_sec_p_clus: .res 1   ; Liczba sektorów na klaster (1 bajt)
fat_res_sec:    .res 2   ; Liczba zarezerwowanych sektorów (2 bajty)
fat_num_fats:   .res 1   ; Liczba tablic FAT (1 bajt)
fat_root_ent:   .res 2   ; Maksymalna liczba wpisów w Root Directory (2 bajty)
fat_sec_p_fat:  .res 2   ; Liczba sektorów na jedną tablicę FAT (2 bajty)
fat_root_lba:   .res 4   ; Wyliczony LBA początkowy katalogu głównego
entries_left:   .res 2   ; Licznik pozostałych wpisów katalogu do sprawdzenia
entry_counter:  .res 1   ; Licznik wpisów w obrębie jednego sektora (16 wpisów)
fat_data_lba:   .res 4   ; Wyliczony początek obszaru danych (LBA pierwszego klastra = 2)
cur_cluster:    .res 2   ; Bieżący klaster pliku
bytes_left:     .res 4   ; Pozostałe bajty pliku do odczytu
;entries_left:   .res 2   ; Licznik pozostałych wpisów w katalogu


; ==============================================================================
; BUFOR DANYCH SEKTORA
; ==============================================================================
.segment "FILE_BUFFER"
sector_buffer:  .res 512 ; Zdefiniowany w pliku konfiguracyjnym ld65

.segment "KERNAL"
.proc cf_init_and_mount
    ;jsr bios_clear_screen

    ; --- 1. Inicjalizacja i przełączenie w tryb 8-bit ---
    lda #<msg_init
    ldy #>msg_init
    jsr bios_print_string

    jsr cf_wait_ready
    bcc :+
    jmp err_no_card
:

    ; Wysłanie komendy przełączenia na transfer 8-bitowy
    lda #CF_FEAT_8BIT
    sta CF_FEATURES
    lda #CF_CMD_FEAT
    sta CF_COMMAND
    jsr cf_wait_ready
    bcc :+
    jmp err_no_card
:

    lda #<msg_cf_ok
    ldy #>msg_cf_ok
    jsr bios_print_string

    ; --- 2. Odczyt MBR (Sektor LBA 0) ---
    stz fat_part_lba
    stz fat_part_lba+1
    stz fat_part_lba+2
    stz fat_part_lba+3
    jsr cf_read_sector
    bcc :+
    jmp err_read
:

    ; Sprawdzanie sygnatury bootsektora ($AA55 na końcu 512B)
    lda sector_buffer + 510
    cmp #$55
    beq :+
    jmp err_invalid_mbr
:
    lda sector_buffer + 511
    cmp #$AA
    beq :+
    jmp err_invalid_mbr
:

    ; --- 3. Weryfikacja pierwszej partycji w MBR ($01BE) ---
    ; Typ partycji leży pod przesunięciem $01BE + 4 = $01C2
    lda sector_buffer + $01C2
    cmp #$04                ; FAT16 (<32MB)
    beq type_ok
    cmp #$06                ; FAT16 (>32MB)
    beq type_ok
    cmp #$0E                ; FAT16 (LBA)
    beq type_ok
    jmp err_not_fat16       ; Inna partycja -> zgłoszenie błędu

type_ok:
    ; Pobranie LBA początkowego dla partycji (offset $01C6, 4 bajty)
    lda sector_buffer + $01C6
    sta fat_part_lba
    lda sector_buffer + $01C7
    sta fat_part_lba+1
    lda sector_buffer + $01C8
    sta fat_part_lba+2
    lda sector_buffer + $01C9
    sta fat_part_lba+3

    ; --- 4. Odczyt Boot Sektora Partycji (VBR) ---
    jsr cf_read_sector
    bcc :+
    jmp err_read
:

    ; Odczyt kluczowych parametrów struktury FAT16 z VBR:
    lda sector_buffer + $0D
    sta fat_sec_p_clus      ; Sektory / klaster (offset $0D)

    lda sector_buffer + $0E
    sta fat_res_sec
    lda sector_buffer + $0F
    sta fat_res_sec+1        ; Zarezerwowane sektory (offset $0E)

    lda sector_buffer + $10
    sta fat_num_fats        ; Liczba tablic FAT (offset $10)

    lda sector_buffer + $11
    sta fat_root_ent
    lda sector_buffer + $12
    sta fat_root_ent+1      ; Liczba wpisów w Root Dir (offset $11)

    lda sector_buffer + $16
    sta fat_sec_p_fat
    lda sector_buffer + $17
    sta fat_sec_p_fat+1      ; Sektory na 1 FAT (offset $16)

    ; --- 5. Obliczenie adresu LBA dla Root Directory ---
    ; Formula: Root_LBA = Partition_LBA + Reserved_Sectors + (Num_FATs * Sec_Per_FAT)
    clc
    lda fat_part_lba
    adc fat_res_sec
    sta fat_root_lba
    lda fat_part_lba+1
    adc fat_res_sec+1
    sta fat_root_lba+1
    lda fat_part_lba+2
    adc #$00
    sta fat_root_lba+2
    lda fat_part_lba+3
    adc #$00
    sta fat_root_lba+3

    ldx fat_num_fats
fat_loop:
    clc
    lda fat_root_lba
    adc fat_sec_p_fat
    sta fat_root_lba
    lda fat_root_lba+1
    adc fat_sec_p_fat+1
    sta fat_root_lba+1
    bcc :+
    inc fat_root_lba+2
    bne :+
    inc fat_root_lba+3
:   dex
    bne fat_loop

    ; Sukces - Gotowy do dalszych operacji
    lda #<msg_fat_ok
    ldy #>msg_fat_ok
    jsr bios_print_string
    clc                     ; Carry clear = OK
    rts

; Obsługa wyjść awaryjnych z kodami błędów
err_no_card:
    lda #<msg_err_nocard
    ldy #>msg_err_nocard
    jmp show_err

err_read:
    lda #<msg_err_read
    ldy #>msg_err_read
    jmp show_err

err_invalid_mbr:
    lda #<msg_err_mbr
    ldy #>msg_err_mbr
    jmp show_err

err_not_fat16:
    lda #<msg_err_notfat16
    ldy #>msg_err_notfat16

show_err:
    jsr bios_print_string
    sec                     ; Carry set = BŁĄD
    rts
.endproc

; ==============================================================================
; PROCEDURY POMOCNICZE W CA65
; ==============================================================================

.proc cf_wait_ready
    phy
    phx
    pha                     ; Zachowaj akumulator
    
    ldx #0
    ldy #0
    lda #10                 ; Zewnętrzny licznik (ok. 1.5 - 2 sekundy oczekiwania na 4MHz)
    sta ptr_l               ; Używamy tymczasowej zmiennej jako 3-bajtowego licznika

wait_loop:
    lda CF_STATUS
    cmp #$FF                ; Jeśli magistrala pływa (brak karty / linia podciągnięta), zwróć błąd
    beq fail_timeout
    
    and #CF_BUSY
    beq ready               ; Jeśli BUSY == 0, sprawdzamy READY

    dex
    bne wait_loop
    dey
    bne wait_loop
    dec ptr_l
    bne wait_loop

fail_timeout:
    pla
    plx
    ply
    sec                     ; Timeout / Błąd
    rts

ready:
    lda CF_STATUS
    and #CF_READY
    beq wait_loop           ; Czekaj, aż bit READY się zapali (READY == 1)

    pla
    ply
    plx
    clc                     ; Karta jest gotowa!
    rts
.endproc

.proc cf_read_sector
    jsr cf_wait_ready
    bcs fail

    ; Ładowanie adresu LBA
    lda #$E0                ; Tryb LBA, Master Device
    ora fat_part_lba+3
    sta CF_HEAD

    lda fat_part_lba+2
    sta CF_LBA_HIGH
    lda fat_part_lba+1
    sta CF_LBA_MID
    lda fat_part_lba
    sta CF_LBA_LOW

    lda #$01                ; Ilość sektorów = 1
    sta CF_SEC_CNT

    lda #CF_CMD_READ        ; Rozkaz odczytu
    sta CF_COMMAND

    jsr cf_wait_ready
    bcs fail

    lda CF_STATUS
    and #CF_ERR
    bne fail                ; Błąd sprzętowy po stronie karty CF

    ; Pobranie bajtów do bufora
    lda #<sector_buffer
    sta ptr_l
    lda #>sector_buffer
    sta ptr_h

    ldy #$00
    ldx #$02                ; Pętla 2 * 256 B = 512 B
read_loop:
    lda CF_DATA
    sta (ptr_l),y
    iny
    bne read_loop
    inc ptr_h
    dex
    bne read_loop

    clc                     ; Odczyt poprawny
    rts
fail:
    sec                     ; Błąd
    rts
.endproc

; ==============================================================================
; PROCEDURA: cf_dir
; WYŚWIETLA ZAWARTOŚĆ KATALOGU GŁÓWNEGO FAT16
; ==============================================================================
.proc cf_dir
    ; Wyświetlenie nagłówka
    lda #<msg_dir_head
    ldy #>msg_dir_head
    jsr print_str

    ; 1. Inicjalizacja liczników
    lda fat_root_ent
    sta entries_left
    lda fat_root_ent+1
    sta entries_left+1

    ; Skopiowanie początkowego LBA Katalogu Głównego
    lda fat_root_lba
    sta fat_part_lba
    lda fat_root_lba+1
    sta fat_part_lba+1
    lda fat_root_lba+2
    sta fat_part_lba+2
    lda fat_root_lba+3
    sta fat_part_lba+3

read_next_sector:
    ; Sprawdzenie czy zostały jeszcze jakieś wpisy do przetworzenia
    lda entries_left
    ora entries_left+1
    bne :+
    jmp dir_done            ; Brak wpisów -> koniec
:
    ;beq dir_done            ; Brak wpisów -> koniec

    ; Odczyt sektora Root Directory do bufora
    jsr cf_read_sector
    bcc :+
    jmp dir_error           ; Błąd odczytu
:
    ;bcs dir_error           ; Błąd odczytu

    ; Ustawienie wskaźnika na początek bufora (sector_buffer)
    lda #<sector_buffer
    sta dir_ptr_l
    lda #>sector_buffer
    sta dir_ptr_h

    lda #16                 ; 16 wpisów po 32 bajty na sektor (512 / 32 = 16)
    sta entry_counter

process_entry:
    ldy #0
    lda (dir_ptr_l),y       ; Pobranie pierwszego bajtu nazwy pliku

    ; A. Koniec katalogu (Bajt $00)
    beq dir_done

    ; B. Skasowany plik (Bajt $E5)
    cmp #$E5
    beq skip_entry

    ; C. Sprawdzenie atrybutów (Offset $0B we wpisie)
    ldy #$0B
    lda (dir_ptr_l),y
    cmp #$0F                ; Długa nazwa VFAT (LFN) -> ignoruj
    beq skip_entry
    and #$08                ; Bit 3 = Etykieta wolumenu (Volume Label) -> ignoruj
    bne skip_entry

    ; --- D. WYŚWIETLENIE NAZWY PLIKU/KATALOGU (8 znaków nazwy) ---
    ldy #0
print_name:
    lda (dir_ptr_l),y
    jsr print_char
    iny
    cpy #8
    bne print_name

    ; Odstęp miedzy nazwą a rozszerzeniem
    lda #'.'
    jsr print_char

    ; --- E. WYŚWIETLENIE ROZSZERZENIA (3 znaki) ---
print_ext:
    lda (dir_ptr_l),y
    jsr print_char
    iny
    cpy #11
    bne print_ext

    ; --- F. SPRAWDZENIE CZY TO KATALOG CZY PLIK ---
    ldy #$0B
    lda (dir_ptr_l),y
    and #$10                ; Bit 4 = Directory
    beq is_file

    ; To jest katalog
    lda #<msg_dir_dir
    ldy #>msg_dir_dir
    jsr print_str
    jmp skip_entry

is_file:
    ; To jest plik
    lda #<msg_dir_file
    ldy #>msg_dir_file
    jsr print_str

skip_entry:
    ; Zmniejszenie ogólnej liczby pozostałych wpisów
    sec
    lda entries_left
    sbc #1
    sta entries_left
    lda entries_left+1
    sbc #0
    sta entries_left+1

    ; Przejście do następnego wpisu (+32 bajty we wskaźniku)
    clc
    lda dir_ptr_l
    adc #32
    sta dir_ptr_l
    bcc :+
    inc dir_ptr_h
:
    ; Zmniejszenie licznika wpisów w sektorze
    dec entry_counter
    bne process_entry

    ; --- Przejście do kolejnego sektora Katalogu Głównego ---
    inc fat_part_lba
    bne :+
    inc fat_part_lba+1
    bne :+
    inc fat_part_lba+2
    bne :+
    inc fat_part_lba+3
:
    jmp read_next_sector

dir_done:
    lda #<msg_dir_end
    ldy #>msg_dir_end
    jsr print_str
    clc
    rts

dir_error:
    sec
    rts
.endproc

; ==============================================================================
; PROCEDURA: cf_read_file
; WEJŚCIE:
;   ptr_filename - adres 11-bajtowego ciągu z nazwą (np. "AUTOEXECBAT")
;   ptr_dest_buf - adres w pamięci RAM, pod który ma zostać załadowany plik
; WYJŚCIE:
;   Carry Clear = Sukces
;   Carry Set   = Błąd (brak pliku lub błąd odczytu)
; ==============================================================================
.proc cf_read_file
    lda #<msg_loading
    ldy #>msg_loading
    jsr print_str

    ; 1. Obliczenie LBA początku obszaru danych (Data Area LBA)
    ; Data_LBA = Root_LBA + (Root_Entries * 32 / 512)
    jsr calc_data_area_lba

    ; 2. Szukanie pliku w katalogu głównym (Root Directory)
    lda fat_root_ent
    sta entries_left
    lda fat_root_ent+1
    sta entries_left+1

    lda fat_root_lba
    sta fat_part_lba
    lda fat_root_lba+1
    sta fat_part_lba+1
    lda fat_root_lba+2
    sta fat_part_lba+2
    lda fat_root_lba+3
    sta fat_part_lba+3

search_sector_loop:
    lda entries_left
    ora entries_left+1
    bne :+
    jmp err_not_found
:

    jsr cf_read_sector
    bcc :+
    jmp err_cf_read
:

    lda #<sector_buffer
    sta dir_ptr_l
    lda #>sector_buffer
    sta dir_ptr_h

    ldx #16                 ; 16 wpisów na sektor
search_entry_loop:
    ldy #0
    lda (dir_ptr_l),y
    bne :+
    jmp err_not_found       ; Bajt $00 = Koniec wpisów
:
    cmp #$E5
    beq skip_entry          ; Bajt $E5 = Plik skasowany

    ; Porównanie 11 bajtów nazwy pliku
    ldy #0
compare_name_loop:
    lda (dir_ptr_l),y
    cmp (ptr_filename),y
    bne name_mismatch
    iny
    cpy #11
    bne compare_name_loop

    ; --- ZNALAZŁO PLIK! ---
    jmp file_found

name_mismatch:
skip_entry:
    ; Decrement entries_left
    sec
    lda entries_left
    sbc #1
    sta entries_left
    lda entries_left+1
    sbc #0
    sta entries_left+1

    ; Przesunięcie wskaźnika o +32B
    clc
    lda dir_ptr_l
    adc #32
    sta dir_ptr_l
    bcc :+
    inc dir_ptr_h
:
    dex
    bne search_entry_loop

    ; Przejście do kolejnego sektora Katalogu Głównego
    inc fat_part_lba
    bne :+
    inc fat_part_lba+1
    bne :+
    inc fat_part_lba+2
    bne :+
    inc fat_part_lba+3
:   jmp search_sector_loop

file_found:
    ; Pobranie numeru pierwszego klastra (offset $1A, 2 bajty)
    ldy #$1A
    lda (dir_ptr_l),y
    sta cur_cluster
    iny
    lda (dir_ptr_l),y
    sta cur_cluster+1

    ; Pobranie rozmiaru pliku w bajtach (offset $1C, 4 bajty)
    ldy #$1C
    lda (dir_ptr_l),y
    sta bytes_left
    iny
    lda (dir_ptr_l),y
    sta bytes_left+1
    iny
    lda (dir_ptr_l),y
    sta bytes_left+2
    iny
    lda (dir_ptr_l),y
    sta bytes_left+3

    ; --------------------------------------------------------------------------
    ; 3. Pętla odczytu klastrów pliku
    ; --------------------------------------------------------------------------
read_cluster_chain:
    ; Sprawdzenie, czy klaster to marker końca pliku (FAT16 EOF >= $FFF8)
    lda cur_cluster+1
    cmp #$FF
    bcc cluster_valid
    lda cur_cluster
    cmp #$F8
    bcs load_success        ; Osiągnięto EOF (End Of File)

cluster_valid:
    ; Obliczenie LBA dla bieżącego klastra:
    ; Sektor_LBA = Data_LBA + (cur_cluster - 2) * fat_sec_p_clus
    jsr calc_cluster_lba

    ; Odczyt wszystkich sektorów w tym klastrze
    ldx fat_sec_p_clus
read_sector_in_cluster:
    jsr cf_read_sector
    bcs err_cf_read

    ; Kopiowanie z bufora 512B (`sector_buffer`) pod docelowy adres `ptr_dest_buf`
    jsr copy_sector_to_dest

    ; Zmniejszenie liczby pozostałych bajtów
    sec
    lda bytes_left
    sbc #<512
    sta bytes_left
    lda bytes_left+1
    sbc #>512
    sta bytes_left+1
    lda bytes_left+2
    sbc #0
    sta bytes_left+2
    lda bytes_left+3
    sbc #0
    sta bytes_left+3

    ; Sprawdzanie czy wczytano już całość pliku
    lda bytes_left
    ora bytes_left+1
    ora bytes_left+2
    ora bytes_left+3
    beq load_success

    ; Następny sektor w klastrze
    inc fat_part_lba
    bne :+
    inc fat_part_lba+1
    bne :+
    inc fat_part_lba+2
    bne :+
    inc fat_part_lba+3
:   dex
    bne read_sector_in_cluster

    ; Odczytanie kolejnego klastra z Tablicy FAT
    jsr get_next_cluster_from_fat
    jmp read_cluster_chain

load_success:
    lda #<msg_file_ok
    ldy #>msg_file_ok
    jsr print_str
    clc                     ; Sukces
    rts

err_not_found:
    lda #<msg_err_notfound
    ldy #>msg_err_notfound
    jsr print_str
    sec                     ; Błąd
    rts

err_cf_read:
    lda #<msg_err_read
    ldy #>msg_err_read
    jsr print_str
    sec                     ; Błąd
    rts
.endproc

; ==============================================================================
; PROCEDURY POMOCNICZE
; ==============================================================================

; Oblicza Data Area LBA
.proc calc_data_area_lba
    ; Bajty katalogu = fat_root_ent * 32
    ; Sektory katalogu = (fat_root_ent * 32) / 512 = fat_root_ent / 16
    lda fat_root_ent
    lsr fat_root_ent+1
    ror a
    lsr fat_root_ent+1
    ror a
    lsr fat_root_ent+1
    ror a
    lsr fat_root_ent+1
    ror a                   ; A mieści liczbę sektorów Katalogu Główna

    clc
    adc fat_root_lba
    sta fat_data_lba
    lda #0
    adc fat_root_lba+1
    sta fat_data_lba+1
    lda #0
    adc fat_root_lba+2
    sta fat_data_lba+2
    lda #0
    adc fat_root_lba+3
    sta fat_data_lba+3
    rts
.endproc

; Oblicza LBA sektora na podstawie klastra: fat_part_lba = Data_LBA + (cluster - 2) * sec_per_clus
.proc calc_cluster_lba
    ; temp = cur_cluster - 2
    sec
    lda cur_cluster
    sbc #2
    sta fat_part_lba
    lda cur_cluster+1
    sbc #0
    sta fat_part_lba+1

    ; Mnożenie przez fat_sec_p_clus (przy założeniu, że sec_per_clus jest potęgą 2: 1, 2, 4, 8, 16...)
    lda fat_sec_p_clus
shift_loop:
    lsr a
    beq shift_done
    asl fat_part_lba
    rol fat_part_lba+1
    jmp shift_loop

shift_done:
    ; fat_part_lba = fat_data_lba + fat_part_lba
    clc
    lda fat_part_lba
    adc fat_data_lba
    sta fat_part_lba
    lda fat_part_lba+1
    adc fat_data_lba+1
    sta fat_part_lba+1
    lda #0
    adc fat_data_lba+2
    sta fat_part_lba+2
    lda #0
    adc fat_data_lba+3
    sta fat_part_lba+3
    rts
.endproc

; Odczytuje wartość następnego klastra z Tablicy FAT16
.proc get_next_cluster_from_fat
    ; W FAT16 każdy wpis ma 2 bajty. Offset bajtowy w FAT = cur_cluster * 2
    ; Sektor FAT = Partition_LBA + Reserved_Sectors + (cur_cluster * 2 / 512)
    
    ; Wskaźnik sektora w FAT (cur_cluster / 256)
    lda cur_cluster+1
    clc
    adc fat_part_lba        ; partition_lba
    adc fat_res_sec
    sta fat_part_lba
    lda #0
    adc fat_part_lba+1
    adc fat_res_sec+1
    sta fat_part_lba+1

    jsr cf_read_sector      ; Odczyt sektora tablicy FAT

    ; Przesunięcie wewnątrz sektora FAT (cur_cluster * 2 % 512)
    lda cur_cluster
    asl a                   ; * 2
    sta dir_ptr_l
    lda #>sector_buffer
    adc #0
    sta dir_ptr_h

    ; Pobranie wartości nowego klastra z bufora
    ldy #0
    lda (dir_ptr_l),y
    sta cur_cluster
    iny
    lda (dir_ptr_l),y
    sta cur_cluster+1
    rts
.endproc

; Kopiuje 512 bajtów z bufora sektora pod docelowy adres w RAM i inkrementuje ptr_dest_buf
.proc copy_sector_to_dest
    phy
    phx
    ldy #0
    ldx #2                  ; 2 * 256 B = 512 B
copy_loop:
    lda sector_buffer,y
    sta (ptr_dest_buf),y
    iny
    bne copy_loop
    inc sector_buffer+1     ; Przesunięcie źródła
    inc ptr_dest_buf+1      ; Przesunięcie celu
    dex
    bne copy_loop

    ply
    plx
    rts
.endproc

; ==============================================================================
; SEKCJA STAŁYCH ŁAŃCUCHÓW ZNAKOWYCH
; ==============================================================================
;.rodata
msg_init:        .asciiz "Sprawdzanie CF... "
msg_cf_ok:       .byte "OK!", 13, 10, 0
msg_fat_ok:      .byte "Partycja FAT16 zaladowana pomyslnie.", 13, 10, 0
msg_err_nocard:  .byte "Brak karty CF!", 13, 10, 0
;msg_err_read:    .byte "Blad odczytu sektora!", 13, 10, 0
msg_err_mbr:     .byte "Bledna sygnatura MBR!", 13, 10, 0
msg_err_notfat16:.byte "Blad: Pierwsza partycja nie jest FAT16!", 13, 10, 0

msg_dir_head:   .byte "--- KATALOG GLOWNY ---", 13, 10, 0
msg_dir_end:    .byte "----------------------", 13, 10, 0
msg_dir_dir:    .byte "  <DIR>", 13, 10, 0
msg_dir_file:   .byte "       ", 13, 10, 0
;msg_crlf:       .byte 13, 10, 0
msg_loading:    .byte "Ladowanie pliku... ", 0
msg_file_ok:    .byte "OK!", 13, 10, 0
msg_err_notfound:.byte "Blad: Plik nie zostal znaleziony!", 13, 10, 0
msg_err_read:   .byte "Blad odczytu z karty CF!", 13, 10, 0


; kod obsługi serial load

serial_load_file: ; loader with IRQ support
    CURRENT_RAM_ADDRESS = Z0 
    LOADING_STATE = Z2

    lda #<RAMSTART2                      ; initializing RAM address counter
    sta CURRENT_RAM_ADDRESS
    lda #>RAMSTART2
    sta CURRENT_RAM_ADDRESS + 1

    lda #0
    sta LOADING_STATE
    
    sei
	lda #<loader_irq
	sta bios_vectors_acia1_irq
	lda #>loader_irq
	sta bios_vectors_acia1_irq+1    
    cli

    lda #<awaiting_data_msg
    ldy #>awaiting_data_msg
    jsr print_str
    lda CURRENT_RAM_ADDRESS+1
    jsr print_a_hex
    lda CURRENT_RAM_ADDRESS 
    jsr print_a_hex
    jsr new_line    

wait_for_first_data:
    lda LOADING_STATE                           ; checking loading state
    cmp #$00                                    ; the ISR will set to $01 as soon as a byte is read
    beq wait_for_first_data

loader_loop:
    lda #$02                                    ; assuming we're done loading, we set loading state to $02
    sta LOADING_STATE
    ldx  #$FF

loader_delay:   
    dex          
    bne  loader_delay   

    lda LOADING_STATE                           ; check back loading state, which was eventually updated by the ISR
    cmp #$02
    bne loader_loop

done_loading:
    sei
    lda #<acia_irq
	sta bios_vectors_acia1_irq
	lda #>acia_irq
	sta bios_vectors_acia1_irq+1
    cli
    jsr new_line
    lda #<loading_complete_msg
    ldy #>loading_complete_msg
    jsr print_str
    lda CURRENT_RAM_ADDRESS+1
    jsr print_a_hex
    lda CURRENT_RAM_ADDRESS 
    jsr print_a_hex
    jsr new_line       

    rts

loader_irq:
    lda #1
    sta LOADING_STATE
	lda ACIA1_DATA         	; read char from ACIA
    ldy #0
    sta (CURRENT_RAM_ADDRESS),y
    inc CURRENT_RAM_ADDRESS
    bne loader_irq_complete
    inc CURRENT_RAM_ADDRESS + 1
    lda #'.'    ; print progress dot every 256 bytes
    jsr print_char    
loader_irq_complete:
    jmp bios_return_from_irq

awaiting_data_msg: .asciiz   "Awaiting data at $"
loading_complete_msg: .asciiz   "Loading complete at $"