// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 4, widgets: a form of stock LVGL widgets with the default theme, laid
//! out with flex and driven by LVGL's own focus group and widget events:
//! lv_textarea, lv_button, lv_slider, lv_spinbox, lv_dropdown, lv_switch,
//! lv_checkbox. F/X move the focus, Z/C change the value, ENTER presses; the
//! text area takes typing.
//!
//! Stock LVGL, plus one adapter for the keyboard
//! ---------------------------------------------
//! Everything on this screen is plain LVGL:
//!   - the look is LVGL's default theme (`ui::set_theme`, called before any
//!     widget exists). The widgets get sizes, never colors; the Color row runs
//!     the theme again with another accent color and every widget follows;
//!   - the layout is flex: a scrolling column of rows, each a label and widgets;
//!   - the focus is an lv_group holding the form's widgets, which the keypad
//!     input device uses while the screen shows. The focused widget gets
//!     LV_STATE_FOCUS_KEY (the theme draws an outline) and scrolls into view;
//!   - cp0_lvgl's keypad input device sends each key to the focused widget as
//!     LV_EVENT_KEY: arrows (F/X/Z/C on the CardputerZero), ENTER, ESC,
//!     BACKSPACE ... as LVGL's keys, and the character for a key that types one.
//!     Each widget reacts the way it always does: the text area takes typing and
//!     BACKSPACE, DEL, LEFT/RIGHT, HOME/END; ENTER clicks a button, toggles the
//!     switch and the checkbox, opens the dropdown and picks an option;
//!     LEFT/RIGHT move the slider; ESC closes the dropdown;
//!   - the form reacts only to widget events (LV_EVENT_CLICKED,
//!     LV_EVENT_VALUE_CHANGED, LV_EVENT_READY), so a mouse click in the simulator
//!     window does exactly what the keys do.
//!
//! The CardputerZero keyboard needs one small adapter and one switch on top:
//!   - Moving the focus. LVGL moves it only on LV_KEY_NEXT/LV_KEY_PREV, which the
//!     keyboard never sends; it has no arrow keys either, so cp0_lvgl turns
//!     F/X/Z/C into UP/DOWN/LEFT/RIGHT. `focus_keys`, an LV_EVENT_KEY
//!     preprocess handler on every widget of the form, turns UP/DOWN into
//!     `Group::focus_prev/focus_next`, except while the dropdown's list is open
//!     (there UP/DOWN choose an option). (`count_keys` gives the spinbox's
//!     LEFT/RIGHT, which would move between digits, to its value.)
//!   - Typing. While the text area has the focus the keyboard is in text mode, so
//!     F/X/Z/C type letters instead of acting as arrows (`lvgl::set_text_input`).

use std::cell::Cell;

use crate::lvgl::ffi::lv_event_code_t;
use crate::lvgl::{
    self, color_hex, keys, Button, Checkbox, Dropdown, Event, Font, Group, Indev, Key, Label, Obj, Slider, Spinbox,
    Switch, Textarea, LV_ANIM_OFF, LV_EVENT_ALL, LV_EVENT_CLICKED, LV_EVENT_DEFOCUSED, LV_EVENT_DELETE,
    LV_EVENT_FOCUSED, LV_EVENT_KEY, LV_EVENT_LONG_PRESSED_REPEAT, LV_EVENT_PREPROCESS, LV_EVENT_READY,
    LV_EVENT_SHORT_CLICKED, LV_EVENT_VALUE_CHANGED, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_START, LV_FLEX_FLOW_COLUMN,
    LV_FLEX_FLOW_ROW, LV_INDEV_TYPE_KEYPAD, LV_KEY_DOWN, LV_KEY_LEFT, LV_KEY_RIGHT, LV_KEY_UP,
    LV_OBJ_FLAG_SCROLL_ON_FOCUS, LV_OPA_TRANSP, LV_SIZE_CONTENT, LV_STATE_CHECKED,
};
use crate::ui::{
    keep, make_demo_keys, make_hint, make_label, set_theme, Action, Screen, ScreenBase, CONTENT_WIDTH, HINT_TOP,
    LANGUAGE_COLOR,
};

const FORM_TOP: i32 = 18; // below the status line
const LABEL_WIDTH: i32 = 62; // the column of row labels
const MAX_NAME: u32 = 24;
const FORM_HINT: &str = "F/X move  Z/C change  ENTER press";
const TYPING_HINT: &str = "type a name  ENTER next";

// The Color row: each template's language and GitHub's color for it, in the
// dropdown's order. This template starts on its own language, Rust.
const COLOR_OPTIONS: &str = "Rust\nZig\nOCaml\nC++";
const COLORS: [u32; 4] = [0xDEA584, 0xEC915C, 0xEF7A08, 0xF34B7D];
const LANGUAGE_OPTION: u32 = 0;

