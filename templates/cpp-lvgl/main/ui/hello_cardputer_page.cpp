/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "hello_cardputer_page.hpp"

#include "cp0_keyboard_navigation_contract.h"
#include "input_keys.h"

#include <string>

namespace {

bool g_quit_requested = false;

lv_obj_t *make_label(lv_obj_t *parent, const char *text, const lv_font_t *font, uint32_t color)
{
    lv_obj_t *label = lv_label_create(parent);
    lv_label_set_text(label, text);
    lv_obj_set_style_text_font(label, font, 0);
    lv_obj_set_style_text_color(label, lv_color_hex(color), 0);
    return label;
}

} // namespace

HelloCardputerPage::HelloCardputerPage()
{
    set_page_title("Hello Cardputer");
    create_ui();
    // Key presses are delivered to the screen as LV_EVENT_KEY.
    lv_obj_add_event_cb(root_screen_, key_event_cb, LV_EVENT_KEY, this);
    update_ui();
}

bool HelloCardputerPage::quit_requested()
{
    return g_quit_requested;
}

void HelloCardputerPage::create_ui()
{
    lv_obj_set_style_bg_color(ui_APP_Container, lv_color_hex(0x101418), 0);
    lv_obj_set_style_bg_opa(ui_APP_Container, LV_OPA_COVER, 0);

    lv_obj_t *title = make_label(ui_APP_Container, "Hello Cardputer", &lv_font_montserrat_20, 0xFFFFFF);
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 10);
    lv_obj_t *subtitle = make_label(ui_APP_Container, "Your CardputerZero app", &lv_font_montserrat_12, 0x9AA4AE);
    lv_obj_align_to(subtitle, title, LV_ALIGN_OUT_BOTTOM_MID, 0, 2);

    counter_label_ = make_label(ui_APP_Container, "", &lv_font_montserrat_28, 0x4FC3F7);
    lv_obj_align(counter_label_, LV_ALIGN_CENTER, 0, 4);

    // Keep UI text at 12px or larger: the screen is only 320x170.
    hint_label_ = make_label(ui_APP_Container, "UP/DOWN change   ENTER reset   ESC quit",
                             &lv_font_montserrat_12, 0x9AA4AE);
    lv_obj_align(hint_label_, LV_ALIGN_BOTTOM_MID, 0, -10);
}

void HelloCardputerPage::update_ui()
{
    lv_label_set_text(counter_label_, std::to_string(counter_).c_str());
}

void HelloCardputerPage::handle_key(uint32_t key)
{
    // The CardputerZero keyboard has no dedicated arrow keys; this maps the
    // keyboard's navigation keys (and real arrows in the simulator) to LV_KEY_*.
    key = cp0_keyboard_navigation_alias(key);
    if (key == LV_KEY_UP || key == LV_KEY_RIGHT) ++counter_;
    else if (key == LV_KEY_DOWN || key == LV_KEY_LEFT) --counter_;
    else if (key == LV_KEY_ENTER) counter_ = 0;
    else if (key == LV_KEY_ESC) g_quit_requested = true;
    update_ui();
}

void HelloCardputerPage::key_event_cb(lv_event_t *event)
{
    auto *self = static_cast<HelloCardputerPage *>(lv_event_get_user_data(event));
    self->handle_key(lv_event_get_key(event));
}
