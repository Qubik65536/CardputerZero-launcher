// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 4, widgets: a small form of real LVGL widgets (lv_textarea, lv_button,
//! lv_slider, a -/+ counter, lv_roller, lv_switch) in an lv_group. F/X move the
//! focus, Z/C change the value, ENTER presses; the text field takes typing.
//!
//! How keys reach the widgets
//! --------------------------
//! cp0_lvgl delivers every key twice: first to the app's key callback
//! (`App::on_key`: Linux key code + the text it types), then through LVGL's
//! keypad input device to the focused object of the page's lv_group, as
//! LV_EVENT_KEY. That second path cannot drive a form on the CardputerZero: the
//! keyboard has no arrow keys (F/X/Z/C turn into arrows, so they could not be
//! typed into the text field), letters arrive as key codes rather than
//! characters, and LVGL only moves the focus on LV_KEY_NEXT/LV_KEY_PREV, which
//! the keyboard never sends.
//!
//! So while this screen shows it turns that path off
//! (`lvgl::set_keypad_intercept`) and handles the keys itself, using LVGL's own
//! machinery for the rest:
//!   - the widgets sit in an lv_group: F/X call focus_prev/focus_next, and the
//!     focused widget gets LV_STATE_FOCUSED, which its styles react to;
//!   - Z/C and ENTER set the focused widget's value through its API and send the
//!     event LVGL itself would send (LV_EVENT_VALUE_CHANGED, LV_EVENT_CLICKED);
//!   - the form reacts to those events only, so a mouse click in the simulator
//!     window (or a touch screen) works the same way as the keys;
//!   - typed text goes into the lv_textarea with add_text, and the keyboard is
//!     in text mode while the text field has the focus.
//!
//! The same works on the device and in the simulator.

use std::cell::Cell;

use crate::lvgl::{
    self, color_hex, keys, Button, Font, Group, Key, Label, Obj, Roller, Slider, Switch, Textarea, Timer,
    LV_ANIM_OFF, LV_EVENT_CLICKED, LV_EVENT_DELETE, LV_EVENT_VALUE_CHANGED, LV_OBJ_FLAG_HIDDEN, LV_OPA_COVER, LV_OPA_TRANSP,
    LV_PART_CURSOR, LV_PART_INDICATOR, LV_PART_KNOB, LV_PART_SELECTED, LV_PART_TEXTAREA_PLACEHOLDER,
    LV_ROLLER_MODE_NORMAL, LV_STATE_CHECKED, LV_STATE_FOCUSED, LV_STATE_PRESSED, LV_TEXT_ALIGN_CENTER,
};
use crate::ui::{
    direction, keep, make_demo_keys, make_hint, make_label, make_panel, typed_text, Action, Direction, Screen,
    ScreenBase, BACKGROUND_COLOR, FRAME_MS, LANGUAGE, LANGUAGE_COLOR, MUTED_COLOR, TEXT_COLOR,
};

const FIELD: u32 = 0x080A0E;
const BORDER: u32 = 0x3C4652;
const FACE: u32 = 0x1C222A;

// The form's rows, top to bottom; the status line sits above them.
const ROW_LABELS: [&str; 6] = ["Name", "Button", "Volume", "Count", "Color", "Sound"];
const NAME_ROW: i32 = 0;
const BUTTON_ROW: i32 = 1;
const VOLUME_ROW: i32 = 2;
const COUNT_ROW: i32 = 3;
const COLOR_ROW: i32 = 4;
const SOUND_ROW: i32 = 5;
const ROWS_TOP: i32 = 18;
const ROW_HEIGHT: i32 = 18;
const WIDGET_LEFT: i32 = 72; // labels on the left, widgets from here
const WIDGET_WIDTH: i32 = 242;
const SLIDER_WIDTH: i32 = 176;
const VOLUME_STEP: i32 = 5;
const MAX_NAME: u32 = 24;
const PRESS_MS: u32 = 10 * FRAME_MS; // how long the button shows as pressed

