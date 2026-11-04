# Planck 6502 Keyboard and Mouse Interface Firmware

Firmware for the keyboard and mouse interface card (rev 1.x).

**This firmware is a work in progress.**

This firmware enables an ATmega microcontroller to act as an I/O coprocessor mapped to a 16-byte memory block (`BASE` to `BASE + $F`) within the 6502 architecture. It offloads peripheral handling, timing-critical tasks, and NVRAM management from the main CPU. 

In default mode, all PS/2 keyboard decoding is processed by the ATmega, allowing the 6502 to directly read ready-to-use ASCII characters straight from its memory-mapped interface.

## Key Features
* **Keyboard**: PS/2 support with Smart ASCII (Extended Mazovia) or raw Scan Code mode via FIFO buffer. (working)
* **Mouse**: PS/2 relative/absolute position tracking, button detection, and scroll wheel support. (not yet working)
* **Real-Time Clock (RTC)**: Integrated DS1307+ RTC using BCD registers with automatic startup timestamping. (working)
* **Non-Volatile RAM**: Indirectly addressed 256-byte EEPROM with optional auto-increment. (not yet working)
* **PRNG/TRNG**: Hardware random number generator using **Xorshift32** seeded with RTC and hardware timer (`Timer1`) input entropy. (not yet working)
* **Interrupt Controller**: Configurable active-low `/IRQ` line for keyboard FIFO data; mouse and RTC IRQs are reserved.

---

## Memory Map (16 Bytes)

| Offset | Symbol | R/W | Function |
| :---: | :--- | :---: | :--- |
| `+$0` | `KBD_DATA` | **R** | Pop next ASCII/Scan Code from FIFO |
| `+$1` | `KBD_STAT` | **R/W** | Mode selection (0: ASCII, 1: Raw) & Read LED states |
| `+$2` | `KBD_CTRL` | **R** | `DATA_READY`, FIFO overflow, and modifier states (Shift/Ctrl/Alt) |
| `+$3` | `MOUSE_DX` | **R** | Relative $\Delta X$ or absolute position |
| `+$4` | `MOUSE_DY` | **R** | Relative $\Delta Y$ or absolute position |
| `+$5` | `MOUSE_STATE` | **R** | Button states (L/R/M) & 3-bit scroll wheel delta |
| `+$6`–`+$B` | `RTC_*` | **R/W** | Time/Date in BCD format (Sec, Min, Hour, Day, Month, Year) |
| `+$C` | `NVRAM_ADDR` | **R/W** | EEPROM byte address pointer (0–255) |
| `+$D` | `NVRAM_DATA` | **R/W** | Read/Write EEPROM cell (auto-increments if enabled) |
| `+$E` | `RND_DATA` | **R** | Read: 8-bit random byte  |
| `+$F` | `SYS_CTRL_STAT` | **R/W** | Read: IRQ status & device detection / Write: IRQ masks |

`SYS_CTRL_STAT` read bits: bit 0 keyboard FIFO non-empty, bits 5/6 keyboard/mouse
detection, bit 7 an enabled IRQ source is active. Write bits 0/1/2 enable
keyboard/mouse/RTC IRQ sources; bit 7 enables the physical `/IRQ` output.
Keyboard IRQ remains asserted while the FIFO is non-empty and clears after its
last byte is read. For keyboard IRQ, write `$81` to enable the keyboard source
and global output.

---

## Registers Summary

### Keyboard (`+$0` .. `+$2`)
* Supports **Mazovia Polish characters** via `AltGr` combinations in Smart ASCII mode.
* Functional keys (`F1`–`F12`) mapped to `0xEA`–`0xF5`, navigation arrows to `0xE0`–`0xE9`.
* Lock keys (Caps, Num, Scroll) automatically manage hardware LEDs.

---

## Quick Start for keyboard (6502 Assembly)

```assembly
; --- Poll and Read Key ---
GET_CHAR:
    LDA KBD_DATA        ; Read character from FIFO buffer, will return $00 if buffer is empty
    RTS
```
