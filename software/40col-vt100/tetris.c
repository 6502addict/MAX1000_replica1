// VT100 Tetris for Apple-1 / MAX1000 Replica1
// Compile: cl65 -t apple1 -o tetris tetris.c
//
// Controls: A=left  D=right  W=rotate  S=drop  Q=quit
// Terminal: VT100 connected to the serial port
//
// NOTE: Apple-1 PIA sets bit 7 on received characters.
//       All input is masked with 0x7F.
//       Apple-1 sends uppercase only - controls are uppercase.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Apple-1 PIA (MC6820) direct register access
// $D010 = KBD    keyboard data    (bit 7 = 1 means key ready)
// $D011 = KBDCR  keyboard control (bit 7 = 1 means key strobe)
// $D012 = DSP    display data
#define KBD    (*(volatile unsigned char *)0xD010)
#define KBDCR  (*(volatile unsigned char *)0xD011)

// returns 1 if a key is waiting
static int kbhit(void) {
    return (KBDCR & 0x80) ? 1 : 0;
}

// waits for a key and returns it, bit 7 masked off
static char pia_getc(void) {
    while (!(KBDCR & 0x80));
    return (char)(KBD & 0x7F);
}

// key codes returned by get_key()
#define KEY_LEFT    'A'
#define KEY_RIGHT   'D'
#define KEY_ROTATE  'W'
#define KEY_DROP    'S'
#define KEY_QUIT    'Q'
#define KEY_NONE    0

// wait up to ~5000 loops for next byte of an escape sequence
static int wait_key(char *out) {
    unsigned int t = 5000U;
    while (t--) {
        if (KBDCR & 0x80) { *out = (char)(KBD & 0x7F); return 1; }
    }
    return 0;  // timeout
}

// reads one keypress, decodes VT100 cursor sequences
// ESC [ A = up    -> rotate
// ESC [ B = down  -> drop
// ESC [ C = right -> move right
// ESC [ D = left  -> move left
static char get_key(void) {
    char ch = pia_getc();
    if (ch == 0x1B) {
        char c2, c3;
        if (!wait_key(&c2)) return KEY_NONE;
        if (c2 != '[')      return KEY_NONE;
        if (!wait_key(&c3)) return KEY_NONE;
        switch (c3) {
            case 'A': return KEY_ROTATE;
            case 'B': return KEY_DROP;
            case 'C': return KEY_RIGHT;
            case 'D': return KEY_LEFT;
        }
        return KEY_NONE;
    }
    switch (ch) {
        case 'A': return KEY_LEFT;
        case 'D': return KEY_RIGHT;
        case 'W': return KEY_ROTATE;
        case 'S': return KEY_DROP;
        case 'Q': return KEY_QUIT;
    }
    return KEY_NONE;
}

// --- Timing ---
// Decrease FALL_BASE if pieces fall too slowly, increase if too fast.
// Calibrated for 10 MHz MX65 CPU.
#define FALL_BASE    20000U  // loop counts for level 0 drop interval (tuned for 15 MHz)
#define LOOP_DIVIDER 10U     // speed step per level

// --- Board dimensions ---
#define COLS     10
#define ROWS     20
#define SIDE_X   2
#define SIDE_Y   2

// --- VT100 macros ---
#define CLR()        printf("\033[2J\033[H")
#define MOVE(r,c)    printf("\033[%d;%dH", (r), (c))
#define BOLD()       printf("\033[1m")
#define RESET_ATTR() printf("\033[0m")
#define COLOR(n)     printf("\033[%dm", (n))

// --- Piece colors (ANSI fg) ---
static const int piece_color[7] = { 36, 33, 35, 32, 31, 34, 37 };

// --- Piece shapes [piece][rotation][4 cells {row,col}] ---
static const int pieces[7][4][4][2] = {
    // I
    {{{0,0},{0,1},{0,2},{0,3}}, {{0,2},{1,2},{2,2},{3,2}},
     {{2,0},{2,1},{2,2},{2,3}}, {{0,1},{1,1},{2,1},{3,1}}},
    // O
    {{{0,0},{0,1},{1,0},{1,1}}, {{0,0},{0,1},{1,0},{1,1}},
     {{0,0},{0,1},{1,0},{1,1}}, {{0,0},{0,1},{1,0},{1,1}}},
    // T
    {{{0,1},{1,0},{1,1},{1,2}}, {{0,1},{1,1},{2,1},{1,2}},
     {{1,0},{1,1},{1,2},{2,1}}, {{0,1},{1,0},{1,1},{2,1}}},
    // S
    {{{0,1},{0,2},{1,0},{1,1}}, {{0,1},{1,1},{1,2},{2,2}},
     {{0,1},{0,2},{1,0},{1,1}}, {{0,1},{1,1},{1,2},{2,2}}},
    // Z
    {{{0,0},{0,1},{1,1},{1,2}}, {{0,2},{1,1},{1,2},{2,1}},
     {{0,0},{0,1},{1,1},{1,2}}, {{0,2},{1,1},{1,2},{2,1}}},
    // L
    {{{0,2},{1,0},{1,1},{1,2}}, {{0,1},{1,1},{2,1},{2,2}},
     {{1,0},{1,1},{1,2},{2,0}}, {{0,0},{0,1},{1,1},{2,1}}},
    // J
    {{{0,0},{1,0},{1,1},{1,2}}, {{0,1},{0,2},{1,1},{2,1}},
     {{1,0},{1,1},{1,2},{2,2}}, {{0,1},{1,1},{2,0},{2,1}}}
};

