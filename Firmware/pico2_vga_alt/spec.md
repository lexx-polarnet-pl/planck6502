# PLANCK VGA — specyfikacja interfejsu karty graficznej

**Wersja:** 0.1 (projekt do implementacji)  
**Platforma:** Raspberry Pi Pico 2 / RP2350  
**Host:** komputer 65C02  
**Interfejs hosta:** 16-bajtowe okienko rejestrowe  
**Backend obrazu:** PicoVGA-CMake (warstwa sprzętowa VGA)

---

## 1. Cel i założenia

Karta jest autonomicznym kontrolerem obrazu. Pico 2 zarządza pamięcią obrazu, renderowaniem, synchronizacją VGA i operacjami graficznymi. Procesor 65C02 komunikuje się z kartą przez 16 rejestrów; nie ma bezpośredniego dostępu do framebufferów ani pamięci wewnętrznej Pico.

Podstawowe założenia:

1. Zapis bajtu pod offset `+$0` pozostaje strumieniem terminala tekstowego. Zachowuje to zgodność z istniejącym firmware i programami zapisującymi znaki do portu terminala.
2. Po resecie karta uruchamia terminal tekstowy jako tryb domyślny.
3. Pozostałe rejestry służą do konfiguracji obrazu, wydawania poleceń i transferu danych.
4. Polecenia graficzne są kolejkowane. Zapis do rejestru polecenia zatwierdza zestaw parametrów i umieszcza operację w kolejce.
5. Host nie zakłada, że polecenie wykonuje się natychmiast. Sprawdza `STATUS.BUSY`, `STATUS.CMD_FULL` i/lub korzysta z IRQ, jeśli linia IRQ jest dostępna.
6. Specyfikacja opisuje interfejs hosta, a nie wewnętrzne API PicoVGA. Konkretne formaty i możliwości warstw muszą zostać zweryfikowane podczas integracji z wybraną wersją biblioteki.

Wszystkie offsety są względne wobec bazowego adresu slotu. Przykładowo, jeżeli karta znajduje się pod bazą `$FF80`, rejestr `DATA` jest pod `$FF80`, a `STATUS` pod `$FF81`.

## 2. Mapa rejestrów

| Offset | Nazwa | Odczyt | Zapis |
|---:|---|---|---|
| `$0` | `DATA` | zwraca `$00` (brak funkcji odczytu) | bajt strumienia terminala VT100 |
| `$1` | `STATUS` | flagi stanu karty i kolejki | zapis nieużywany |
| `$2` | `CONTROL` | aktualna konfiguracja podstawowa | sterowanie kartą |
| `$3` | `COMMAND` | ostatni kod polecenia / `$00` | zatwierdza polecenie |
| `$4` | `ARG0` | wartość rejestru | parametr polecenia |
| `$5` | `ARG1` | wartość rejestru | parametr polecenia |
| `$6` | `ARG2` | wartość rejestru | parametr polecenia |
| `$7` | `ARG3` | wartość rejestru | parametr polecenia |
| `$8` | `VIDEO_MODE` | aktywny tryb obrazu | tryb żądany; zatwierdzany przez `SET_MODE` |
| `$9` | `LAYER` | wybrana warstwa | wybór warstwy dla operacji graficznych |
| `$A` | `X_LO` | młodszy bajt X | młodszy bajt X |
| `$B` | `X_HI` | starszy bajt X | starszy bajt X |
| `$C` | `Y_LO` | młodszy bajt Y | młodszy bajt Y |
| `$D` | `Y_HI` | starszy bajt Y | starszy bajt Y |
| `$E` | `GFX_DATA` | `$00` (brak funkcji odczytu) | kolejny bajt bieżącego transferu danych |
| `$F` | `IRQ_STATUS` | przyczyny przerwania | kasowanie flag przez zapis jedynki (W1C) |

Rejestry argumentów, współrzędnych, trybu i warstwy są rejestrami roboczymi. Polecenie pobiera ich kopię w chwili zapisu do `COMMAND`. Późniejsza zmiana rejestrów przez 6502 nie może zmienić parametrów polecenia już umieszczonego w kolejce.

### 2.1. STATUS — offset `$1`

