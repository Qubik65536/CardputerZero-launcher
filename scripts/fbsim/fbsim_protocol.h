/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

/*
 * Host side of the fbsim contract, shared by scripts/fbsim/fbsim.c and the
 * CardputerZero-Emulator. Header-only, usable from C and C++.
 *
 * The host owns a session directory holding
 *   fb     W*H RGB565 little-endian pixels, stride W*2   -> CARDPUTER_FB
 *   input  FIFO of 24-byte Linux `struct input_event`    -> CARDPUTER_INPUT
 * and tells the app the size through CARDPUTER_FB_SIZE ("WxH").
 */

#pragma once

#if defined(__has_include)
#if __has_include(<SDL.h>)
#include <SDL.h>
#else
#include <SDL2/SDL.h>
#endif
#else
#include <SDL.h>
#endif

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

enum {
    FBSIM_EV_SYN = 0x00,
    FBSIM_EV_KEY = 0x01,
    FBSIM_SYN_REPORT = 0,
    FBSIM_INPUT_EVENT_SIZE = 24, /* struct input_event on 64-bit Linux */
    FBSIM_KEY_LEFTSHIFT = 42,
    FBSIM_KEY_LEFTCTRL = 29,
    FBSIM_KEY_LEFTALT = 56,
    FBSIM_KEY_ESC = 1,
    FBSIM_KEY_FN = 0x1d0,
};

struct fbsim_session {
    int width;
    int height;
    size_t size; /* bytes in the framebuffer file */
    int fb_fd;
    int input_fd; /* opened O_RDWR | O_NONBLOCK, so writes never block */
    char dir[64];
    char fb_path[128];
    char input_path[128];
    char env_fb[160];    /* "CARDPUTER_FB=..." */
    char env_input[160]; /* "CARDPUTER_INPUT=..." */
    char env_size[48];   /* "CARDPUTER_FB_SIZE=WxH" */
};

/* SDL keycode -> Linux input-event-codes.h KEY_* value (0 = not forwarded). */
static inline uint16_t fbsim_linux_key_code(SDL_Keycode key)
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

static inline void fbsim_put_u16(unsigned char *out, uint16_t value)
{
    out[0] = (unsigned char)(value & 0xff);
    out[1] = (unsigned char)(value >> 8);
}

static inline void fbsim_put_u64(unsigned char *out, uint64_t value)
{
    for (int i = 0; i < 8; ++i) out[i] = (unsigned char)(value >> (8 * i));
}

static inline void fbsim_write_input_event(int fd, uint16_t type, uint16_t code, int32_t value)
{
    unsigned char record[FBSIM_INPUT_EVENT_SIZE] = {0};
    struct timeval now;
    gettimeofday(&now, NULL);
    fbsim_put_u64(record, (uint64_t)now.tv_sec);
    fbsim_put_u64(record + 8, (uint64_t)now.tv_usec);
    fbsim_put_u16(record + 16, type);
    fbsim_put_u16(record + 18, code);
    fbsim_put_u16(record + 20, (uint16_t)((uint32_t)value & 0xffff));
    fbsim_put_u16(record + 22, (uint16_t)((uint32_t)value >> 16));
    /* A slow reader only fills the pipe buffer; drop events rather than block. */
    if (write(fd, record, sizeof(record)) < 0 && errno != EAGAIN)
        perror("fbsim: write input event");
}

/* value: 0 released, 1 pressed, 2 auto-repeat. */
static inline void fbsim_send_key(const struct fbsim_session *session, uint16_t code,
                                  int32_t value)
{
    if (code == 0) return;
    fbsim_write_input_event(session->input_fd, FBSIM_EV_KEY, code, value);
    fbsim_write_input_event(session->input_fd, FBSIM_EV_SYN, FBSIM_SYN_REPORT, 0);
}

/* Discards events nobody read (for example, left over from an app that exited). */
static inline void fbsim_drain_input(const struct fbsim_session *session)
{
    unsigned char scratch[FBSIM_INPUT_EVENT_SIZE * 32];
    while (read(session->input_fd, scratch, sizeof(scratch)) > 0) {
    }
}

static inline void fbsim_session_close(struct fbsim_session *session)
{
    if (session->fb_fd >= 0) close(session->fb_fd);
    if (session->input_fd >= 0) close(session->input_fd);
    session->fb_fd = session->input_fd = -1;
    if (session->fb_path[0]) unlink(session->fb_path);
    if (session->input_path[0]) unlink(session->input_path);
    if (session->dir[0]) rmdir(session->dir);
    session->fb_path[0] = session->input_path[0] = session->dir[0] = '\0';
}

/* Creates the session files; returns 0 on success. */
static inline int fbsim_session_open(struct fbsim_session *session, int width, int height)
{
    memset(session, 0, sizeof(*session));
    session->fb_fd = session->input_fd = -1;
    session->width = width;
    session->height = height;
    session->size = (size_t)width * (size_t)height * 2;

    snprintf(session->dir, sizeof(session->dir), "/tmp/fbsim.XXXXXX");
    if (!mkdtemp(session->dir)) {
        perror("fbsim: mkdtemp");
        session->dir[0] = '\0';
        return -1;
    }
    snprintf(session->fb_path, sizeof(session->fb_path), "%s/fb", session->dir);
    snprintf(session->input_path, sizeof(session->input_path), "%s/input", session->dir);

    session->fb_fd = open(session->fb_path, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (session->fb_fd < 0 || ftruncate(session->fb_fd, (off_t)session->size) != 0) {
        perror("fbsim: framebuffer file");
        fbsim_session_close(session);
        return -1;
    }
    if (mkfifo(session->input_path, 0600) != 0) {
        perror("fbsim: mkfifo");
        fbsim_session_close(session);
        return -1;
    }
    /* O_RDWR keeps the FIFO open without a reader, so the app may (re)open it. */
    session->input_fd = open(session->input_path, O_RDWR | O_NONBLOCK);
    if (session->input_fd < 0) {
        perror("fbsim: open fifo");
        fbsim_session_close(session);
        return -1;
    }

    snprintf(session->env_fb, sizeof(session->env_fb), "CARDPUTER_FB=%s", session->fb_path);
    snprintf(session->env_input, sizeof(session->env_input), "CARDPUTER_INPUT=%s",
             session->input_path);
    snprintf(session->env_size, sizeof(session->env_size), "CARDPUTER_FB_SIZE=%dx%d", width,
             height);
    return 0;
}

/* For a freshly forked child (single-threaded parent only: setenv allocates). */
static inline void fbsim_session_export(const struct fbsim_session *session)
{
    char size[32];
    snprintf(size, sizeof(size), "%dx%d", session->width, session->height);
    setenv("CARDPUTER_FB", session->fb_path, 1);
    setenv("CARDPUTER_FB_SIZE", size, 1);
    setenv("CARDPUTER_INPUT", session->input_path, 1);
}

/* Copies the current frame into `pixels` (session->size bytes); 0 on success. */
static inline int fbsim_read_frame(const struct fbsim_session *session, void *pixels)
{
    return pread(session->fb_fd, pixels, session->size, 0) == (ssize_t)session->size ? 0 : -1;
}

/* Replaces the frame, e.g. to hand the previous screen contents to a new app. */
static inline void fbsim_write_frame(const struct fbsim_session *session, const void *pixels)
{
    if (pwrite(session->fb_fd, pixels, session->size, 0) != (ssize_t)session->size)
        perror("fbsim: write framebuffer");
}
