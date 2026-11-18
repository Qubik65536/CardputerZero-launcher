// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 4, widgets: a small form with a text field, two buttons, a slider, a counter, a
//! chooser and a switch, drawn by hand on the framebuffer. One widget has the focus;
//! F/X move it, Z/C change the value, ENTER presses. The text field takes typing.

use crate::display::{rgb, Display, CHAR_HEIGHT, CHAR_WIDTH};
use crate::input::{self, keys, Direction, KeyEvent};
use crate::ui::{self, Action, LANGUAGE, MUTED, TEXT};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Widget {
    Name,
    Button,
    AddOne,
    Volume,
    Count,
    Color,
    Sound,
}

/// The order F/X move the focus in. The two buttons share the "Button" row.
const FOCUS_ORDER: [Widget; 7] =
    [Widget::Name, Widget::Button, Widget::AddOne, Widget::Volume, Widget::Count, Widget::Color, Widget::Sound];

/// The form's rows, top to bottom, with each row's label.
const ROWS: [(Widget, &str); 6] = [
    (Widget::Name, "Name"),
    (Widget::Button, "Button"),
    (Widget::Volume, "Volume"),
    (Widget::Count, "Count"),
    (Widget::Color, "Color"),
    (Widget::Sound, "Sound"),
];

/// The chooser's options: each template language and GitHub's color for it.
const CHOICES: [(&str, u16); 4] = [
    ("Rust", rgb(0xDE, 0xA5, 0x84)),
    ("Zig", rgb(0xEC, 0x91, 0x5C)),
    ("OCaml", rgb(0xEF, 0x7A, 0x08)),
    ("C++", rgb(0xF3, 0x4B, 0x7D)),
];

const TOP: i32 = ui::HEADER_HEIGHT + 2;
const ROW_HEIGHT: i32 = 18;
const WIDGET_LEFT: i32 = 72; // labels on the left, widgets from here
const WIDGET_WIDTH: i32 = 242;
const MAX_NAME: usize = 24;
const SLIDER_WIDTH: i32 = 176;
const VOLUME_STEP: i32 = 5;
const PRESS_FRAMES: u32 = 10; // how long a button shows as pressed
const HELLO_WIDTH: i32 = 120;
const ADD_ONE_LEFT: i32 = WIDGET_LEFT + HELLO_WIDTH + 8;
const ADD_ONE_WIDTH: i32 = 96;
const FIELD: u16 = rgb(8, 10, 14);
const BORDER: u16 = rgb(60, 70, 82);
const FACE: u16 = rgb(28, 34, 42);

pub struct Widgets {
    focus: usize, // index into FOCUS_ORDER
    name: String,
    volume: i32, // 0..=100
    count: i32,
    choice: usize, // index into CHOICES
    sound: bool,
    pressed: Widget, // the button shown pressed while pressed_frames > 0
    pressed_frames: u32,
    status: String, // what the last action did
}

impl Widgets {
    pub fn new() -> Widgets {
        Widgets {
            focus: 0,
            name: String::new(),
            volume: 50,
            count: 0,
            choice: CHOICES.iter().position(|(name, _)| *name == LANGUAGE).unwrap_or(0),
            sound: true,
            pressed: Widget::Button,
            pressed_frames: 0,
            status: "Try every widget".to_string(),
        }
    }

    /// The accent color is whatever the chooser picked.
    fn accent(&self) -> u16 {
        CHOICES[self.choice].1
    }

    fn focused(&self) -> Widget {
        FOCUS_ORDER[self.focus]
    }

    /// True while a button shows its pressed state.
    pub fn animated(&self) -> bool {
        self.pressed_frames > 0
    }

    pub fn tick(&mut self) {
        self.pressed_frames = self.pressed_frames.saturating_sub(1);
    }

    fn move_focus(&mut self, step: isize) {
        self.focus = (self.focus as isize + step).rem_euclid(FOCUS_ORDER.len() as isize) as usize;
    }