| Bit | Nazwa | Znaczenie |
|---:|---|---|
| 0 | `BUSY` | karta wykonuje polecenie lub transfer |
| 1 | `CMD_FULL` | kolejka poleceń nie może przyjąć kolejnego polecenia |
| 2 | `CMD_EMPTY` | kolejka poleceń jest pusta |
| 3 | `VBLANK` | trwa pionowy okres wygaszania |
| 4 | `FRAME_READY` | zakończono operację oczekującą na granicę klatki / przełączenie obrazu |
| 5 | `ERROR` | wystąpił błąd protokołu lub polecenia |
| 6 | `IRQ_PENDING` | co najmniej jedno źródło IRQ oczekuje |
| 7 | `INITIALIZED` | firmware i silnik obrazu są gotowe |

`CMD_FULL` i `CMD_EMPTY` opisują kolejkę poleceń, nie transfer danych. `BUSY` może być ustawione także podczas transferu bitmapy. Bity `VBLANK` i `FRAME_READY` są informacyjne; host nie powinien zakładać określonego czasu trwania klatki.

### 2.2. CONTROL — offset `$2`

| Bit | Nazwa | Znaczenie |
|---:|---|---|
| 0 | `TERMINAL_ENABLE` | włącza wyświetlanie warstwy terminala |
| 1 | `IRQ_ENABLE` | globalne zezwolenie na wyjście IRQ |
| 2 | `CLEAR_ERROR` | zapis 1 kasuje zatrzaśnięty błąd; bit samoczynnie wraca do 0 |
| 3 | `FLUSH_COMMANDS` | zapis 1 odrzuca oczekujące polecenia, o ile nie trwa nieprzerywalny transfer |
| 4 | `TERMINAL_RESET` | zapis 1 resetuje parser i stan terminala |
| 5–6 | zarezerwowane | zapisywać 0 |
| 7 | `SOFT_RESET` | zapis 1 inicjuje reset programowy; bit samoczynnie wraca do 0 |

Po resecie `TERMINAL_ENABLE=1`, `IRQ_ENABLE=0`, aktywny jest tryb terminala, a pozostałe bity są wyzerowane. Reset programowy przywraca ten stan. Sprzętowy reset Pico również musi prowadzić do tego samego stanu.

### 2.3. IRQ_STATUS — offset `$F`

| Bit | Nazwa | Znaczenie |
|---:|---|---|
| 0 | `CMD_DONE` | zakończono polecenie |
| 1 | `VBLANK_IRQ` | wystąpił początek VBLANK |
| 2 | `TRANSFER_DONE` | zakończono transfer danych |
| 3 | `ERROR_IRQ` | wystąpił błąd |
| 4–7 | zarezerwowane | odczyt 0 |

Flagi są zatrzaskiwane. Zapis jedynki na odpowiedniej pozycji kasuje flagę (write-one-to-clear). `STATUS.IRQ_PENDING` jest sumą logiczną aktywnych flag. Jeśli karta nie ma fizycznie podłączonej linii IRQ, host może odpytywać te same flagi.

## 3. Rejestry parametrów i konwencje

### 3.1. Współrzędne

`X = X_LO + 256 * X_HI`, `Y = Y_LO + 256 * Y_HI`.

Współrzędne są bez znaku, liczone od lewego górnego rogu aktywnego obszaru obrazu. Punkt `(0,0)` oznacza lewy górny piksel. Operacje wychodzące poza ekran lub obszar warstwy są przycinane; nie powodują zawinięcia współrzędnych.

### 3.2. Rejestry ARG0–ARG3

Znaczenie argumentów zależy od polecenia. Dla poleceń wymagających dwóch dodatkowych wartości 16-bitowych:

- `ARG0` = młodszy bajt wartości P0,
- `ARG1` = starszy bajt wartości P0,
- `ARG2` = młodszy bajt wartości P1,
- `ARG3` = starszy bajt wartości P1.

Dla poleceń wymagających koloru lub flag używane są pojedyncze bajty zgodnie z opisem danego polecenia.

### 3.3. LAYER

| Wartość | Znaczenie |
|---:|---|
| 0 | warstwa bazowa |
| 1 | overlay 1 |
| 2 | overlay 2 |
| 3 | overlay 3 |

