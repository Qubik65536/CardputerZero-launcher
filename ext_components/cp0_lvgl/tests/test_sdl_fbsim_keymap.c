/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

// fbsim evdev events -> cp0 key items (SDL backend fbsim mode).

#include "../src/sdl/sdl_fbsim_keymap.h"

#include <assert.h>
#include <string.h>

static struct key_item press(uint16_t code, int32_t value, uint32_t *mods, int *produced)
{
    struct key_item item;
    memset(&item, 0, sizeof(item));
    *produced = cp0_fbsim_translate_key(code, value, mods, KBD_INPUT_CONTEXT_NAVIGATION, &item);
    return item;
}

int main(void)
{
    uint32_t mods = 0;
    int produced = 0;

    struct key_item a = press(KEY_A, 1, &mods, &produced);
    assert(produced && a.key_code == KEY_A && a.key_state == 1);
    assert(strcmp(a.utf8, "a") == 0 && a.codepoint == 'a' && a.mods == 0);

    // Modifiers only update the state; Shift selects the upper row.
    press(KEY_LEFTSHIFT, 1, &mods, &produced);
    assert(!produced && mods == KBD_MOD_SHIFT);
    assert(strcmp(press(KEY_A, 1, &mods, &produced).utf8, "A") == 0);
    assert(strcmp(press(KEY_1, 1, &mods, &produced).utf8, "!") == 0);
    assert(strcmp(press(KEY_SLASH, 1, &mods, &produced).utf8, "?") == 0);
    press(KEY_LEFTSHIFT, 0, &mods, &produced);
    assert(mods == 0);
    assert(strcmp(press(KEY_SLASH, 1, &mods, &produced).utf8, "/") == 0);
    assert(strcmp(press(KEY_SPACE, 1, &mods, &produced).utf8, " ") == 0);

    // Ctrl+letter is a control character; Fn is its own modifier.
    press(KEY_LEFTCTRL, 1, &mods, &produced);
    struct key_item ctrl_c = press(KEY_C, 1, &mods, &produced);
    assert(ctrl_c.utf8[0] == 3 && ctrl_c.utf8[1] == 0 && (ctrl_c.mods & KBD_MOD_CTRL));
    press(KEY_LEFTCTRL, 0, &mods, &produced);
    press(CP0_FBSIM_KEY_FN, 1, &mods, &produced);
    assert(!produced && mods == KBD_MOD_FN);
    press(CP0_FBSIM_KEY_FN, 0, &mods, &produced);

    // Control keys carry the terminal sequences; releases and repeats keep the state.
    struct key_item enter = press(KEY_ENTER, 0, &mods, &produced);
    assert(produced && enter.key_state == 0 && strcmp(enter.utf8, "\r") == 0);
    struct key_item up = press(KEY_UP, 2, &mods, &produced);
    assert(produced && up.key_state == 2 && strcmp(up.utf8, "\033[A") == 0);

    // F/X/Z/C navigate in the navigation context, as on the device.
    struct key_item f = press(KEY_F, 1, &mods, &produced);
    assert(f.semantic_key == cp0_keyboard_semantic_key(KEY_F, KBD_INPUT_CONTEXT_NAVIGATION));
    assert(strcmp(f.utf8, "f") == 0);

    // Unknown values are dropped.
    press(KEY_A, 7, &mods, &produced);
    assert(!produced);
    return 0;
}