    /// Z/C (or left/right): step the focused widget's value.
    fn change(&mut self, step: i32) {
        match self.focused() {
            Widget::Volume => {
                self.volume = (self.volume + step * VOLUME_STEP).clamp(0, 100);
                self.status = format!("Volume {}", self.volume);
            }
            Widget::Count => {
                self.count += step;
                self.status = format!("Count {}", self.count);
            }
            Widget::Color => {
                self.choice = (self.choice as i32 + step).rem_euclid(CHOICES.len() as i32) as usize;
                self.status = format!("Color {}", CHOICES[self.choice].0);
            }
            Widget::Sound => {
                self.sound = !self.sound;
                self.status = format!("Sound {}", if self.sound { "on" } else { "off" });
            }
            Widget::Name | Widget::Button | Widget::AddOne => {}
        }
    }

    fn press(&mut self, button: Widget) {
        self.pressed = button;
        self.pressed_frames = PRESS_FRAMES;
    }

    /// ENTER or SPACE on the focused widget.
    fn activate(&mut self) {
        match self.focused() {
            Widget::Button => {
                self.press(Widget::Button);
                let name = self.name.trim();
                self.status = format!("Hello, {}!", if name.is_empty() { "stranger" } else { name });
            }
            Widget::AddOne => {
                self.press(Widget::AddOne);
                self.count += 1;
                self.status = format!("Count {}", self.count);
            }
            Widget::Count => {
                self.count = 0;
                self.status = "Count reset".to_string();
            }
            Widget::Color | Widget::Sound => self.change(1),
            Widget::Name => self.move_focus(1),
            Widget::Volume => {}
        }
    }

    /// `typed` is the character the key produces, if any (see input::Typist).
    pub fn handle_key(&mut self, event: KeyEvent, typed: Option<char>) -> Action {
        if !event.is_down() {
            return Action::Stay;
        }
        match event.code {
            keys::ESC => return Action::Home,
            keys::TAB => return Action::Next,
            // Real arrow keys always move the focus, even out of the text field.
            keys::UP => self.move_focus(-1),
            keys::DOWN => self.move_focus(1),
            _ if self.focused() == Widget::Name => match event.code {
                // In the text field F/X/Z/C are letters; ENTER moves on.
                keys::ENTER => self.move_focus(1),
                keys::BACKSPACE => {
                    self.name.pop();
                }
                _ => {
                    if let Some(character) = typed.filter(|_| self.name.len() < MAX_NAME) {
                        self.name.push(character);
                    }
                }
            },
            code => match input::direction(code) {
                Some(Direction::Up) => self.move_focus(-1),
                Some(Direction::Down) => self.move_focus(1),
                Some(Direction::Left) => self.change(-1),
                Some(Direction::Right) => self.change(1),
                None if code == keys::ENTER || code == keys::SPACE => self.activate(),
                None => {}
            },
        }
        Action::Stay
    }

    fn draw_text_field(&self, display: &mut Display, y: i32, focused: bool) {
        let accent = self.accent();
        display.fill_rect(WIDGET_LEFT, y, WIDGET_WIDTH, ROW_HEIGHT, FIELD);
        display.stroke_rect(WIDGET_LEFT, y, WIDGET_WIDTH, ROW_HEIGHT, if focused { accent } else { BORDER });
        if self.name.is_empty() && !focused {
            display.draw_text(WIDGET_LEFT + 4, y + 1, "your name", MUTED, 1);
            return;
        }
        let width = display.draw_text(WIDGET_LEFT + 4, y + 1, &self.name, TEXT, 1);
        if focused {
            display.fill_rect(WIDGET_LEFT + 4 + width, y + 3, CHAR_WIDTH, CHAR_HEIGHT - 4, accent); // cursor
        }
    }

    fn draw_button(&self, display: &mut Display, x: i32, y: i32, width: i32, button: Widget, label: &str) {
        let accent = self.accent();
        let pressed = self.pressed_frames > 0 && self.pressed == button;
        display.fill_rect(x, y, width, ROW_HEIGHT, if pressed { accent } else { FACE });
        display.stroke_rect(x, y, width, ROW_HEIGHT, if self.focused() == button { accent } else { BORDER });
        let text_x = x + (width - Display::text_width(label, 1)) / 2;
        display.draw_text(text_x, y + 1, label, if pressed { ui::BACKGROUND } else { TEXT }, 1);
    }

    fn draw_buttons(&self, display: &mut Display, y: i32) {
        self.draw_button(display, WIDGET_LEFT, y, HELLO_WIDTH, Widget::Button, "Say hello");
        self.draw_button(display, ADD_ONE_LEFT, y, ADD_ONE_WIDTH, Widget::AddOne, "Count +1");
    }

