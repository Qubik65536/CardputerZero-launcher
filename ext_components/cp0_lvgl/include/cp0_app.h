/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

/*
 * cp0_app: a plain C entry point to cp0_lvgl, for apps written in C or in any
 * language that can call C (Rust, Zig, OCaml, ...).
 *
 * cp0_app_run() does what C++ apps get from cp0_lvgl_run_app<Page>(): it sets up
 * LVGL, the display (SDL window, fbsim framebuffer or the device panel), the
 * keyboard and the platform services, shows a standard page (the 20 px top bar
 * with title, clock, Wi-Fi and battery above a 320x150 content area) and runs
 * the event loop until cp0_app_quit(). Everything else is ordinary LVGL:
 * create widgets on cp0_app_content() with the lv_* functions.
 *
 * All functions must be called on the LVGL thread: from the setup callback,
 * the key callback, LVGL event callbacks or lv_timer callbacks.
 */

#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct _lv_obj_t lv_obj_t;

/* Key states, as in keyboard_input.h. */
#define CP0_APP_KEY_RELEASED 0
#define CP0_APP_KEY_PRESSED 1
#define CP0_APP_KEY_REPEATED 2

/* Modifier bits in cp0_app_key_t.mods, as KBD_MOD_* in keyboard_input.h. */
#define CP0_APP_MOD_SHIFT (1u << 0)
#define CP0_APP_MOD_CTRL (1u << 1)
#define CP0_APP_MOD_ALT (1u << 2)

/* One key event. Pointers are valid only during the callback. */
typedef struct {
    uint32_t code;    /* Linux key code (KEY_ESC = 1, KEY_ENTER = 28, KEY_F = 33, ...) */
    int state;        /* CP0_APP_KEY_RELEASED / _PRESSED / _REPEATED */
    uint32_t mods;    /* CP0_APP_MOD_* bits */
    const char *text; /* UTF-8 text the key types, with Shift and the symbol layer applied; "" if none */
} cp0_app_key_t;

/* Called once, after the page exists: build the UI on `content` (320x150). */
typedef void (*cp0_app_setup_fn)(lv_obj_t *content, void *user_data);
/* Called for every key event while the app runs (releases included). */
typedef void (*cp0_app_key_fn)(const cp0_app_key_t *key, void *user_data);

/* Run the app; returns the process exit status (0 after cp0_app_quit()).
 * `on_key` may be NULL. */
int cp0_app_run(const char *title, cp0_app_setup_fn setup, cp0_app_key_fn on_key, void *user_data);

/* Leave the event loop; cp0_app_run() returns soon after. */
void cp0_app_quit(void);

/* The top bar's title. */
void cp0_app_set_title(const char *title);

/* The 320x150 content area below the top bar, and the whole screen. */
lv_obj_t *cp0_app_content(void);
lv_obj_t *cp0_app_screen(void);

/* Nonzero: keys type text (F/X/Z/C are letters). Zero (the default): F/X/Z/C
 * also act as up/down/left/right, like the launcher. */
void cp0_app_set_text_input(int enabled);

/* Nonzero: keys reach only the key callback, not LVGL's focused widget. Use it
 * when the app moves focus and changes widgets itself. */
void cp0_app_set_keypad_intercept(int enabled);

/* Path of a resource file installed with the app (APPLaunch/share/images/<name>
 * and friends) that LVGL can open, e.g. for lv_image_set_src(), on the simulator
 * and the device alike. Writes at most `size` bytes including the terminating
 * NUL; returns the full length. */
size_t cp0_app_file_path(const char *name, char *out, size_t size);

#ifdef __cplusplus
}
#endif