// --- Game state ---
static int  board[ROWS][COLS];
static int  cur_piece, cur_rot, cur_r, cur_c;
static int  next_piece;
static int  score, lines, level;
static int  game_over;

// simple LCG random (no stdlib rand on Apple-1 target)
static unsigned int rng_state = 12345U;
static int rnd7(void) {
    rng_state = rng_state * 1664525U + 1013904223U;
    return (int)((rng_state >> 13) % 7);
}

// --- Drawing ---
static void draw_cell(int r, int c, int color) {
    MOVE(SIDE_Y + r, SIDE_X + c * 2);
    if (color) {
        COLOR(color);
        printf("[]");
    } else {
        RESET_ATTR();
        printf("  ");
    }
    RESET_ATTR();
}

static void draw_board_frame(void) {
    int r, c;
    BOLD();
    MOVE(SIDE_Y - 1, SIDE_X - 1);
    printf("+");
    for (c = 0; c < COLS; c++) printf("--");
    printf("+");
    for (r = 0; r < ROWS; r++) {
        MOVE(SIDE_Y + r, SIDE_X - 1);
        printf("|");
        MOVE(SIDE_Y + r, SIDE_X + COLS * 2);
        printf("|");
    }
    MOVE(SIDE_Y + ROWS, SIDE_X - 1);
    printf("+");
    for (c = 0; c < COLS; c++) printf("--");
    printf("+");
    RESET_ATTR();
}

static void draw_full_board(void) {
    int r, c;
    for (r = 0; r < ROWS; r++)
        for (c = 0; c < COLS; c++)
            draw_cell(r, c, board[r][c]);
}

static void draw_sidebar(void) {
    int r, i;
    MOVE(SIDE_Y,     SIDE_X + COLS * 2 + 3); printf("TETRIS");
    MOVE(SIDE_Y + 2, SIDE_X + COLS * 2 + 3); printf("SCORE");
    MOVE(SIDE_Y + 3, SIDE_X + COLS * 2 + 3); printf("%d     ", score);
    MOVE(SIDE_Y + 5, SIDE_X + COLS * 2 + 3); printf("LINES");
    MOVE(SIDE_Y + 6, SIDE_X + COLS * 2 + 3); printf("%d     ", lines);
    MOVE(SIDE_Y + 8, SIDE_X + COLS * 2 + 3); printf("LEVEL");
    MOVE(SIDE_Y + 9, SIDE_X + COLS * 2 + 3); printf("%d     ", level);
    MOVE(SIDE_Y +11, SIDE_X + COLS * 2 + 3); printf("NEXT");
    for (r = 0; r < 4; r++) {
        MOVE(SIDE_Y + 12 + r, SIDE_X + COLS * 2 + 3);
        printf("        ");
    }
    for (i = 0; i < 4; i++) {
        int pr = pieces[next_piece][0][i][0];
        int pc = pieces[next_piece][0][i][1];
        MOVE(SIDE_Y + 12 + pr, SIDE_X + COLS * 2 + 3 + pc * 2);
        COLOR(piece_color[next_piece]);
        printf("[]");
        RESET_ATTR();
    }
    MOVE(SIDE_Y +17, SIDE_X + COLS * 2 + 3); printf("KEYS");
    MOVE(SIDE_Y +18, SIDE_X + COLS * 2 + 3); printf("</>  MOVE");
    MOVE(SIDE_Y +19, SIDE_X + COLS * 2 + 3); printf("^    ROT");
    MOVE(SIDE_Y +20, SIDE_X + COLS * 2 + 3); printf("v    DROP");
    MOVE(SIDE_Y +21, SIDE_X + COLS * 2 + 3); printf("Q    QUIT");
}

// --- Piece helpers ---
static void piece_cells(int piece, int rot, int pr, int pc, int out[4][2]) {
    int i;
    for (i = 0; i < 4; i++) {
        out[i][0] = pr + pieces[piece][rot][i][0];
        out[i][1] = pc + pieces[piece][rot][i][1];
    }
}

