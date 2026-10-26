// C program to implement an interactive
// snake game
#include <conio.h>
#include <ctype.h>
#include <stdlib.h>
#include <lexx.h>

// Macros variable (HEIGHT, WIDTH)
#define HEIGHT 26
#define WIDTH 78

// Array to store the coordinates of snake
// tail (x-axis, y-axis)
int snakeTailX[100], snakeTailY[100];

// Variable to store the length of the
// snake's tail
int snakeTailLen;

// Score and signal flags
int gameover, key, score;

// Coordinates of snake's head and fruit
int x, y, fruitx, fruity;

int prevX, prevY;

// Function to generate the fruit
// within the boundary
void setup() {
    key = 0;
    snakeTailLen = 0;
    // Flag to signal the gameover
    gameover = 0;

    // Initial coordinates of the snake
    x = WIDTH / 2;
    y = HEIGHT / 2;
    
    // Initial coordinates of the fruit
    fruitx = rand() % WIDTH;
    fruity = rand() % HEIGHT;
    while (fruitx == 0) {
        fruitx = rand() % WIDTH;
    }

    while (fruity == 0) {
        fruity = rand() % HEIGHT;
    }

    // Score initialzed
    score = 0;
}

void default_colors() {
    simple_printf("\x1B[100;37m");
}

void print_score() {
    default_colors();
    simple_printf("\x1B[%d;9H%d    ", HEIGHT+3, score);
}

void print_food() {
    char fruit_color;
    fruit_color = rand() % 16;
    // Creating the sanke's food with '*'
    while (fruit_color == 0 || fruit_color == 5) {
        fruit_color = rand() % 16;
    }    
    if (fruitx>0 && fruity>0)
        //simple_printf("\x1B[%d;%dH\x1B[31m\03", fruity+2,fruitx+2);
        fcolor(fruit_color);
        simple_printf("\x1B[%d;%dH\03", fruity+2,fruitx+2);
}

// Function do draw the game field, to be executed just once
void draw_game_field() {
    int i;
    print_str("\x1B[?25l"); // Hide cursor
    print_str("\x1B[2J"); // ANSI escape codes to clear screen
    print_str("\x1B[1;1H"); 

    // Creating top wall
    for (i = 0; i < WIDTH+2; i++)
        print_char(0xCD);
    
    for (i = 0; i < HEIGHT+2; i++) {
        simple_printf("\x1B[%d;%dH\xBA",i,1);
        simple_printf("\x1B[%d;%dH\xBA",i,WIDTH+2);
    }

    simple_printf("\x1B[%d;1H", HEIGHT+2); 
    
    // Creating bottom walls
    for (i = 0; i < WIDTH+2; i++)
        print_char(0xCD);

    // now, drive corners
    simple_printf("\x1B[1;1H\xC9"); // Top-left
    simple_printf("\x1B[1;%dH\xBB", WIDTH+2); // Top-right
    simple_printf("\x1B[%d;1H\xC8", HEIGHT+2); // Bottom-left
    simple_printf("\x1B[%d;%dH\xBC", HEIGHT+2, WIDTH+2); // Bottom-right

    // Print the score and instructions
    //print_str("score = %d", score); TODO
    simple_printf("\x1B[%d;3HScore:",HEIGHT+3);
    simple_printf("\x1B[%d;50HPress W, A, S, D for movement.",HEIGHT+3);
    print_score();
    print_food();
}

void draw_snake() {
    // Creating snake's head
    simple_printf("\x1B[%d;%dH\x1B[32m\02", y+2,x+2);
    if (key != 0) {
        // create snake first section
        if (snakeTailLen>0) {
            simple_printf("\x1B[%d;%dH\xE5", snakeTailY[0]+2,snakeTailX[0]+2);
        } else {
            simple_printf("\x1B[%d;%dH ", snakeTailY[0]+2,snakeTailX[0]+2);
        }
        // erase last part of snake's tail
        simple_printf("\x1B[%d;%dH ", prevY+2,prevX+2);    
    }

}

void draw_game_over() {
    default_colors();
    print_str("\x1B[10;37HGame Over!");
    print_str("\x1B[12;30HYour final score is: ");
    print_number(score);
    //print_str("\x1B[28;1H");
    print_str("\x1B[14;32H'R'estart or 'Q'uit?");
}

// Function to take the real time input and
// set the 'flag' variable accordingly
void input() {
    //print_char(tolower(getch());
    //if (kbhit()) {
        switch (getch()) {
        case 'A':
            if(key!=2)
            key = 1;
            break;
        case 'D':
            if(key!=1)
            key = 2;
            break;
        case 'W':
            if(key!=4)
            key = 3;
            break;
        case 'S':
            if(key!=3)
            key = 4;
            break;
        }
    //}
}


// Function for the movement logic that
// checks eat, move, collisions
void logic() {
    int i, prev2X, prev2Y;

    // Updating the coordinates for continous
    // movement of snake
    prevX = snakeTailX[0];
    prevY = snakeTailY[0];
    snakeTailX[0] = x;
    snakeTailY[0] = y;
    for (i = 1; i < snakeTailLen; i++) {
        prev2X = snakeTailX[i];
        prev2Y = snakeTailY[i];
        snakeTailX[i] = prevX;
        snakeTailY[i] = prevY;
        prevX = prev2X;
        prevY = prev2Y;
    }
    
    // Changing the direction of movement of snake
    switch (key) {
    case 1:
        x--;
        break;
    case 2:
        x++;
        break;
    case 3:
        y--;
        break;
    case 4:
        y++;
        break;
    default:
        break;
    }

    // If the game is over
    if (x < 0 || x >= WIDTH || y < 0 || y >= HEIGHT)
        gameover = 1;
        
    // Checks for collision with the tail (o)
    for (i = 0; i < snakeTailLen; i++) {
        if (snakeTailX[i] == x && snakeTailY[i] == y)
            gameover = 1;
    }

    // If snake reaches the fruit
    // then update the score
    if (x == fruitx && y == fruity) {
        fruitx = rand() % WIDTH;
        fruity = rand() % HEIGHT;
        while (fruitx == 0)
            fruitx = rand() % WIDTH;

        // Generation of new fruit
        while (fruity == 0)
            fruity = rand() % HEIGHT;
        
        score += 10;
        print_score();
        print_food();
        bell();
        snakeTailLen++;
    }
}

void main() {
    int delay,exit;
    // Initial set up that initialize the
    // required variables
    exit = 0;
    while (exit != 1) {
        setup();
        default_colors();
        draw_game_field();

        // Game loop starts here
        while (!gameover) {

            // Functions that will be called
            // repeatedly after the given interval
            draw_snake();
            input();
            logic();
            //sleep(33);
            for (delay = 1; delay < 6000; delay++) { 

            }
        }
        draw_snake(); // draw final state
        draw_game_over();
        while (key != 5) {
            switch (getch()) {
                case 'R':
                    key = 5;
                    break;
                case 'Q':
                    exit = 1;
                    key = 5;
                    break;
            }
        }
    }
    print_str("\x1B[0m\x1B[2J\x1B[1;1H"); // ANSI escape codes to clear screen and reset colors
    print_str("\x1B[?25h"); // Show cursor
}