struct Choice {
    name: &'static str,
    color: u32,
}

/// The chooser's options: each template language and GitHub's color for it.
const CHOICES: [Choice; 4] = [
    Choice { name: "Rust", color: 0xDEA584 },
    Choice { name: "Zig", color: 0xEC915C },
    Choice { name: "OCaml", color: 0xEF7A08 },
    Choice { name: "C++", color: 0xF34B7D },
];

fn row_top(row: i32) -> i32 {
    ROWS_TOP + row * ROW_HEIGHT
}

fn default_choice() -> u32 {
    CHOICES.iter().position(|choice| choice.name == LANGUAGE).unwrap_or(0) as u32
}

// The form's widgets are styled from scratch (no theme), flat like the rest of the app.
fn style_box(obj: Obj, background: u32) {
    obj.set_style_bg_color(color_hex(background), 0);
    obj.set_style_bg_opa(LV_OPA_COVER, 0);
    obj.set_style_border_width(1, 0);
    obj.set_style_border_color(color_hex(BORDER), 0);
    obj.set_style_text_font(Font::montserrat_14(), 0);
    obj.set_style_text_color(color_hex(TEXT_COLOR), 0);
}

fn make_box_button(parent: Obj, text: &str, x: i32, y: i32, width: i32) -> Button {
    let button = Button::create(parent);
    button.remove_style_all();
    style_box(*button, FACE);
    button.set_pos(x, y);
    button.set_size(width, ROW_HEIGHT);
    let label = Label::create(*button);
    label.set_text(text);
    label.center();
    button
}

fn make_name(parent: Obj, y: i32) -> Textarea {
    let name = Textarea::create(parent);
    name.remove_style_all();
    style_box(*name, FIELD);
    name.set_one_line(true);
    name.set_placeholder_text("your name");
    name.set_max_length(MAX_NAME);
    name.set_style_pad_hor(4, 0);
    name.set_pos(WIDGET_LEFT, y);
    name.set_size(WIDGET_WIDTH, ROW_HEIGHT);
    name.set_style_text_color(color_hex(MUTED_COLOR), LV_PART_TEXTAREA_PLACEHOLDER);
    // An empty focused field shows just the cursor: a solid block that does not blink.
    name.set_style_text_opa(LV_OPA_TRANSP, LV_PART_TEXTAREA_PLACEHOLDER | LV_STATE_FOCUSED);
    name.set_style_bg_opa(LV_OPA_COVER, LV_PART_CURSOR | LV_STATE_FOCUSED);
    name.set_style_pad_right(4, LV_PART_CURSOR);
    name.set_style_anim_duration(0, LV_PART_CURSOR);
    name
}

fn make_button(parent: Obj, y: i32) -> Button {
    let button = make_box_button(parent, "Say hello", WIDGET_LEFT, y, 120);
    button.set_style_text_color(color_hex(BACKGROUND_COLOR), LV_STATE_PRESSED);
    button
}

struct Volume {
    slider: Slider,
    value: Label,
}

fn make_volume(parent: Obj, y: i32) -> Volume {
    let slider = Slider::create(parent);
    slider.remove_style_all();
    slider.set_pos(WIDGET_LEFT, y + 7);
    slider.set_size(SLIDER_WIDTH, 4);
    slider.set_range(0, 100);
    slider.set_value(50, LV_ANIM_OFF);
    slider.set_style_bg_color(color_hex(BORDER), 0);
    slider.set_style_bg_opa(LV_OPA_COVER, 0);
    slider.set_style_bg_opa(LV_OPA_COVER, LV_PART_INDICATOR);
    // The knob is the 4 px track height grown by its padding: 6 x 14.
    slider.set_style_bg_color(color_hex(MUTED_COLOR), LV_PART_KNOB);
    slider.set_style_bg_color(color_hex(TEXT_COLOR), LV_PART_KNOB | LV_STATE_FOCUSED);
    slider.set_style_bg_opa(LV_OPA_COVER, LV_PART_KNOB);
    slider.set_style_pad_hor(1, LV_PART_KNOB);
    slider.set_style_pad_ver(5, LV_PART_KNOB);

    let value = make_label(parent, "50", Font::montserrat_14(), TEXT_COLOR);
    value.set_pos(WIDGET_LEFT + SLIDER_WIDTH + 12, y + 1);
    Volume { slider, value }
}

