// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Hello Cardputer: a CardputerZero app in Rust with LVGL.
//!
//! `lvgl::run` sets up LVGL, the display (an SDL window on the desktop, the
//! panel on the device), the keyboard, the standard top bar and the platform
//! services, calls `HelloCardputer::new` to build the UI, and runs the event
//! loop until the app calls `lvgl::quit()`. Start reading in app.rs.

mod app;
mod calc;
mod canvas;
mod colors;
mod home;
mod lvgl;
mod motion;
mod repl;
mod ui;
mod widgets;

use std::process;

fn main() {
    process::exit(lvgl::run("Hello Cardputer", app::HelloCardputer::new));
}
