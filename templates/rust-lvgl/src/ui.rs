// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! The app's look and plumbing, shared by every screen: colors, key helpers,
//! label/panel helpers and the `Screen` trait with its `ScreenBase`.

use std::cell::Cell;

use crate::lvgl::{
    color_hex, keys, Font, Key, Label, Obj, Timer, LV_ALIGN_TOP_MID, LV_ALIGN_TOP_RIGHT, LV_OBJ_FLAG_CLICKABLE,
    LV_OBJ_FLAG_HIDDEN, LV_OBJ_FLAG_SCROLLABLE, LV_OPA_COVER,
};

/// The language this template is written in, and GitHub's color for it.
pub const LANGUAGE: &str = "Rust";
pub const LANGUAGE_COLOR: u32 = 0xDEA584;

pub const BACKGROUND_COLOR: u32 = 0x0E1217;
pub const TEXT_COLOR: u32 = 0xFFFFFF;
pub const MUTED_COLOR: u32 = 0x96A0AA;
pub const ERROR_COLOR: u32 = 0xFF6E6E;

/// The content area below the 20 px top bar that every screen fills.
pub const CONTENT_WIDTH: i32 = 320;
pub const CONTENT_HEIGHT: i32 = 150;
/// Top of the key-help line at the bottom of a screen (content coordinates).
pub const HINT_TOP: i32 = CONTENT_HEIGHT - 17;
/// Animation frame period: about 60 frames per second.
pub const FRAME_MS: u32 = 16;

/// What a screen asks the app to do after a key press.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    Stay,
    /// Back to the home screen.
    Home,
    /// On to the next demo (TAB).
    Next,
    /// Open demo number N (0-based) from the home screen.
    Open(usize),
    Quit,
}

/// The CardputerZero keyboard has no arrow keys: like the launcher, F/X/Z/C
/// act as up/down/left/right. Real arrow keys (simulator, USB keyboards) work too.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Direction {
    Up,
    Down,
    Left,
    Right,
}

pub fn direction(code: u32) -> Option<Direction> {
    match code {
        keys::UP | keys::F => Some(Direction::Up),
        keys::DOWN | keys::X => Some(Direction::Down),
        keys::LEFT | keys::Z => Some(Direction::Left),
        keys::RIGHT | keys::C => Some(Direction::Right),
        _ => None,
    }
}

/// Text the key typed (cp0_lvgl applies Shift and the symbol layer), or `None`
/// for keys that type nothing printable.
pub fn typed_text<'a>(key: &Key<'a>) -> Option<&'a str> {
    let printable = matches!(key.text.as_bytes(), [byte] if (0x20..0x7F).contains(byte));
    printable.then_some(key.text)
}

pub fn make_label(parent: Obj, text: &str, font: Font, color: u32) -> Label {
    let label = Label::create(parent);
    label.set_text(text);
    label.set_style_text_font(font, 0);
    label.set_style_text_color(color_hex(color), 0);
    label
}

/// A plain rectangle; `opa` below `LV_OPA_COVER` shades what is under it.
pub fn make_panel(parent: Obj, x: i32, y: i32, width: i32, height: i32, color: u32, opa: u8) -> Obj {
    let panel = Obj::create(parent);
    panel.remove_style_all();
    panel.set_pos(x, y);
    panel.set_size(width, height);
    panel.set_style_bg_color(color_hex(color), 0);
    panel.set_style_bg_opa(opa, 0);
    panel.remove_flag(LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_SCROLLABLE);
    panel
}

/// One line of key help, centered at the bottom of a screen.
pub fn make_hint(parent: Obj, text: &str) -> Label {
    let hint = make_label(parent, text, Font::montserrat_14(), MUTED_COLOR);
    hint.align(LV_ALIGN_TOP_MID, 0, HINT_TOP);
    hint
}

/// "TAB next  ESC home", top right: how to leave a demo.
pub fn make_demo_keys(parent: Obj) -> Label {
    let keys = make_label(parent, "TAB next  ESC home", Font::montserrat_12(), MUTED_COLOR);
    keys.align(LV_ALIGN_TOP_RIGHT, -6, 2);
    keys
}

/// What every screen has: a full-size container inside the content area that
/// is shown while the screen is active, and an optional frame timer.
pub struct ScreenBase {
    root: Obj,
    timer: Cell<Option<Timer>>,
}

impl ScreenBase {
    pub fn new(parent: Obj) -> ScreenBase {
        let root = make_panel(parent, 0, 0, CONTENT_WIDTH, CONTENT_HEIGHT, BACKGROUND_COLOR, LV_OPA_COVER);
        root.add_flag(LV_OBJ_FLAG_HIDDEN);
        ScreenBase { root, timer: Cell::new(None) }
    }

    pub fn root(&self) -> Obj {
        self.root
    }

    pub fn is_shown(&self) -> bool {
        !self.root.has_flag(LV_OBJ_FLAG_HIDDEN)
    }

    /// Animated screens call this once: `screen.on_frame()` then runs every
    /// FRAME_MS while the screen shows.
    pub fn animate<S: Screen>(&self, screen: &'static S) {
        if self.timer.get().is_some() {
            return;
        }
        let timer = Timer::create(FRAME_MS, screen, |screen| screen.on_frame());
        timer.pause();
        self.timer.set(Some(timer));
    }
}

/// One screen of the app. Screens live as long as the app (`&'static`), so
/// LVGL callbacks can refer to them; state that changes sits in `Cell`s.
pub trait Screen: 'static {
    fn base(&self) -> &ScreenBase;
    /// Shown in the top bar while this screen is active.
    fn title(&self) -> String;
    /// Called for key presses and auto-repeats (not releases).
    fn handle_key(&self, key: &Key) -> Action;

    fn on_show(&self) {}
    fn on_hide(&self) {}
    fn on_frame(&self) {}

    fn show(&self) {
        self.base().root.remove_flag(LV_OBJ_FLAG_HIDDEN);
        if let Some(timer) = self.base().timer.get() {
            timer.resume();
        }
        self.on_show();
    }

    fn hide(&self) {
        if let Some(timer) = self.base().timer.get() {
            timer.pause();
        }
        self.base().root.add_flag(LV_OBJ_FLAG_HIDDEN);
        self.on_hide();
    }
}

/// Keep a screen for the rest of the app's life (LVGL holds pointers to it).
pub fn keep<S: Screen>(screen: S) -> &'static S {
    Box::leak(Box::new(screen))
}
