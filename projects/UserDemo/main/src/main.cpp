/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "cp0_lvgl_app_runner.hpp"
#include "ui/ui.h"

int main(void)
{
    // cp0_lvgl_run owns lv_init(), the platform (SDL / framebuffer) setup, and a
    // portable wait loop, so the demo builds on Linux devices and macOS alike.
    Cp0LvglRunOptions options;
    options.setup = [] {
        ui_init();
        return true;
    };
    return cp0_lvgl_run(std::move(options));
}
