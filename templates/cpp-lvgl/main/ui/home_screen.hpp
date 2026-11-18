/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#pragma once

// The home screen: wallpaper, greeting and a menu of the demos.

#include "app_ui.hpp"

#include <array>

namespace app {

struct DemoInfo
{
    const char *name;
    const char *description;
};

// The demos, in menu order (and TAB order).
constexpr std::array<DemoInfo, 4> kDemos = {{
    {"Colors", "color triangle and wheel"},
    {"Motion", "steer a glowing ball"},
    {"REPL", "a tiny calculator language"},
    {"Widgets", "text field, slider, more"},
}};

class HomeScreen final : public Screen
{
public:
    explicit HomeScreen(lv_obj_t *parent);

    std::string title() const override { return "Hello Cardputer"; }
    Action handle_key(const key_item &key) override;

private:
    struct MenuRow
    {
        lv_obj_t *accent = nullptr;
        lv_obj_t *name = nullptr;
        lv_obj_t *description = nullptr;
    };

    void update_selection();

    int selected_ = 0;
    std::array<MenuRow, kDemos.size()> rows_;
};

} // namespace app
