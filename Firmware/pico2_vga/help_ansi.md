# help_ansi — obsługiwane sekwencje ANSI przez `vga_text_mode.c`

Poniżej znajduje się lista wszystkich sekwencji sterujących ANSI, które faktycznie obsługuje program w pliku `vga_text_mode.c`.

Uwaga ogólna:
- `ESC` oznacza bajt `0x1B`. Program rozpoznaje tylko sekwencje CSI zaczynające się od `ESC[`; pozostałe pojedyncze sekwencje `ESC` są ignorowane.
- Parser CSI przyjmuje maksymalnie 4 parametrów.

1) Znaki kontrolne (obsługiwane w trybie normalnym)
- `\n` (LF): ustawia kolumnę na 0 (w tym kodzie zachowanie odwrotne od niektórych terminali — traktowane jako „carriage return”).
- `\r` (CR): przesuwa wiersz w dół o 1 (tj. inkrementuje `txt_cursor_y`); jeśli poza ekranem — przewija w górę.
- `\b` (BS): backspace — usuwa znak w bieżącej pozycji (wstawia spację), zmniejsza `txt_cursor_x` (nie schodzi poniżej 0).
- `\t` (TAB): przesuwa kursor o 4 kolumny w prawo (proste przesunięcie, brak skoków do tabstopów).

2) Sekwencje CSI (`ESC[ ... <final>`)
Ogólny format: `ESC[<param1>;<param2>;...<final>` (parametry liczbowe, brak parametru = domyślna wartość).

- ESC [ 2 J
  - Opis: wyczyść cały ekran.
  - Implementacja: tylko `p == 2` jest obsługiwane; wykonuje `clear_screen` i zeruje bufor znaków/kolorów.

- ESC [ <r> ; <c> H
  - Opis: ustaw pozycję kursora (CUP). Parametry są 1‑based (rzadek, kolumna).
  - Implementacja: zapisywane do `txt_cursor_y = r-1`, `txt_cursor_x = c-1`.
  - Uwaga: jeśli parametry pominięte, domyślnie `1;1` (home).

- ESC [ ? 25 h
  - Opis: prywatny tryb DEC — pokaż kursora (DECTC?).
  - Implementacja: wywołuje `cursor_enable()` i ustawia `cursorDisabled = false`.

- ESC [ ? 25 l
  - Opis: prywatny tryb DEC — ukryj kursora.
  - Implementacja: wywołuje `cursor_disable()` i ustawia `cursorDisabled = true`.

- ESC [ <...> m
  - Opis: SGR — Select Graphic Rendition (atrybuty/kolory).
  - Implementacja: obsługiwane wartości parametrów (pojedynczo lub wielokrotnie):
    - `0` — reset atrybutów (przywraca kolory domyślne `default_fg_color` / `default_bg_color`).
    - Foreground: `30`..`37` (standardowe 8 kolorów).
    - Background: `40`..`47` (standardowe 8 kolorów).
    - Reset kolorów: `39` (przywróć foreground do domyślnego), `49` (przywróć background do domyślnego).
    - Jasne warianty (16-color support): `90`..`97` (bright foreground) i `100`..`107` (bright background).
  - Uwaga: tylko powyższe kody są obsługiwane; np. `1` (bold), `4` (underline) itp. nie są obsługiwane i zostaną zignorowane.

3) Parser i ograniczenia
- Parser rozpoznaje `ESC` tylko jako początek sekwencji; jeśli następny bajt nie jest `'['`, sekwencja jest zignorowana.
- Maksymalna liczba parametrów CSI: 4.
- Nieobsługiwane CSI (np. `C`/`D`/`A`/`B` — ruch kursora w górę/dół/lewo/prawo) są ignorowane.
- Brak obsługi OSC (`ESC]`), DSR (`ESC[n` z odpowiedzią), DCS (`ESC P`), ani sekwencji zapisz/przywróć kursora (`ESC7`/`ESC8`) — chociaż w kodzie są funkcje `cursor_enable`/`cursor_disable`, nie ma mapowania na `ESC7`/`ESC8`.

4) Zachowania tekstowe i stożkowe przypadki
- Wstawianie zwykłego znaku: zapisuje do `txt_chars` i `txt_colors`, rysuje przez `drawCharBig`, przesuwa `txt_cursor_x` i przy przejściu końca linii przewija w dół (scroll). Rozmiar ekranu: 80×30 (`TXT_SCREEN_SIZE_X` × `TXT_SCREEN_SIZE_Y`).
- Backspace: przywraca spację w starym miejscu i zmniejsza `txt_cursor_x`.
- Tab: proste `+4` do `txt_cursor_x` bez wyrównania do stopów.

5) Podsumowanie — krótkie „ściągawka” (lista sekwencji do wklejenia):
- `\n` — ustaw kolumnę na 0
- `\r` — przejdź do następnego wiersza (inkrementuj y / przewiń jeśli potrzeba)
- `\b` — backspace (usuń i cofnij kolumnę)
- `\t` — tab = +4 kolumny
- `ESC[2J` — wyczyść cały ekran
- `ESC[<r>;<c>H` — ustaw pozycję kursora (1‑based)
- `ESC[?25h` — pokaż kursor
- `ESC[?25l` — ukryj kursor
- `ESC[...m` — SGR: obsługiwane: `0`, `30..37`, `40..47`, `39`, `49`, `90..97`, `100..107`

6) Jeśli chcesz
- Mogę rozszerzyć obsługę (np. dodać `ESC[2K`, ruch kursora `A/B/C/D`, zapis/przywróć `ESC7/ESC8`, obsługę OSC lub 24-bit kolorów). Powiedz które sekwencje chcesz dodać, a przygotuję patch.

Plik wygenerowany na podstawie implementacji w `vga_text_mode.c`.

*** Koniec pliku
