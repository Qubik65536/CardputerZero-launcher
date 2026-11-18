/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

/*
 * Pure translation of fbsim evdev key events into cp0_lvgl key items, used by
 * the SDL backend's fbsim mode (sdl_fbsim.c). Header-only and free of LVGL so
 * tests/test_sdl_fbsim_keymap.c can exercise it directly.
 *
 * The desktop sends standard US-layout key codes, so text follows the US
 * layout (Shift selects the upper row), like the SDL window build.
 */

#pragma once

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "cp0_keyboard_navigation_contract.h"
#include "input_keys.h"
#include "keyboard_input.h"
#include "../cp0_keyboard_key_contract.h"

#ifdef __cplusplus
extern "C" {
#endif

enum { CP0_FBSIM_KEY_FN = 0x1d0 };

/* Returns the modifier bit a key code controls, or 0. */
static inline uint32_t cp0_fbsim_modifier_bit(uint16_t code)
{
    switch (code) {
    case KEY_LEFTSHIFT:
    case KEY_RIGHTSHIFT: return KBD_MOD_SHIFT;
    case KEY_LEFTCTRL:
    case KEY_RIGHTCTRL: return KBD_MOD_CTRL;
    case KEY_LEFTALT:
    case KEY_RIGHTALT: return KBD_MOD_ALT;
    case KEY_LEFTMETA:
    case KEY_RIGHTMETA: return KBD_MOD_LOGO;
    case CP0_FBSIM_KEY_FN: return KBD_MOD_FN;
    default: return 0;
    }
}

/* The character a key produces on a US layout, or 0. Codes 0..57. */
static inline char cp0_fbsim_us_char(uint16_t code, int shifted)
{
    static const char plain[] =
        "\0\0" "1234567890-=" "\0\0" "qwertyuiop[]" "\0\0" "asdfghjkl;'`" "\0\\"
        "zxcvbnm,./" "\0\0\0 ";
    static const char shift[] =
        "\0\0" "!@#$%^&*()_+" "\0\0" "QWERTYUIOP{}" "\0\0" "ASDFGHJKL:\"~" "\0|"
        "ZXCVBNM<>?" "\0\0\0 ";
    if (code >= sizeof(plain) - 1) return 0;
    return shifted ? shift[code] : plain[code];
}

/*
 * Applies one EV_KEY event. `mods` carries the modifier state between calls.
 * Returns 1 and fills `out` when the event should reach the app; modifier
 * keys only update `mods` and return 0.
 */
static inline int cp0_fbsim_translate_key(uint16_t code, int32_t value, uint32_t *mods,
                                          cp0_keyboard_input_context_t context,
                                          struct key_item *out)
{
    const uint32_t modifier = cp0_fbsim_modifier_bit(code);
    if (modifier != 0) {
        if (value == 0) *mods &= ~modifier;
        else *mods |= modifier;
        return 0;
    }
    if (code == 0 || value < 0 || value > 2) return 0;

    memset(out, 0, sizeof(*out));
    out->key_code = code;
    out->key_state = value;
    out->mods = *mods;
    out->input_context = context;
    out->semantic_key = cp0_keyboard_semantic_key(code, context);
    snprintf(out->sym_name, sizeof(out->sym_name), "FBSIM_%u", (unsigned)code);

    const char *control = cp0_keyboard_control_utf8(code);
    if (control != NULL) {
        snprintf(out->utf8, sizeof(out->utf8), "%s", control);
    } else {
        char ch = cp0_fbsim_us_char(code, (*mods & KBD_MOD_SHIFT) != 0);
        if (ch != 0 && (*mods & KBD_MOD_CTRL) && ((ch | 0x20) >= 'a' && (ch | 0x20) <= 'z'))
            ch = (char)((ch | 0x20) - 'a' + 1); /* Ctrl+letter -> control character */
        if (ch != 0) out->utf8[0] = ch;
    }
    out->codepoint = (uint8_t)out->utf8[0];
    return 1;
}

#ifdef __cplusplus
}
#endif
