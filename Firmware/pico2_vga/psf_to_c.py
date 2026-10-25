import sys

def convert_psf_to_c(psf_path, output_path="font.h", font_name="bigFont"):
    with open(psf_path, "rb") as f:
        header = f.read(4)
        
        # Sprawdzenie nagłówka PSF
        if header[:2] == b'\x36\x04':  # PSF1
            mode = 1
            magic, mode_flags, charsize = header[0], header[1], header[3]
            # PSF1 może mieć 256 lub 512 znaków w zależności od flag
            num_glyphs = 512 if (mode_flags & 0x01) else 256
            font_data = f.read()
            # Obcięcie ewentualnej tabeli unicode, jeśli istnieje
            font_data = font_data[:num_glyphs * charsize]
            
        elif header[:4] == b'\x72\xb5\x4a\x86':  # PSF2
            mode = 2
            header_data = f.read(28) # Wczytaj resztę nagłówka PSF2 (32 bajty łącznie)
            import struct
            # version, flags, headersize, flags, length (liczba glyphs), charsize, height, width
            _, _, headersize, _, num_glyphs, charsize, height, width = struct.unpack("<IIIIIIII", header + header_data)
            
            # Przejdź do początku danych bitmapy
            f.seek(headersize)
            font_data = f.read(num_glyphs * charsize)
        else:
            print("Błąd: To nie jest poprawny plik w formacie PSF (brak rozpoznanej magii PSF1/PSF2).")
            return

    # Jeśli czcionka ma mniej niż 256 znaków, uzupełniamy zerami, a jeśli więcej, bierzemy pierwsze 256 (lub dostosuj do potrzeb)
    target_glyphs = 256
    bytes_per_char = charsize # Zazwyczaj 16 dla wysokości 16 pikseli
    
    output_lines = []
    output_lines.append(f"const unsigned char {font_name}[{bytes_per_char}*{target_glyphs}] = {{")
    output_lines.append(f"  // array size is {bytes_per_char * target_glyphs}")

    for i in range(target_glyphs):
        if i < num_glyphs:
            start_idx = i * bytes_per_char
            char_bytes = font_data[start_idx:start_idx + bytes_per_char]
        else:
            char_bytes = bytes(bytes_per_char) # Puste znaki, jeśli plik ma ich mniej niż 256

        hex_str = ", ".join(f"0x{b:02x}" for b in char_bytes)
        
        # Próba dodania czytelnego znaku w komentarzu
        char_repr = chr(i) if 32 <= i <= 126 else ' '
        
        output_lines.append(f"  {hex_str},  // Char {i} (0x{i:02X}) '{char_repr}'")

    output_lines.append("};")

    # Zapis do pliku nagłówkowego C
    with open(output_path, "w", encoding="utf-8") as out:
        out.write("\n".join(output_lines) + "\n")

    print(f"Konwersja zakończona sukcesem! Wygenerowano plik: {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Użycie: python psf_to_c.py <plik.psf> [nazwa_wyjsciowa.h]")
    else:
        psf_file = sys.argv[1]
        out_file = sys.argv[2] if len(sys.argv) > 2 else "font.h"
        convert_psf_to_c(psf_file, out_file)