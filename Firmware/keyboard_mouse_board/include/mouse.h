#ifndef MOUSE_H
#define MOUSE_H

void mouse_init();
bool mouse_is_present();
void mouse_on_clock_falling();
void mouse_on_clock_rising();
void mouse_poll();

#endif
