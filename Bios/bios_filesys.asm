; ==============================================================================
; DOS / COMPACTFLASH FAT16 - TRYB TYLKO DO ODCZYTU
; ==============================================================================
;
; Założenia:
;   - jedna karta CF
;   - jedna pierwsza partycja podstawowa
;   - partycja FAT16
;   - sektor = 512 bajtów
;   - CF pracuje w trybie 8-bitowym
;   - LBA28
;   - brak zapisu na CF
;   - ignorowane są:
;       * pozostałe partycje
;       * LFN (VFAT)
;       * Volume Label
;       * wpisy skasowane
;
; ------------------------------------------------------------------------------
; PUBLICZNY INTERFEJS MODUŁU
; ------------------------------------------------------------------------------
;
; cf_init_and_mount
;   WEJŚCIE: brak
;   WYJŚCIE: C=0 sukces, C=1 błąd
;   Działanie:
;       inicjalizuje CF, włącza tryb 8-bit, znajduje pierwszą
;       partycję FAT16, odczytuje BPB i przygotowuje system FAT.
;
; cf_dir
;   WEJŚCIE: brak
;   WYJŚCIE: C=0 sukces, C=1 błąd
;   Działanie:
;       wyświetla zawartość bieżącego katalogu.
;
; cf_cd
;   WEJŚCIE:
;       ptr_filename -> 11-bajtowa nazwa FAT 8.3
;   WYJŚCIE:
;       C=0 sukces, C=1 błąd
;   Działanie:
;       przechodzi do podanego katalogu.
;       Obsługiwane są również:
;           "."   - bieżący katalog
;           ".."  - katalog nadrzędny
;
; cf_cd_root
;   WEJŚCIE: brak
;   WYJŚCIE: C=0
;   Działanie:
;       przechodzi do katalogu głównego.
;
; cf_load
;   WEJŚCIE:
;       ptr_filename -> 11-bajtowa nazwa FAT 8.3
;       ptr_dest_buf -> adres docelowy w RAM
;   WYJŚCIE:
;       C=0 sukces, C=1 błąd
;   Działanie:
;       odczytuje cały plik do RAM.
;       Po zakończeniu ptr_dest_buf wskazuje za ostatni bajt.
;
; cf_type
;   WEJŚCIE:
;       ptr_filename -> 11-bajtowa nazwa FAT 8.3
;   WYJŚCIE:
;       C=0 sukces, C=1 błąd
;   Działanie:
;       wyświetla zawartość pliku przez BIOS print_char.
;
; ------------------------------------------------------------------------------
; ZMIENNE WEJŚCIOWE - ZEROPAGE
; ------------------------------------------------------------------------------
;
; ptr_filename = Z0/Z1
; ptr_dest_buf = Z2/Z3
; dir_ptr      = Z4/Z5       - wewnętrzny wskaźnik wpisu FAT
;
; ------------------------------------------------------------------------------
; WAŻNE
; ------------------------------------------------------------------------------
;
; Moduł korzysta z:
;
;   bios_print_string
;       A = low byte adresu
;       Y = high byte adresu
;
;   bios_print_char
;       A = znak
;
; oraz z symbolu:
;
;   CF_CARD_PORT
;
; ==============================================================================

; ==============================================================================
; REJESTRY COMPACTFLASH
; ==============================================================================

CF_DATA       = CF_CARD_PORT
CF_ERROR      = CF_CARD_PORT + 1
CF_FEATURES   = CF_CARD_PORT + 1
CF_SEC_CNT    = CF_CARD_PORT + 2
CF_LBA_LOW    = CF_CARD_PORT + 3
CF_LBA_MID    = CF_CARD_PORT + 4
CF_LBA_HIGH   = CF_CARD_PORT + 5
CF_HEAD       = CF_CARD_PORT + 6
CF_STATUS     = CF_CARD_PORT + 7
CF_COMMAND    = CF_CARD_PORT + 7

; ------------------------------------------------------------------------------
; ATA / CF COMMANDS
; ------------------------------------------------------------------------------

CF_CMD_READ   = $20
CF_CMD_FEAT   = $EF

CF_FEAT_8BIT  = $01

; ------------------------------------------------------------------------------
; STATUS BITS
; ------------------------------------------------------------------------------

CF_BUSY       = $80
CF_READY      = $40
CF_DRQ        = $08
CF_ERR        = $01

; ------------------------------------------------------------------------------
; BŁĘDY WEWNĘTRZNE MODUŁU
; ------------------------------------------------------------------------------

CFERR_NONE       = $00
CFERR_READ       = $01
CFERR_NOT_FOUND  = $02
CFERR_NOT_DIR    = $03
CFERR_NOT_FILE   = $04
CFERR_BAD_FAT    = $05
CFERR_NOT_MOUNT  = $06
CFERR_BAD_FS     = $07
CFERR_PATH_LONG  = $08


; ==============================================================================
; ZEROPAGE
; ==============================================================================

.zeropage

ptr_filename = Z0       ; 2B - nazwa FAT 8.3
ptr_dest_buf = Z2       ; 2B - adres docelowy LOAD

dir_ptr_l    = Z4       ; 2B - wskaźnik wpisu katalogowego
dir_ptr_h    = Z5


; ==============================================================================
; BIOS VECTORS / ZMIENNE DOS
; ==============================================================================

.segment "BIOS_VECTORS"

; ------------------------------------------------------------------------------
; Informacje o partycji
; ------------------------------------------------------------------------------

fat_part_lba:       .res 4     ; początek pierwszej partycji

fat_sec_p_clus:     .res 1     ; sektory / klaster
fat_res_sec:        .res 2     ; sektory zarezerwowane
fat_num_fats:       .res 1     ; liczba FAT
fat_root_ent:       .res 2     ; liczba wpisów Root Directory
fat_sec_p_fat:      .res 2     ; sektory / FAT

fat_fat_lba:        .res 4     ; początek pierwszej FAT
fat_root_lba:       .res 4     ; początek Root Directory
fat_root_secs:      .res 2     ; liczba sektorów Root Directory
fat_data_lba:       .res 4     ; początek obszaru danych

; ------------------------------------------------------------------------------
; Bieżący katalog
; ------------------------------------------------------------------------------

cur_dir_cluster:    .res 2     ; 0 = Root Directory

dir_cluster:        .res 2     ; aktualny klaster podczas iteracji katalogu
dir_sector_idx:     .res 1     ; sektor w aktualnym klastrze
dir_root:           .res 1     ; !=0 gdy iterujemy Root Directory
dir_root_left:      .res 2     ; pozostałe sektory Root Directory

dir_entry_count:    .res 1     ; wpisy pozostałe w sektorze

dir_file_count:     .res 2
dir_folder_count:   .res 2
dir_total_bytes:    .res 4
dir_num:            .res 4
dir_num_rem:        .res 1
dir_num_bit:        .res 1
dir_digits:         .res 10
dir_digits_count:   .res 1
dir_digits_left:    .res 1
dir_pad_count:      .res 1
dir_tmp:            .res 1
dir_decimal_value:  .res 1

; ------------------------------------------------------------------------------
; Bieżący LBA I/O
; ------------------------------------------------------------------------------

cf_lba:             .res 4

; ------------------------------------------------------------------------------
; Dane otwartego pliku
; ------------------------------------------------------------------------------

file_cluster:       .res 2
file_sector_idx:     .res 1
file_bytes:         .res 4

; ------------------------------------------------------------------------------
; Tymczasowe dane
; ------------------------------------------------------------------------------

cf_lookup_cluster:  .res 2

cf_mul:             .res 4
cf_tmp16:           .res 2
cf_tmp8:            .res 1

