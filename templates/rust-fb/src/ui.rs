// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! The app's look, shared by every screen: colors, the header bar and the hint line.

use crate::display::{rgb, Display, CHAR_HEIGHT, WHITE};

/// The language this template is written in, and GitHub's color for it.
pub const LANGUAGE: &str = "Rust";
pub const LANGUAGE_COLOR: u16 = rgb(0xDE, 0xA5, 0x84);

pub const BACKGROUND: u16 = rgb(14, 18, 23);
pub const HEADER: u16 = rgb(28, 34, 42);
pub const TEXT: u16 = WHITE;
pub const MUTED: u16 = rgb(150, 160, 170);
pub const ERROR: u16 = rgb(255, 110, 110);

/// Height of the header bar; demo content starts below it.
pub const HEADER_HEIGHT: i32 = 20;
/// Top of the hint line at the bottom of the screen.
pub const HINT_TOP: i32 = 170 - CHAR_HEIGHT - 1;

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

/// The bar at the top of a demo: its title, and how to leave.
pub fn draw_header(display: &mut Display, title: &str) {
    let width = display.width() as i32;
    display.fill_rect(0, 0, width, HEADER_HEIGHT, HEADER);
    display.draw_text(6, 2, title, LANGUAGE_COLOR, 1);
    let keys = "TAB next  ESC home";
    display.draw_text(width - Display::text_width(keys, 1) - 6, 2, keys, MUTED, 1);
}

/// One line of key help, centered at the bottom of the screen.
pub fn draw_hint(display: &mut Display, hint: &str) {
    let x = (display.width() as i32 - Display::text_width(hint, 1)) / 2;
    display.draw_text(x, HINT_TOP, hint, MUTED, 1);
}

/// Text with a dark shadow, readable on top of a picture.
pub fn draw_shadowed_text(display: &mut Display, x: i32, y: i32, text: &str, color: u16, scale: i32) {
    display.draw_text(x + scale, y + scale, text, rgb(0, 0, 0), scale);
    display.draw_text(x, y, text, color, scale);
}