Warstwa bazowa musi być dostępna w każdym profilu obrazu. Dostępność i format warstw nakładanych zależą od ograniczeń PicoVGA. Firmware powinien odrzucić konfigurację nieobsługiwaną przez wybrany profil, zamiast próbować uruchamiać niezgodny zestaw formatów.

## 4. Tryby obrazu

Tryb jest wybierany przez zapis do `VIDEO_MODE`, a następnie polecenie `SET_MODE`. Odczyt `VIDEO_MODE` zwraca tryb faktycznie aktywny, nie tylko ostatnią wartość żądaną. Po resecie aktywny jest tryb 0.

| ID | Nazwa | Parametry | Zastosowanie |
|---:|---|---|---|
| 0 | `TEXT_80x30` | 640×480, komórka 8×16, 80×30 znaków | domyślny terminal VT100 |
| 1 | `BITMAP_320x240_8` | 320×240, 8 bpp, paleta 256 kolorów | gry i grafika pikselowa |
| 2 | `BITMAP_640x480_4` | 640×480, 4 bpp, paleta 16 kolorów | GUI i klasyczna grafika |
| 3 | `BITMAP_640x480_1` | 640×480, 1 bpp, dwa kolory z palety | grafika monochromatyczna |
| 4 | `TILE_320x240` | tilemap 8×8 lub 16×16; format i liczba kafli ustalone przez firmware | gry i tła |
| 5 | `LAYERED_320x240_8` | bitmapa bazowa 8 bpp oraz zgodne overlaye | grafika z warstwami i sprite'ami |

Tryby 4 i 5 są profilami logicznymi firmware. Nie oznacza to, że PicoVGA udostępnia dokładnie takie same nazwy lub konfiguracje bezpośrednio. Podczas implementacji należy dobrać odpowiadające im formaty biblioteki.

### 4.1. Terminal

Terminal jest niezależnym buforem tekstowym. W trybie 0 jest główną zawartością ekranu. W trybie warstwowym może być wyświetlany jako overlay, jeżeli wybrana konfiguracja PicoVGA na to pozwala i `TERMINAL_ENABLE=1`.

Zapis do `DATA` zawsze trafia do parsera terminala, niezależnie od aktywnego trybu obrazu. Wyłączenie `TERMINAL_ENABLE` ukrywa terminal, ale nie zmienia znaczenia rejestru `DATA`. W trybach, w których terminal nie jest widoczny, dane nadal aktualizują jego bufor.

Wymagane zachowanie terminala:
- zachować istniejącą implementację ANSI/VT100;
- zachować dotychczasowe mapowanie znaków i obsługiwane sekwencje sterujące;
- zachować dotychczasowe zachowanie przy zapisie pojedynczego bajtu do `DATA`;
- używać fontu 8×16 dla profilu 80×30;
- umożliwić zmianę atrybutów kolorów terminala bez zmiany protokołu hosta.

Pełna zgodność VT100 nie jest wymagana, jeśli obecne firmware obsługuje podzbiór. Nowa wersja nie może jednak nieumyślnie usuwać już działających sekwencji ANSI.

### 4.2. Paleta

W trybach indeksowanych kolor jest indeksem do palety. W trybie 8 bpp domyślny format palety może być R3G3B2. W trybach 4 bpp i 1 bpp używane są odpowiednio 16 i 2 wpisy palety.

Polecenie `SET_PALETTE` zmienia pojedynczy wpis. Format wartości palety należy ustalić zgodnie z formatem wyjściowym używanym przez PicoVGA; nie należy zakładać, że format R3G3B2 i format wewnętrzny biblioteki są identyczne.

## 5. Polecenia graficzne

Polecenie jest zatwierdzane zapisem kodu do `COMMAND`. W chwili zatwierdzenia firmware kopiuje wszystkie rejestry parametrów do wewnętrznego opisu polecenia. Jeśli kolejka jest pełna, polecenie nie jest przyjmowane, ustawiany jest `ERROR`, a host musi ponowić próbę po sprawdzeniu `CMD_FULL`.

