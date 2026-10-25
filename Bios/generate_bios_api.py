import re
import sys
from pathlib import Path


BIOS_FUNCTIONS_START = 0xFF00
BIOS_FUNCTIONS_END = 0xFF80
LABEL_PATTERN = re.compile(r"^al\s+([0-9A-Fa-f]{6})\s+\.([A-Za-z_][A-Za-z0-9_]*)$")


def generate_bios_api(label_file, output_file):
    functions = []
    for line in Path(label_file).read_text(encoding="ascii").splitlines():
        match = LABEL_PATTERN.match(line)
        if match is None:
            continue

        address = int(match.group(1), 16)
        name = match.group(2)
        if name.startswith("bios_") and BIOS_FUNCTIONS_START <= address < BIOS_FUNCTIONS_END:
            functions.append((address, name))

    if not functions:
        raise ValueError(f"No BIOS function labels found in {label_file}")

    functions.sort()
    output = [
        "; Generated from the ld65 label file. Do not edit.",
        *[f"{name} = ${address:04X}" for address, name in functions],
        "",
    ]
    Path(output_file).write_text("\n".join(output), encoding="ascii", newline="\n")
    print(f"[OK] Generated {output_file} with {len(functions)} BIOS functions")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: python generate_bios_api.py <bios.lbl> <bios_api.inc>")
    generate_bios_api(sys.argv[1], sys.argv[2])
