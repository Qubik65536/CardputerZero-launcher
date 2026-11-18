/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

/*
 * fbsim mode of the SDL backend.
 *
 * When CARDPUTER_FB is set (by scripts/fbsim/fbsim, scripts/fbsim/headless.py
 * or `cardputer-zero-emu --fb` / the emulator's launcher), the desktop build
 * renders into that RGB565 framebuffer file instead of opening an SDL window,
 * and reads keys from the evdev FIFO in CARDPUTER_INPUT. The same binary still
 * opens a normal window when the variables are absent.
 */

#pragma once

#include "lvgl/lvgl.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Non-zero when CARDPUTER_FB names a framebuffer file. */
int cp0_fbsim_active(void);

/* Maps CARDPUTER_FB and creates the default LVGL display on it; NULL on error. */
lv_display_t *cp0_fbsim_display_create(void);

/* Reads pending CARDPUTER_INPUT events into the cp0 keyboard queue (LVGL thread).
 * Returns the number of key items queued. */
int cp0_fbsim_input_poll(void);

#ifdef __cplusplus
}
#endif
