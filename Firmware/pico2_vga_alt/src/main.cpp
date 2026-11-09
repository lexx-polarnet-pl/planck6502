#include <string.h>
#include "pico/stdlib.h"
#include "picovga.h"
#include "textmode.cpp"

// Przykładowy duszek 8x8 px w kolorze czerwonym z przezroczystym środkiem/tłem (0 = przezroczysty)
u8 SpriteImg[64] __attribute__((aligned(4))) = {
    0, 0, 224, 224, 224, 224, 0, 0,
    0, 224, 224, 224, 224, 224, 224, 0,
    224, 224, 0, 0, 0, 0, 224, 224,
    224, 224, 0, 0, 0, 0, 224, 224,
    224, 224, 0, 0, 0, 0, 224, 224,
    224, 224, 0, 0, 0, 0, 224, 224,
    0, 224, 224, 224, 224, 224, 224, 0,
    0, 0, 224, 224, 224, 224, 0, 0,
};


u8 SpriteX0[8];
u8 SpriteW0[8];

sSprite MySprite = {
    .img = SpriteImg,       // Wskaźnik do pikseli
    .x0 = SpriteX0,         // Początek widocznego fragmentu każdego wiersza
    .w0 = SpriteW0,         // Długość widocznego fragmentu każdego wiersza
    .keycol = 0,            // Czarny kolor jest przezroczysty w trybie SPRITEBLACK
    .x = -10,               // Pozycja X na ekranie (w pikselach)
    .y = -10,                // Pozycja Y na ekranie (w pikselach)
    .w = 8,                 // Szerokość w pikselach
    .h = 8,                 // Wysokość w pikselach
    .wb = 8                 // Krok w bajtach (stride, zazwyczaj równy szerokości)
};

sSprite* SpriteList[1] = { &MySprite };

uint64_t last_sprite_update = time_us_64();
const uint64_t sprite_interval_us = 16666; // OK. 60 FPS (16 666 mikrosekund = 16.6 ms)
#include "6502bus.cpp"

int main()
{
	setup6502bus();
    SpritePrepLines(SpriteImg, SpriteX0, SpriteW0, 8, 8, 8, 0, False);
    terminal_setup_text_mode(SpriteList, 1);

    while (1)
    {
        terminal_process_queue();
        // Sprawdzamy, czy upłynął wyznaczony czas dla ruchu duszka
        /*uint64_t now = time_us_64();
        if (now - last_sprite_update >= sprite_interval_us)
        {
            last_sprite_update = now;

            MySprite.x += 1;
            if (MySprite.x >= 640) MySprite.x = 0;
            
            MySprite.y += 1;
            if (MySprite.y >= 480) MySprite.y = 0;
        }*/
    }
}
