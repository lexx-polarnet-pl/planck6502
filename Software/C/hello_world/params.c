#include <stdio.h>
#include <stdarg.h>
#include <lexx.h>

int main(int argc, char *argv[]) {
    int i;

    printf("--- LexxDOS Arg Test ---\r\n");
    printf("Number of arguments (argc): %d\r\n\r\n", argc);

    // Display argv[0]
    if (argv[0][0] == '\0') {
        printf("argv[0] = \"\" (no program name)\r\n");
    } else {
        printf("argv[0] = %s\r\n", argv[0]);
    }

    // Display remaining arguments
    if (argc > 1) {
        printf("\r\nPassed parameters:\r\n");
        for (i = 1; i < argc; ++i) {
            printf("argv[%d] = %s\r\n", i, argv[i]);
        }
    } else {
        printf("\r\nNo additional parameters.\r\n");
    }

    return 0;
}