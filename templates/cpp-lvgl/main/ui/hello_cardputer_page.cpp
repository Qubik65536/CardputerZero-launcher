/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "hello_cardputer_page.hpp"

#include "keyboard_input.h"

#include <algorithm>

namespace {

bool g_quit_requested = false;

} // namespace

bool HelloCardputerPage::quit_requested()
{
    return g_quit_requested;
}

void HelloCardputerPage::show(app::Screen &screen)
{
    if (current_ == &screen) return;
    if (current_) current_->hide();
    current_ = &screen;
    current_->show();
}

void HelloCardputerPage::apply(const app::Action &action)
{
    using Kind = app::Action::Kind;
    switch (action.kind) {
    case Kind::Stay: break;
    case Kind::Home: show(home_); break;
    case Kind::Open: show(*demos_[action.demo]); break;
    case Kind::Next: {
        const auto found = std::find(demos_.begin(), demos_.end(), current_);
        const size_t index = found == demos_.end() ? 0 : static_cast<size_t>(found - demos_.begin());
        show(*demos_[(index + 1) % demos_.size()]);
        break;
    }
    case Kind::Quit: g_quit_requested = true; break;
    }
    // The title follows the screen (and the Colors scene).
    set_page_title(current_->title());
}

void HelloCardputerPage::handle_key(const key_item &key)
{
    // Key presses and auto-repeats; releases carry no new input. (Text sent by
    // the automation RPC arrives as released items without a key code.)
    const bool injected_text = key.key_code == 0 && key.utf8[0] != '\0';
    if (key.key_state == KBD_KEY_RELEASED && !injected_text) return;
    apply(current_->handle_key(key));
}

// cp0_lvgl sends every key to the active screen as LV_EVENT_KEYBOARD, with the
// Linux key code, modifiers and the text it types (Shift and the keyboard's
// symbol layer already applied), on the device and in the simulator alike.
void HelloCardputerPage::keyboard_event_cb(lv_event_t *event)
{
    if (lv_event_get_code(event) != static_cast<lv_event_code_t>(LV_EVENT_KEYBOARD)) return;
    auto *self = static_cast<HelloCardputerPage *>(lv_event_get_user_data(event));
    self->handle_key(*static_cast<const key_item *>(lv_event_get_param(event)));
}

HelloCardputerPage::HelloCardputerPage()
    : home_(ui_APP_Container), colors_(ui_APP_Container), motion_(ui_APP_Container), repl_(ui_APP_Container)
{
    lv_obj_set_style_bg_color(ui_APP_Container, lv_color_hex(app::kBackgroundColor), 0);
    lv_obj_set_style_bg_opa(ui_APP_Container, LV_OPA_COVER, 0);
    lv_obj_add_event_cb(root_screen_, keyboard_event_cb, LV_EVENT_ALL, this);
    apply(app::Action::home());
}
