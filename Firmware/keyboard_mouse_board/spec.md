# Specyfikacja Podsystemu I/O dla Procesora 6502 (ATmega Coprocessor)

Dokument zawiera specyfikację techniczną układu I/O opartego na mikrokontrolerze ATmega, zmapowanego w 16-bajtowym bloku pamięci procesora 6502 (`BASE` do `BASE + $F`). Układ odpowiada za obsługę:
- Klawiatury (ASCII + Scan Codes z buforem FIFO)
- Myszy (współrzędne $X$, $Y$, przyciski, rolka)
- Zegara Czasu Rzeczywistego (RTC)
- Pamięci Nieulotnej (NVRAM / EEPROM z adresowaniem pośrednim)
- Hardware PRNG / TRNG (Generatora Liczb Losowych opartego o entropię czasową i RTC)
- Kontrolera Przerwań (`/IRQ`)

---

## 1. Mapa Pamięci (Memory Map - 16 Bajtów)

| Adres | Symbol | R/W | Opis i funkcjonalność |
| :---: | :--- | :---: | :--- |
| **`BASE + $0`** | `KBD_DATA` | **R** | **Bufor Klawiatury** – Domyślnie zwraca bajt Smart ASCII / Extended Mazovia; opcjonalnie surowy Scan Code. Odczyt automatycznie zdejmuje bajt z kolejki FIFO. |
| **`BASE + $1`** | `KBD_CTRL` | **R/W** | **Kontrola Klawiatury** – Wybór trybu Smart ASCII / surowy Scan Code; odczyt zwraca również stany blokad i odpowiadających im LED. |
| **`BASE + $2`** | `KBD_STAT` | **R** | **Status Klawiatury** – Liczba znaków/flaga `DATA_READY`, stan klawiszy modyfikujących (Shift, Ctrl, Alt). |
| **`BASE + $3`** | `MOUSE_X` | **R** | **Mysz X** – Przesunięcie względne $\Delta X$ (signed byte) lub os `X` w trybie bezwzględnym. |
| **`BASE + $4`** | `MOUSE_Y` | **R** | **Mysz Y** – Przesunięcie względne $\Delta Y$ (signed byte) lub os `Y` w trybie bezwzględnym. |
| **`BASE + $5`** | `MOUSE_BTN` | **R** | **Przyciski i Rolka Myszy** – Stan przycisków (L, R, M) + delta rolki scrolla. |
| **`BASE + $6`** | `RTC_SEC` | **R/W** | **RTC: Sekundy** (0–59 / BCD). |
| **`BASE + $7`** | `RTC_MIN` | **R/W** | **RTC: Minuty** (0–59 / BCD). |
| **`BASE + $8`** | `RTC_HOUR` | **R/W** | **RTC: Godziny** (0–23 / BCD). |
| **`BASE + $9`** | `RTC_DAY` | **R/W** | **RTC: Dzień miesiąca** (1–31 BCD). |
| **`BASE + $A`** | `RTC_MONTH` | **R/W** | **RTC: Miesiąc** (1–12 BCD). |
| **`BASE + $B`** | `RTC_YEAR` | **R/W** | **RTC: Rok** (0–99 BCD). |
| **`BASE + $C`** | `NVRAM_ADDR`| **R/W** | **NVRAM Adres** – Wskaźnik komórki EEPROM (0–255). |
| **`BASE + $D`** | `NVRAM_DATA`| **R/W** | **NVRAM Dane** – Odczyt/Zapis pod wskazanym adresem. Opcjonalny auto-inkrement `NVRAM_ADDR`. |
| **`BASE + $E`** | `RNG_DATA` | **R/W** | **Generator Liczb Losowych**:<br>• **Odczyt (R):** Zwraca nową 8-bitową liczbę losową.<br>• **Zapis (W):** Zapis ziarna (Seed). |
| **`BASE + $F`** | `SYS_CTRL_STAT`| **R/W** | **Rejestr Systemowy / IRQ**:<br>• **Odczyt (R):** Status źródeł zgłoszonego przerwania IRQ.<br>• **Zapis (W):** Maska włączenia przerwań IRQ. |