/// One focusable container holding "-", the value and "+".
struct Counter {
    panel: Obj,
    minus: Button,
    plus: Button,
    value: Label,
}

fn make_counter(parent: Obj, y: i32) -> Counter {
    let panel = make_panel(parent, WIDGET_LEFT, y, 108, ROW_HEIGHT, BACKGROUND_COLOR, LV_OPA_TRANSP);
    let minus = make_box_button(panel, "-", 0, 0, 24);
    let plus = make_box_button(panel, "+", 84, 0, 24);
    let value = make_label(panel, "0", Font::montserrat_14(), TEXT_COLOR);
    value.set_width(60);
    value.set_style_text_align(LV_TEXT_ALIGN_CENTER, 0);
    value.set_pos(24, 1);
    Counter { panel, minus, plus, value }
}

/// "< Rust >" and a color swatch.
struct Chooser {
    left: Label,
    roller: Roller,
    right: Label,
    swatch: Obj,
}

fn make_chooser(parent: Obj, y: i32) -> Chooser {
    let left = make_label(parent, "<", Font::montserrat_14(), MUTED_COLOR);
    left.set_pos(WIDGET_LEFT, y + 1);
    let options: Vec<&str> = CHOICES.iter().map(|choice| choice.name).collect();
    let roller = Roller::create(parent);
    roller.remove_style_all();
    roller.set_style_text_font(Font::montserrat_14(), 0);
    roller.set_style_text_font(Font::montserrat_14(), LV_PART_SELECTED);
    roller.set_style_text_align(LV_TEXT_ALIGN_CENTER, 0);
    roller.set_options(&options.join("\n"), LV_ROLLER_MODE_NORMAL);
    roller.set_visible_row_count(1);
    roller.set_selected(default_choice(), LV_ANIM_OFF);
    roller.set_pos(WIDGET_LEFT + 12, y + 1);
    roller.set_width(56);
    let right = make_label(parent, ">", Font::montserrat_14(), MUTED_COLOR);
    right.set_pos(WIDGET_LEFT + 72, y + 1);
    let swatch = make_panel(parent, WIDGET_LEFT + 88, y + 2, 14, ROW_HEIGHT - 4, LANGUAGE_COLOR, LV_OPA_COVER);
    Chooser { left, roller, right, swatch }
}

struct Sound {
    switch: Switch,
    value: Label,
}

fn make_switch(parent: Obj, y: i32) -> Sound {
    let switch = Switch::create(parent);
    switch.remove_style_all();
    switch.set_pos(WIDGET_LEFT, y + 2);
    switch.set_size(32, ROW_HEIGHT - 4);
    switch.set_style_bg_color(color_hex(BORDER), 0);
    switch.set_style_bg_opa(LV_OPA_COVER, 0);
    switch.set_style_bg_opa(LV_OPA_COVER, LV_PART_INDICATOR | LV_STATE_CHECKED);
    switch.set_style_bg_color(color_hex(TEXT_COLOR), LV_PART_KNOB);
    switch.set_style_bg_opa(LV_OPA_COVER, LV_PART_KNOB);
    switch.set_style_pad_all(-2, LV_PART_KNOB);
    switch.set_style_outline_color(color_hex(TEXT_COLOR), LV_STATE_FOCUSED);
    switch.set_style_outline_width(1, LV_STATE_FOCUSED);
    switch.set_style_outline_pad(2, LV_STATE_FOCUSED);
    switch.add_state(LV_STATE_CHECKED);

    let value = make_label(parent, "on", Font::montserrat_14(), TEXT_COLOR);
    value.set_pos(WIDGET_LEFT + 40, y + 1);
    Sound { switch, value }
}