| Kod | Nazwa | Opis |
|---:|---|---|
| `$00` | `NOP` | brak działania |
| `$01` | `CLEAR` | czyści wybraną warstwę |
| `$02` | `SET_PIXEL` | rysuje punkt |
| `$03` | `LINE` | rysuje linię |
| `$04` | `RECT` | rysuje obrys prostokąta |
| `$05` | `FILL_RECT` | rysuje wypełniony prostokąt |
| `$06` | `SET_PALETTE` | ustawia wpis palety |
| `$07` | `SET_CLIP` | ustawia obszar przycinania warstwy |
| `$08` | `SCROLL` | przewija obszar warstwy |
| `$09` | `BLIT_UPLOAD` | rozpoczyna transfer prostokątnego obrazu do warstwy |
| `$0A` | `LAYER_ENABLE` | włącza lub wyłącza warstwę |
| `$0B` | `LAYER_POSITION` | ustawia pozycję warstwy nakładanej |
| `$0C` | `SET_MODE` | przełącza profil obrazu |
| `$0D` | `TILEMAP_UPLOAD` | rozpoczyna transfer danych tilemapy |
| `$0E` | `SPRITE_CONFIG` | konfiguruje wybrany sprite, jeśli profil go obsługuje |
| `$0F` | `PRESENT` | żąda przełączenia/odświeżenia obrazu na granicy klatki |

### 5.1. Parametry poleceń

W poniższej tabeli `X,Y` pochodzą z rejestrów `$A–$D`, `P0` to `ARG0:ARG1`, a `P1` to `ARG2:ARG3`. Kolory są indeksami palety, chyba że wybrany tryb określa inaczej.

| Polecenie | Parametry |
|---|---|
| `CLEAR` | `ARG0` = kolor wypełnienia |
| `SET_PIXEL` | `X,Y`; `ARG0` = kolor |
| `LINE` | `X,Y` = punkt początkowy; `P0` = X końcowe; `P1` = Y końcowe; `ARG0` = kolor |
| `RECT` | `X,Y` = lewy górny róg; `P0` = szerokość; `P1` = wysokość; `ARG0` = kolor |
| `FILL_RECT` | jak `RECT` |
| `SET_PALETTE` | `ARG0` = indeks wpisu; `ARG1` = kolor 8-bitowy w formacie R3G3B2 |
| `SET_CLIP` | `X,Y` = początek; `P0` = szerokość; `P1` = wysokość; `ARG0` bit 0 = włączenie |
| `SCROLL` | `X,Y` = początek obszaru; `P0` = szerokość; `P1` = wysokość; `ARG0` = kierunek; `ARG1` = liczba pikseli/linii |
| `BLIT_UPLOAD` | `X,Y` = cel; `P0` = szerokość; `P1` = wysokość; format danych wynika z formatu pikseli wybranej warstwy; `ARG0` = flagi transferu (zarezerwowane w 0.1, zapisywać 0) |
| `LAYER_ENABLE` | `ARG0` bit 0 = enable |
| `LAYER_POSITION` | `X,Y` = pozycja warstwy |
| `SET_MODE` | `VIDEO_MODE` = żądany tryb |
| `TILEMAP_UPLOAD` | `X,Y` = początek obszaru mapy; `P0` = liczba kolumn; `P1` = liczba wierszy; `ARG0` = rozmiar kafla / wariant formatu |
| `SPRITE_CONFIG` | `ARG0` = indeks sprite'a; `X,Y` = pozycja; `P0/P1` = rozmiar; szczegóły atrybutów zależą od implementacji |
| `PRESENT` | `ARG0` bit 0 = żądanie przełączenia bufora, jeśli tryb używa buforowania podwójnego |

**Paleta w wersji 0.1:** jeden wpis jest ustawiany przez parę `ARG0` (indeks) i `ARG1` (kolor R3G3B2). W trybach 4 bpp i 1 bpp wykorzystywana jest odpowiednia liczba najmłodszych wpisów palety. Wartości RGB są mapowane przez firmware na format wymagany przez backend PicoVGA.

## 6. Transfer danych

`GFX_DATA` jest portem strumieniowym. Transfer rozpoczyna się poleceniem `BLIT_UPLOAD` lub `TILEMAP_UPLOAD`. Po przyjęciu polecenia karta oblicza oczekiwaną liczbę bajtów na podstawie wymiarów i formatu transferu.