    fn draw_slider(&self, display: &mut Display, y: i32, focused: bool) {
        let accent = self.accent();
        let filled = self.volume * SLIDER_WIDTH / 100;
        display.fill_rect(WIDGET_LEFT, y + 7, SLIDER_WIDTH, 4, BORDER);
        display.fill_rect(WIDGET_LEFT, y + 7, filled, 4, accent);
        let knob = WIDGET_LEFT + filled - 3;
        display.fill_rect(knob, y + 2, 6, ROW_HEIGHT - 4, if focused { TEXT } else { MUTED });
        display.draw_text(WIDGET_LEFT + SLIDER_WIDTH + 12, y + 1, &self.volume.to_string(), TEXT, 1);
    }

    fn draw_counter(&self, display: &mut Display, y: i32, focused: bool) {
        let border = if focused { self.accent() } else { BORDER };
        for (x, sign) in [(WIDGET_LEFT, "-"), (WIDGET_LEFT + 84, "+")] {
            display.fill_rect(x, y, 24, ROW_HEIGHT, FACE);
            display.stroke_rect(x, y, 24, ROW_HEIGHT, border);
            display.draw_text(x + 8, y + 1, sign, TEXT, 1);
        }
        let value = self.count.to_string();
        let x = WIDGET_LEFT + 24 + (60 - Display::text_width(&value, 1)) / 2;
        display.draw_text(x, y + 1, &value, TEXT, 1);
    }

    fn draw_chooser(&self, display: &mut Display, y: i32, focused: bool) {
        let (name, color) = CHOICES[self.choice];
        let arrows = if focused { self.accent() } else { MUTED };
        display.draw_text(WIDGET_LEFT, y + 1, "<", arrows, 1);
        display.draw_text(WIDGET_LEFT + 16, y + 1, name, color, 1);
        display.draw_text(WIDGET_LEFT + 16 + 6 * CHAR_WIDTH, y + 1, ">", arrows, 1);
        display.fill_rect(WIDGET_LEFT + 16 + 8 * CHAR_WIDTH, y + 2, 14, ROW_HEIGHT - 4, color); // swatch
    }

    fn draw_switch(&self, display: &mut Display, y: i32, focused: bool) {
        let accent = self.accent();
        display.fill_rect(WIDGET_LEFT, y + 2, 32, ROW_HEIGHT - 4, if self.sound { accent } else { BORDER });
        if focused {
            display.stroke_rect(WIDGET_LEFT - 2, y, 36, ROW_HEIGHT, TEXT);
        }
        let knob = if self.sound { WIDGET_LEFT + 18 } else { WIDGET_LEFT + 2 };
        display.fill_rect(knob, y + 4, 12, ROW_HEIGHT - 8, TEXT);
        display.draw_text(WIDGET_LEFT + 40, y + 1, if self.sound { "on" } else { "off" }, TEXT, 1);
    }

    pub fn draw(&self, display: &mut Display) {
        let accent = self.accent();
        display.clear(ui::BACKGROUND);
        for (index, (widget, label)) in ROWS.iter().enumerate() {
            let y = TOP + index as i32 * ROW_HEIGHT;
            // The Button row is focused when either of its buttons is.
            let focused = *widget == self.focused() || (*widget == Widget::Button && self.focused() == Widget::AddOne);
            if focused {
                display.fill_rect(0, y, 3, ROW_HEIGHT, accent);
            }
            display.draw_text(8, y + 1, label, if focused { accent } else { MUTED }, 1);
            match widget {
                Widget::Name => self.draw_text_field(display, y, focused),
                Widget::Button | Widget::AddOne => self.draw_buttons(display, y),
                Widget::Volume => self.draw_slider(display, y, focused),
                Widget::Count => self.draw_counter(display, y, focused),
                Widget::Color => self.draw_chooser(display, y, focused),
                Widget::Sound => self.draw_switch(display, y, focused),
            }
        }
        display.draw_text(8, TOP + ROWS.len() as i32 * ROW_HEIGHT + 2, &self.status, accent, 1);
        ui::draw_header(display, "Widgets");
        let hint = if self.focused() == Widget::Name { "type a name  ENTER next" } else { "F/X move  Z/C change  ENTER press" };
        ui::draw_hint(display, hint);
    }
}