Obsługa RTC odczytuje czas z DS1307+ podczas startu i dodaje do bufora
klawiatury wpis `RTC: YYYY-MM-DD HH:MM:SS`. Rejestry RTC są dostępne przez
magistralę 6502 jako wartości BCD; godzina jest zawsze zwracana i zapisywana
w formacie 24-godzinnym. Nieprawidłowe wartości podczas zapisu są odrzucane.

Wstępna obsługa myszy PS/2 używa PB5 (DATA) i PB6 (CLK), wykonuje reset myszy
i włącza raportowanie ruchu. Status połączenia oraz raport z pozycją
względną X/Y, przyciskami L/R/M i liczbą odebranych pakietów trafiają do bufora
klawiatury co 3 sekundy. Błędy inicjalizacji wskazują etap, na którym nie
powiodła się komunikacja (ACK, odpowiedź resetu, autotest, ID albo enable).

---

## 2. Szczegółowy Opis Rejestrów

### Klawiatura (`BASE + $0` .. `BASE + $2`)

#### `KBD_CTRL` (`BASE + $1`)
- **Bit 0**: `SCAN_MODE` (0 = Smart ASCII / Extended Mazovia, 1 = surowy Scan Code)
- **Bit 1**: zarezerwowany (zapis zachowywany do odczytu; powtarzanie klawiszy nie jest konfigurowane przez ten bit)
- **Bit 2**: `CAPS_LOCK` (stan Caps Lock; LED sterowany autonomicznie przez ATmegę)
- **Bit 3**: `NUM_LOCK` (stan Num Lock; LED sterowany autonomicznie przez ATmegę)
- **Bit 4**: `SCROLL_LOCK` (stan Scroll Lock; LED sterowany autonomicznie przez ATmegę)

Wartość po resecie to `0x00`, czyli Smart ASCII. Zapis do `KBD_CTRL` zmienia
tryb `SCAN_MODE` i zachowuje bit 1; bity 2–4 są tylko do odczytu i wynikają
z naciśnięć klawiszy Caps Lock, Num Lock i Scroll Lock. Po zmianie stanu
blokady ATmega wysyła do klawiatury polecenie aktualizacji diod.

W Smart ASCII ATmega śledzi Shift, Ctrl i prawy Alt (AltGr). `Shift` zmienia
wielkość liter i znaki interpunkcyjne; Caps Lock zmienia wielkość liter, a
połączenie Caps Lock i Shift odwraca ten efekt. `Ctrl+A`–`Ctrl+Z` zwraca
kody `0x01`–`0x1A`. Enter zwraca CR (`0x0D`), a Tab, Backspace i Escape
zwracają odpowiednio `0x09`, `0x08` i `0x1B`.

AltGr z literą zwraca jednobajtowy kod Mazovii:

| Litera | Kod | Litera | Kod |
|:---:|:---:|:---:|:---:|
| Ą / ą | `8F` / `86` | Ć / ć | `95` / `8D` |
| Ę / ę | `90` / `91` | Ł / ł | `9C` / `92` |
| Ń / ń | `A5` / `A4` | Ó / ó | `A3` / `A2` |
| Ś / ś | `98` / `9E` | Ź / ź | `A0` / `A6` |
| Ż / ż | `A1` / `A7` | | |

Klawisze nawigacyjne zwracają `0xE0`–`0xE9` (Up, Down, Left, Right, Home,
End, Page Up, Page Down, Insert, Delete). F1–F12 zwracają `0xEA`–`0xF5`;
Print Screen, Scroll Lock, Pause, Menu, Left GUI, Right GUI i Numpad Enter
zwracają odpowiednio `0xF6`–`0xFC`. Nieobsługiwane klawisze nie dodają bajtu
do FIFO. Num Lock wybiera cyfry i kropkę na bloku numerycznym; przy
wyłączonym Num Lock lub wciśniętym Shift jego klawisze nawigacyjne zwracają
kody `0xE0`–`0xE9`. Operatory `+`, `-`, `*` i `/` pozostają znakami ASCII.

