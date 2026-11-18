/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "widgets_screen.hpp"

#include "input_keys.h"

// Stock LVGL, plus one adapter for the keyboard
// -----------------------------------------------
// Everything on this screen is plain LVGL:
//   - the look is LVGL's default theme (set_theme() in app_ui.cpp, called
//     before any widget exists). The widgets get sizes, never colors; the Color
//     row runs the theme again with another accent color and every widget follows;
//   - the layout is flex: a scrolling column of rows, each a label and widgets;
//   - the focus is an lv_group holding the form's widgets, which the keypad input
//     device uses while the screen shows. The focused widget gets
//     LV_STATE_FOCUS_KEY (the theme draws an outline) and scrolls into view;
//   - cp0_lvgl's keypad input device sends each key to the focused widget as
//     LV_EVENT_KEY: arrows (F/X/Z/C on the CardputerZero), ENTER, ESC,
//     BACKSPACE ... as LVGL's keys, and the character for a key that types one.
//     Each widget reacts the way it always does: the text area takes typing and
//     BACKSPACE, DEL, LEFT/RIGHT, HOME/END; ENTER clicks a button, toggles the
//     switch and the checkbox, opens the dropdown and picks an option;
//     LEFT/RIGHT move the slider; ESC closes the dropdown;
//   - the form reacts only to widget events (LV_EVENT_CLICKED,
//     LV_EVENT_VALUE_CHANGED, LV_EVENT_READY), so a mouse click in the simulator
//     window does exactly what the keys do.
//
// The CardputerZero keyboard needs one small adapter and one switch on top:
//   - Moving the focus. LVGL moves it only on LV_KEY_NEXT/LV_KEY_PREV, which the
//     keyboard never sends; it has no arrow keys either, so cp0_lvgl turns
//     F/X/Z/C into UP/DOWN/LEFT/RIGHT. focus_keys_cb, an LV_EVENT_KEY
//     preprocess handler on every widget of the form, turns UP/DOWN into
//     lv_group_focus_prev/next, except while the dropdown's list is open (there
//     UP/DOWN choose an option). (count_keys_cb gives the spinbox's LEFT/RIGHT,
//     which would move between digits, to its value.)
//   - Typing. While the text area has the focus the keyboard is in text mode, so
//     F/X/Z/C type letters instead of acting as arrows
//     (cp0_keyboard_set_input_context; cp0_app_set_text_input in the C API).

