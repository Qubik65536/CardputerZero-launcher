/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "widgets_screen.hpp"

#include "input_keys.h"

#include <algorithm>
#include <cstring>

// How keys reach the widgets
// --------------------------
// cp0_lvgl delivers every key twice: first as LV_EVENT_KEYBOARD to the active
// screen (Linux key code + the text it types), then through LVGL's keypad input
// device to the focused object of the page's lv_group, as LV_EVENT_KEY. That
// second path cannot drive a form on the CardputerZero: the keyboard has no
// arrow keys (F/X/Z/C turn into arrows, so they could not be typed into the text
// field), letters arrive as key codes rather than characters, and LVGL only moves
// the focus on LV_KEY_NEXT/LV_KEY_PREV, which the keyboard never sends.
//
// So while this screen shows it turns that path off
// (cp0_keyboard_set_lvgl_keypad_intercept) and handles LV_EVENT_KEYBOARD
// itself, using LVGL's own machinery for the rest:
//   - the widgets sit in an lv_group: F/X call lv_group_focus_prev/next, and the
//     focused widget gets LV_STATE_FOCUSED, which its styles react to;
//   - Z/C and ENTER set the focused widget's value through its API and send the
//     event LVGL itself would send (LV_EVENT_VALUE_CHANGED, LV_EVENT_CLICKED);
//   - the form reacts to those events only, so a mouse click in the simulator
//     window (or a touch screen) works the same way as the keys;
//   - typed text goes into the lv_textarea with lv_textarea_add_text, and the
//     keyboard is in text mode while the text field has the focus.
// The same works on the device and in the simulator.