cf_copy_count:      .res 2

cf_timeout0:        .res 1
cf_timeout1:        .res 1
cf_timeout2:        .res 1

cf_mounted:         .res 1
cf_error:           .res 1


; ==============================================================================
; BUFOR SEKTORA
; ==============================================================================

.segment "FILE_BUFFER"

sector_buffer:
    .res 512


; ==============================================================================
; KOD
; ==============================================================================

.segment "KERNAL"


; ==============================================================================
; CF INITIALIZATION + FAT16 MOUNT
; ==============================================================================

.proc cf_init_and_mount

    jsr cf_cwd_reset
    stz cf_mounted
    stz cf_error

    lda #<msg_init
    ldy #>msg_init
    jsr bios_print_string

    ; --------------------------------------------------------------------------
    ; Czekamy na fizyczną gotowość CF.
    ;
    ; To jest specjalnie DŁUŻSZY timeout.
    ; Nie zakładamy, że CF po resecie wystartuje tak szybko jak 6502.
    ; --------------------------------------------------------------------------

    jsr cf_wait_ready_long
    bcc @ready

    jmp err_no_card

@ready:

    ; --------------------------------------------------------------------------
    ; Włączenie trybu 8-bitowego
    ; --------------------------------------------------------------------------

    lda #CF_FEAT_8BIT
    sta CF_FEATURES

    lda #CF_CMD_FEAT
    sta CF_COMMAND

    jsr cf_wait_ready_long
    bcc @feature_ok

    jmp err_no_card

@feature_ok:

    lda #<msg_cf_ok
    ldy #>msg_cf_ok
    jsr bios_print_string

    ; --------------------------------------------------------------------------
    ; LBA = 0
    ; --------------------------------------------------------------------------

    stz cf_lba
    stz cf_lba+1
    stz cf_lba+2
    stz cf_lba+3

    jsr cf_read_sector
    bcc @mbr_ok

    jmp err_read

@mbr_ok:

    ; --------------------------------------------------------------------------
    ; Sygnatura MBR AA55
    ; --------------------------------------------------------------------------

    lda sector_buffer+$1FE
    cmp #$55
    beq @sig_low_ok

    jmp err_invalid_mbr

@sig_low_ok:

    lda sector_buffer+$1FF
    cmp #$AA
    beq @sig_ok

    jmp err_invalid_mbr

@sig_ok:

    ; --------------------------------------------------------------------------
    ; Pierwsza partycja:
    ;
    ; wpis zaczyna się od $1BE
    ; typ = +4 = $1C2
    ; LBA start = +8 = $1C6
    ; --------------------------------------------------------------------------

    lda sector_buffer+$1C2

    cmp #$04
    beq @fat_type_ok

    cmp #$06
    beq @fat_type_ok

    cmp #$0E
    beq @fat_type_ok

    jmp err_not_fat16

@fat_type_ok:

    ; --------------------------------------------------------------------------
    ; LBA początku partycji
    ; --------------------------------------------------------------------------

    lda sector_buffer+$1C6
    sta fat_part_lba

    lda sector_buffer+$1C7
    sta fat_part_lba+1

    lda sector_buffer+$1C8
    sta fat_part_lba+2

    lda sector_buffer+$1C9
    sta fat_part_lba+3

    ; --------------------------------------------------------------------------
    ; VBR
    ; --------------------------------------------------------------------------

    lda fat_part_lba
    sta cf_lba

    lda fat_part_lba+1
    sta cf_lba+1

    lda fat_part_lba+2
    sta cf_lba+2

    lda fat_part_lba+3
    sta cf_lba+3

    jsr cf_read_sector
    bcc @vbr_ok

    jmp err_read

@vbr_ok:

    ; --------------------------------------------------------------------------
    ; Bytes per sector musi być 512
    ; BPB offset $0B
    ; --------------------------------------------------------------------------

    lda sector_buffer+$0B
    cmp #$00
    beq @bytes_per_sector_low_ok
    jmp err_bad_bpb

@bytes_per_sector_low_ok:

    lda sector_buffer+$0C
    cmp #$02
    beq @bytes_per_sector_high_ok
    jmp err_bad_bpb

@bytes_per_sector_high_ok:

    ; --------------------------------------------------------------------------
    ; Sectors / cluster
    ; --------------------------------------------------------------------------

    lda sector_buffer+$0D
    sta fat_sec_p_clus

    bne @spc_nonzero
    jmp err_bad_bpb

@spc_nonzero:

    ; FAT16 wymaga potęgi 2.
    ; Test: x & (x-1) == 0

    sta cf_tmp8
    sec
    sbc #1
    and cf_tmp8
    beq @spc_ok

    jmp err_bad_bpb

@spc_ok:

    ; --------------------------------------------------------------------------
    ; Reserved sectors
    ; --------------------------------------------------------------------------

    lda sector_buffer+$0E
    sta fat_res_sec

    lda sector_buffer+$0F
    sta fat_res_sec+1

    ; --------------------------------------------------------------------------
    ; Number of FATs
    ; --------------------------------------------------------------------------

    lda sector_buffer+$10
    sta fat_num_fats

    bne @fats_nonzero
    jmp err_bad_bpb

@fats_nonzero:

    ; --------------------------------------------------------------------------
    ; Root entries
    ; --------------------------------------------------------------------------

    lda sector_buffer+$11
    sta fat_root_ent

    lda sector_buffer+$12
    sta fat_root_ent+1

    ; --------------------------------------------------------------------------
    ; Sectors / FAT
    ; --------------------------------------------------------------------------

    lda sector_buffer+$16
    sta fat_sec_p_fat

    lda sector_buffer+$17
    sta fat_sec_p_fat+1

    lda fat_sec_p_fat
    ora fat_sec_p_fat+1
    bne @fat_size_ok

    jmp err_bad_bpb

@fat_size_ok:

    ; --------------------------------------------------------------------------
    ; FAT_LBA =
    ;     partition_lba + reserved_sectors
    ; --------------------------------------------------------------------------

    clc

    lda fat_part_lba
    adc fat_res_sec
    sta fat_fat_lba

    lda fat_part_lba+1
    adc fat_res_sec+1
    sta fat_fat_lba+1

    lda fat_part_lba+2
    adc #0
    sta fat_fat_lba+2

    lda fat_part_lba+3
    adc #0
    sta fat_fat_lba+3

    ; --------------------------------------------------------------------------
    ; ROOT_LBA =
    ;     FAT_LBA + NumFATs * SectorsPerFAT
    ; --------------------------------------------------------------------------

    lda fat_fat_lba
    sta fat_root_lba

    lda fat_fat_lba+1
    sta fat_root_lba+1

    lda fat_fat_lba+2
    sta fat_root_lba+2

    lda fat_fat_lba+3
    sta fat_root_lba+3

    ldx fat_num_fats

@fat_add_loop:

    clc

    lda fat_root_lba
    adc fat_sec_p_fat
    sta fat_root_lba

    lda fat_root_lba+1
    adc fat_sec_p_fat+1
    sta fat_root_lba+1

    bcc @fat_add_no_carry

    inc fat_root_lba+2

    bne @fat_add_no_carry

    inc fat_root_lba+3