namespace app {

namespace {

constexpr int kFormTop = 18;     // below the status line
constexpr int kLabelWidth = 62;  // the column of row labels
constexpr uint32_t kMaxName = 24;
constexpr const char *kFormHint = "F/X move  Z/C change  ENTER press";
constexpr const char *kTypingHint = "type a name  ENTER next";

// The Color row: each template's language and GitHub's color for it, in the
// dropdown's order. This template starts on its own language, C++.
constexpr const char *kColorOptions = "Rust\nZig\nOCaml\nC++";
constexpr uint32_t kColors[] = {0xDEA584, 0xEC915C, 0xEF7A08, 0xF34B7D};
constexpr uint32_t kLanguageOption = 3;

constexpr lv_event_code_t kKeyPreprocess = static_cast<lv_event_code_t>(LV_EVENT_KEY | LV_EVENT_PREPROCESS);

std::string trim(const std::string &text)
{
    const size_t first = text.find_first_not_of(" \t");
    if (first == std::string::npos) return {};
    return text.substr(first, text.find_last_not_of(" \t") - first + 1);
}

// One row of the form: a transparent flex row holding a fixed-width label;
// the caller adds the row's widgets after it.
lv_obj_t *make_row(lv_obj_t *form, const char *text)
{
    lv_obj_t *row = lv_obj_create(form);
    lv_obj_remove_style_all(row);  // layout only: no background, border or padding
    lv_obj_set_size(row, LV_PCT(100), LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_all(row, 4, 0);  // room for the theme's focus outline around the widgets
    lv_obj_set_style_pad_column(row, 6, 0);
    lv_obj_t *label = lv_label_create(row);
    lv_label_set_text(label, text);
    lv_obj_set_width(label, kLabelWidth);
    return row;
}

// The default theme pads widgets for bigger screens. On 320 x 150 the form
// trims the vertical padding of the taller widgets to fit more rows.
void compact(lv_obj_t *widget)
{
    lv_obj_set_style_pad_ver(widget, 4, 0);
}

lv_obj_t *make_button(lv_obj_t *parent, const char *text)
{
    lv_obj_t *button = lv_button_create(parent);
    compact(button);
    lv_obj_t *label = lv_label_create(button);
    lv_label_set_text(label, text);
    lv_obj_center(label);
    return button;
}

// The adapter: F/X (UP/DOWN) move the focus to the previous/next widget.
void focus_keys_cb(lv_event_t *event)
{
    const uint32_t key = lv_event_get_key(event);
    if (key != LV_KEY_UP && key != LV_KEY_DOWN) return;
    lv_obj_t *widget = lv_event_get_target_obj(event);
    if (lv_obj_check_type(widget, &lv_dropdown_class) && lv_dropdown_is_open(widget)) return;
    lv_group_t *group = lv_obj_get_group(widget);
    if (key == LV_KEY_UP) lv_group_focus_prev(group);
    else lv_group_focus_next(group);
    lv_event_stop_processing(event);  // the widget itself never sees the key
}

// Z/C (LEFT/RIGHT) step the spinbox's value; nothing else edits it (typed
// characters included: the spinbox is a text area underneath).
void count_keys_cb(lv_event_t *event)
{
    lv_obj_t *spinbox = lv_event_get_target_obj(event);
    const uint32_t key = lv_event_get_key(event);
    if (key == LV_KEY_UP || key == LV_KEY_DOWN) return;  // focus moves
    if (key == LV_KEY_LEFT) lv_spinbox_decrement(spinbox);
    else if (key == LV_KEY_RIGHT) lv_spinbox_increment(spinbox);
    lv_event_stop_processing(event);
}

// ENTER in the one-line text area: on to the next widget. The ENTER key is still
// down; waiting for its release keeps it from clicking the newly focused button.
void name_ready_cb(lv_event_t *event)
{
    lv_group_focus_next(lv_obj_get_group(lv_event_get_target_obj(event)));
    if (lv_indev_t *keypad = lv_indev_active()) lv_indev_wait_release(keypad);
}

// The spinbox's -/+ buttons, as in LVGL's spinbox example: a click steps once,
// holding the mouse button repeats.
bool is_step_event(lv_event_t *event)
{
    const lv_event_code_t code = lv_event_get_code(event);
    return code == LV_EVENT_SHORT_CLICKED || code == LV_EVENT_LONG_PRESSED_REPEAT;
}

void minus_cb(lv_event_t *event)
{
    if (is_step_event(event)) lv_spinbox_decrement(static_cast<lv_obj_t *>(lv_event_get_user_data(event)));
}

void plus_cb(lv_event_t *event)
{
    if (is_step_event(event)) lv_spinbox_increment(static_cast<lv_obj_t *>(lv_event_get_user_data(event)));
}

// The -/+ buttons are for the mouse: Z/C do the same from the keyboard. Keep
// them out of every focus group (lv_button_create adds a button to the default
// group, if there is one).
lv_obj_t *make_step_button(lv_obj_t *row, const char *text)
{
    lv_obj_t *button = make_button(row, text);
    lv_group_remove_obj(button);
    return button;
}

// The root object gets LV_EVENT_DELETE before its children are deleted. Deleting
// the group then means that deleting the focused widget moves no focus, so no
// focus callback runs on widgets that are already gone.
void root_deleted_cb(lv_event_t *event)
{
    lv_group_delete(static_cast<lv_group_t *>(lv_event_get_user_data(event)));
}

WidgetsScreen *screen_of(lv_event_t *event)
{
    return static_cast<WidgetsScreen *>(lv_event_get_user_data(event));
}

} // namespace

void WidgetsScreen::set_status(const std::string &text)
{
    lv_label_set_text(status_, text.c_str());
}

// The text area has the focus: keys type text, and the hint says so.
void WidgetsScreen::set_typing(bool typing)
{
    lv_label_set_text(hint_, typing ? kTypingHint : kFormHint);
    if (shown()) cp0_keyboard_set_input_context(typing ? KBD_INPUT_CONTEXT_TEXT : KBD_INPUT_CONTEXT_NAVIGATION);
}

void WidgetsScreen::name_focus_cb(lv_event_t *event)
{
    screen_of(event)->set_typing(lv_event_get_code(event) == LV_EVENT_FOCUSED);
}

void WidgetsScreen::hello_clicked_cb(lv_event_t *event)
{
    WidgetsScreen *self = screen_of(event);
    const std::string name = trim(lv_textarea_get_text(self->name_));
    self->set_status("Hello, " + (name.empty() ? std::string("stranger") : name) + "!");
}

void WidgetsScreen::add_one_clicked_cb(lv_event_t *event)
{
    lv_obj_t *count = screen_of(event)->count_;
    lv_spinbox_set_value(count, lv_spinbox_get_value(count) + 1);  // the spinbox reports the change
}

void WidgetsScreen::volume_changed_cb(lv_event_t *event)
{
    WidgetsScreen *self = screen_of(event);
    const std::string value = std::to_string(lv_slider_get_value(self->volume_));
    lv_label_set_text(self->volume_value_, value.c_str());
    self->set_status("Volume " + value);
}

void WidgetsScreen::count_changed_cb(lv_event_t *event)
{
    WidgetsScreen *self = screen_of(event);
    self->set_status("Count " + std::to_string(lv_spinbox_get_value(self->count_)));
}

void WidgetsScreen::color_changed_cb(lv_event_t *event)
{
    WidgetsScreen *self = screen_of(event);
    const uint32_t color = kColors[lv_dropdown_get_selected(self->color_)];
    set_theme(color);  // every themed widget in the app takes the new accent color
    lv_obj_set_style_text_color(self->status_, lv_color_hex(color), 0);
    char name[16];
    lv_dropdown_get_selected_str(self->color_, name, sizeof(name));
    self->set_status(std::string("Color ") + name);
}

void WidgetsScreen::sound_changed_cb(lv_event_t *event)
{
    WidgetsScreen *self = screen_of(event);
    const char *state = lv_obj_has_state(self->sound_, LV_STATE_CHECKED) ? "on" : "off";
    lv_label_set_text(self->sound_value_, state);
    self->set_status(std::string("Sound ") + state);
}

void WidgetsScreen::like_changed_cb(lv_event_t *event)
{
    WidgetsScreen *self = screen_of(event);
    self->set_status(lv_obj_has_state(self->like_, LV_STATE_CHECKED) ? "Thanks!" : "Oh no");
}

// Every focusable widget: into the group (F/X order is the order of these
// calls), the adapter for F/X, and scrolled into view when it gets the focus.
void WidgetsScreen::add_to_form(lv_obj_t *widget)
{
    lv_group_add_obj(group_, widget);
    lv_obj_add_event_cb(widget, focus_keys_cb, kKeyPreprocess, nullptr);
    lv_obj_add_flag(widget, LV_OBJ_FLAG_SCROLL_ON_FOCUS);
}

void WidgetsScreen::make_name_row()
{
    lv_obj_t *row = make_row(form_, "Name");
    name_ = lv_textarea_create(row);
    lv_textarea_set_one_line(name_, true);
    lv_textarea_set_placeholder_text(name_, "your name");
    lv_textarea_set_max_length(name_, kMaxName);
    lv_obj_set_flex_grow(name_, 1);
    compact(name_);
    add_to_form(name_);
    lv_obj_add_event_cb(name_, name_focus_cb, LV_EVENT_FOCUSED, this);
    lv_obj_add_event_cb(name_, name_focus_cb, LV_EVENT_DEFOCUSED, this);
    lv_obj_add_event_cb(name_, name_ready_cb, LV_EVENT_READY, nullptr);
}

void WidgetsScreen::make_buttons_row()
{
    lv_obj_t *row = make_row(form_, "Buttons");
    lv_obj_t *hello = make_button(row, "Say hello");
    add_to_form(hello);
    lv_obj_add_event_cb(hello, hello_clicked_cb, LV_EVENT_CLICKED, this);
    lv_obj_t *add_one = make_button(row, "Count +1");
    add_to_form(add_one);
    lv_obj_add_event_cb(add_one, add_one_clicked_cb, LV_EVENT_CLICKED, this);
}

void WidgetsScreen::make_volume_row()
{
    lv_obj_t *row = make_row(form_, "Volume");
    volume_ = lv_slider_create(row);
    lv_slider_set_range(volume_, 0, 100);
    lv_slider_set_value(volume_, 50, LV_ANIM_OFF);
    lv_obj_set_flex_grow(volume_, 1);
    add_to_form(volume_);
    lv_obj_add_event_cb(volume_, volume_changed_cb, LV_EVENT_VALUE_CHANGED, this);
    volume_value_ = lv_label_create(row);
    lv_label_set_text(volume_value_, "50");
    lv_obj_set_width(volume_value_, 30);
}

void WidgetsScreen::make_count_row()
{
    lv_obj_t *row = make_row(form_, "Count");
    lv_obj_t *minus = make_step_button(row, "-");
    count_ = lv_spinbox_create(row);
    lv_spinbox_set_range(count_, -999, 999);
    lv_spinbox_set_digit_format(count_, 3, 0);
    lv_obj_set_width(count_, 64);
    compact(count_);
    add_to_form(count_);
    lv_obj_add_event_cb(count_, count_keys_cb, kKeyPreprocess, nullptr);
    lv_obj_add_event_cb(count_, count_changed_cb, LV_EVENT_VALUE_CHANGED, this);
    lv_obj_t *plus = make_step_button(row, "+");
    lv_obj_add_event_cb(minus, minus_cb, LV_EVENT_ALL, count_);
    lv_obj_add_event_cb(plus, plus_cb, LV_EVENT_ALL, count_);
}

void WidgetsScreen::make_color_row()
{
    lv_obj_t *row = make_row(form_, "Color");
    color_ = lv_dropdown_create(row);
    lv_dropdown_set_options(color_, kColorOptions);
    lv_dropdown_set_selected(color_, kLanguageOption);
    lv_obj_set_width(color_, 100);
    compact(color_);
    add_to_form(color_);
    lv_obj_add_event_cb(color_, color_changed_cb, LV_EVENT_VALUE_CHANGED, this);
}

void WidgetsScreen::make_sound_row()
{
    lv_obj_t *row = make_row(form_, "Sound");
    sound_ = lv_switch_create(row);
    lv_obj_add_state(sound_, LV_STATE_CHECKED);
    add_to_form(sound_);
    lv_obj_add_event_cb(sound_, sound_changed_cb, LV_EVENT_VALUE_CHANGED, this);
    sound_value_ = lv_label_create(row);
    lv_label_set_text(sound_value_, "on");
}

void WidgetsScreen::make_like_row()
{
    lv_obj_t *row = make_row(form_, "Like");
    like_ = lv_checkbox_create(row);
    lv_checkbox_set_text(like_, "I like LVGL");
    add_to_form(like_);
    lv_obj_add_event_cb(like_, like_changed_cb, LV_EVENT_VALUE_CHANGED, this);
}

WidgetsScreen::WidgetsScreen(lv_obj_t *parent) : Screen(parent)
{
    status_ = make_label(root(), "Try every widget", &lv_font_montserrat_14, kLanguageColor);
    lv_obj_set_pos(status_, 8, 0);
    make_demo_keys(root());

    // The form: a flex column that scrolls when the rows don't fit. It keeps the
    // theme's scrollbar but not its card background.
    form_ = lv_obj_create(root());
    lv_obj_set_pos(form_, 0, kFormTop);
    lv_obj_set_size(form_, kContentWidth, kHintTop - kFormTop);
    lv_obj_set_style_bg_opa(form_, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(form_, 0, 0);
    lv_obj_set_style_pad_all(form_, 2, 0);
    lv_obj_set_style_pad_row(form_, 0, 0);
    lv_obj_set_flex_flow(form_, LV_FLEX_FLOW_COLUMN);

    hint_ = make_hint(root(), kFormHint);

    group_ = lv_group_create();
    lv_group_set_wrap(group_, true);  // X on the last widget goes back to the first
    lv_obj_add_event_cb(root(), root_deleted_cb, LV_EVENT_DELETE, group_);

    // The rows, top to bottom; F/X visit their widgets in this order.
    make_name_row();
    make_buttons_row();
    make_volume_row();
    make_count_row();
    make_color_row();
    make_sound_row();
    make_like_row();
}

WidgetsScreen::~WidgetsScreen()
{
    // The page deletes its LVGL objects only after its screens are destroyed.
    // Delete this screen's now, while their callbacks can still reach `this`
    // (root_deleted_cb deletes the group first).
    lv_obj_delete(root());
}

void WidgetsScreen::on_show()
{
    // The keypad input device(s) use the form's group while the screen shows.
    // The key that opened the screen (4, ENTER, TAB) is still being handled:
    // lv_indev_wait_release keeps it from reaching the focused widget (ENTER
    // would leave the text area, 4 would be typed into it).
    for (lv_indev_t *indev = lv_indev_get_next(nullptr); indev; indev = lv_indev_get_next(indev)) {
        if (lv_indev_get_type(indev) != LV_INDEV_TYPE_KEYPAD) continue;
        previous_group_ = lv_indev_get_group(indev);
        lv_indev_set_group(indev, group_);
        lv_indev_wait_release(indev);
    }
    // Focus a widget, now from the keypad, so it gets LV_STATE_FOCUS_KEY (the
    // theme's outline) and its LV_EVENT_FOCUSED handlers run: the one that had
    // the focus, or the first time the first one (hidden widgets can't take the
    // focus, so none has it yet).
    if (lv_obj_t *focused = lv_group_get_focused(group_)) lv_group_focus_obj(focused);
    else lv_group_focus_next(group_);
    // LVGL 9.5 does not grow the drawing area of a widget that was never drawn
    // when its new state also changes its layout, as the text area's cursor
    // style does; without this the first outline would be clipped away.
    lv_obj_refresh_ext_draw_size(lv_group_get_focused(group_));
}

void WidgetsScreen::on_hide()
{
    lv_dropdown_close(color_);  // its list belongs to the LVGL screen, not to this container
    for (lv_indev_t *indev = lv_indev_get_next(nullptr); indev; indev = lv_indev_get_next(indev)) {
        if (lv_indev_get_group(indev) == group_) lv_indev_set_group(indev, previous_group_);
    }
    cp0_keyboard_set_input_context(KBD_INPUT_CONTEXT_NAVIGATION);
}

Action WidgetsScreen::handle_key(const key_item &key)
{
    // Only the app's keys; LVGL's keypad device delivers every key to the
    // focused widget as well. ESC first closes an open dropdown list: LVGL gets
    // the same ESC right after this and closes it.
    if (key.key_code == KEY_ESC) return lv_dropdown_is_open(color_) ? Action::stay() : Action::home();
    if (key.key_code == KEY_TAB) return Action::next();
    return Action::stay();
}

} // namespace app