/// The accent bar and label at the left of each row.
fn make_row_markers(parent: Obj) -> (Vec<Obj>, Vec<Label>) {
    let mut bars = Vec::new();
    let mut labels = Vec::new();
    for (row, text) in ROW_LABELS.iter().enumerate() {
        let y = row_top(row as i32);
        bars.push(make_panel(parent, 0, y, 3, ROW_HEIGHT, LANGUAGE_COLOR, LV_OPA_COVER));
        let label = make_label(parent, text, Font::montserrat_14(), MUTED_COLOR);
        label.set_pos(8, y + 1);
        labels.push(label);
    }
    (bars, labels)
}

pub struct WidgetsScreen {
    base: ScreenBase,
    group: Group,
    bars: Vec<Obj>,
    labels: Vec<Label>,
    focusables: Vec<Obj>, // the focusable object of each row
    name: Textarea,
    button: Button,
    volume: Volume,
    counter: Counter,
    chooser: Chooser,
    sound: Sound,
    status: Label,
    hint: Label,
    release_timer: Cell<Option<Timer>>,
    count: Cell<i32>,
}

impl WidgetsScreen {
    fn focused(&self) -> Option<Obj> {
        self.group.focused()
    }

    fn accent(&self) -> u32 {
        CHOICES[self.chooser.roller.selected() as usize].color
    }

    fn set_status(&self, text: &str) {
        self.status.set_text(text);
    }

    fn set_count(&self, count: i32, status: &str) {
        self.count.set(count);
        self.counter.value.set_text(&count.to_string());
        self.set_status(status);
    }

    /// The row markers that are not LVGL focus styles: accent bar, label colors,
    /// counter and chooser decorations, the hint, and the keyboard mode.
    fn refresh_focus(&self) {
        let focused = self.focused();
        let accent = color_hex(self.accent());
        for ((bar, label), widget) in self.bars.iter().zip(&self.labels).zip(&self.focusables) {
            let is_focused = Some(*widget) == focused;
            if is_focused {
                bar.remove_flag(LV_OBJ_FLAG_HIDDEN);
            } else {
                bar.add_flag(LV_OBJ_FLAG_HIDDEN);
            }
            label.set_style_text_color(if is_focused { accent } else { color_hex(MUTED_COLOR) }, 0);
        }
        let counter_border = if focused == Some(self.counter.panel) { accent } else { color_hex(BORDER) };
        self.counter.minus.set_style_border_color(counter_border, 0);
        self.counter.plus.set_style_border_color(counter_border, 0);
        let arrows = if focused == Some(self.chooser.roller.obj()) { accent } else { color_hex(MUTED_COLOR) };
        self.chooser.left.set_style_text_color(arrows, 0);
        self.chooser.right.set_style_text_color(arrows, 0);

        let typing = focused == Some(self.name.obj());
        self.hint.set_text(if typing { "type a name  ENTER next" } else { "F/X move  Z/C change  ENTER press" });
        if self.base.is_shown() {
            lvgl::set_text_input(typing);
        }
    }

    /// The accent color is whatever the chooser picked; every focus style uses it.
    fn apply_accent(&self) {
        let color = color_hex(self.accent());
        self.name.set_style_border_color(color, LV_STATE_FOCUSED);
        self.name.set_style_bg_color(color, LV_PART_CURSOR | LV_STATE_FOCUSED);
        self.button.set_style_border_color(color, LV_STATE_FOCUSED);
        self.button.set_style_bg_color(color, LV_STATE_PRESSED);
        self.volume.slider.set_style_bg_color(color, LV_PART_INDICATOR);
        self.chooser.roller.set_style_text_color(color, LV_PART_SELECTED);
        self.chooser.swatch.set_style_bg_color(color, 0);
        self.sound.switch.set_style_bg_color(color, LV_PART_INDICATOR | LV_STATE_CHECKED);
        self.status.set_style_text_color(color, 0);
        self.refresh_focus();
    }