static int piece_valid(int piece, int rot, int pr, int pc) {
    int cells[4][2], i;
    piece_cells(piece, rot, pr, pc, cells);
    for (i = 0; i < 4; i++) {
        int r = cells[i][0], c = cells[i][1];
        if (r < 0 || r >= ROWS || c < 0 || c >= COLS) return 0;
        if (board[r][c]) return 0;
    }
    return 1;
}

static void piece_draw(int piece, int rot, int pr, int pc, int erase) {
    int cells[4][2], i;
    piece_cells(piece, rot, pr, pc, cells);
    for (i = 0; i < 4; i++)
        draw_cell(cells[i][0], cells[i][1], erase ? 0 : piece_color[piece]);
}

static void piece_lock(void) {
    int cells[4][2], i;
    piece_cells(cur_piece, cur_rot, cur_r, cur_c, cells);
    for (i = 0; i < 4; i++)
        board[cells[i][0]][cells[i][1]] = piece_color[cur_piece];
}

// --- Line clear ---
static void clear_lines(void) {
    int r, c, cleared, dst;
    static const int pts[5] = {0, 100, 300, 500, 800};
    cleared = 0;
    for (r = ROWS - 1; r >= 0; r--) {
        int full = 1;
        for (c = 0; c < COLS; c++) if (!board[r][c]) { full = 0; break; }
        if (full) {
            for (dst = r; dst > 0; dst--)
                memcpy(board[dst], board[dst-1], sizeof(board[0]));
            memset(board[0], 0, sizeof(board[0]));
            cleared++;
            r++;
        }
    }
    if (cleared) {
        lines += cleared;
        score += pts[cleared] * (level + 1);
        level  = lines / 10;
        draw_full_board();
        draw_sidebar();
    }
}

static void spawn(void) {
    cur_piece = next_piece;
    next_piece = rnd7();
    cur_rot = 0;
    cur_r   = 0;
    cur_c   = COLS / 2 - 2;
    if (!piece_valid(cur_piece, cur_rot, cur_r, cur_c))
        game_over = 1;
}

// fall interval in loop counts, decreases with level
static unsigned int fall_count(void) {
    unsigned int f = FALL_BASE - (unsigned int)level * (FALL_BASE / LOOP_DIVIDER);
    return f < 500U ? 500U : f;   // minimum speed cap
}

// --- Main ---
int main(void) {
    unsigned int counter = 0;
    unsigned int fall_limit;

    // seed rng from a free-running read (approximate)
    rng_state = 42U;

    CLR();
    memset(board, 0, sizeof(board));
    score = lines = level = game_over = 0;
    next_piece = rnd7();

    draw_board_frame();
    spawn();
    draw_full_board();
    draw_sidebar();
    piece_draw(cur_piece, cur_rot, cur_r, cur_c, 0);

    fall_limit = fall_count();

    while (!game_over) {

        // non-blocking key check
        if (kbhit()) {
            char ch = get_key();
            piece_draw(cur_piece, cur_rot, cur_r, cur_c, 1);
            switch (ch) {
                case KEY_QUIT:  game_over = 1; break;
                case KEY_LEFT:
                    if (piece_valid(cur_piece, cur_rot, cur_r, cur_c - 1)) cur_c--;
                    break;
                case KEY_RIGHT:
                    if (piece_valid(cur_piece, cur_rot, cur_r, cur_c + 1)) cur_c++;
                    break;
                case KEY_ROTATE: {
                    int nr = (cur_rot + 1) % 4;
                    if (piece_valid(cur_piece, nr, cur_r, cur_c)) cur_rot = nr;
                    break;
                }
                case KEY_DROP:
                    while (piece_valid(cur_piece, cur_rot, cur_r + 1, cur_c)) cur_r++;
                    break;
            }
            piece_draw(cur_piece, cur_rot, cur_r, cur_c, 0);
        }

        // fall timer - simple counter
        counter++;
        if (counter >= fall_limit) {
            counter = 0;
            fall_limit = fall_count();
            piece_draw(cur_piece, cur_rot, cur_r, cur_c, 1);
            if (piece_valid(cur_piece, cur_rot, cur_r + 1, cur_c)) {
                cur_r++;
                piece_draw(cur_piece, cur_rot, cur_r, cur_c, 0);
            } else {
                piece_lock();
                draw_full_board();
                clear_lines();
                draw_sidebar();
                spawn();
                piece_draw(cur_piece, cur_rot, cur_r, cur_c, 0);
            }
        }
    }

    MOVE(SIDE_Y + ROWS / 2,     SIDE_X + 1);
    BOLD();
    printf("GAME OVER");
    RESET_ATTR();
    MOVE(SIDE_Y + ROWS / 2 + 1, SIDE_X + 1);
    printf("SCORE: %d", score);
    MOVE(SIDE_Y + ROWS + 2, 1);
    return 0;
}
