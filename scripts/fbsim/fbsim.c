/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

/*
 * fbsim - desktop stand-in for the CardputerZero framebuffer and keyboard.
 *
 * Apps that draw straight to the Linux framebuffer and read the evdev keyboard
 * (the Rust / Zig / OCaml templates) run unchanged on a desktop with fbsim:
 *
 *   fbsim [--scale N] [--width W --height H] -- ./my-app [args...]
 *
 * fbsim creates
 *   - a framebuffer file (W*H RGB565 little-endian, stride W*2), exported to
 *     the app as CARDPUTER_FB, and
 *   - a FIFO carrying Linux `struct input_event` records (64-bit layout,
 *     24 bytes), exported as CARDPUTER_INPUT,
 * starts the app, shows the framebuffer in a window and turns key presses into
 * EV_KEY/EV_SYN events with Linux KEY_* codes. Closing the window sends SIGTERM
 * to the app; fbsim exits with the app's exit status.
 *
 * Build: cc -O2 fbsim.c $(pkg-config --cflags --libs sdl2) -o fbsim
 *        (scripts/fbsim/build.sh does this)
 */

#include <SDL.h>

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

enum {
    EV_SYN = 0x00,
    EV_KEY = 0x01,
    SYN_REPORT = 0,
    INPUT_EVENT_SIZE = 24, /* struct input_event on 64-bit Linux */
};

struct options {
    int width;
    int height;
    int scale;
    char **command;
};

/* SDL keycode -> Linux input-event-codes.h KEY_* value (0 = not forwarded). */
static uint16_t linux_key_code(SDL_Keycode key)
{
    if (key >= SDLK_a && key <= SDLK_z) {
        static const uint16_t letters[26] = {
            30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50, /* a..m */
            49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44, /* n..z */
        };
        return letters[key - SDLK_a];
    }
    if (key >= SDLK_1 && key <= SDLK_9) return (uint16_t)(2 + (key - SDLK_1));
    switch (key) {
    case SDLK_0: return 11;
    case SDLK_ESCAPE: return 1;
    case SDLK_MINUS: return 12;
    case SDLK_EQUALS: return 13;
    case SDLK_BACKSPACE: return 14;
    case SDLK_TAB: return 15;
    case SDLK_LEFTBRACKET: return 26;
    case SDLK_RIGHTBRACKET: return 27;
    case SDLK_RETURN: return 28;
    case SDLK_LCTRL: return 29;
    case SDLK_SEMICOLON: return 39;
    case SDLK_QUOTE: return 40;
    case SDLK_BACKQUOTE: return 41;
    case SDLK_LSHIFT: return 42;
    case SDLK_BACKSLASH: return 43;
    case SDLK_COMMA: return 51;
    case SDLK_PERIOD: return 52;
    case SDLK_SLASH: return 53;
    case SDLK_RSHIFT: return 54;
    case SDLK_LALT: return 56;
    case SDLK_SPACE: return 57;
    case SDLK_F1: return 59;
    case SDLK_F2: return 60;
    case SDLK_F3: return 61;
    case SDLK_F4: return 62;
    case SDLK_F5: return 63;
    case SDLK_F6: return 64;
    case SDLK_F7: return 65;
    case SDLK_F8: return 66;
    case SDLK_F9: return 67;
    case SDLK_F10: return 68;
    case SDLK_RCTRL: return 97;
    case SDLK_RALT: return 100;
    case SDLK_HOME: return 102;
    case SDLK_UP: return 103;
    case SDLK_PAGEUP: return 104;
    case SDLK_LEFT: return 105;
    case SDLK_RIGHT: return 106;
    case SDLK_END: return 107;
    case SDLK_DOWN: return 108;
    case SDLK_PAGEDOWN: return 109;
    case SDLK_DELETE: return 111;
    default: return 0;
    }
}

static void put_u16(unsigned char *out, uint16_t value)
{
    out[0] = (unsigned char)(value & 0xff);
    out[1] = (unsigned char)(value >> 8);
}

static void put_u64(unsigned char *out, uint64_t value)
{
    for (int i = 0; i < 8; ++i) out[i] = (unsigned char)(value >> (8 * i));
}

static void write_input_event(int fd, uint16_t type, uint16_t code, int32_t value)
{
    unsigned char record[INPUT_EVENT_SIZE] = {0};
    struct timeval now;
    gettimeofday(&now, NULL);
    put_u64(record, (uint64_t)now.tv_sec);
    put_u64(record + 8, (uint64_t)now.tv_usec);
    put_u16(record + 16, type);
    put_u16(record + 18, code);
    put_u16(record + 20, (uint16_t)((uint32_t)value & 0xffff));
    put_u16(record + 22, (uint16_t)((uint32_t)value >> 16));
    /* The FIFO is opened O_RDWR, so a slow reader only fills the pipe buffer. */
    if (write(fd, record, sizeof(record)) < 0 && errno != EAGAIN)
        perror("fbsim: write input event");
}

static void forward_key(int input_fd, const SDL_KeyboardEvent *key)
{
    uint16_t code = linux_key_code(key->keysym.sym);
    if (code == 0) return;
    int32_t value = key->type == SDL_KEYUP ? 0 : (key->repeat ? 2 : 1);
    write_input_event(input_fd, EV_KEY, code, value);
    write_input_event(input_fd, EV_SYN, SYN_REPORT, 0);
}

