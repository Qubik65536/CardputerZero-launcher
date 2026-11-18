/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "home_screen.hpp"

#include "cp0_lvgl_filesystem.hpp"
#include "input_keys.h"

namespace app {

namespace {

constexpr int kMenuTop = 50;
constexpr int kRowHeight = 20;
constexpr int kDescriptionX = 98;

// Text with a dark shadow, readable on top of a picture.
lv_obj_t *make_shadowed_label(lv_obj_t *parent, const char *text, const lv_font_t *font, uint32_t color, int x,
                              int y, int offset)
{
    lv_obj_t *shadow = make_label(parent, text, font, 0x000000);
    lv_obj_set_pos(shadow, x + offset, y + offset);
    lv_obj_t *label = make_label(parent, text, font, color);
    lv_obj_set_pos(label, x, y);
    return label;
}

} // namespace

void HomeScreen::update_selection()
{
    for (size_t index = 0; index < rows_.size(); ++index) {
        const bool selected = static_cast<int>(index) == selected_;
        if (selected) lv_obj_remove_flag(rows_[index].accent, LV_OBJ_FLAG_HIDDEN);
        else lv_obj_add_flag(rows_[index].accent, LV_OBJ_FLAG_HIDDEN);
        lv_obj_set_style_text_color(rows_[index].name, lv_color_hex(selected ? kTextColor : kMutedColor), 0);
        lv_obj_set_style_text_color(rows_[index].description,
                                    lv_color_hex(selected ? kLanguageColor : kMutedColor), 0);
    }
}

HomeScreen::HomeScreen(lv_obj_t *parent) : Screen(parent)
{
    // Images from APPLaunch/share/images/: cp0_file_path() resolves the name for
    // both the device (/usr/share/APPLaunch) and the simulator (dist/APPLaunch).
    lv_obj_t *wallpaper = lv_image_create(root());
    lv_image_set_src(wallpaper, cp0_file_path("wallpaper.png").c_str());
    lv_obj_set_pos(wallpaper, 0, 0);

    const std::string greeting = std::string("Hello, ") + kLanguage + "!";
    make_shadowed_label(root(), greeting.c_str(), &lv_font_montserrat_28, kLanguageColor, 14, -2, 2);
    make_shadowed_label(root(), "Your CardputerZero app", &lv_font_montserrat_14, kMutedColor, 16, 29, 1);

    make_panel(root(), 8, kMenuTop - 4, kContentWidth - 16, kRowHeight * static_cast<int>(kDemos.size()) + 6,
               0x000000, 150);
    for (size_t index = 0; index < kDemos.size(); ++index) {
        const int y = kMenuTop + static_cast<int>(index) * kRowHeight;
        MenuRow &row = rows_[index];
        row.accent = make_panel(root(), 8, y - 2, 3, kRowHeight - 2, kLanguageColor, LV_OPA_COVER);
        const std::string name = std::to_string(index + 1) + " " + kDemos[index].name;
        row.name = make_label(root(), name.c_str(), &lv_font_montserrat_14, kMutedColor);
        lv_obj_set_pos(row.name, 18, y);
        row.description = make_label(root(), kDemos[index].description, &lv_font_montserrat_14, kMutedColor);
        lv_obj_set_pos(row.description, kDescriptionX, y);
    }

    make_panel(root(), 0, kHintTop - 1, kContentWidth, kContentHeight - kHintTop + 1, 0x000000, 170);
    make_hint(root(), "F/X choose  ENTER open  ESC quit");
    update_selection();
}

Action HomeScreen::handle_key(const key_item &key)
{
    const int count = static_cast<int>(kDemos.size());
    switch (direction(key.key_code)) {
    case Direction::Up:
    case Direction::Left: selected_ = (selected_ + count - 1) % count; break;
    case Direction::Down:
    case Direction::Right: selected_ = (selected_ + 1) % count; break;
    case Direction::None:
        switch (key.key_code) {
        case KEY_ENTER:
        case KEY_SPACE: return Action::open(selected_);
        case KEY_1: return Action::open(0);
        case KEY_2: return Action::open(1);
        case KEY_3: return Action::open(2);
        case KEY_4: return Action::open(3);
        // Quit on a short ESC press. (Holding ESC for 3 s makes the launcher kill the app.)
        case KEY_ESC: return Action::quit();
        default: break;
        }
        break;
    }
    update_selection();
    return Action::stay();
}

} // namespace app