@fat_add_no_carry:

    dex
    bne @fat_add_loop

    ; --------------------------------------------------------------------------
    ; Root sectors =
    ;     ceil(RootEntries * 32 / 512)
    ;   = ceil(RootEntries / 16)
    ;
    ; +15 / 16
    ; --------------------------------------------------------------------------

    clc

    lda fat_root_ent
    adc #15
    sta cf_tmp16

    lda fat_root_ent+1
    adc #0
    sta cf_tmp16+1

    lsr cf_tmp16+1
    ror cf_tmp16

    lsr cf_tmp16+1
    ror cf_tmp16

    lsr cf_tmp16+1
    ror cf_tmp16

    lsr cf_tmp16+1
    ror cf_tmp16

    lda cf_tmp16
    sta fat_root_secs

    lda cf_tmp16+1
    sta fat_root_secs+1

    ; --------------------------------------------------------------------------
    ; DATA_LBA = ROOT_LBA + RootSectors
    ; --------------------------------------------------------------------------

    clc

    lda fat_root_lba
    adc fat_root_secs
    sta fat_data_lba

    lda fat_root_lba+1
    adc fat_root_secs+1
    sta fat_data_lba+1

    lda fat_root_lba+2
    adc #0
    sta fat_data_lba+2

    lda fat_root_lba+3
    adc #0
    sta fat_data_lba+3

    ; --------------------------------------------------------------------------
    ; Startujemy w ROOT
    ; --------------------------------------------------------------------------

    stz cur_dir_cluster
    stz cur_dir_cluster+1

    lda #<msg_fat_ok
    ldy #>msg_fat_ok
    jsr bios_print_string

    lda #1
    sta cf_mounted

    clc
    rts

@bad_bpb:
    jmp err_bad_bpb

.endproc


; ==============================================================================
; CF WAIT READY
;
; Zwykły timeout ~2.6 s przy 8 MHz.
; ==============================================================================
.proc cf_wait_ready

    lda #$10
    sta cf_timeout2

    jmp cf_wait_ready_common

.endproc


; ==============================================================================
; CF WAIT READY LONG
;
; Długi timeout ~10 s przy 8 MHz.
; Używany przede wszystkim podczas inicjalizacji.
; ==============================================================================
.proc cf_wait_ready_long

    lda #$40
    sta cf_timeout2

    jmp cf_wait_ready_common

.endproc


; ==============================================================================
; CF WAIT READY COMMON
; ==============================================================================
.proc cf_wait_ready_common

    phx
    phy
    pha

    stz cf_timeout0
    stz cf_timeout1

@wait:

    lda CF_STATUS

    ; $FF - typowy stan "magistrala nie istnieje / pływa"
    cmp #$FF
    beq @fail

    ; BUSY?
    and #CF_BUSY
    beq @not_busy

    jmp @timeout_tick

@not_busy:

    lda CF_STATUS
    and #CF_ERR
    bne @fail

    lda CF_STATUS
    and #CF_READY
    bne @success

@timeout_tick:

    dec cf_timeout0
    bne @wait

    dec cf_timeout1
    bne @wait

    dec cf_timeout2
    bne @wait

@fail:

    pla
    ply
    plx

    sec
    rts

@success:

    pla
    ply
    plx

    clc
    rts

.endproc


; ==============================================================================
; CF WAIT DRQ
;
; Po READ SECTORS nie wystarczy READY.
; Musimy poczekać na DRQ, a jednocześnie pilnować ERR.
; ==============================================================================
.proc cf_wait_drq

    phx
    phy
    pha

    lda #$10
    sta cf_timeout2

    stz cf_timeout0
    stz cf_timeout1

@wait:

    lda CF_STATUS

    cmp #$FF
    beq @fail

    lda CF_STATUS
    and #CF_BUSY
    bne @timeout

    lda CF_STATUS
    and #CF_ERR
    bne @fail

    lda CF_STATUS
    and #CF_DRQ
    bne @success

@timeout:

    dec cf_timeout0
    bne @wait

    dec cf_timeout1
    bne @wait

    dec cf_timeout2
    bne @wait

@fail:

    pla
    ply
    plx

    sec
    rts

@success:

    pla
    ply
    plx

    clc
    rts

.endproc


; ==============================================================================
; CF READ SECTOR
;
; Wejście:
;   cf_lba = 28-bitowy LBA
;
; Wyjście:
;   sector_buffer = 512 bajtów
;   C=0 OK
;   C=1 ERROR
; ==============================================================================
.proc cf_read_sector

    jsr cf_wait_ready
    bcc @ready

    jmp @fail

@ready:

    ; LBA28 - tylko 4 dolne bity ostatniego bajtu

    lda cf_lba+3
    and #$F0
    beq @lba_ok

    jmp @fail

@lba_ok:

    lda #$E0
    ora cf_lba+3
    and #$EF
    sta CF_HEAD

    lda cf_lba+2
    sta CF_LBA_HIGH

    lda cf_lba+1
    sta CF_LBA_MID

    lda cf_lba
    sta CF_LBA_LOW

    lda #1
    sta CF_SEC_CNT

    lda #CF_CMD_READ
    sta CF_COMMAND

    ; Po READ czekamy na DRQ, nie na samo READY.

    jsr cf_wait_drq
    bcc @data_ready

    jmp @fail

@data_ready:

    ; --------------------------------------------------------------------------
    ; 512 bajtów
    ; --------------------------------------------------------------------------

    ldy #0

@read_byte:

    lda CF_DATA
    sta sector_buffer,y

    iny
    bne @read_byte

    ldy #0

@read_second_page:

    lda CF_DATA
    sta sector_buffer+$100,y

    iny
    bne @read_second_page

    clc
    rts

@fail:

    lda #CFERR_READ
    sta cf_error

    sec
    rts

.endproc


; ==============================================================================
; CF DIRECTORY OPEN
;
; Przygotowuje stan iteratora bieżącego katalogu.
;
; C=0 OK
; C=1 ERROR
; ==============================================================================
.proc cf_dir_open

    stz dir_entry_count
    stz dir_sector_idx

    lda cur_dir_cluster
    ora cur_dir_cluster+1
    bne @subdir

    ; --------------------------------------------------------------------------
    ; ROOT DIRECTORY
    ; --------------------------------------------------------------------------

    lda #1
    sta dir_root

    lda fat_root_lba
    sta cf_lba

    lda fat_root_lba+1
    sta cf_lba+1

    lda fat_root_lba+2
    sta cf_lba+2

    lda fat_root_lba+3
    sta cf_lba+3

    lda fat_root_secs
    sta dir_root_left

    lda fat_root_secs+1
    sta dir_root_left+1

    clc
    rts

@subdir:

    stz dir_root

    lda cur_dir_cluster
    sta dir_cluster

    lda cur_dir_cluster+1
    sta dir_cluster+1

    lda dir_cluster
    sta cf_lookup_cluster

    lda dir_cluster+1
    sta cf_lookup_cluster+1

    jsr cf_calc_cluster_lba

    clc
    rts

.endproc


; ==============================================================================
; CF DIRECTORY NEXT SECTOR
;
; Przesuwa iterator katalogu na kolejny sektor.
;
; C=0 - kolejny sektor istnieje
; C=1 - koniec katalogu lub błąd
;
; cf_error != 0 oznacza błąd.
; ==============================================================================
.proc cf_dir_next_sector

    lda dir_root
    beq @subdir

    ; --------------------------------------------------------------------------
    ; ROOT
    ; --------------------------------------------------------------------------

    sec

    lda dir_root_left
    sbc #1
    sta dir_root_left

    lda dir_root_left+1
    sbc #0
    sta dir_root_left+1

    lda dir_root_left
    ora dir_root_left+1
    bne @root_more

    sec
    rts

@root_more:

    jsr cf_inc_lba

    clc
    rts

