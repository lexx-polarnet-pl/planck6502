
import sys
import struct


def convert_psf_to_c(psf_path, output_path="font.h", font_name="bigFont"):
    with open(psf_path, "rb") as f:
        header = f.read(4)

        # PSF1
        if header[:2] == b'\x36\x04':
            mode_flags = header[1]
            charsize = header[3]

            num_glyphs = 512 if (mode_flags & 0x01) else 256

            font_data = f.read()
            font_data = font_data[:num_glyphs * charsize]

        # PSF2
        elif header[:4] == b'\x72\xb5\x4a\x86':
            header_data = f.read(28)

            _, _, headersize, _, num_glyphs, charsize, height, width = \
                struct.unpack("<IIIIIIII", header + header_data)

            f.seek(headersize)
            font_data = f.read(num_glyphs * charsize)

        else:
            print("Błąd: Niepoprawny format PSF1/PSF2.")
            return

    target_glyphs = 256
    bytes_per_char = charsize

    output_lines = []

    output_lines.append(
        f"const unsigned char {font_name}[{bytes_per_char}*{target_glyphs}] = {{"
    )
    output_lines.append(
        f"  // array size is {bytes_per_char * target_glyphs}"
    )
    output_lines.append(
        "  // Format: wszystkie znaki pogrupowane według linii fontu"
    )

    # Generowanie danych w układzie:
    # linia 0: bajt 0 wszystkich znaków
    # linia 1: bajt 1 wszystkich znaków
    # itd.

    for line in range(bytes_per_char):
        output_lines.append(f"\n  // Font line {line}")

        for i in range(target_glyphs):
            if i < num_glyphs:
                index = i * bytes_per_char + line
                value = font_data[index]
            else:
                value = 0

            char_repr = chr(i) if 32 <= i <= 126 else ' '

            output_lines.append(
                f"  0x{value:02x},  // Char {i} (0x{i:02X}) '{char_repr}'"
            )

    output_lines.append("};")

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