    // Event handlers: LVGL calls them when the widgets change, whether by key or by click.

    fn button_clicked(&self) {
        let text = self.name.text();
        let name = text.trim_matches([' ', '\t']);
        self.set_status(&format!("Hello, {}!", if name.is_empty() { "stranger" } else { name }));
    }

    fn button_released(&self) {
        self.button.remove_state(LV_STATE_PRESSED);
        if let Some(timer) = self.release_timer.get() {
            timer.pause();
        }
    }

    fn volume_changed(&self) {
        let value = self.volume.slider.value().to_string();
        self.volume.value.set_text(&value);
        self.set_status(&format!("Volume {value}"));
    }

    fn minus_clicked(&self) {
        let count = self.count.get() - 1;
        self.set_count(count, &format!("Count {count}"));
    }

    fn plus_clicked(&self) {
        let count = self.count.get() + 1;
        self.set_count(count, &format!("Count {count}"));
    }

    fn choice_changed(&self) {
        self.apply_accent();
        self.set_status(&format!("Color {}", CHOICES[self.chooser.roller.selected() as usize].name));
    }

    fn sound_changed(&self) {
        let state = if self.sound.switch.has_state(LV_STATE_CHECKED) { "on" } else { "off" };
        self.sound.value.set_text(state);
        self.set_status(&format!("Sound {state}"));
    }

    /// The app is ending and LVGL is deleting the screen. Delete the group
    /// first: otherwise deleting the focused widget moves the focus and calls
    /// refresh_focus on widgets that are already gone.
    fn deleting(&self) {
        self.group.delete();
    }

    /// Hook the handlers up; needs the screen's final, `'static` address.
    fn connect(&'static self) {
        self.base.root().on_event(LV_EVENT_DELETE, self, Self::deleting);
        self.button.on_event(LV_EVENT_CLICKED, self, Self::button_clicked);
        self.volume.slider.on_event(LV_EVENT_VALUE_CHANGED, self, Self::volume_changed);
        self.counter.minus.on_event(LV_EVENT_CLICKED, self, Self::minus_clicked);
        self.counter.plus.on_event(LV_EVENT_CLICKED, self, Self::plus_clicked);
        self.chooser.roller.on_event(LV_EVENT_VALUE_CHANGED, self, Self::choice_changed);
        self.sound.switch.on_event(LV_EVENT_VALUE_CHANGED, self, Self::sound_changed);
        self.group.on_focus(self, Self::refresh_focus);
        // How long ENTER shows the button pressed: started by press_button.
        let timer = Timer::create(PRESS_MS, self, Self::button_released);
        timer.pause();
        self.release_timer.set(Some(timer));
    }

    pub fn new(parent: Obj) -> &'static WidgetsScreen {
        let base = ScreenBase::new(parent);
        let root = base.root();
        let status = make_label(root, "Try every widget", Font::montserrat_14(), LANGUAGE_COLOR);
        status.set_pos(8, 0);
        make_demo_keys(root);
        let (bars, labels) = make_row_markers(root);
        let name = make_name(root, row_top(NAME_ROW));
        let button = make_button(root, row_top(BUTTON_ROW));
        let volume = make_volume(root, row_top(VOLUME_ROW));
        let counter = make_counter(root, row_top(COUNT_ROW));
        let chooser = make_chooser(root, row_top(COLOR_ROW));
        let sound = make_switch(root, row_top(SOUND_ROW));
        let focusables =
            vec![name.obj(), button.obj(), volume.slider.obj(), counter.panel, chooser.roller.obj(), sound.switch.obj()];
        let hint = make_hint(root, "");

