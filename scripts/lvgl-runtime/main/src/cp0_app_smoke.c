/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

/*
 * The smallest cp0_app program, in C: a page with a label; ESC quits. build.sh
 * builds it to produce the runtime and to learn the compile and link flags, and
 * runs it headless as a check. Other languages make the same calls.
 */

#include "cp0_app.h"
#include "lvgl/lvgl.h"

#define KEY_ESC 1

static void setup(lv_obj_t *content, void *user_data)
{
    (void)user_data;
    lv_obj_t *label = lv_label_create(content);
    lv_label_set_text(label, "Hello from C");
    lv_obj_set_style_text_font(label, &lv_font_montserrat_20, 0);
    lv_obj_set_style_text_color(label, lv_color_hex(0xFFFFFF), 0);
    lv_obj_center(label);
}

static void on_key(const cp0_app_key_t *key, void *user_data)
{
    (void)user_data;
    if (key->state != CP0_APP_KEY_RELEASED && key->code == KEY_ESC) cp0_app_quit();
}

int main(void)
{
    return cp0_app_run("cp0_app", setup, on_key, NULL);
}
