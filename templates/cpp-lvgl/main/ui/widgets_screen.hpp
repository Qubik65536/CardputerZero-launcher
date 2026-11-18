/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#pragma once

// Demo 4, widgets: a small form of real LVGL widgets (lv_textarea, lv_button,
// lv_slider, a -/+ counter, lv_roller, lv_switch) in an lv_group. F/X move the
// focus, Z/C change the value, ENTER presses; the text field takes typing.
// See widgets_screen.cpp for how keys reach the widgets.

#include "app_ui.hpp"

#include <array>
#include <cstdint>
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
    static constexpr size_t kRowCount = 6;

    void make_rows();
    void make_name(int y);
    void make_button(int y);
    void make_volume(int y);
    void make_counter(int y);
    void make_chooser(int y);
    void make_switch(int y);

    uint32_t accent() const;
    void set_status(const std::string &text);
    void set_count(int count, const std::string &status);
    void refresh_focus();
    void apply_accent();
    void press_button();
    void change(int step);
    void activate();

    static void focus_cb(lv_group_t *group);
    static void button_clicked_cb(lv_event_t *event);
    static void button_release_cb(lv_timer_t *timer);
    static void volume_changed_cb(lv_event_t *event);
    static void minus_clicked_cb(lv_event_t *event);
    static void plus_clicked_cb(lv_event_t *event);
    static void choice_changed_cb(lv_event_t *event);
    static void sound_changed_cb(lv_event_t *event);

    lv_group_t *group_ = nullptr;
    std::array<lv_obj_t *, kRowCount> bars_{};
    std::array<lv_obj_t *, kRowCount> labels_{};
    std::array<lv_obj_t *, kRowCount> widgets_{};  // the focusable object of each row
    lv_obj_t *name_ = nullptr;
    lv_obj_t *button_ = nullptr;
    lv_obj_t *volume_ = nullptr;
    lv_obj_t *volume_value_ = nullptr;
    lv_obj_t *counter_ = nullptr;
    lv_obj_t *minus_ = nullptr;
    lv_obj_t *plus_ = nullptr;
    lv_obj_t *count_value_ = nullptr;
    lv_obj_t *chooser_ = nullptr;
    lv_obj_t *chooser_left_ = nullptr;
    lv_obj_t *chooser_right_ = nullptr;
    lv_obj_t *swatch_ = nullptr;
    lv_obj_t *sound_ = nullptr;
    lv_obj_t *sound_value_ = nullptr;
    lv_obj_t *status_ = nullptr;
    lv_obj_t *hint_ = nullptr;
    lv_timer_t *release_timer_ = nullptr;
    int count_ = 0;
};

} // namespace app
