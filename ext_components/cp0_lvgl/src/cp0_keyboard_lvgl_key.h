/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

/*
 * What the LVGL keypad input device reports for a cp0 key item, shared by the
 * device (cp0/cp0_keyboard_lvgl_input.c) and desktop (sdl/sdl_lvgl_keyboard.c)
 * backends. Header-only and free of LVGL so tests can include it.
 *
 * LVGL's keypad keys are characters plus a few control values (LV_KEY_UP = 17,
 * LV_KEY_ENTER = 10, ...). Navigation and editing keys map to those controls.
 * Keys that type something report the character, so lv_textarea and friends
 * edit text natively. Other keys pass their Linux code through (e.g.
 * KEY_PAGEUP for pages that page by it), except codes that LVGL would read as
 * a control key (KEY_W is 17 = LV_KEY_UP, KEY_9 is 10 = LV_KEY_ENTER, ...).
 */

#pragma once

#include "input_keys.h"
#include "keyboard_input.h"

#include <stdint.h>

/* LVGL's control keys (lv_group.h, lv_key_t); the backends check them against LVGL. */
enum {
    CP0_LV_KEY_UP = 17,
    CP0_LV_KEY_DOWN = 18,
    CP0_LV_KEY_RIGHT = 19,
    CP0_LV_KEY_LEFT = 20,
    CP0_LV_KEY_ESC = 27,
    CP0_LV_KEY_DEL = 127,
    CP0_LV_KEY_BACKSPACE = 8,
    CP0_LV_KEY_ENTER = 10,
    CP0_LV_KEY_NEXT = 9,
    CP0_LV_KEY_PREV = 11,
    CP0_LV_KEY_HOME = 2,
    CP0_LV_KEY_END = 3,
};

static inline int cp0_keyboard_is_lvgl_control_key(uint32_t key)
{
    switch (key) {
    case CP0_LV_KEY_UP:
    case CP0_LV_KEY_DOWN:
    case CP0_LV_KEY_RIGHT:
    case CP0_LV_KEY_LEFT:
    case CP0_LV_KEY_ESC:
    case CP0_LV_KEY_DEL:
    case CP0_LV_KEY_BACKSPACE:
    case CP0_LV_KEY_ENTER:
    case CP0_LV_KEY_NEXT:
    case CP0_LV_KEY_PREV:
    case CP0_LV_KEY_HOME:
    case CP0_LV_KEY_END:
        return 1;
    default:
        return 0;
    }
}

/* `semantic_key` is the item's semantic key (KEY_UP for F in navigation
 * context) or its key code; `codepoint` the character it types, 0 if none. */
static inline uint32_t cp0_keyboard_lvgl_key(uint32_t semantic_key, uint32_t codepoint)
{
    switch (semantic_key) {
    case KEY_UP: return CP0_LV_KEY_UP;
    case KEY_DOWN: return CP0_LV_KEY_DOWN;
    case KEY_RIGHT: return CP0_LV_KEY_RIGHT;
    case KEY_LEFT: return CP0_LV_KEY_LEFT;
    case KEY_ESC: return CP0_LV_KEY_ESC;
    case KEY_DELETE: return CP0_LV_KEY_DEL;
    case KEY_BACKSPACE: return CP0_LV_KEY_BACKSPACE;
    case KEY_ENTER:
    case KEY_KPENTER: return CP0_LV_KEY_ENTER;
    case KEY_NEXT: return CP0_LV_KEY_NEXT;
    case KEY_TAB: return KEY_TAB; /* not LV_KEY_NEXT: TAB is an app-level key here */
    case KEY_PREVIOUS: return CP0_LV_KEY_PREV;
    case KEY_HOME: return CP0_LV_KEY_HOME;
    case KEY_END: return CP0_LV_KEY_END;
    default: break;
    }
    if (codepoint >= 0x20 && codepoint != 0x7f) return codepoint;
    return cp0_keyboard_is_lvgl_control_key(semantic_key) ? 0 : semantic_key;
}

/* LVGL keypads know pressed and released only: an auto-repeat is still pressed,
 * which lets LVGL's own long-press repeat run. */
static inline int cp0_keyboard_lvgl_key_pressed(int key_state)
{
    return key_state != KBD_KEY_RELEASED;
}