@subdir:

    inc dir_sector_idx

    lda dir_sector_idx
    cmp fat_sec_p_clus
    bcc @same_cluster

    ; --------------------------------------------------------------------------
    ; Koniec bieżącego klastra katalogu.
    ; Pobieramy następny klaster z FAT.
    ; --------------------------------------------------------------------------

    lda dir_cluster
    sta cf_lookup_cluster

    lda dir_cluster+1
    sta cf_lookup_cluster+1

    jsr cf_get_next_cluster
    bcc @next_cluster_ok

    sec
    rts

@next_cluster_ok:

    jsr cf_cluster_status

    cmp #1
    beq @dir_end

    cmp #0
    beq @valid_cluster

    lda #CFERR_BAD_FAT
    sta cf_error

    sec
    rts

@valid_cluster:

    lda cf_lookup_cluster
    sta dir_cluster

    lda cf_lookup_cluster+1
    sta dir_cluster+1

    stz dir_sector_idx

    jsr cf_calc_cluster_lba

    clc
    rts

@same_cluster:

    jsr cf_inc_lba

    clc
    rts

@dir_end:

    sec
    rts

.endproc


; ==============================================================================
; CF DIRECTORY FIND
;
; Szuka ptr_filename w bieżącym katalogu.
;
; C=0 - znaleziono, dir_ptr wskazuje wpis
; C=1 - nie znaleziono / błąd
; ==============================================================================
.proc cf_find_current

    stz cf_error

    jsr cf_dir_open
    bcc @open_ok

    jmp @fail

@open_ok:

@sector_loop:

    jsr cf_read_sector
    bcc @sector_ok

    jmp @fail

@sector_ok:

    lda #<sector_buffer
    sta dir_ptr_l

    lda #>sector_buffer
    sta dir_ptr_h

    lda #16
    sta dir_entry_count

@entry_loop:

    ldy #0

    lda (dir_ptr_l),y

    ; $00 = koniec katalogu
    beq @not_found

    ; $E5 = usunięty wpis
    cmp #$E5
    beq @next_entry

    ; --------------------------------------------------------------------------
    ; Atrybuty
    ; --------------------------------------------------------------------------

    ldy #$0B
    lda (dir_ptr_l),y

    ; LFN
    cmp #$0F
    beq @next_entry

    ; Volume Label
    and #$08
    bne @next_entry

    ; --------------------------------------------------------------------------
    ; Porównanie 11 bajtów
    ; --------------------------------------------------------------------------

    ldy #0

@compare:

    lda (dir_ptr_l),y
    cmp (ptr_filename),y
    bne @next_entry

    iny
    cpy #11
    bne @compare

    ; znaleziono

    clc
    rts

@next_entry:

    clc
    lda dir_ptr_l
    adc #32
    sta dir_ptr_l

    bcc @entry_no_page

    inc dir_ptr_h

@entry_no_page:

    dec dir_entry_count
    bne @entry_loop

    ; --------------------------------------------------------------------------
    ; Następny sektor
    ; --------------------------------------------------------------------------

    jsr cf_dir_next_sector
    bcc @next_sector

    lda cf_error
    bne @fail

    jmp @not_found

@next_sector:

    jmp @sector_loop

@not_found:

    lda #CFERR_NOT_FOUND
    sta cf_error

@fail:

    sec
    rts

.endproc


; ==============================================================================
; CF DIR
; ==============================================================================
.proc cf_dir

    lda cf_mounted
    bne @mounted

    lda #CFERR_NOT_MOUNT
    sta cf_error

    jmp err_not_mounted

@mounted:

    stz cf_error

    ;lda #<msg_dir_head
    ;ldy #>msg_dir_head
    ;jsr bios_print_string
    jsr new_line
    lda #<msg_dir_head
    ldy #>msg_dir_head
    jsr bios_print_string   
    lda #<cwd_buffer
    ldy #>cwd_buffer
    jsr bios_print_string
    jsr new_line
    jsr new_line     

    stz dir_file_count
    stz dir_file_count+1
    stz dir_folder_count
    stz dir_folder_count+1
    stz dir_total_bytes
    stz dir_total_bytes+1
    stz dir_total_bytes+2
    stz dir_total_bytes+3

    jsr cf_dir_open
    bcc @open_ok

    jmp @error

@open_ok:

@sector_loop:

    jsr cf_read_sector
    bcc @sector_ok

    jmp @error

@sector_ok:

    lda #<sector_buffer
    sta dir_ptr_l

    lda #>sector_buffer
    sta dir_ptr_h

    lda #16
    sta dir_entry_count

@entry_loop:

    ldy #0
    lda (dir_ptr_l),y

    ; $00 = koniec katalogu

    bne @entry_present
    jmp @done

@entry_present:

    ; $E5 = deleted

    cmp #$E5
    bne @not_deleted
    jmp @skip_entry

@not_deleted:

    ; "." oraz ".." pomijamy w DIR

    cmp #'.'
    beq @dot_entry
    jmp @check_attributes

@dot_entry:
    ldy #1
    lda (dir_ptr_l),y
    cmp #'.'
    bne @not_parent
    jmp @skip_entry

@not_parent:
    cmp #' '
    bne @check_attributes
    jmp @skip_entry

@check_attributes:

    ldy #$0B
    lda (dir_ptr_l),y

    ; LFN

    cmp #$0F
    bne @not_lfn
    jmp @skip_entry

@not_lfn:

    ; Volume Label

    and #$08
    beq @not_volume
    jmp @skip_entry

@not_volume:

    ldy #$0B
    lda (dir_ptr_l),y
    and #$10
    beq @file

    inc dir_folder_count
    bne @folder_counted
    inc dir_folder_count+1

@folder_counted:
    jsr cf_print_dir_name
    jsr cf_print_date_time
    jsr new_line
    jmp @skip_entry

@file:
    inc dir_file_count
    bne @file_counted
    inc dir_file_count+1

@file_counted:
    jsr cf_add_file_size
    jsr cf_print_file_name
    jsr cf_load_file_size
    jsr cf_u32_to_digits

    stz dir_tmp
    lda dir_digits_count
    cmp #4
    bcc @size_padding_counted
    inc dir_tmp
    cmp #7
    bcc @size_padding_counted
    inc dir_tmp
    cmp #10
    bcc @size_padding_counted
    inc dir_tmp

@size_padding_counted:
    lda dir_digits_count
    clc
    adc dir_tmp
    cmp #10
    bcs @no_size_padding
    lda #10
    sec
    sbc dir_digits_count
    sec
    sbc dir_tmp
    sta dir_pad_count
    bra @size_pad

@no_size_padding:
    stz dir_pad_count
@size_pad:
    lda dir_pad_count
    beq @size_print
    lda #' '
    jsr bios_print_char
    dec dir_pad_count
    bra @size_pad

@size_print:
    jsr cf_print_u32_grouped
    lda #' '
    jsr bios_print_char
    lda #' '
    jsr bios_print_char
    jsr cf_print_date_time
    jsr new_line

@skip_entry:

    clc
    lda dir_ptr_l
    adc #32
    sta dir_ptr_l

    bcc @entry_no_page

    inc dir_ptr_h

@entry_no_page:

    dec dir_entry_count
    beq @entries_done
    jmp @entry_loop

@entries_done:
    jsr cf_dir_next_sector
    bcc @next_sector

    lda cf_error
    beq @directory_end
    jmp @error

@directory_end:

    jmp @done

@next_sector:

    jmp @sector_loop

