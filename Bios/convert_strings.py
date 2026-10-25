import sys
import datetime

# Słownik konwersji ze znaków UTF-8 na bajty kodowania Mazovia
MAZOVIA_MAP = {
    'ą': b'\x86', 'ć': b'\x8d', 'ę': b'\x91', 'ł': b'\x92', 'ń': b'\xa4',
    'ó': b'\xa2', 'ś': b'\x9e', 'ź': b'\xa6', 'ż': b'\xa7',
    'Ą': b'\x8f', 'Ć': b'\x95', 'Ę': b'\x90', 'Ł': b'\x9c', 'Ń': b'\xa5',
    'Ó': b'\xa0', 'Ś': b'\x9d', 'Ź': b'\xa6', 'Ż': b'\xa7'
}

def generate_short_build_id():
    """
    Generuje ultrakrótki numer builda na podstawie daty i czasu.
    Format: RRMMDDHHMM (np. 2610151758 -> 15 października 2026, 17:58)
    Długość: dokładnie 10 znaków.
    """
    now = datetime.datetime.now()
    return now.strftime("%y%m%d%H%M")

def convert_utf8_to_mazovia(input_file, output_file):
    # 1. Odczytujemy plik wejściowy UTF-8 jako tekst
    with open(input_file, 'r', encoding='utf-8') as f:
        content = f.read()

    # 2. Podmieniamy tag {build} na wygenerowany znacznik
    build_id = generate_short_build_id()
    content = content.replace("{build}", build_id)

    # 3. Konwertujemy tekst znak po znaku na bajty Mazovii
    output_bytes = bytearray()
    for char in content:
        if char in MAZOVIA_MAP:
            output_bytes.extend(MAZOVIA_MAP[char])
        else:
            # Standardowe znaki ASCII zamieniamy bezpośrednio na bajty
            output_bytes.extend(char.encode('ascii', errors='replace'))

    # 4. Zapisujemy wynikowy plik binarne/tekstowy
    with open(output_file, 'wb') as f:
        f.write(output_bytes)

    print(f"[OK] Przekonwertowano {input_file} -> {output_file} (Build ID: {build_id})")

if __name__ == "__main__":
    in_file = sys.argv[1] if len(sys.argv) > 1 else "bios_strings.asm"
    out_file = sys.argv[2] if len(sys.argv) > 2 else "bios_strings_mazovia.asm"
    
    convert_utf8_to_mazovia(in_file, out_file)