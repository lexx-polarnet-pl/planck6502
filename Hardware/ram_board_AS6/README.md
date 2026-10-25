## Planck 6502 RAM board

This is a banked RAM board for the Planck 6502 computer (AS6C4008-55PCN version).

The original project used the IS61C5128AL-10TLI, which was hard for me to obtain and was an SMD version. The AS6 is THT, so the soldering process should be much easier.

## Revision History

| Version | Date | Author | Status | Changes |
| :---: | :---: | :--- | :---: | :--- |
| **1.0** | 2026-07-04 | Lexx | Partially working | Forked from original banked RAM project, replacing IS6 with AS6 |

**This version doesn't work correctly.**

The address decoder in this version is used only for OE; therefore, the card works properly in READ mode. However, it is not used to control WE signals. As a result, if the CPU wants to write a value into a memory area that should be out of range for this card (e.g., $0080), the value will be stored both in main RAM (at $0080) and in banked RAM (at $8080).

How it should work:

When active, it gives access to a bank or RAM in the $8000-$BFFF address space.

To activate, store a byte with it's high bit set to the first register of the slot where it is placed.

For example 
lda #$80
sta $FFD0
will activate bank 0

There are 32 banks. You can choose which one is active by setting the first 5 bits of the data when storing to the first register. There is no way to get the currently active bank.

When the RAM card is active, it will respond to requests in the $8000 to $BFFF range instead of the ROM

lda #$8E
sta $FFD0
will activate the 14th bank

Setting the high bit to 0 will deactivate the banked RAM

For example the following code will deactivate the banked RAM and restore the ROM :

lda #0
sta $FFD0

<a rel="license" href="http://creativecommons.org/licenses/by-sa/4.0/"><img alt="Creative Commons License" style="border-width:0" src="https://i.creativecommons.org/l/by-sa/4.0/88x31.png" /></a><br />This documentation is licensed under a <a rel="license" href="http://creativecommons.org/licenses/by-sa/4.0/">Creative Commons Attribution-ShareAlike 4.0 International License</a>.