@done:
    lda dir_file_count
    sta dir_num
    lda dir_file_count+1
    sta dir_num+1
    stz dir_num+2
    stz dir_num+3
    jsr cf_u32_to_digits
    jsr cf_print_u32_grouped
    lda #<msg_dir_files_label
    ldy #>msg_dir_files_label
    jsr bios_print_string

    lda dir_total_bytes
    sta dir_num
    lda dir_total_bytes+1
    sta dir_num+1
    lda dir_total_bytes+2
    sta dir_num+2
    lda dir_total_bytes+3
    sta dir_num+3
    jsr cf_u32_to_digits
    jsr cf_print_u32_grouped
    lda #<msg_dir_bytes_label
    ldy #>msg_dir_bytes_label
    jsr bios_print_string
    jsr new_line

    lda dir_folder_count
    sta dir_num
    lda dir_folder_count+1
    sta dir_num+1
    stz dir_num+2
    stz dir_num+3
    jsr cf_u32_to_digits
    jsr cf_print_u32_grouped
    lda #<msg_dir_folders_label
    ldy #>msg_dir_folders_label
    jsr bios_print_string
    jsr new_line

    clc
    rts

@error:

    lda #<msg_err_read
    ldy #>msg_err_read
    jsr bios_print_string

    sec
    rts

.endproc


; ==============================================================================
; DIRECTORY LISTING FORMATTERS
; ==============================================================================
.proc cf_print_dir_name
    ldy #0
@name:
    lda (dir_ptr_l),y
    jsr bios_print_char
    iny
    cpy #8
    bne @name
    lda #' '
    jsr bios_print_char
@extension:
    lda (dir_ptr_l),y
    jsr bios_print_char
    iny
    cpy #11
    bne @extension
    lda #<msg_dir_dir
    ldy #>msg_dir_dir
    jsr bios_print_string
    rts
.endproc

.proc cf_print_file_name
    ldy #0
@name:
    lda (dir_ptr_l),y
    jsr bios_print_char
    iny
    cpy #8
    bne @name
    lda #' '
    jsr bios_print_char
@extension:
    lda (dir_ptr_l),y
    jsr bios_print_char
    iny
    cpy #11
    bne @extension
    lda #' '
    jsr bios_print_char
    lda #' '
    jsr bios_print_char
    rts
.endproc

.proc cf_add_file_size
    ldy #28
    clc
    lda dir_total_bytes
    adc (dir_ptr_l),y
    sta dir_total_bytes
    iny
    lda dir_total_bytes+1
    adc (dir_ptr_l),y
    sta dir_total_bytes+1
    iny
    lda dir_total_bytes+2
    adc (dir_ptr_l),y
    sta dir_total_bytes+2
    iny
    lda dir_total_bytes+3
    adc (dir_ptr_l),y
    sta dir_total_bytes+3
    rts
.endproc

.proc cf_load_file_size
    ldy #28
    lda (dir_ptr_l),y
    sta dir_num
    iny
    lda (dir_ptr_l),y
    sta dir_num+1
    iny
    lda (dir_ptr_l),y
    sta dir_num+2
    iny
    lda (dir_ptr_l),y
    sta dir_num+3
    rts
.endproc

.proc cf_u32_to_digits
    stz dir_digits_count
@divide:
    stz dir_num_rem
    ldx #32
@bit:
    asl dir_num
    rol dir_num+1
    rol dir_num+2
    rol dir_num+3
    lda #0
    rol a
    sta dir_num_bit
    lda dir_num_rem
    asl a
    clc
    adc dir_num_bit
    cmp #10
    bcc @remainder_ready
    sec
    sbc #10
    pha
    lda dir_num
    ora #1
    sta dir_num
    pla
@remainder_ready:
    sta dir_num_rem
    dex
    bne @bit

    ldx dir_digits_count
    lda dir_num_rem
    sta dir_digits,x
    inc dir_digits_count

    lda dir_num
    ora dir_num+1
    ora dir_num+2
    ora dir_num+3
    bne @divide
    rts
.endproc

.proc cf_print_u32_grouped
    lda dir_digits_count
    sta dir_digits_left
@digit:
    ldx dir_digits_left
    dex
    lda dir_digits,x
    clc
    adc #'0'
    jsr bios_print_char
    stx dir_digits_left
    lda dir_digits_left
    beq @finished
    cmp #3
    beq @group_boundary
    cmp #6
    beq @group_boundary
    cmp #9
    bne @digit

@group_boundary:
    lda #','
    jsr bios_print_char
    bra @digit

@finished:
    rts
.endproc

.proc cf_print_date_time
    ; FAT date: day
    ldy #24
    lda (dir_ptr_l),y
    and #$1F
    jsr cf_print_two_digits
    lda #'.'
    jsr bios_print_char

    ; FAT date: month
    ldy #24
    lda (dir_ptr_l),y
    lsr a
    lsr a
    lsr a
    and #$07
    sta dir_tmp
    ldy #25
    lda (dir_ptr_l),y
    and #$01
    asl a
    asl a
    asl a
    ora dir_tmp
    jsr cf_print_two_digits
    lda #'.'
    jsr bios_print_char

    ; FAT date: four-digit year (1980-2107)
    ldy #25
    lda (dir_ptr_l),y
    lsr a
    cmp #20
    bcc @year_19xx
    cmp #120
    bcc @year_20xx

@year_21xx:
    lda #'2'
    jsr bios_print_char
    lda #'1'
    jsr bios_print_char
    ldy #25
    lda (dir_ptr_l),y
    lsr a
    sec
    sbc #120
    jsr cf_print_two_digits
    bra @year_done

@year_20xx:
    lda #'2'
    jsr bios_print_char
    lda #'0'
    jsr bios_print_char
    ldy #25
    lda (dir_ptr_l),y
    lsr a
    sec
    sbc #20
    jsr cf_print_two_digits
    bra @year_done

@year_19xx:
    lda #'1'
    jsr bios_print_char
    lda #'9'
    jsr bios_print_char
    ldy #25
    lda (dir_ptr_l),y
    lsr a
    clc
    adc #80
    jsr cf_print_two_digits

@year_done:
    lda #' '
    jsr bios_print_char

    ; FAT time: hour
    ldy #23
    lda (dir_ptr_l),y
    lsr a
    lsr a
    lsr a
    jsr cf_print_two_digits
    lda #':'
    jsr bios_print_char

    ; FAT time: minute
    ldy #22
    lda (dir_ptr_l),y
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    and #$07
    sta dir_tmp
    ldy #23
    lda (dir_ptr_l),y
    and #$07
    asl a
    asl a
    asl a
    ora dir_tmp
    jsr cf_print_two_digits
    rts
.endproc

.proc cf_print_two_digits
    sta dir_tmp
    stz dir_decimal_value
@tens:
    lda dir_tmp
    cmp #10
    bcc @ones
    sec
    sbc #10
    sta dir_tmp
    inc dir_decimal_value
    bra @tens
@ones:
    lda dir_decimal_value
    clc
    adc #'0'
    jsr bios_print_char
    lda dir_tmp
    clc
    adc #'0'
    jsr bios_print_char
    rts
.endproc


; ==============================================================================
; PRINT FAT 8.3 NAME
;
; dir_ptr wskazuje wpis 32B.
;
; Wynik:
;   NAME.TXT
; zamiast:
;   NAME    .TXT
; ==============================================================================
.proc cf_print_83

    ; --------------------------------------------------------------------------
    ; NAME
    ; --------------------------------------------------------------------------

    ldy #0

@name:

    lda (dir_ptr_l),y

    cmp #' '
    beq @name_done

    jsr bios_print_char

    iny
    cpy #8
    bne @name

@name_done:

    ; --------------------------------------------------------------------------
    ; Extension
    ; --------------------------------------------------------------------------

    ldy #8
    lda (dir_ptr_l),y

    cmp #' '
    beq @end

    lda #'.'
    jsr bios_print_char

