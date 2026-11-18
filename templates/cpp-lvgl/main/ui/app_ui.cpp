/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "app_ui.hpp"

#include "cp0_keyboard_navigation_contract.h"
#include "input_keys.h"

namespace app {

Direction direction(uint32_t key_code)
{
    switch (cp0_keyboard_navigation_alias(key_code)) {
    case KEY_UP: return Direction::Up;
    case KEY_DOWN: return Direction::Down;
    case KEY_LEFT: return Direction::Left;
    case KEY_RIGHT: return Direction::Right;
    default: return Direction::None;
    }
}

const char *typed_text(const key_item &key)
{
    const unsigned char first = static_cast<unsigned char>(key.utf8[0]);
    const bool printable = first >= 0x20 && first < 0x7F && key.utf8[1] == '\0';
    return printable ? key.utf8 : nullptr;
}

lv_obj_t *make_label(lv_obj_t *parent, const char *text, const lv_font_t *font, uint32_t color)
{
    lv_obj_t *label = lv_label_create(parent);
    lv_label_set_text(label, text);
    lv_obj_set_style_text_font(label, font, 0);
    lv_obj_set_style_text_color(label, lv_color_hex(color), 0);
    return label;
}

lv_obj_t *make_panel(lv_obj_t *parent, int x, int y, int width, int height, uint32_t color, lv_opa_t opa)
{
    lv_obj_t *panel = lv_obj_create(parent);
    lv_obj_remove_style_all(panel);
    lv_obj_set_pos(panel, x, y);
    lv_obj_set_size(panel, width, height);
    lv_obj_set_style_bg_color(panel, lv_color_hex(color), 0);
    lv_obj_set_style_bg_opa(panel, opa, 0);
    lv_obj_remove_flag(panel, static_cast<lv_obj_flag_t>(LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_SCROLLABLE));
    return panel;
}

void set_theme(uint32_t primary)
{
    lv_display_t *display = lv_display_get_default();
    lv_theme_t *theme = lv_theme_default_init(display, lv_color_hex(primary), lv_palette_main(LV_PALETTE_BLUE),
                                              true, &lv_font_montserrat_14);
    lv_display_set_theme(display, theme);
}

lv_obj_t *make_hint(lv_obj_t *parent, const char *text)
{
    lv_obj_t *hint = make_label(parent, text, &lv_font_montserrat_14, kMutedColor);
    lv_obj_align(hint, LV_ALIGN_TOP_MID, 0, kHintTop);
    return hint;
}

lv_obj_t *make_demo_keys(lv_obj_t *parent)
{
    lv_obj_t *keys = make_label(parent, "TAB next  ESC home", &lv_font_montserrat_12, kMutedColor);
    lv_obj_align(keys, LV_ALIGN_TOP_RIGHT, -6, 2);
    return keys;
}

Screen::Screen(lv_obj_t *parent)
{
    root_ = make_panel(parent, 0, 0, kContentWidth, kContentHeight, kBackgroundColor, LV_OPA_COVER);
    lv_obj_add_flag(root_, LV_OBJ_FLAG_HIDDEN);
}

Screen::~Screen()
{
    if (timer_) lv_timer_delete(timer_);
}

bool Screen::shown() const
{
    return !lv_obj_has_flag(root_, LV_OBJ_FLAG_HIDDEN);
}

void Screen::frame_cb(lv_timer_t *timer)
{
    static_cast<Screen *>(lv_timer_get_user_data(timer))->on_frame();
}

void Screen::animate()
{
    if (timer_) return;
    timer_ = lv_timer_create(frame_cb, kFrameMs, this);
    lv_timer_pause(timer_);
}

void Screen::show()
{
    lv_obj_remove_flag(root_, LV_OBJ_FLAG_HIDDEN);
    if (timer_) lv_timer_resume(timer_);
    on_show();
}

void Screen::hide()
{
    if (timer_) lv_timer_pause(timer_);
    lv_obj_add_flag(root_, LV_OBJ_FLAG_HIDDEN);
    on_hide();
}

} // namespace app