        let group = Group::create();
        group.set_wrap(true);
        for widget in &focusables {
            group.add_obj(*widget);
        }
        name.focus();
        let screen = keep(WidgetsScreen {
            base,
            group,
            bars,
            labels,
            focusables,
            name,
            button,
            volume,
            counter,
            chooser,
            sound,
            status,
            hint,
            release_timer: Cell::new(None),
            count: Cell::new(0),
        });
        screen.connect();
        screen.apply_accent();
        screen
    }

    /// ENTER on the button: show it pressed for a moment and click it.
    fn press_button(&self) {
        self.button.add_state(LV_STATE_PRESSED);
        if let Some(timer) = self.release_timer.get() {
            timer.reset();
            timer.resume();
        }
        self.button.send_event(LV_EVENT_CLICKED);
    }

    /// Z/C (or left/right): step the focused widget's value.
    fn change(&self, step: i32) {
        let focused = self.focused();
        if focused == Some(self.volume.slider.obj()) {
            let value = self.volume.slider.value() + step * VOLUME_STEP;
            self.volume.slider.set_value(value.clamp(0, 100), LV_ANIM_OFF);
            self.volume.slider.send_event(LV_EVENT_VALUE_CHANGED);
        } else if focused == Some(self.counter.panel) {
            let button = if step < 0 { self.counter.minus } else { self.counter.plus };
            button.send_event(LV_EVENT_CLICKED);
        } else if focused == Some(self.chooser.roller.obj()) {
            let count = CHOICES.len() as i32;
            let choice = (self.chooser.roller.selected() as i32 + count + step) % count;
            self.chooser.roller.set_selected(choice as u32, LV_ANIM_OFF);
            self.chooser.roller.send_event(LV_EVENT_VALUE_CHANGED);
        } else if focused == Some(self.sound.switch.obj()) {
            let switch = self.sound.switch;
            switch.set_state(LV_STATE_CHECKED, !switch.has_state(LV_STATE_CHECKED));
            switch.send_event(LV_EVENT_VALUE_CHANGED);
        }
    }

    /// ENTER or SPACE on the focused widget.
    fn activate(&self) {
        let focused = self.focused();
        if focused == Some(self.button.obj()) {
            self.press_button();
        } else if focused == Some(self.counter.panel) {
            self.set_count(0, "Count reset");
        } else if focused == Some(self.chooser.roller.obj()) || focused == Some(self.sound.switch.obj()) {
            self.change(1);
        }
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
        // Keys come only through App::on_key while the form shows (see the top of this file).
        lvgl::set_keypad_intercept(true);
        self.refresh_focus();
    }

    fn on_hide(&self) {
        lvgl::set_keypad_intercept(false);
        lvgl::set_text_input(false);
    }

    fn handle_key(&self, key: &Key) -> Action {
        match key.code {
            keys::ESC => return Action::Home,
            keys::TAB => return Action::Next,
            // Real arrow keys always move the focus, even out of the text field.
            keys::UP => {
                self.group.focus_prev();
                return Action::Stay;
            }
            keys::DOWN => {
                self.group.focus_next();
                return Action::Stay;
            }
            _ => {}
        }
        if self.focused() == Some(self.name.obj()) {
            // In the text field F/X/Z/C are letters; ENTER moves on.
            if key.code == keys::ENTER {
                self.group.focus_next();
            } else if key.code == keys::BACKSPACE {
                self.name.delete_char();
            } else if let Some(text) = typed_text(key) {
                self.name.add_text(text);
            }
            return Action::Stay;
        }
        match direction(key.code) {
            Some(Direction::Up) => self.group.focus_prev(),
            Some(Direction::Down) => self.group.focus_next(),
            Some(Direction::Left) => self.change(-1),
            Some(Direction::Right) => self.change(1),
            None => {
                if key.code == keys::ENTER || key.code == keys::SPACE {
                    self.activate();
                }
            }
        }
        Action::Stay
    }
}