@ext:

    lda (dir_ptr_l),y

    cmp #' '
    beq @end

    jsr bios_print_char

    iny
    cpy #11
    bne @ext

@end:

    rts

.endproc


; ==============================================================================
; CF CD ROOT
; ==============================================================================
.proc cf_cd_root

    stz cur_dir_cluster
    stz cur_dir_cluster+1
    jsr cf_cwd_reset

    lda #<msg_cd_root
    ldy #>msg_cd_root
    jsr bios_print_string

    clc
    rts

.endproc


; ==============================================================================
; CWD PATH HELPERS
; ==============================================================================
.proc cf_cwd_reset

    ldx #0
@copy_root:
    lda cf_cwd_root_path,x
    sta cwd_buffer,x
    inx
    cpx #6
    bne @copy_root
    rts

.endproc



.proc cf_cwd_append

    ldx #0
@path_length:
    lda cwd_buffer,x
    beq @path_length_done
    inx
    cpx #$40
    bne @path_length
    sec
    rts

@path_length_done:
    stx cf_tmp16
    lda #1
    sta cf_tmp16+1
    stz cf_tmp8

    cpx #0
    beq @separator_checked
    dex
    lda cwd_buffer,x
    cmp #$5C
    bne @separator_checked
    stz cf_tmp16+1

@separator_checked:

    ldy #0
@base_length:
    cpy #8
    beq @extension_length_start
    lda (ptr_filename),y
    cmp #' '
    beq @extension_length_start
    inc cf_tmp8
    iny
    bra @base_length

@extension_length_start:
    ldy #8
    lda (ptr_filename),y
    cmp #' '
    beq @check_length
    inc cf_tmp8
    @extension_length:
    iny
    cpy #11
    beq @check_length
    lda (ptr_filename),y
    cmp #' '
    beq @check_length
    inc cf_tmp8
    bra @extension_length

@check_length:
    lda cf_tmp16
    clc
    adc cf_tmp8
    adc cf_tmp16+1
    cmp #$40
    bcs @path_too_long

    ldx cf_tmp16
    lda cf_tmp16+1
    beq @copy_base_start
    lda #$5C
    sta cwd_buffer,x
    inx

@copy_base_start:
    ldy #0
@copy_base:
    cpy #8
    beq @copy_extension
    lda (ptr_filename),y
    cmp #' '
    beq @copy_extension
    sta cwd_buffer,x
    inx
    iny
    bra @copy_base

@copy_extension:
    ldy #8
    lda (ptr_filename),y
    cmp #' '
    beq @terminate
    lda #'.'
    sta cwd_buffer,x
    inx
@copy_extension_chars:
    iny
    cpy #11
    beq @terminate
    lda (ptr_filename),y
    cmp #' '
    beq @terminate
    sta cwd_buffer,x
    inx
    bra @copy_extension_chars

@terminate:
    stz cwd_buffer,x
    clc
    rts

@path_too_long:
    sec
    rts

.endproc

.proc cf_cwd_parent

    ldx #0
@find_end:
    lda cwd_buffer,x
    beq @at_end
    inx
    cpx #$40
    bne @find_end
    jmp cf_cwd_reset

@at_end:
    cpx #6
    bcc @done
    dex
@find_separator:
    lda cwd_buffer,x
    cmp #$5C
    beq @separator_found
    dex
    bne @find_separator
    jmp cf_cwd_reset

@separator_found:
    cpx #5
    bcs @truncate_parent
    inx
@truncate_parent:
    stz cwd_buffer,x

@done:
    rts

.endproc


; ==============================================================================
; CF CD
;
; ptr_filename = 11-bajtowa nazwa FAT 8.3
;
; "."  = pozostaje
; ".." = parent
; ==============================================================================
.proc cf_cd

    lda cf_mounted
    bne @mounted

    lda #CFERR_NOT_MOUNT
    sta cf_error

    jmp err_not_mounted

@mounted:

    ; --------------------------------------------------------------------------
    ; "." ?
    ; --------------------------------------------------------------------------

    ldy #0
    lda (ptr_filename),y
    cmp #'.'
    bne @check_parent

    iny
    lda (ptr_filename),y
    cmp #' '
    bne @check_parent

    clc
    rts

@check_parent:

    ; --------------------------------------------------------------------------
    ; ".." ?
    ; --------------------------------------------------------------------------

    lda (ptr_filename),y
    cmp #'.'
    bne @normal_name

    ; W ROOT ".." niczego nie zmienia.
    lda cur_dir_cluster
    ora cur_dir_cluster+1
    beq @root_parent

    ; Szukamy wpisu ".." normalnie.
    jmp @find

@root_parent:

    clc
    rts

@normal_name:

@find:

    jsr cf_find_current
    bcc @found

    lda cf_error
    cmp #CFERR_NOT_FOUND
    beq @not_found

    jmp @error

@found:

    ; --------------------------------------------------------------------------
    ; Musi być katalog
    ; --------------------------------------------------------------------------

    ldy #$0B
    lda (dir_ptr_l),y
    and #$10
    bne @is_dir

    lda #CFERR_NOT_DIR
    sta cf_error

    jmp @not_dir

@is_dir:

    ldy #0
    lda (ptr_filename),y
    cmp #'.'
    bne @append_cwd
    iny
    lda (ptr_filename),y
    cmp #'.'
    bne @append_cwd
    jsr cf_cwd_parent
    bra @set_current_cluster

@append_cwd:
    jsr cf_cwd_append
    bcc @set_current_cluster
    lda #CFERR_PATH_LONG
    sta cf_error
    sec
    rts

@set_current_cluster:

    ; --------------------------------------------------------------------------
    ; Odczyt pierwszego klastra
    ; --------------------------------------------------------------------------

    ldy #$1A

    lda (dir_ptr_l),y
    sta cur_dir_cluster

    iny

    lda (dir_ptr_l),y
    sta cur_dir_cluster+1

    clc
    rts

@root:

    stz cur_dir_cluster
    stz cur_dir_cluster+1
    jsr cf_cwd_reset

    clc
    rts

@not_found:

    lda #<msg_err_notfound
    ldy #>msg_err_notfound
    jsr bios_print_string

    sec
    rts

@not_dir:

    lda #<msg_err_notdir
    ldy #>msg_err_notdir
    jsr bios_print_string

    sec
    rts

@error:

    lda #<msg_err_read
    ldy #>msg_err_read
    jsr bios_print_string

    sec
    rts

.endproc


; ==============================================================================
; CF OPEN FILE
;
; Szuka pliku w bieżącym katalogu i pobiera:
;
;   file_cluster
;   file_bytes
;
; C=0 OK
; C=1 ERROR
; ==============================================================================
.proc cf_open_file

    jsr cf_find_current
    bcc @found

    jmp @fail

@found:

    ; --------------------------------------------------------------------------
    ; Nie może być katalogiem
    ; --------------------------------------------------------------------------

    ldy #$0B
    lda (dir_ptr_l),y
    and #$10
    beq @file

    lda #CFERR_NOT_FILE
    sta cf_error

    jmp @fail

@file:

    ; --------------------------------------------------------------------------
    ; First Cluster
    ; --------------------------------------------------------------------------

    ldy #$1A

    lda (dir_ptr_l),y
    sta file_cluster

    iny

    lda (dir_ptr_l),y
    sta file_cluster+1

    ; --------------------------------------------------------------------------
    ; File Size
    ; --------------------------------------------------------------------------

    ldy #$1C

    lda (dir_ptr_l),y
    sta file_bytes

    iny
    lda (dir_ptr_l),y
    sta file_bytes+1

    iny
    lda (dir_ptr_l),y
    sta file_bytes+2

    iny
    lda (dir_ptr_l),y
    sta file_bytes+3

    stz file_sector_idx

    clc
    rts

