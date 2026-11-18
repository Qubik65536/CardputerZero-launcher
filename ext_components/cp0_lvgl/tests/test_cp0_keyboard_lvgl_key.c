/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

// cp0 key items -> LVGL keypad keys (both backends).

#include "../src/cp0_keyboard_lvgl_key.h"

#include <assert.h>

int main(void)
{
    // Navigation and editing keys become LVGL's control keys.
    assert(cp0_keyboard_lvgl_key(KEY_UP, 0) == CP0_LV_KEY_UP);
    assert(cp0_keyboard_lvgl_key(KEY_ENTER, '\r') == CP0_LV_KEY_ENTER);
    assert(cp0_keyboard_lvgl_key(KEY_BACKSPACE, 8) == CP0_LV_KEY_BACKSPACE);
    assert(cp0_keyboard_lvgl_key(KEY_ESC, 27) == CP0_LV_KEY_ESC);
    assert(cp0_keyboard_lvgl_key(KEY_TAB, '\t') == KEY_TAB);

    // Keys that type something report the character, so text areas can edit natively.
    assert(cp0_keyboard_lvgl_key(KEY_A, 'a') == 'a');
    assert(cp0_keyboard_lvgl_key(KEY_A, 'A') == 'A');
    assert(cp0_keyboard_lvgl_key(KEY_SPACE, ' ') == ' ');
    assert(cp0_keyboard_lvgl_key(52, '*') == '*'); // symbol layer: code 52 types '*'
    assert(cp0_keyboard_lvgl_key(KEY_A, 0x00e9) == 0x00e9); // non-ASCII text

    // Raw codes that LVGL would read as control keys never leak through:
    // KEY_W = 17 = LV_KEY_UP, KEY_9 = 10 = LV_KEY_ENTER, KEY_7 = 8 = LV_KEY_BACKSPACE.
    assert(cp0_keyboard_lvgl_key(KEY_W, 'w') == 'w');
    assert(cp0_keyboard_lvgl_key(KEY_W, 0) == 0);
    assert(cp0_keyboard_lvgl_key(KEY_9, 0) == 0);
    assert(cp0_keyboard_lvgl_key(KEY_7, 0) == 0);
    assert(cp0_keyboard_lvgl_key(127, 0) == 0); // SYM (KEY_COMPOSE) would be LV_KEY_DEL

    // Other keys without text report nothing, except the page keys settings pages use.
    assert(cp0_keyboard_lvgl_key(KEY_PAGEUP, 0) == KEY_PAGEUP);
    assert(cp0_keyboard_lvgl_key(KEY_PAGEDOWN, 0) == KEY_PAGEDOWN);
    assert(cp0_keyboard_lvgl_key(KEY_F1, 0) == 0); // 59 would type ';'
    assert(cp0_keyboard_lvgl_key(KEY_H, 8) == 0);  // Ctrl+H: a control character, not text

    // Injected text (no key code, released) needs a synthetic press; real keys don't.
    assert(cp0_keyboard_lvgl_needs_press(0, KBD_KEY_RELEASED, 'a'));
    assert(!cp0_keyboard_lvgl_needs_press(KEY_A, KBD_KEY_RELEASED, 'a'));
    assert(!cp0_keyboard_lvgl_needs_press(0, KBD_KEY_PRESSED, 'a'));
    assert(!cp0_keyboard_lvgl_needs_press(0, KBD_KEY_RELEASED, 0));

    // Auto-repeat keeps the key pressed for LVGL.
    assert(cp0_keyboard_lvgl_key_pressed(KBD_KEY_PRESSED));
    assert(cp0_keyboard_lvgl_key_pressed(KBD_KEY_REPEATED));
    assert(!cp0_keyboard_lvgl_key_pressed(KBD_KEY_RELEASED));
    return 0;
}
