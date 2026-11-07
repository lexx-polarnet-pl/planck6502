
#include "picovga.h"
#include <string.h>

// 512x400, font 8x16 = 64x25 characters
ALIGNED u8 Framebuffer[80 * 30 * 2];

// 256 characters x 8 pixels x 16 lines = 4096 bytes
ALIGNED u8 FontBuffer[4096];

int main()
{
    // Copy font from Flash to RAM
    memcpy(FontBuffer, FontBoldB8x16, sizeof(FontBuffer));

    // Initialize monochrome text mode
    Video(DEV_VGA, RES_VGA, FORM_TEXT16,
          Framebuffer, FontBuffer);
	//PrintSetup(Framebuffer, 80, 30, 4800);
		  

    // Print some text
    PrintSetPos(0, 0);
    PrintText("HELLO FROM PICOVGA!");

    PrintSetPos(0, 2);
    PrintText("COLOR TEST MODE");

    PrintSetPos(0, 4);
	PrintSetCol(PC_COLOR(PC_GREEN, PC_YELLOW));
    PrintText("640 x 480 PIXELS");

    PrintSetPos(0, 6);
    PrintText("80 COLUMNS x 30 ROWS");

    PrintSetPos(0, 10);
    PrintText("0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ");

    PrintSetPos(0, 12);
    PrintText("THE QUICK BROWN FOX");

    PrintSetPos(0, 14);
    PrintText("1234567890 !@#$%^&*()");

    while (1)
    {
        tight_loop_contents();
    }
}