@fail:

    sec
    rts

.endproc


; ==============================================================================
; CF LOAD
; ==============================================================================
.proc cf_load

    lda cf_mounted
    bne @mounted

    lda #CFERR_NOT_MOUNT
    sta cf_error

    jmp err_not_mounted

@mounted:

    lda #<msg_loading
    ldy #>msg_loading
    jsr bios_print_string

    jsr cf_open_file
    bcc @opened

    lda cf_error
    cmp #CFERR_NOT_FOUND
    beq @not_found

    cmp #CFERR_NOT_FILE
    beq @not_file

    jmp @read_error

@opened:

    ; Plik 0-bajtowy nie potrzebuje klastra.

    lda file_bytes
    ora file_bytes+1
    ora file_bytes+2
    ora file_bytes+3
    bne @read_loop

    jmp @success

@read_loop:

    jsr cf_file_read_sector
    bcc @sector_ok

    jmp @read_error

@sector_ok:

    jsr cf_prepare_copy_count

    jsr cf_copy_to_dest

    jsr cf_subtract_copy_count

    lda file_bytes
    ora file_bytes+1
    ora file_bytes+2
    ora file_bytes+3
    beq @success

    inc file_sector_idx

    jmp @read_loop

@success:

    lda #<msg_file_ok
    ldy #>msg_file_ok
    jsr bios_print_string

    clc
    rts

@not_found:

    lda #<msg_err_notfound
    ldy #>msg_err_notfound
    jsr bios_print_string

    sec
    rts

@not_file:

    lda #<msg_err_notfile
    ldy #>msg_err_notfile
    jsr bios_print_string

    sec
    rts

@read_error:

    lda #<msg_err_read
    ldy #>msg_err_read
    jsr bios_print_string

    sec
    rts

.endproc


; ==============================================================================
; CF TYPE
;
; Czyta plik tak samo jak LOAD, ale zamiast kopiować go do RAM
; wysyła bajty przez bios_print_char.
; ==============================================================================
.proc cf_type

    lda cf_mounted
    bne @mounted

    lda #CFERR_NOT_MOUNT
    sta cf_error

    jmp err_not_mounted

@mounted:

    jsr cf_open_file
    bcc @opened

    lda cf_error
    cmp #CFERR_NOT_FOUND
    beq @not_found

    cmp #CFERR_NOT_FILE
    beq @not_file

    jmp @read_error

@opened:

    lda file_bytes
    ora file_bytes+1
    ora file_bytes+2
    ora file_bytes+3
    bne @read_loop

    jmp @done

@read_loop:

    jsr cf_file_read_sector
    bcc @sector_ok

    jmp @read_error

@sector_ok:

    jsr cf_prepare_copy_count

    jsr cf_print_buffer

    jsr cf_subtract_copy_count

    lda file_bytes
    ora file_bytes+1
    ora file_bytes+2
    ora file_bytes+3
    beq @done

    inc file_sector_idx

    jmp @read_loop

@done:

    lda #13
    jsr bios_print_char

    lda #10
    jsr bios_print_char

    clc
    rts

@not_found:

    lda #<msg_err_notfound
    ldy #>msg_err_notfound
    jsr bios_print_string

    sec
    rts

@not_file:

    lda #<msg_err_notfile
    ldy #>msg_err_notfile
    jsr bios_print_string

    sec
    rts

@read_error:

    lda #<msg_err_read
    ldy #>msg_err_read
    jsr bios_print_string

    sec
    rts

.endproc


; ==============================================================================
; CF FILE READ SECTOR
;
; Przygotowuje cf_lba dla kolejnego sektora pliku i go odczytuje.
;
; C=0 OK
; C=1 ERROR
; ==============================================================================
.proc cf_file_read_sector

    ; --------------------------------------------------------------------------
    ; Czy bieżący klaster jest prawidłowy?
    ; --------------------------------------------------------------------------

    lda file_cluster
    sta cf_lookup_cluster

    lda file_cluster+1
    sta cf_lookup_cluster+1

    jsr cf_cluster_status

    cmp #0
    beq @cluster_valid

    ; EOF przed końcem pliku = uszkodzony łańcuch

    lda #CFERR_BAD_FAT
    sta cf_error

    sec
    rts

@cluster_valid:

    ; --------------------------------------------------------------------------
    ; Jeśli przekroczyliśmy sektory bieżącego klastra,
    ; pobieramy następny klaster.
    ; --------------------------------------------------------------------------

    lda file_sector_idx
    cmp fat_sec_p_clus
    bcc @sector_in_cluster

    lda file_cluster
    sta cf_lookup_cluster

    lda file_cluster+1
    sta cf_lookup_cluster+1

    jsr cf_get_next_cluster
    bcc @next_ok

    jmp @fail

@next_ok:

    jsr cf_cluster_status

    cmp #0
    beq @new_cluster

    ; EOF / bad cluster przed końcem pliku

    lda #CFERR_BAD_FAT
    sta cf_error

    sec
    rts

@new_cluster:

    lda cf_lookup_cluster
    sta file_cluster

    lda cf_lookup_cluster+1
    sta file_cluster+1

    stz file_sector_idx

@sector_in_cluster:

    ; --------------------------------------------------------------------------
    ; LBA pierwszego sektora klastra
    ; --------------------------------------------------------------------------

    lda file_cluster
    sta cf_lookup_cluster

    lda file_cluster+1
    sta cf_lookup_cluster+1

    jsr cf_calc_cluster_lba

    ; + numer sektora wewnątrz klastra

    clc

    lda cf_lba
    adc file_sector_idx
    sta cf_lba

    bcc @lba_done

    inc cf_lba+1

    bne @lba_done

    inc cf_lba+2

    bne @lba_done

    inc cf_lba+3

@lba_done:

    jsr cf_read_sector
    bcc @ok

@fail:

    sec
    rts

@ok:

    clc
    rts

.endproc


; ==============================================================================
; CF PREPARE COPY COUNT
;
; Ustawia cf_copy_count na:
;   512, jeśli zostało >=512 bajtów
;   file_bytes, jeśli zostało <512 bajtów
; ==============================================================================
.proc cf_prepare_copy_count

    ; Jeżeli starsze 16 bitów != 0 -> >= 65536 -> 512

    lda file_bytes+2
    ora file_bytes+3
    bne @full

    ; Jeżeli high byte low-word >= 2 -> >=512

    lda file_bytes+1
    cmp #2
    bcs @full

    ; <512

    lda file_bytes
    sta cf_copy_count

    lda file_bytes+1
    sta cf_copy_count+1

    rts

@full:

    lda #$00
    sta cf_copy_count

    lda #$02
    sta cf_copy_count+1

    rts

.endproc


; ==============================================================================
; CF SUBTRACT COPY COUNT
; ==============================================================================
.proc cf_subtract_copy_count

    sec

    lda file_bytes
    sbc cf_copy_count
    sta file_bytes

    lda file_bytes+1
    sbc cf_copy_count+1
    sta file_bytes+1

    lda file_bytes+2
    sbc #0
    sta file_bytes+2

    lda file_bytes+3
    sbc #0
    sta file_bytes+3

    rts

.endproc


; ==============================================================================
; CF COPY BUFFER -> DEST
;
; cf_copy_count = liczba bajtów
; ptr_dest_buf  = adres docelowy
;
; Maksymalnie 512 bajtów.
; ==============================================================================
.proc cf_copy_to_dest

    lda #<sector_buffer
    sta dir_ptr_l

    lda #>sector_buffer
    sta dir_ptr_h

    lda cf_copy_count+1
    beq @low_only

    tax

