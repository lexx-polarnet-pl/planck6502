# Planck/Lexx W65C02 BIOS

In this folder, you will find the complete BIOS for the Planck/Lexx W65C02 computer. It is an entirely separate build from the original Planck BIOS; therefore, you cannot expect any compatibility with original software written for the Planck.

The current version of the BIOS assumes that the system is equipped with the following cards in the specified slots:

```asm
GPU_PORT = PLANCK_SLOT_0
KEY_PORT = PLANCK_SLOT_1
SOUND_CARD_PORT = PLANCK_SLOT_2
CF_CARD_PORT = PLANCK_SLOT_3
MEM_CARD_PORT = PLANCK_SLOT_4
MEGA_CONSOLE_PORT = PLANCK_SLOT_5
```
However, the BIOS should run even if none of these cards are installed, by falling back to the serial console.

After flashing an EEPROM with this BIOS, the computer should perform a short self-test and welcome the user with a DOS prompt. From there, several commands are available: HELP, CD, TYPE, CLS, DIR, VER, MON, BASIC, SLOAD.

In addition to typical DOS commands, a few extra ones are provided:
* MON - Runs Wozmon (a memory monitor originally written by Steve Wozniak for Apple computers).
* BASIC - Runs the Microsoft BASIC interpreter.
* SLOAD - Allows loading programs via serial, enabling execution without a CF card.