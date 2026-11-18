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

#include "fbsim_protocol.h"

#include <signal.h>
#include <sys/wait.h>

struct options {
    int width;
    int height;
    int scale;
    char **command;
};

static void forward_key(const struct fbsim_session *session, const SDL_KeyboardEvent *key)
{
    int32_t value = key->type == SDL_KEYUP ? 0 : (key->repeat ? 2 : 1);
    fbsim_send_key(session, fbsim_linux_key_code(key->keysym.sym), value);
}

static pid_t spawn_app(char **command, const struct fbsim_session *session)
{
    pid_t pid = fork();
    if (pid == 0) {
        fbsim_session_export(session);
        execvp(command[0], command);
        perror("fbsim: exec");
        _exit(127);
    }
    if (pid < 0) perror("fbsim: fork");
    return pid;
}

/* Read the framebuffer file and copy it into the RGB565 streaming texture. */
static void present_frame(const struct fbsim_session *session, SDL_Renderer *renderer,
                          SDL_Texture *texture, unsigned char *pixels)
{
    if (fbsim_read_frame(session, pixels) != 0) return;
    SDL_UpdateTexture(texture, NULL, pixels, session->width * 2);
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
    struct fbsim_session session;
    if (fbsim_session_open(&session, options->width, options->height) != 0) return 1;
    unsigned char *pixels = malloc(session.size);
    if (!pixels) return 1;

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

    pid_t app = spawn_app(options->command, &session);
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
                forward_key(&session, &event.key);
            }
        }
        if (running && waitpid(app, &status, WNOHANG) == app) running = 0;
        present_frame(&session, renderer, texture, pixels);
        SDL_Delay(16);
    }

    SDL_DestroyTexture(texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    free(pixels);
    fbsim_session_close(&session);
    return app_exit_status(status);
}

int main(int argc, char **argv)
{
    struct options options;
    if (parse_options(argc, argv, &options) != 0) return 2;
    return run(&options);
}
