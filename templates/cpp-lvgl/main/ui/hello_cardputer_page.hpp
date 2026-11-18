/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#pragma once

#include "ui_app_page.hpp"

#include <cstdint>

// One screen of the app. AppPage gives you:
//   - the standard 20px top bar (title, clock, battery), title set with set_page_title()
//   - ui_APP_Container: the 320x150 content area below it, where your widgets go
//   - root_screen_: the LVGL screen, which receives keyboard events
class HelloCardputerPage : public AppPage
{
public:
    HelloCardputerPage();
    ~HelloCardputerPage() override = default;

    // Set when the user presses ESC; main.cpp's should_quit hook ends the app.
    static bool quit_requested();

private:
    void create_ui();
    void update_ui();
    void handle_key(uint32_t key);

    static void key_event_cb(lv_event_t *event);

    int counter_ = 0;
    lv_obj_t *counter_label_ = nullptr;
    lv_obj_t *hint_label_ = nullptr;
};
