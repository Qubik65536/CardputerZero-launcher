/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#pragma once

#include "app_ui.hpp"
#include "colors_screen.hpp"
#include "home_screen.hpp"
#include "motion_screen.hpp"
#include "repl_screen.hpp"
#include "ui_app_page.hpp"

#include <array>

// The app's one page. AppPage gives you:
//   - the standard 20px top bar (title, clock, battery), title set with set_page_title()
//   - ui_APP_Container: the 320x150 content area below it, where your widgets go
//   - root_screen_: the LVGL screen, which receives keyboard events
//
// The home screen greets you and opens three demos: color rendering
// (colors_screen), an interactive animation (motion_screen) and a
// terminal-style REPL (repl_screen, running the little language in calc).
// Each is an app::Screen inside ui_APP_Container; one shows at a time. TAB
// moves to the next demo, ESC goes back home, ESC at home quits. Keep what you
// need and delete the rest.
class HelloCardputerPage : public AppPage
{
public:
    HelloCardputerPage();
    ~HelloCardputerPage() override = default;

    // Set when the user presses ESC at home; main.cpp's should_quit hook ends the app.
    static bool quit_requested();

private:
    void show(app::Screen &screen);
    void apply(const app::Action &action);
    void handle_key(const key_item &key);

    static void keyboard_event_cb(lv_event_t *event);

    app::HomeScreen home_;
    app::ColorsScreen colors_;
    app::MotionScreen motion_;
    app::ReplScreen repl_;
    // The demos in menu and TAB order (app::kDemos).
    std::array<app::Screen *, 3> demos_ = {&colors_, &motion_, &repl_};
    app::Screen *current_ = nullptr;
};
