#include <string.h>
#include "picovga.h"
#include "textmode.cpp"
#include "6502bus.cpp"



int main()
{
	setup6502bus();
    terminal_setup_text_mode();


/*
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
    PrintText("1234567890 !@#$%^&*()");*/

    while (1)
    {
        //tight_loop_contents();
		// print out terminal data
        //if (terminal_buffer_head != terminal_buffer_tail) {
        //    //char znak = terminal_buffer[terminal_buffer_tail];
        //    PrintChar(terminal_buffer[terminal_buffer_tail]);
        //    terminal_buffer_tail = (terminal_buffer_tail + 1) % TERMINAL_BUFFER_SIZE;
        // }		
        terminal_process_queue();
    }
}