#### `KBD_STAT` (`BASE + $2`)
- **Bit 0**: `SCAN_MODE_ACTIVE` (Stan bitu 0 z CTRL)
- **Bit 1**: `SHIFT_ACTIVE` (1 = wciśnięty lewy lub prawy Shift)
- **Bit 2**: `CTRL_ACTIVE` (1 = wciśnięty lewy lub prawy Ctrl)
- **Bit 3**: `ALT_ACTIVE` (1 = wciśnięty Alt lub AltGr)
- **Bit 4**: `CAPS_LOCK_ACTIVE` (Stan Caps Lock)
- **Bit 6**: `BUF_OVERFLOW` (1 = Przepełnienie FIFO)
- **Bit 7**: `DATA_READY` (1 = Przynajmniej jeden znak czeka w buforze FIFO)

---

### Mysz (`BASE + $3` .. `BASE + $5`)

#### `MOUSE_BTN` (`BASE + $5`)
- **Bit 0**: `LEFT_BTN` (1 = Wciśnięty lewy przycisk)
- **Bit 1**: `RIGHT_BTN` (1 = Wciśnięty prawy przycisk)
- **Bit 2**: `MIDDLE_BTN` (1 = Wciśnięty środkowy przycisk)
- **Bits 6-4**: `SCROLL_DELTA` (Wartość ze znakiem U2 reprezentująca ruch rolki: `-3` do `+3`)
- **Bit 7**: `MOUSE_MOVED` (1 = Od ostatniego odczytu nastąpiła zmiana pozycji lub stanu przycisków)

---

### Pamięć Nieulotna NVRAM (`BASE + $C`, `BASE + $D`)

NVRAM wykorzystuje adresowanie pośrednie:
1. Zapisz adres bajtu (0–255) do `NVRAM_ADDR` (`BASE + $C`).
2. Odczytaj/zapisz dane w `NVRAM_DATA` (`BASE + $D`).
3. Jeśli w `SYS_CTRL_STAT` włączono bit `AUTO_INC_NVRAM`, odczyt lub zapis do `NVRAM_DATA` automatycznie zwiększy `NVRAM_ADDR` o 1.

---

### Generator Liczb Losowych RNG (`BASE + $E`)

Układ wykorzystuje mieszaną entropię sprzętową i czasową:
1. **Inicjalizacja**: Przy włączeniu zasilania ATmega pobiera początkową wartość z rejestrów czasu RTC (godzina, minuta, sekunda).
2. **Zbieranie entropii**: Mikrokontroler mierzy czas z dokładnością do mikrosekund/nanosekund (`Timer1`) przy każdym przerwaniu generowanym przez naciśnięcie klawisza lub ruch myszy. Wynik pomiaru jest mieszany z wewnętrznym stanem generatora (`rng_state`).
3. **Odczyt (`RNG_DATA`)**: Zwraca 8-bitowy wynik algorytmu **Xorshift32**.
4. **Zapis (`RNG_DATA`)**: Pozwala procesorowi 6502 ręcznie narzucić nowe ziarno (Seed).

---

### Kontrola Systemu i Przerwań (`BASE + $F`)

#### Zapis do `SYS_CTRL_STAT` (Konfiguracja):
- **Bit 0**: `AUTO_INC_NVRAM` (1 = Automatyczna inkrementacja adresu NVRAM przy odczycie/zapisie danych)
- **Bit 1**: `KBD_IRQEN` (1 = Generuj przerwanie `/IRQ` dla 6502 gdy bufor klawiatury jest niepusty)
- **Bit 2**: `MOUSE_IRQEN` (1 = Generuj przerwanie `/IRQ` dla 6502 przy ruchu/kliknięciu myszy)
- **Bit 3**: `RTC_IRQEN` (1 = Generuj przerwanie `/IRQ` dla 6502 przy tyknięciu zegara 1 Hz / Alarmie)
- **Bit 7**: `GLOBAL_IRQEN` (1 = Zezwól na wyzwalanie linii `/IRQ` procesora 6502)