Zasady:
1. Host czeka, aż polecenie zostanie przyjęte.
2. Host zapisuje kolejne bajty do `GFX_DATA`.
3. Firmware przyjmuje dane do wewnętrznego FIFO lub bufora transferu.
4. Jeżeli FIFO nie może przyjąć danych, host sprawdza `STATUS` i wstrzymuje zapis.
5. Po przyjęciu oczekiwanej liczby bajtów karta kończy transfer i ustawia `IRQ_STATUS.TRANSFER_DONE`.
6. Zapis do `GFX_DATA`, gdy transfer nie jest aktywny, ustawia `ERROR` i jest ignorowany.
7. Przerwanie transferu przez reset lub jawne anulowanie musi pozostawić kartę w stanie, z którego można rozpocząć nowy transfer.

### 6.1. Formaty transferu bitmapy

| `ARG0` | Format | Bajty na piksel |
|---:|---|---:|
| 0 | 8 bpp, indeks palety | 1 |
| 1 | 4 bpp, dwa piksele na bajt | 0,5 |
| 2 | 1 bpp, osiem pikseli na bajt | 0,125 |

Dla formatów 4 bpp i 1 bpp kolejność pikseli w bajcie musi być ustalona w implementacji. Zalecana konwencja: najpierw piksel o niższym X; dla 4 bpp najpierw starszy nibble, dla 1 bpp najpierw bit 7. Wymiary transferu muszą uwzględniać zaokrąglenie do pełnego bajtu na końcu wiersza. Zaleca się pakowanie każdego wiersza osobno, bez przenoszenia niepełnych bitów/nibbli pomiędzy wierszami.

Wersja 0.1 nie definiuje odczytu framebufferu przez 6502. Karta jest urządzeniem wyjściowym; transfer danych przebiega wyłącznie od hosta do Pico.

## 7. Błędy i zachowanie graniczne

Firmware powinien ustawiać `STATUS.ERROR` oraz `IRQ_STATUS.ERROR_IRQ` w przypadku:
- nieznanego kodu polecenia;
- polecenia niedozwolonego w aktualnym trybie;
- nieobsługiwanej kombinacji trybu i warstwy;
- zapisu do `GFX_DATA` poza transferem;
- próby zatwierdzenia polecenia przy pełnej kolejce;
- nieprawidłowego formatu lub wymiarów transferu.

Błędy nie powinny powodować zawieszenia magistrali 6502. Rejestry muszą pozostać dostępne, a host powinien móc odczytać status i skasować błąd.

Współrzędne poza obszarem obrazu są przycinane. Wymiary równe zero oznaczają operację pustą, która kończy się bez błędu. Nieprawidłowy identyfikator warstwy lub trybu jest błędem.

## 8. Inicjalizacja i zgodność wsteczna

Po uruchomieniu firmware:
1. inicjalizuje magistralę i rejestry;
2. inicjalizuje PicoVGA i wyjście VGA;
3. ustawia profil `TEXT_80x30`;
4. czyści bufor terminala;
5. włącza terminal;
6. ustawia `INITIALIZED`.

Host może czekać na `STATUS.INITIALIZED` przed wysłaniem danych. W przypadku starszych programów, które nie sprawdzają statusu, zachowanie zapisu do `DATA` powinno pozostać zgodne z dotychczasową kartą po zakończeniu inicjalizacji.

Zgodność wsteczna dotyczy przede wszystkim zapisu znaków i sekwencji ANSI do offsetu `$0`. Nowe funkcje nie mogą wymagać inicjalizacji rejestrów graficznych, aby terminal działał.

## 9. Zalecana kolejność implementacji

### Etap 1 — zgodność i fundament
- zachować dotychczasowy terminal VT100;
- dodać rejestry `STATUS`, `CONTROL`, `VIDEO_MODE`;
- uruchamiać PicoVGA w profilu tekstowym;
- zweryfikować brak utraty znaków przy ciągłym zapisie z 6502.

### Etap 2 — podstawowa grafika
- dodać `SET_MODE`;
- uruchomić `BITMAP_320x240_8`;
- dodać `CLEAR`, `SET_PIXEL`, `LINE`, `RECT`, `FILL_RECT`;
- dodać `BLIT_UPLOAD` i `GFX_DATA`.