const KEY_PREPROCESS: lv_event_code_t = LV_EVENT_KEY | LV_EVENT_PREPROCESS;

/// One row of the form: a transparent flex row holding a fixed-width label;
/// the caller adds the row's widgets after it.
fn make_row(form: Obj, text: &str) -> Obj {
    let row = Obj::create(form);
    row.remove_style_all(); // layout only: no background, border or padding
    row.set_size(lvgl::lv_pct(100), LV_SIZE_CONTENT);
    row.set_flex_flow(LV_FLEX_FLOW_ROW);
    row.set_flex_align(LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    row.set_style_pad_all(4, 0); // room for the theme's focus outline around the widgets
    row.set_style_pad_column(6, 0);
    let label = Label::create(row);
    label.set_text(text);
    label.set_width(LABEL_WIDTH);
    row
}

/// The default theme pads widgets for bigger screens. On 320 x 150 the form
/// trims the vertical padding of the taller widgets to fit more rows.
fn compact(widget: Obj) {
    widget.set_style_pad_ver(4, 0);
}

fn make_button(parent: Obj, text: &str) -> Button {
    let button = Button::create(parent);
    compact(*button);
    let label = Label::create(*button);
    label.set_text(text);
    label.center();
    button
}

/// The adapter: F/X (UP/DOWN) move the focus to the previous/next widget.
fn focus_keys(event: &Event) {
    let key = event.key();
    if key != LV_KEY_UP && key != LV_KEY_DOWN {
        return;
    }
    let widget = event.target();
    if Dropdown::cast(widget).is_some_and(|dropdown| dropdown.is_open()) {
        return;
    }
    if let Some(group) = widget.group() {
        if key == LV_KEY_UP {
            group.focus_prev();
        } else {
            group.focus_next();
        }
    }
    event.stop_processing(); // the widget itself never sees the key
}

/// Every focusable widget: into the group (F/X order is the order of these
/// calls), the adapter for F/X, and scrolled into view when it gets the focus.
fn add_to_form(group: Group, widget: Obj) {
    group.add_obj(widget);
    widget.on_event_fn(KEY_PREPROCESS, focus_keys);
    widget.add_flag(LV_OBJ_FLAG_SCROLL_ON_FOCUS);
}

/// Z/C (LEFT/RIGHT) step the spinbox's value; nothing else edits it (typed
/// characters included: the spinbox is a text area underneath).
fn count_keys(count: Spinbox, event: &Event) {
    let key = event.key();
    if key == LV_KEY_UP || key == LV_KEY_DOWN {
        return; // focus moves
    }
    if key == LV_KEY_LEFT {
        count.decrement();
    } else if key == LV_KEY_RIGHT {
        count.increment();
    }
    event.stop_processing();
}

/// ENTER in the one-line text area: on to the next widget. The ENTER key is still
/// down; waiting for its release keeps it from clicking the newly focused button.
fn name_ready(event: &Event) {
    if let Some(group) = event.target().group() {
        group.focus_next();
    }
    if let Some(keypad) = Indev::active() {
        keypad.wait_release();
    }
}

/// The spinbox's -/+ buttons, as in LVGL's spinbox example: a click steps once,
/// holding the mouse button repeats.
fn is_step_event(event: &Event) -> bool {
    let code = event.code();
    code == LV_EVENT_SHORT_CLICKED || code == LV_EVENT_LONG_PRESSED_REPEAT
}

fn step_down(count: Spinbox, event: &Event) {
    if is_step_event(event) {
        count.decrement();
    }
}

fn step_up(count: Spinbox, event: &Event) {
    if is_step_event(event) {
        count.increment();
    }
}

/// The -/+ buttons are for the mouse: Z/C do the same from the keyboard. Keep
/// them out of every focus group (`Button::create` adds a button to the default
/// group, if there is one).
fn make_step_button(row: Obj, text: &str) -> Button {
    let button = make_button(row, text);
    button.remove_from_group();
    button
}

// The rows, built before the screen exists: each returns the widgets the
// screen's handlers use (`WidgetsScreen::connect` hooks those up).

fn make_name_row(form: Obj, group: Group) -> Textarea {
    let row = make_row(form, "Name");
    let name = Textarea::create(row);
    name.set_one_line(true);
    name.set_placeholder_text("your name");
    name.set_max_length(MAX_NAME);
    name.set_flex_grow(1);
    compact(*name);
    add_to_form(group, name.obj());
    name.on_event_fn(LV_EVENT_READY, name_ready);
    name
}

struct Buttons {
    hello: Button,
    add_one: Button,
}

fn make_buttons_row(form: Obj, group: Group) -> Buttons {
    let row = make_row(form, "Buttons");
    let hello = make_button(row, "Say hello");
    add_to_form(group, hello.obj());
    let add_one = make_button(row, "Count +1");
    add_to_form(group, add_one.obj());
    Buttons { hello, add_one }
}

fn make_volume_row(form: Obj, group: Group) -> (Slider, Label) {
    let row = make_row(form, "Volume");
    let volume = Slider::create(row);
    volume.set_range(0, 100);
    volume.set_value(50, LV_ANIM_OFF);
    volume.set_flex_grow(1);
    add_to_form(group, volume.obj());
    let value = Label::create(row);
    value.set_text("50");
    value.set_width(30);
    (volume, value)
}

fn make_count_row(form: Obj, group: Group) -> Spinbox {
    let row = make_row(form, "Count");
    let minus = make_step_button(row, "-");
    let count = Spinbox::create(row);
    count.set_range(-999, 999);
    count.set_digit_format(3, 0);
    count.set_width(64);
    compact(*count);
    add_to_form(group, count.obj());
    count.on_event_with(KEY_PREPROCESS, count, count_keys);
    let plus = make_step_button(row, "+");
    minus.on_event_with(LV_EVENT_ALL, count, step_down);
    plus.on_event_with(LV_EVENT_ALL, count, step_up);
    count
}

fn make_color_row(form: Obj, group: Group) -> Dropdown {
    let row = make_row(form, "Color");
    let color = Dropdown::create(row);
    color.set_options(COLOR_OPTIONS);
    color.set_selected(LANGUAGE_OPTION);
    color.set_width(100);
    compact(*color);
    add_to_form(group, color.obj());
    color
}

fn make_sound_row(form: Obj, group: Group) -> (Switch, Label) {
    let row = make_row(form, "Sound");
    let sound = Switch::create(row);
    sound.add_state(LV_STATE_CHECKED);
    add_to_form(group, sound.obj());
    let value = Label::create(row);
    value.set_text("on");
    (sound, value)
}

fn make_like_row(form: Obj, group: Group) -> Checkbox {
    let row = make_row(form, "Like");
    let like = Checkbox::create(row);
    like.set_text("I like LVGL");
    add_to_form(group, like.obj());
    like
}

pub struct WidgetsScreen {
    base: ScreenBase,
    group: Group,                        // the form's focusable widgets, in F/X order
    previous_group: Cell<Option<Group>>, // the keypad's group before this screen showed
    status: Label,
    hint: Label,
    name: Textarea,
    buttons: Buttons,
    volume: Slider,
    volume_value: Label,
    count: Spinbox,
    color: Dropdown,
    sound: Switch,
    sound_value: Label,
    like: Checkbox,
}

impl WidgetsScreen {
    fn set_status(&self, text: &str) {
        self.status.set_text(text);
    }

    /// The text area has the focus: keys type text, and the hint says so.
    fn set_typing(&self, typing: bool) {
        self.hint.set_text(if typing { TYPING_HINT } else { FORM_HINT });
        if self.base.is_shown() {
            lvgl::set_text_input(typing);
        }
    }

    // Widget events: LVGL calls them when the widgets change, by key or by click.

    fn name_focus(&self, event: &Event) {
        self.set_typing(event.code() == LV_EVENT_FOCUSED);
    }

    fn hello_clicked(&self) {
        let text = self.name.text();
        let name = text.trim_matches([' ', '\t']);
        self.set_status(&format!("Hello, {}!", if name.is_empty() { "stranger" } else { name }));
    }

    fn add_one_clicked(&self) {
        self.count.set_value(self.count.value() + 1); // the spinbox reports the change
    }

    fn volume_changed(&self) {
        let value = self.volume.value().to_string();
        self.volume_value.set_text(&value);
        self.set_status(&format!("Volume {value}"));
    }

    fn count_changed(&self) {
        self.set_status(&format!("Count {}", self.count.value()));
    }

    fn color_changed(&self) {
        let color = COLORS[self.color.selected() as usize];
        set_theme(color); // every themed widget in the app takes the new accent color
        self.status.set_style_text_color(color_hex(color), 0);
        self.set_status(&format!("Color {}", self.color.selected_str()));
    }

    fn sound_changed(&self) {
        let state = if self.sound.has_state(LV_STATE_CHECKED) { "on" } else { "off" };
        self.sound_value.set_text(state);
        self.set_status(&format!("Sound {state}"));
    }

    fn like_changed(&self) {
        self.set_status(if self.like.has_state(LV_STATE_CHECKED) { "Thanks!" } else { "Oh no" });
    }

    /// Hook the handlers up; needs the screen's final, `'static` address.
    fn connect(&'static self) {
        self.name.on_event_with(LV_EVENT_FOCUSED, self, Self::name_focus);
        self.name.on_event_with(LV_EVENT_DEFOCUSED, self, Self::name_focus);
        self.buttons.hello.on_event(LV_EVENT_CLICKED, self, Self::hello_clicked);
        self.buttons.add_one.on_event(LV_EVENT_CLICKED, self, Self::add_one_clicked);
        self.volume.on_event(LV_EVENT_VALUE_CHANGED, self, Self::volume_changed);
        self.count.on_event(LV_EVENT_VALUE_CHANGED, self, Self::count_changed);
        self.color.on_event(LV_EVENT_VALUE_CHANGED, self, Self::color_changed);
        self.sound.on_event(LV_EVENT_VALUE_CHANGED, self, Self::sound_changed);
        self.like.on_event(LV_EVENT_VALUE_CHANGED, self, Self::like_changed);
    }

    pub fn new(parent: Obj) -> &'static WidgetsScreen {
        let base = ScreenBase::new(parent);
        let root = base.root();
        let status = make_label(root, "Try every widget", Font::montserrat_14(), LANGUAGE_COLOR);
        status.set_pos(8, 0);
        make_demo_keys(root);

        // The form: a flex column that scrolls when the rows don't fit. It keeps the
        // theme's scrollbar but not its card background.
        let form = Obj::create(root);
        form.set_pos(0, FORM_TOP);
        form.set_size(CONTENT_WIDTH, HINT_TOP - FORM_TOP);
        form.set_style_bg_opa(LV_OPA_TRANSP, 0);
        form.set_style_border_width(0, 0);
        form.set_style_pad_all(2, 0);
        form.set_style_pad_row(0, 0);
        form.set_flex_flow(LV_FLEX_FLOW_COLUMN);

        let hint = make_hint(root, FORM_HINT);

        let group = Group::create();
        group.set_wrap(true); // X on the last widget goes back to the first

        // The root object gets LV_EVENT_DELETE before its children are deleted.
        // Deleting the group then means that deleting the focused widget moves no
        // focus, so no focus handler runs on widgets that are already gone.
        root.on_event_with(LV_EVENT_DELETE, group, |group, _| group.delete());

        // The rows, top to bottom; F/X visit their widgets in this order.
        let name = make_name_row(form, group);
        let buttons = make_buttons_row(form, group);
        let (volume, volume_value) = make_volume_row(form, group);
        let count = make_count_row(form, group);
        let color = make_color_row(form, group);
        let (sound, sound_value) = make_sound_row(form, group);
        let like = make_like_row(form, group);

        let screen = keep(WidgetsScreen {
            base,
            group,
            previous_group: Cell::new(None),
            status,
            hint,
            name,
            buttons,
            volume,
            volume_value,
            count,
            color,
            sound,
            sound_value,
            like,
        });
        screen.connect();
        screen
    }
}