@page_loop:

    ldy #0

@page:

    lda (dir_ptr_l),y
    sta (ptr_dest_buf),y

    iny
    bne @page

    inc dir_ptr_h
    inc ptr_dest_buf+1

    dex
    bne @page_loop

@low_only:

    lda cf_copy_count
    beq @done

    sta cf_tmp8

    ldy #0

@low:

    lda (dir_ptr_l),y
    sta (ptr_dest_buf),y

    iny
    cpy cf_tmp8
    bne @low

    clc

    lda ptr_dest_buf
    adc cf_tmp8
    sta ptr_dest_buf

    bcc @done

    inc ptr_dest_buf+1

@done:

    rts

.endproc


; ==============================================================================
; CF PRINT BUFFER
;
; Wyświetla cf_copy_count bajtów z sector_buffer.
; ==============================================================================
.proc cf_print_buffer

    lda #<sector_buffer
    sta dir_ptr_l

    lda #>sector_buffer
    sta dir_ptr_h

    lda cf_copy_count+1
    beq @low_only

    tax

@page_loop:

    ldy #0

@page:

    lda (dir_ptr_l),y
    jsr bios_print_char

    iny
    bne @page

    inc dir_ptr_h

    dex
    bne @page_loop

@low_only:

    lda cf_copy_count
    beq @done

    sta cf_tmp8

    ldy #0

@low:

    lda (dir_ptr_l),y
    jsr bios_print_char

    iny
    cpy cf_tmp8
    bne @low

@done:

    rts

.endproc


; ==============================================================================
; CF GET NEXT CLUSTER FROM FAT16
;
; Wejście:
;   cf_lookup_cluster = numer klastra
;
; Wyjście:
;   cf_lookup_cluster = następny klaster
;   C=0 OK
;   C=1 błąd odczytu FAT
; ==============================================================================
.proc cf_get_next_cluster

    ; --------------------------------------------------------------------------
    ; FAT16:
    ;
    ; wpis = cluster * 2
    ; sektor = cluster / 256
    ; offset = (cluster & $FF) * 2
    ; --------------------------------------------------------------------------

    lda fat_fat_lba
    sta cf_lba

    lda fat_fat_lba+1
    sta cf_lba+1

    lda fat_fat_lba+2
    sta cf_lba+2

    lda fat_fat_lba+3
    sta cf_lba+3

    clc

    lda cf_lookup_cluster+1
    adc cf_lba
    sta cf_lba

    lda #0
    adc cf_lba+1
    sta cf_lba+1

    lda #0
    adc cf_lba+2
    sta cf_lba+2

    lda #0
    adc cf_lba+3
    sta cf_lba+3

    ; --------------------------------------------------------------------------
    ; Odczyt sektora FAT
    ; --------------------------------------------------------------------------

    jsr cf_read_sector
    bcc @fat_ok

    sec
    rts

@fat_ok:

    ; --------------------------------------------------------------------------
    ; Offset = low_byte(cluster) * 2
    ;
    ; Wynik 0..510.
    ; --------------------------------------------------------------------------

    lda cf_lookup_cluster
    asl a
    sta dir_ptr_l

    lda #>sector_buffer
    adc #0
    sta dir_ptr_h

    ; --------------------------------------------------------------------------
    ; Pobranie wpisu FAT16
    ; --------------------------------------------------------------------------

    ldy #0

    lda (dir_ptr_l),y
    sta cf_lookup_cluster

    iny

    lda (dir_ptr_l),y
    sta cf_lookup_cluster+1

    clc
    rts

.endproc


; ==============================================================================
; CF CLUSTER STATUS
;
; Wejście:
;   cf_lookup_cluster
;
; Wyjście:
;   A=0  prawidłowy klaster
;   A=1  EOF
;   A=2  nieprawidłowy / zarezerwowany klaster
; ==============================================================================
.proc cf_cluster_status

    lda cf_lookup_cluster+1

    ; 0xxx
    bne @high_nonzero

    lda cf_lookup_cluster
    cmp #2
    bcs @valid

    lda #2
    rts

@high_nonzero:

    cmp #$FF
    bne @valid

    lda cf_lookup_cluster
    cmp #$F0
    bcc @valid

    cmp #$F8
    bcs @eof

    lda #2
    rts

@valid:

    lda #0
    rts

@eof:

    lda #1
    rts

.endproc


; ==============================================================================
; CF CALCULATE CLUSTER LBA
;
; Wejście:
;   cf_lookup_cluster
;
; Wyjście:
;   cf_lba = DataLBA + (cluster-2)*SectorsPerCluster
;
; Nie zakładamy już, że wynik mieści się w 16 bitach.
; ==============================================================================
.proc cf_calc_cluster_lba

    ; --------------------------------------------------------------------------
    ; cf_mul = cluster - 2
    ; --------------------------------------------------------------------------

    sec

    lda cf_lookup_cluster
    sbc #2
    sta cf_mul

    lda cf_lookup_cluster+1
    sbc #0
    sta cf_mul+1

    stz cf_mul+2
    stz cf_mul+3

    lda fat_sec_p_clus
    sta cf_tmp8

    ; --------------------------------------------------------------------------
    ; Mnożenie przez potęgę 2.
    ;
    ; Dla 1 nie wykonujemy przesunięcia.
    ; Dla 2 -> 1 przesunięcie
    ; Dla 4 -> 2
    ; itd.
    ; --------------------------------------------------------------------------

@shift:

    lsr cf_tmp8
    beq @multiply_done

    asl cf_mul
    rol cf_mul+1
    rol cf_mul+2
    rol cf_mul+3

    jmp @shift

@multiply_done:

    ; --------------------------------------------------------------------------
    ; Data_LBA + offset
    ; --------------------------------------------------------------------------

    clc

    lda fat_data_lba
    adc cf_mul
    sta cf_lba

    lda fat_data_lba+1
    adc cf_mul+1
    sta cf_lba+1

    lda fat_data_lba+2
    adc cf_mul+2
    sta cf_lba+2

    lda fat_data_lba+3
    adc cf_mul+3
    sta cf_lba+3

    rts

.endproc


; ==============================================================================
; INCREMENT 32-BIT LBA
; ==============================================================================
.proc cf_inc_lba

    inc cf_lba
    bne @done

    inc cf_lba+1
    bne @done

    inc cf_lba+2
    bne @done

    inc cf_lba+3

@done:

    rts

.endproc


; ==============================================================================
; BŁĘDY
; ==============================================================================

err_no_card:

    lda #<msg_err_nocard
    ldy #>msg_err_nocard
    jmp cf_show_error


err_read:

    lda #<msg_err_read
    ldy #>msg_err_read
    jmp cf_show_error


err_invalid_mbr:

    lda #<msg_err_mbr
    ldy #>msg_err_mbr
    jmp cf_show_error


err_not_fat16:

    lda #<msg_err_notfat16
    ldy #>msg_err_notfat16
    jmp cf_show_error


err_bad_bpb:

    lda #<msg_err_bpb
    ldy #>msg_err_bpb
    jmp cf_show_error


err_not_mounted:

    lda #<msg_err_notmounted
    ldy #>msg_err_notmounted
    jmp cf_show_error


cf_show_error:

    jsr bios_print_string

    sec
    rts


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
    lda #$08    ; backspace to delete spinn
    jsr print_char
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
    ;lda #'.'    ; print progress dot every 256 bytes
    ;jsr print_char    
    jsr spinner_update
loader_irq_complete:
    jmp bios_return_from_irq

