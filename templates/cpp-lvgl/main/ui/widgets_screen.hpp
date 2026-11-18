/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#pragma once

// Demo 4, widgets: a form of stock LVGL widgets with the default theme, laid
// out with flex and driven by LVGL's own focus group and widget events:
// lv_textarea, lv_button, lv_slider, lv_spinbox, lv_dropdown, lv_switch,
// lv_checkbox. F/X move the focus, Z/C change the value, ENTER presses; the
// text area takes typing. See widgets_screen.cpp for how the keys get there.

#include "app_ui.hpp"

#include <string>

namespace app {

class WidgetsScreen final : public Screen
{
public:
    explicit WidgetsScreen(lv_obj_t *parent);
    ~WidgetsScreen() override;

    std::string title() const override { return "Widgets"; }
    Action handle_key(const key_item &key) override;

protected:
    void on_show() override;
    void on_hide() override;

private:
    void add_to_form(lv_obj_t *widget);
    void make_name_row();
    void make_buttons_row();
    void make_volume_row();
    void make_count_row();
    void make_color_row();
    void make_sound_row();
    void make_like_row();

    void set_status(const std::string &text);
    void set_typing(bool typing);

    // Widget events. (The keyboard adapter and the other callbacks that need no
    // screen are free functions in widgets_screen.cpp.)
    static void name_focus_cb(lv_event_t *event);
    static void hello_clicked_cb(lv_event_t *event);
    static void add_one_clicked_cb(lv_event_t *event);
    static void volume_changed_cb(lv_event_t *event);
    static void count_changed_cb(lv_event_t *event);
    static void color_changed_cb(lv_event_t *event);
    static void sound_changed_cb(lv_event_t *event);
    static void like_changed_cb(lv_event_t *event);

    lv_group_t *group_ = nullptr;           // the form's focusable widgets, in F/X order
    lv_group_t *previous_group_ = nullptr;  // the keypad's group before this screen showed
    lv_obj_t *status_ = nullptr;
    lv_obj_t *form_ = nullptr;  // the scrolling column of rows
    lv_obj_t *hint_ = nullptr;
    lv_obj_t *name_ = nullptr;
    lv_obj_t *volume_ = nullptr;
    lv_obj_t *volume_value_ = nullptr;
    lv_obj_t *count_ = nullptr;
    lv_obj_t *color_ = nullptr;
    lv_obj_t *sound_ = nullptr;
    lv_obj_t *sound_value_ = nullptr;
    lv_obj_t *like_ = nullptr;
};

} // namespace app
