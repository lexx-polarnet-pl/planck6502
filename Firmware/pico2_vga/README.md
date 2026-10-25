# Planck 6502 Pico2-VGA Firmware

Firmware for the Pico2-VGA card used in the Planck 6502 homebrew computer.

**This firmware is a work in progress.**

## Hardware Requirements

This firmware turns a **Raspberry Pi Pico 2** into a dedicated VGA graphics card. It uses the original Planck 6502 Pico-VGA hardware design, but **requires a Pico 2** — the original RP2040 Pico does not have enough RAM to store the complete framebuffer.

## Capabilities

Although the Pico 2 operates in full graphical mode internally, the current firmware provides an emulated **80×30 text mode** interface to the 6502 processor. Text formatting, color adjustments, cursor movement, and screen clearing are handled via a subset of standard **ANSI / VT100 control sequences**.

---
## Memory Map (16 Bytes)

| Offset | Symbol | R/W | Function |
| :---: | :--- | :---: | :--- |
| `+$0` | `CHR_OUT` | **W** | Write ASCII / ANSI control byte to screen |

---
## Supported Control Sequences & ANSI Codes

All sequences are sent by writing characters sequentially to `CHR_OUT`. `ESC` represents the byte `0x1B`.

### Control Characters

| Character | Name | Behavior |
| :---: | :--- | :--- |
| `\n` | Line Feed | Resets column position to 0 (Carriage Return behavior). |
| `\r` | Carriage Return | Moves cursor down 1 row (scrolls screen up if at the bottom). |
| `\b` | Backspace | Erases character at current position with a space and moves cursor left. |
| `\t` | Tab | Advances cursor position by 4 columns. |

### ANSI / VT100 Escape Sequences (`ESC[ ...`)

> **Note:** Only CSI sequences starting with `ESC[` are supported. Other `ESC` characters are ignored. The parser supports up to 4 numeric parameters.

| Sequence | Name | Description |
| :--- | :--- | :--- |
| `ESC[2J` | Clear Screen | Clears screen contents and resets character/color buffers. |
| `ESC[<r>;<c>H` | Cursor Position (CUP) | Moves cursor to row `<r>` and column `<c>` (1-based index, defaults to `1;1`). |
| `ESC[?25h` | Show Cursor | Enables visible cursor rendering. |
| `ESC[?25l` | Hide Cursor | Disables cursor rendering. |
| `ESC[<params>m` | Select Graphic Rendition | Sets text attributes and colors (SGR). See details below. |

#### Supported SGR Parameters (`ESC[...m`)

Multiple parameters can be combined using semicolons (e.g., `ESC[0;31;100m`).

* **`0`**: Reset all color attributes to default (`default_fg_color` / `default_bg_color`).
* **`30`–`37` / `40`–`47`**: Standard 8 Foreground / Background colors.
* **`39` / `49`**: Reset Foreground / Background to default color.
* **`90`–`97` / `100`–`107`**: Bright 8 Foreground / Background colors (16-color palette support).

*(Note: Style attributes like `1` (Bold) or `4` (Underline) are currently ignored).*