namespace app {

namespace {

constexpr uint32_t kField = 0x080A0E;
constexpr uint32_t kBorder = 0x3C4652;
constexpr uint32_t kFace = 0x1C222A;

// The form's rows, top to bottom; the status line sits above them.
const char *const kRowLabels[] = {"Name", "Button", "Volume", "Count", "Color", "Sound"};
enum Row { kNameRow, kButtonRow, kVolumeRow, kCountRow, kColorRow, kSoundRow };
constexpr int kRowsTop = 18;
constexpr int kRowHeight = 18;
constexpr int kWidgetLeft = 72;  // labels on the left, widgets from here
constexpr int kWidgetWidth = 242;
constexpr int kSliderWidth = 176;
constexpr int kVolumeStep = 5;
constexpr uint32_t kMaxName = 24;
constexpr uint32_t kPressMs = 10 * kFrameMs;  // how long the button shows as pressed

struct Choice
{
    const char *name;
    uint32_t color;
};

// The chooser's options: each template language and GitHub's color for it.
constexpr Choice kChoices[] = {{"Rust", 0xDEA584}, {"Zig", 0xEC915C}, {"OCaml", 0xEF7A08}, {"C++", 0xF34B7D}};
constexpr uint32_t kChoiceCount = sizeof(kChoices) / sizeof(kChoices[0]);

uint32_t default_choice()
{
    for (uint32_t index = 0; index < kChoiceCount; ++index) {
        if (std::strcmp(kChoices[index].name, kLanguage) == 0) return index;
    }
    return 0;
}

// The form's widgets are styled from scratch (no theme), flat like the rest of the app.
void style_box(lv_obj_t *obj, uint32_t background)
{
    lv_obj_set_style_bg_color(obj, lv_color_hex(background), 0);
    lv_obj_set_style_bg_opa(obj, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(obj, 1, 0);
    lv_obj_set_style_border_color(obj, lv_color_hex(kBorder), 0);
    lv_obj_set_style_text_font(obj, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(obj, lv_color_hex(kTextColor), 0);
}

lv_obj_t *make_box_button(lv_obj_t *parent, const char *text, int x, int y, int width)
{
    lv_obj_t *button = lv_button_create(parent);
    lv_obj_remove_style_all(button);
    style_box(button, kFace);
    lv_obj_set_pos(button, x, y);
    lv_obj_set_size(button, width, kRowHeight);
    lv_obj_t *label = lv_label_create(button);
    lv_label_set_text(label, text);
    lv_obj_center(label);
    return button;
}

std::string trim(const std::string &text)
{
    const size_t first = text.find_first_not_of(" \t");
    if (first == std::string::npos) return {};
    return text.substr(first, text.find_last_not_of(" \t") - first + 1);
}

} // namespace

uint32_t WidgetsScreen::accent() const
{
    return kChoices[lv_roller_get_selected(chooser_)].color;
}

void WidgetsScreen::set_status(const std::string &text)
{
    lv_label_set_text(status_, text.c_str());
}

void WidgetsScreen::set_count(int count, const std::string &status)
{
    count_ = count;
    lv_label_set_text(count_value_, std::to_string(count_).c_str());
    set_status(status);
}

// The row markers that are not LVGL focus styles: accent bar, label colors,
// counter and chooser decorations, the hint, and the keyboard mode.
void WidgetsScreen::refresh_focus()
{
    const lv_obj_t *focused = lv_group_get_focused(group_);
    const lv_color_t accent_color = lv_color_hex(accent());
    for (size_t row = 0; row < kRowCount; ++row) {
        const bool is_focused = widgets_[row] == focused;
        if (is_focused) lv_obj_remove_flag(bars_[row], LV_OBJ_FLAG_HIDDEN);
        else lv_obj_add_flag(bars_[row], LV_OBJ_FLAG_HIDDEN);
        lv_obj_set_style_text_color(labels_[row], is_focused ? accent_color : lv_color_hex(kMutedColor), 0);
    }
    const lv_color_t counter_border = focused == counter_ ? accent_color : lv_color_hex(kBorder);
    lv_obj_set_style_border_color(minus_, counter_border, 0);
    lv_obj_set_style_border_color(plus_, counter_border, 0);
    const lv_color_t arrows = focused == chooser_ ? accent_color : lv_color_hex(kMutedColor);
    lv_obj_set_style_text_color(chooser_left_, arrows, 0);
    lv_obj_set_style_text_color(chooser_right_, arrows, 0);

    const bool typing = focused == name_;
    lv_label_set_text(hint_, typing ? "type a name  ENTER next" : "F/X move  Z/C change  ENTER press");
    if (!lv_obj_has_flag(root(), LV_OBJ_FLAG_HIDDEN))
        cp0_keyboard_set_input_context(typing ? KBD_INPUT_CONTEXT_TEXT : KBD_INPUT_CONTEXT_NAVIGATION);
}

// The accent color is whatever the chooser picked; every focus style uses it.
void WidgetsScreen::apply_accent()
{
    const lv_color_t color = lv_color_hex(accent());
    lv_obj_set_style_border_color(name_, color, LV_STATE_FOCUSED);
    lv_obj_set_style_bg_color(name_, color, static_cast<lv_style_selector_t>(LV_PART_CURSOR) | LV_STATE_FOCUSED);
    lv_obj_set_style_border_color(button_, color, LV_STATE_FOCUSED);
    lv_obj_set_style_bg_color(button_, color, LV_STATE_PRESSED);
    lv_obj_set_style_bg_color(volume_, color, LV_PART_INDICATOR);
    lv_obj_set_style_text_color(chooser_, color, LV_PART_SELECTED);
    lv_obj_set_style_bg_color(swatch_, color, 0);
    lv_obj_set_style_bg_color(sound_, color, static_cast<lv_style_selector_t>(LV_PART_INDICATOR) | LV_STATE_CHECKED);
    lv_obj_set_style_text_color(status_, color, 0);
    refresh_focus();
}

void WidgetsScreen::focus_cb(lv_group_t *group)
{
    if (auto *self = static_cast<WidgetsScreen *>(lv_group_get_user_data(group))) self->refresh_focus();
}

void WidgetsScreen::button_clicked_cb(lv_event_t *event)
{
    auto *self = static_cast<WidgetsScreen *>(lv_event_get_user_data(event));
    const std::string name = trim(lv_textarea_get_text(self->name_));
    self->set_status("Hello, " + (name.empty() ? std::string("stranger") : name) + "!");
}

void WidgetsScreen::button_release_cb(lv_timer_t *timer)
{
    auto *self = static_cast<WidgetsScreen *>(lv_timer_get_user_data(timer));
    lv_obj_remove_state(self->button_, LV_STATE_PRESSED);
    self->release_timer_ = nullptr;  // a one-shot timer deletes itself
}

void WidgetsScreen::volume_changed_cb(lv_event_t *event)
{
    auto *self = static_cast<WidgetsScreen *>(lv_event_get_user_data(event));
    const std::string value = std::to_string(lv_slider_get_value(self->volume_));
    lv_label_set_text(self->volume_value_, value.c_str());
    self->set_status("Volume " + value);
}

void WidgetsScreen::minus_clicked_cb(lv_event_t *event)
{
    auto *self = static_cast<WidgetsScreen *>(lv_event_get_user_data(event));
    self->set_count(self->count_ - 1, "Count " + std::to_string(self->count_ - 1));
}

void WidgetsScreen::plus_clicked_cb(lv_event_t *event)
{
    auto *self = static_cast<WidgetsScreen *>(lv_event_get_user_data(event));
    self->set_count(self->count_ + 1, "Count " + std::to_string(self->count_ + 1));
}

void WidgetsScreen::choice_changed_cb(lv_event_t *event)
{
    auto *self = static_cast<WidgetsScreen *>(lv_event_get_user_data(event));
    self->apply_accent();
    self->set_status(std::string("Color ") + kChoices[lv_roller_get_selected(self->chooser_)].name);
}

void WidgetsScreen::sound_changed_cb(lv_event_t *event)
{
    auto *self = static_cast<WidgetsScreen *>(lv_event_get_user_data(event));
    const char *state = lv_obj_has_state(self->sound_, LV_STATE_CHECKED) ? "on" : "off";
    lv_label_set_text(self->sound_value_, state);
    self->set_status(std::string("Sound ") + state);
}

void WidgetsScreen::make_name(int y)
{
    name_ = lv_textarea_create(root());
    lv_obj_remove_style_all(name_);
    style_box(name_, kField);
    lv_textarea_set_one_line(name_, true);
    lv_textarea_set_placeholder_text(name_, "your name");
    lv_textarea_set_max_length(name_, kMaxName);
    lv_obj_set_style_pad_hor(name_, 4, 0);
    lv_obj_set_pos(name_, kWidgetLeft, y);
    lv_obj_set_size(name_, kWidgetWidth, kRowHeight);
    lv_obj_set_style_text_color(name_, lv_color_hex(kMutedColor), LV_PART_TEXTAREA_PLACEHOLDER);
    // An empty focused field shows just the cursor: a solid block that does not blink.
    lv_obj_set_style_text_opa(name_, LV_OPA_TRANSP,
                              static_cast<lv_style_selector_t>(LV_PART_TEXTAREA_PLACEHOLDER) | LV_STATE_FOCUSED);
    lv_obj_set_style_bg_opa(name_, LV_OPA_COVER, static_cast<lv_style_selector_t>(LV_PART_CURSOR) | LV_STATE_FOCUSED);
    lv_obj_set_style_pad_right(name_, 4, LV_PART_CURSOR);
    lv_obj_set_style_anim_duration(name_, 0, LV_PART_CURSOR);
}

void WidgetsScreen::make_button(int y)
{
    button_ = make_box_button(root(), "Say hello", kWidgetLeft, y, 120);
    lv_obj_set_style_text_color(button_, lv_color_hex(kBackgroundColor), LV_STATE_PRESSED);
    lv_obj_add_event_cb(button_, button_clicked_cb, LV_EVENT_CLICKED, this);
}

void WidgetsScreen::make_volume(int y)
{
    volume_ = lv_slider_create(root());
    lv_obj_remove_style_all(volume_);
    lv_obj_set_pos(volume_, kWidgetLeft, y + 7);
    lv_obj_set_size(volume_, kSliderWidth, 4);
    lv_slider_set_range(volume_, 0, 100);
    lv_slider_set_value(volume_, 50, LV_ANIM_OFF);
    lv_obj_set_style_bg_color(volume_, lv_color_hex(kBorder), 0);
    lv_obj_set_style_bg_opa(volume_, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_opa(volume_, LV_OPA_COVER, LV_PART_INDICATOR);
    // The knob is the 4 px track height grown by its padding: 6 x 14.
    lv_obj_set_style_bg_color(volume_, lv_color_hex(kMutedColor), LV_PART_KNOB);
    lv_obj_set_style_bg_color(volume_, lv_color_hex(kTextColor),
                              static_cast<lv_style_selector_t>(LV_PART_KNOB) | LV_STATE_FOCUSED);
    lv_obj_set_style_bg_opa(volume_, LV_OPA_COVER, LV_PART_KNOB);
    lv_obj_set_style_pad_hor(volume_, 1, LV_PART_KNOB);
    lv_obj_set_style_pad_ver(volume_, 5, LV_PART_KNOB);
    lv_obj_add_event_cb(volume_, volume_changed_cb, LV_EVENT_VALUE_CHANGED, this);

    volume_value_ = make_label(root(), "50", &lv_font_montserrat_14, kTextColor);
    lv_obj_set_pos(volume_value_, kWidgetLeft + kSliderWidth + 12, y + 1);
}

void WidgetsScreen::make_counter(int y)
{
    // One focusable container holding "-", the value and "+".
    counter_ = make_panel(root(), kWidgetLeft, y, 108, kRowHeight, kBackgroundColor, LV_OPA_TRANSP);
    minus_ = make_box_button(counter_, "-", 0, 0, 24);
    plus_ = make_box_button(counter_, "+", 84, 0, 24);
    lv_obj_add_event_cb(minus_, minus_clicked_cb, LV_EVENT_CLICKED, this);
    lv_obj_add_event_cb(plus_, plus_clicked_cb, LV_EVENT_CLICKED, this);
    count_value_ = make_label(counter_, "0", &lv_font_montserrat_14, kTextColor);
    lv_obj_set_width(count_value_, 60);
    lv_obj_set_style_text_align(count_value_, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_pos(count_value_, 24, 1);
}

void WidgetsScreen::make_chooser(int y)
{
    chooser_left_ = make_label(root(), "<", &lv_font_montserrat_14, kMutedColor);
    lv_obj_set_pos(chooser_left_, kWidgetLeft, y + 1);
    std::string options;
    for (const Choice &choice : kChoices) options += std::string(options.empty() ? "" : "\n") + choice.name;
    chooser_ = lv_roller_create(root());
    lv_obj_remove_style_all(chooser_);
    lv_obj_set_style_text_font(chooser_, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_font(chooser_, &lv_font_montserrat_14, LV_PART_SELECTED);
    lv_obj_set_style_text_align(chooser_, LV_TEXT_ALIGN_CENTER, 0);
    lv_roller_set_options(chooser_, options.c_str(), LV_ROLLER_MODE_NORMAL);
    lv_roller_set_visible_row_count(chooser_, 1);
    lv_roller_set_selected(chooser_, default_choice(), LV_ANIM_OFF);
    lv_obj_set_pos(chooser_, kWidgetLeft + 12, y + 1);
    lv_obj_set_width(chooser_, 56);
    lv_obj_add_event_cb(chooser_, choice_changed_cb, LV_EVENT_VALUE_CHANGED, this);
    chooser_right_ = make_label(root(), ">", &lv_font_montserrat_14, kMutedColor);
    lv_obj_set_pos(chooser_right_, kWidgetLeft + 72, y + 1);
    swatch_ = make_panel(root(), kWidgetLeft + 88, y + 2, 14, kRowHeight - 4, kLanguageColor, LV_OPA_COVER);
}

void WidgetsScreen::make_switch(int y)
{
    sound_ = lv_switch_create(root());
    lv_obj_remove_style_all(sound_);
    lv_obj_set_pos(sound_, kWidgetLeft, y + 2);
    lv_obj_set_size(sound_, 32, kRowHeight - 4);
    lv_obj_set_style_bg_color(sound_, lv_color_hex(kBorder), 0);
    lv_obj_set_style_bg_opa(sound_, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_opa(sound_, LV_OPA_COVER, static_cast<lv_style_selector_t>(LV_PART_INDICATOR) | LV_STATE_CHECKED);
    lv_obj_set_style_bg_color(sound_, lv_color_hex(kTextColor), LV_PART_KNOB);
    lv_obj_set_style_bg_opa(sound_, LV_OPA_COVER, LV_PART_KNOB);
    lv_obj_set_style_pad_all(sound_, -2, LV_PART_KNOB);
    lv_obj_set_style_outline_color(sound_, lv_color_hex(kTextColor), LV_STATE_FOCUSED);
    lv_obj_set_style_outline_width(sound_, 1, LV_STATE_FOCUSED);
    lv_obj_set_style_outline_pad(sound_, 2, LV_STATE_FOCUSED);
    lv_obj_add_state(sound_, LV_STATE_CHECKED);
    lv_obj_add_event_cb(sound_, sound_changed_cb, LV_EVENT_VALUE_CHANGED, this);

    sound_value_ = make_label(root(), "on", &lv_font_montserrat_14, kTextColor);
    lv_obj_set_pos(sound_value_, kWidgetLeft + 40, y + 1);
}

void WidgetsScreen::make_rows()
{
    for (size_t row = 0; row < kRowCount; ++row) {
        const int y = kRowsTop + static_cast<int>(row) * kRowHeight;
        bars_[row] = make_panel(root(), 0, y, 3, kRowHeight, kLanguageColor, LV_OPA_COVER);
        labels_[row] = make_label(root(), kRowLabels[row], &lv_font_montserrat_14, kMutedColor);
        lv_obj_set_pos(labels_[row], 8, y + 1);
    }
    make_name(kRowsTop + kNameRow * kRowHeight);
    make_button(kRowsTop + kButtonRow * kRowHeight);
    make_volume(kRowsTop + kVolumeRow * kRowHeight);
    make_counter(kRowsTop + kCountRow * kRowHeight);
    make_chooser(kRowsTop + kColorRow * kRowHeight);
    make_switch(kRowsTop + kSoundRow * kRowHeight);
    widgets_ = {name_, button_, volume_, counter_, chooser_, sound_};
}

WidgetsScreen::WidgetsScreen(lv_obj_t *parent) : Screen(parent)
{
    status_ = make_label(root(), "Try every widget", &lv_font_montserrat_14, kLanguageColor);
    lv_obj_set_pos(status_, 8, 0);
    make_demo_keys(root());
    make_rows();
    hint_ = make_hint(root(), "");

    group_ = lv_group_create();
    lv_group_set_wrap(group_, true);
    for (lv_obj_t *widget : widgets_) lv_group_add_obj(group_, widget);
    lv_group_focus_obj(name_);
    lv_group_set_user_data(group_, this);
    lv_group_set_focus_cb(group_, focus_cb);
    apply_accent();
}

WidgetsScreen::~WidgetsScreen()
{
    if (release_timer_) lv_timer_delete(release_timer_);
    lv_group_delete(group_);
}

// ENTER on the button: show it pressed for a moment and click it.
void WidgetsScreen::press_button()
{
    lv_obj_add_state(button_, LV_STATE_PRESSED);
    if (release_timer_) lv_timer_delete(release_timer_);
    release_timer_ = lv_timer_create(button_release_cb, kPressMs, this);
    lv_timer_set_repeat_count(release_timer_, 1);
    lv_obj_send_event(button_, LV_EVENT_CLICKED, nullptr);
}

// Z/C (or left/right): step the focused widget's value.
void WidgetsScreen::change(int step)
{
    const lv_obj_t *focused = lv_group_get_focused(group_);
    if (focused == volume_) {
        const int32_t value = lv_slider_get_value(volume_) + step * kVolumeStep;
        lv_slider_set_value(volume_, std::clamp<int32_t>(value, 0, 100), LV_ANIM_OFF);
        lv_obj_send_event(volume_, LV_EVENT_VALUE_CHANGED, nullptr);
    } else if (focused == counter_) {
        lv_obj_send_event(step < 0 ? minus_ : plus_, LV_EVENT_CLICKED, nullptr);
    } else if (focused == chooser_) {
        const uint32_t choice = (lv_roller_get_selected(chooser_) + kChoiceCount + step) % kChoiceCount;
        lv_roller_set_selected(chooser_, choice, LV_ANIM_OFF);
        lv_obj_send_event(chooser_, LV_EVENT_VALUE_CHANGED, nullptr);
    } else if (focused == sound_) {
        lv_obj_set_state(sound_, LV_STATE_CHECKED, !lv_obj_has_state(sound_, LV_STATE_CHECKED));
        lv_obj_send_event(sound_, LV_EVENT_VALUE_CHANGED, nullptr);
    }
}

// ENTER or SPACE on the focused widget.
void WidgetsScreen::activate()
{
    const lv_obj_t *focused = lv_group_get_focused(group_);
    if (focused == button_) press_button();
    else if (focused == counter_) set_count(0, "Count reset");
    else if (focused == chooser_ || focused == sound_) change(1);
}

void WidgetsScreen::on_show()
{
    // Keys come only through LV_EVENT_KEYBOARD while the form shows (see the top of this file).
    cp0_keyboard_set_lvgl_keypad_intercept(1);
    refresh_focus();
}

void WidgetsScreen::on_hide()
{
    cp0_keyboard_set_lvgl_keypad_intercept(0);
    cp0_keyboard_set_input_context(KBD_INPUT_CONTEXT_NAVIGATION);
}

Action WidgetsScreen::handle_key(const key_item &key)
{
    switch (key.key_code) {
    case KEY_ESC: return Action::home();
    case KEY_TAB: return Action::next();
    // Real arrow keys always move the focus, even out of the text field.
    case KEY_UP: lv_group_focus_prev(group_); return Action::stay();
    case KEY_DOWN: lv_group_focus_next(group_); return Action::stay();
    default: break;
    }
    if (lv_group_get_focused(group_) == name_) {
        // In the text field F/X/Z/C are letters; ENTER moves on.
        if (key.key_code == KEY_ENTER) lv_group_focus_next(group_);
        else if (key.key_code == KEY_BACKSPACE) lv_textarea_delete_char(name_);
        else if (const char *text = typed_text(key)) lv_textarea_add_text(name_, text);
        return Action::stay();
    }
    switch (direction(key.key_code)) {
    case Direction::Up: lv_group_focus_prev(group_); break;
    case Direction::Down: lv_group_focus_next(group_); break;
    case Direction::Left: change(-1); break;
    case Direction::Right: change(1); break;
    case Direction::None:
        if (key.key_code == KEY_ENTER || key.key_code == KEY_SPACE) activate();
        break;
    }
    return Action::stay();
}

} // namespace app