### Etap 3 — formaty i palety
- dodać `BITMAP_640x480_4` i `BITMAP_640x480_1`;
- ustalić format palety;
- dodać `SET_PALETTE` i `SCROLL`.

### Etap 4 — warstwy i grafika kafelkowa
- dodać profile warstwowe;
- dodać `LAYER_ENABLE` i `LAYER_POSITION`;
- dodać tilemap i sprite'y tylko w zakresie rzeczywiście obsługiwanym przez backend;
- dodać `PRESENT` i synchronizację zmian z VBLANK.

## 10. Kwestie do rozstrzygnięcia przed zamrożeniem ABI

Ta specyfikacja jest projektem wersji 0.1. Przed napisaniem finalnego firmware należy potwierdzić:

1. Dokładne tryby i formaty framebufferów obsługiwane przez konkretną wersję PicoVGA-CMake na Pico 2.
2. Czy warstwa terminala może być overlayem w wybranym profilu, czy wymaga osobnego bufora/ścieżki kompozycji.
3. Czy transfer danych może być strumieniowany bezpośrednio do docelowej pamięci, czy wymaga bufora pośredniego.
4. Rzeczywistą pojemność kolejki poleceń i FIFO transferu.
5. Czy linia IRQ karty jest fizycznie podłączona do systemu 65C02.
6. Dokładny format palety oraz kolejność bajtów dla transferów 4 bpp i 1 bpp.
7. Czy tryby wymagające dużej pamięci (np. 640×480 4 bpp) mieszczą się wraz z buforami i kodem PicoVGA w dostępnej SRAM.

Po rozstrzygnięciu tych punktów należy oznaczyć specyfikację jako 1.0 i traktować mapę rejestrów oraz kody poleceń jako stabilne ABI dla programów 65C02.

---

## Załącznik A — przykładowa sekwencja ustawienia trybu bitmapowego

Pseudokod 6502:

```asm
; Czekaj na inicjalizację
wait_gpu:
    LDA GPU_STATUS
    AND #$80
    BEQ wait_gpu

; Wybierz tryb 320x240 / 8 bpp
    LDA #$01
    STA GPU_VIDEO_MODE
    LDA #$0C              ; SET_MODE
    STA GPU_COMMAND

; Poczekaj na zakończenie polecenia
wait_mode:
    LDA GPU_STATUS
    AND #$01              ; BUSY
    BNE wait_mode

; Wyczyść warstwę bazową kolorem 0
    LDA #$00
    STA GPU_LAYER
    STA GPU_ARG0
    LDA #$01              ; CLEAR
    STA GPU_COMMAND
```

## Załącznik B — przykładowy transfer bitmapy

Pseudokod zakłada, że obraz ma 64×32 piksele w formacie zgodnym z wybraną warstwą. Dla trybu `BITMAP_320x240_8` oznacza to 2048 bajtów danych.

```asm
; Cel: X=10, Y=20
    LDA #10
    STA GPU_X_LO
    LDA #0
    STA GPU_X_HI
    LDA #20
    STA GPU_Y_LO
    LDA #0
    STA GPU_Y_HI

; Wymiary: P0=64, P1=32
    LDA #64
    STA GPU_ARG0
    LDA #0
    STA GPU_ARG1
    LDA #32
    STA GPU_ARG2
    LDA #0
    STA GPU_ARG3

; Format transferu wynika z aktywnego trybu/warstwy.
; BLIT_UPLOAD rozpoczyna przyjmowanie 64*32 bajtów dla 8 bpp.
    LDA #$09
    STA GPU_COMMAND

; Wysyłaj dokładnie 2048 bajtów do GPU_GFX_DATA.
; W rzeczywistym kodzie należy uwzględnić FIFO/status.
    LDX #0
upload_loop:
    LDA image_data,X
    STA GPU_GFX_DATA
    INX
    ; Pętla jest schematyczna: 6502 musi obsłużyć
    ; licznik 16-bitowy i kontrolę gotowości FIFO.
```

Dla 4 bpp i 1 bpp liczba bajtów wynika z szerokości, wysokości oraz pakowania wierszy opisanego w rozdziale 6. Format transferu nie jest osobnym argumentem polecenia — wynika z formatu docelowej warstwy. Dzięki temu `ARG0–ARG3` mogą jednoznacznie przechowywać szerokość i wysokość.