static int create_framebuffer_file(const char *path, size_t size)
{
    int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (fd < 0 || ftruncate(fd, (off_t)size) != 0) {
        perror("fbsim: framebuffer file");
        return -1;
    }
    return fd;
}

static int create_input_fifo(const char *path)
{
    unlink(path);
    if (mkfifo(path, 0600) != 0) {
        perror("fbsim: mkfifo");
        return -1;
    }
    /* O_RDWR keeps the FIFO open without a reader, so the app may (re)open it. */
    int fd = open(path, O_RDWR | O_NONBLOCK);
    if (fd < 0) perror("fbsim: open fifo");
    return fd;
}

static pid_t spawn_app(char **command, const char *fb_path, const char *input_path,
                       int width, int height)
{
    char size[32];
    snprintf(size, sizeof(size), "%dx%d", width, height);
    pid_t pid = fork();
    if (pid == 0) {
        setenv("CARDPUTER_FB", fb_path, 1);
        setenv("CARDPUTER_FB_SIZE", size, 1);
        setenv("CARDPUTER_INPUT", input_path, 1);
        execvp(command[0], command);
        perror("fbsim: exec");
        _exit(127);
    }
    if (pid < 0) perror("fbsim: fork");
    return pid;
}

/* Read the framebuffer file and copy it into the RGB565 streaming texture. */
static void present_frame(int fb_fd, SDL_Renderer *renderer, SDL_Texture *texture,
                          unsigned char *pixels, size_t size, int width)
{
    ssize_t got = pread(fb_fd, pixels, size, 0);
    if (got != (ssize_t)size) return;
    SDL_UpdateTexture(texture, NULL, pixels, width * 2);
    SDL_RenderClear(renderer);
    SDL_RenderCopy(renderer, texture, NULL, NULL);
    SDL_RenderPresent(renderer);
}

static int app_exit_status(int status)
{
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return 1;
}

static int parse_options(int argc, char **argv, struct options *options)
{
    options->width = 320;
    options->height = 170;
    options->scale = 2;
    options->command = NULL;
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--") == 0 && i + 1 < argc) {
            options->command = &argv[i + 1];
            return 0;
        }
        if (i + 1 < argc && strcmp(argv[i], "--scale") == 0) options->scale = atoi(argv[++i]);
        else if (i + 1 < argc && strcmp(argv[i], "--width") == 0) options->width = atoi(argv[++i]);
        else if (i + 1 < argc && strcmp(argv[i], "--height") == 0) options->height = atoi(argv[++i]);
        else break;
    }
    fprintf(stderr,
            "usage: fbsim [--scale N] [--width W --height H] -- <app> [args...]\n"
            "  Runs <app> with CARDPUTER_FB / CARDPUTER_INPUT pointing at a simulated\n"
            "  320x170 RGB565 framebuffer and an evdev-format keyboard FIFO.\n");
    return 1;
}

static int run(const struct options *options)
{
    char dir_template[] = "/tmp/fbsim.XXXXXX";
    char *dir = mkdtemp(dir_template);
    if (!dir) {
        perror("fbsim: mkdtemp");
        return 1;
    }
    char fb_path[256], input_path[256];
    snprintf(fb_path, sizeof(fb_path), "%s/fb", dir);
    snprintf(input_path, sizeof(input_path), "%s/input", dir);

    const size_t size = (size_t)options->width * (size_t)options->height * 2;
    int fb_fd = create_framebuffer_file(fb_path, size);
    int input_fd = create_input_fifo(input_path);
    unsigned char *pixels = malloc(size);
    if (fb_fd < 0 || input_fd < 0 || !pixels) return 1;

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "fbsim: SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    SDL_Window *window = SDL_CreateWindow("CardputerZero fbsim", SDL_WINDOWPOS_CENTERED,
                                          SDL_WINDOWPOS_CENTERED, options->width * options->scale,
                                          options->height * options->scale, 0);
    SDL_Renderer *renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_PRESENTVSYNC);
    SDL_Texture *texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGB565,
                                             SDL_TEXTUREACCESS_STREAMING, options->width,
                                             options->height);
    if (!window || !renderer || !texture) {
        fprintf(stderr, "fbsim: SDL setup failed: %s\n", SDL_GetError());
        return 1;
    }

    pid_t app = spawn_app(options->command, fb_path, input_path, options->width, options->height);
    if (app < 0) return 1;

    int status = 0;
    int running = 1;
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) {
                kill(app, SIGTERM);
                waitpid(app, &status, 0);
                running = 0;
            } else if (event.type == SDL_KEYDOWN || event.type == SDL_KEYUP) {
                forward_key(input_fd, &event.key);
            }
        }
        if (running && waitpid(app, &status, WNOHANG) == app) running = 0;
        present_frame(fb_fd, renderer, texture, pixels, size, options->width);
        SDL_Delay(16);
    }

    SDL_DestroyTexture(texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    free(pixels);
    close(fb_fd);
    close(input_fd);
    unlink(fb_path);
    unlink(input_path);
    rmdir(dir);
    return app_exit_status(status);
}

int main(int argc, char **argv)
{
    struct options options;
    if (parse_options(argc, argv, &options) != 0) return 2;
    return run(&options);
}
