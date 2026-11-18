/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#pragma once

// The app's look and plumbing, shared by every screen: colors, key helpers,
// label/panel helpers and the Screen base class.

#include "keyboard_input.h"
#include "lvgl/lvgl.h"

#include <cstdint>
#include <string>

namespace app {

// The language this template is written in, and GitHub's color for it.
constexpr const char *kLanguage = "C++";
constexpr uint32_t kLanguageColor = 0xF34B7D;

constexpr uint32_t kBackgroundColor = 0x0E1217;
constexpr uint32_t kTextColor = 0xFFFFFF;
constexpr uint32_t kMutedColor = 0x96A0AA;
constexpr uint32_t kErrorColor = 0xFF6E6E;

// ui_APP_Container, the area below the 20 px top bar that every screen fills.
constexpr int kContentWidth = 320;
constexpr int kContentHeight = 150;
// Top of the key-help line at the bottom of a screen (content coordinates).
constexpr int kHintTop = kContentHeight - 17;
// Animation frame period: about 60 frames per second.
constexpr uint32_t kFrameMs = 16;

// What a screen asks the app to do after a key press.
struct Action
{
    enum class Kind { Stay, Home, Next, Open, Quit };
    Kind kind = Kind::Stay;
    int demo = 0;  // for Open: which demo, 0-based

    static Action stay() { return {}; }
    static Action home() { return {Kind::Home, 0}; }
    static Action next() { return {Kind::Next, 0}; }
    static Action open(int demo) { return {Kind::Open, demo}; }
    static Action quit() { return {Kind::Quit, 0}; }
};

// The CardputerZero keyboard has no arrow keys: like the launcher, F/X/Z/C
// act as up/down/left/right. Real arrow keys (simulator, USB keyboards) work too.
enum class Direction { None, Up, Down, Left, Right };
Direction direction(uint32_t key_code);

// Text the key typed (cp0_lvgl applies Shift and the symbol layer), or nullptr
// for keys that type nothing printable.
const char *typed_text(const key_item &key);

lv_obj_t *make_label(lv_obj_t *parent, const char *text, const lv_font_t *font, uint32_t color);
// A plain rectangle; `opa` below LV_OPA_COVER shades what is under it.
lv_obj_t *make_panel(lv_obj_t *parent, int x, int y, int width, int height, uint32_t color, lv_opa_t opa);
// Makes LVGL's default theme (dark, Montserrat 14) the app's theme, with
// `primary` as its accent color. Widgets created afterwards take their look from
// it; calling it again restyles the existing ones (the Widgets demo's Color row).
void set_theme(uint32_t primary);

// One line of key help, centered at the bottom of a screen.
lv_obj_t *make_hint(lv_obj_t *parent, const char *text);
// "TAB next  ESC home", top right: how to leave a demo.
lv_obj_t *make_demo_keys(lv_obj_t *parent);

// One screen of the app: a full-size container inside ui_APP_Container that is
// shown while the screen is active. Animated screens call animate() once;
// on_frame() then runs every kFrameMs while the screen shows.
class Screen
{
public:
    explicit Screen(lv_obj_t *parent);
    virtual ~Screen();

    Screen(const Screen &) = delete;
    Screen &operator=(const Screen &) = delete;

    // Shown in the top bar while this screen is active.
    virtual std::string title() const = 0;
    // Called for key presses and auto-repeats (not releases).
    virtual Action handle_key(const key_item &key) = 0;

    void show();
    void hide();

protected:
    lv_obj_t *root() const { return root_; }
    bool shown() const;
    void animate();
    virtual void on_show() {}
    virtual void on_hide() {}
    virtual void on_frame() {}

private:
    static void frame_cb(lv_timer_t *timer);

    lv_obj_t *root_ = nullptr;
    lv_timer_t *timer_ = nullptr;
};

} // namespace app