#### Odczyt z `SYS_CTRL_STAT` (Status IRQ):
- **Bit 0**: `RTC_IRQ_PENDING`
- **Bit 1**: `KBD_IRQ_PENDING`
- **Bit 2**: `MOUSE_IRQ_PENDING`
- **Bit 4**: `KBD_PRESENT` (1 = klawiatura wykryta podczas inicjalizacji)
- **Bit 5**: `MOUSE_PRESENT` (1 = mysz wykryta i poprawnie zainicjalizowana)
- **Bit 7**: `IRQ_ACTIVE` (1 = Linia `/IRQ` jest obecnie w stanie niskim)

Aktualna obsługa odczytu `SYS_CTRL_STAT` zwraca bity `KBD_PRESENT` i
`MOUSE_PRESENT`; pozostałe bity odczytu są obecnie zerowe. Zapis do tego
rejestru nie jest jeszcze obsługiwany.

---

## 3. Przykład Użycia w Asemblerze 6502

```assembly
; ==============================================================================
; DEFOWANIE REJESTRÓW (Założenie: Adres bazowy I/O to $C000)
; ==============================================================================
IO_BASE        = $C000
KBD_DATA       = IO_BASE + $0
KBD_CTRL       = IO_BASE + $1
KBD_STAT       = IO_BASE + $2
MOUSE_X        = IO_BASE + $3
MOUSE_Y        = IO_BASE + $4
MOUSE_BTN      = IO_BASE + $5
NVRAM_ADDR     = IO_BASE + $C
NVRAM_DATA     = IO_BASE + $D
RNG_DATA       = IO_BASE + $E
SYS_CTRL_STAT  = IO_BASE + $F

; ------------------------------------------------------------------------------
; Odczyt znaku z klawiatury (pętla odpytująca / polling)
; ------------------------------------------------------------------------------
GET_CHAR:
    LDA KBD_STAT
    AND #$80            ; Sprawdź bit 7 (DATA_READY)
    BEQ GET_CHAR        ; Czekaj, jeśli bufor jest pusty
    LDA KBD_DATA        ; Pobierz kod ASCII
    RTS

; ------------------------------------------------------------------------------
; Pobranie liczby losowej
; ------------------------------------------------------------------------------
GET_RANDOM:
    LDA RNG_DATA        ; Wracaj natychmiast z nową wartością 0-255 w akumulatorze
    RTS

; ------------------------------------------------------------------------------
; Odczyt bloku 16 bajtów z NVRAM (EEPROM)
; ------------------------------------------------------------------------------
READ_CONFIG_BLOCK:
    LDA #$01
    STA SYS_CTRL_STAT   ; Włącz AUTO_INC_NVRAM (bit 0)
    
    LDA #$00
    STA NVRAM_ADDR      ; Ustaw adres początkowy NVRAM na $00

    LDX #$00
.LOOP:
    LDA NVRAM_DATA      ; Odczytaj bajt (NVRAM_ADDR zwiększy się automatycznie)
    STA $0200, X        ; Zapisz do RAM 6502
    INX
    CPX #$10            ; Odczytaj 16 bajtów
    BNE .LOOP
    RTS
```

---

## 4. Referencyjna Implementacja RNG w C (Dla ATmega)

```c
#include <avr/io.h>

static uint32_t rng_state = 0x12345678;

// Inicjalizacja przy starcie układu wartościami z RTC
void rng_init(uint8_t sec, uint8_t min, uint8_t hour) {
    rng_state ^= ((uint32_t)hour << 16) | ((uint32_t)min << 8) | sec;
}

// Zbieranie entropii - wywoływane w procedurze przerwania PS/2 klawiatury lub myszy
void rng_add_entropy(uint8_t input_byte) {
    uint16_t timer1_val = TCNT1; // Odczyt sprzętowego licznika mikrokontrolera
    rng_state ^= ((uint32_t)timer1_val << 8) | input_byte;
}

// Obsługa odczytu rejestru BASE + $E przez 6502
uint8_t rng_read_byte(void) {
    // Algorytm Xorshift32
    rng_state ^= (rng_state << 13);
    rng_state ^= (rng_state >> 17);
    rng_state ^= (rng_state << 5);

    return (uint8_t)(rng_state & 0xFF);
}

// Obsługa zapisu rejestru BASE + $E przez 6502
void rng_write_seed(uint8_t seed) {
    rng_state ^= (uint32_t)seed;
}
```