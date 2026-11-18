/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "app_ui.hpp"
#include "cp0_lvgl_app_runner.hpp"
#include "hello_cardputer_page.hpp"

#include <utility>

int main()
{
    // cp0_lvgl_run_app sets up LVGL, the display (SDL window or the device
    // framebuffer), the keyboard and the platform services, shows the page,
    // and runs the event loop until should_quit returns true.
    Cp0LvglAppHooks hooks;
    // The display exists now and the page does not yet: set the theme first, so
    // the page and every widget on it are created with it.
    hooks.after_resource_init = [] { app::set_theme(app::kLanguageColor); };
    hooks.should_quit = [] { return HelloCardputerPage::quit_requested(); };
    return cp0_lvgl_run_app<HelloCardputerPage>(std::move(hooks));
}