impl Screen for WidgetsScreen {
    fn base(&self) -> &ScreenBase {
        &self.base
    }

    fn title(&self) -> String {
        "Widgets".to_string()
    }

    fn on_show(&self) {
        // The keypad input device(s) use the form's group while the screen shows.
        // The key that opened the screen (4, ENTER, TAB) is still being handled:
        // wait_release keeps it from reaching the focused widget (ENTER would
        // leave the text area, 4 would be typed into it).
        for indev in Indev::all().filter(|indev| indev.indev_type() == LV_INDEV_TYPE_KEYPAD) {
            self.previous_group.set(indev.group());
            indev.set_group(Some(self.group));
            indev.wait_release();
        }
        // Focus a widget, now from the keypad, so it gets LV_STATE_FOCUS_KEY (the
        // theme's outline) and its LV_EVENT_FOCUSED handlers run: the one that had
        // the focus, or the first time the first one (hidden widgets can't take the
        // focus, so none has it yet).
        match self.group.focused() {
            Some(focused) => focused.focus(),
            None => self.group.focus_next(),
        }
        // LVGL 9.5 does not grow the drawing area of a widget that was never drawn
        // when its new state also changes its layout, as the text area's cursor
        // style does; without this the first outline would be clipped away.
        if let Some(focused) = self.group.focused() {
            focused.refresh_ext_draw_size();
        }
    }

    fn on_hide(&self) {
        self.color.close(); // its list belongs to the LVGL screen, not to this container
        for indev in Indev::all().filter(|indev| indev.group() == Some(self.group)) {
            indev.set_group(self.previous_group.get());
        }
        lvgl::set_text_input(false);
    }

    fn handle_key(&self, key: &Key) -> Action {
        // Only the app's keys; LVGL's keypad device delivers every key to the
        // focused widget as well. ESC first closes an open dropdown list: LVGL gets
        // the same ESC right after this and closes it.
        match key.code {
            keys::ESC if self.color.is_open() => Action::Stay,
            keys::ESC => Action::Home,
            keys::TAB => Action::Next,
            _ => Action::Stay,
        }
    }
}
