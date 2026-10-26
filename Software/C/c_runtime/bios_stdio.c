#include <unistd.h>

void __fastcall__ print_char(char c);

int __fastcall__ write(int fd, const void *buffer, unsigned count)
{
    const unsigned char *bytes = buffer;
    unsigned written;

    if (fd != STDOUT_FILENO && fd != STDERR_FILENO) {
        return -1;
    }

    for (written = 0; written < count; ++written) {
        print_char((char)bytes[written]);
    }

    return (int)written;
}
