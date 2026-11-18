// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Hello Cardputer: a CardputerZero app in Rust.
//!
//! The home screen greets you and opens three demos: color rendering (`colors.rs`),
//! an interactive animation (`motion.rs`) and a terminal-style REPL (`repl.rs`, running
//! the little language in `calc.rs`). TAB moves to the next demo, ESC goes back home,
//! ESC at home quits. Keep what you need and delete the rest.

mod calc;
mod colors;
mod display;
mod font;
mod home;
mod input;
mod motion;
mod repl;
mod ui;

use std::process::ExitCode;
use std::thread;
use std::time::Duration;

use colors::Colors;
use display::Display;
use home::Home;
use input::{KeyEvent, Keyboard, Typist};
use motion::Motion;
use repl::Repl;
use ui::Action;

const FRAME_TIME: Duration = Duration::from_millis(16); // ~60 frames per second

/// Which screen is showing. The demos are in home::DEMOS order.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Screen {
    Home,
    Colors,
    Motion,
    Repl,
}

const DEMO_SCREENS: [Screen; 3] = [Screen::Colors, Screen::Motion, Screen::Repl];

struct App {
    screen: Screen,
    home: Home,
    colors: Colors,
    motion: Motion,
    repl: Repl,
    running: bool,
}

impl App {
    fn new() -> App {
        App {
            screen: Screen::Home,
            home: Home::new(),
            colors: Colors::new(),
            motion: Motion::new(),
            repl: Repl::new(),
            running: true,
        }
    }

    fn apply(&mut self, action: Action) {
        match action {
            Action::Stay => {}
            Action::Home => self.screen = Screen::Home,
            Action::Open(index) => self.screen = DEMO_SCREENS[index],
            Action::Next => {
                let index = DEMO_SCREENS.iter().position(|screen| *screen == self.screen).unwrap_or(0);
                self.screen = DEMO_SCREENS[(index + 1) % DEMO_SCREENS.len()];
            }
            Action::Quit => self.running = false,
        }
    }

    fn handle_key(&mut self, event: KeyEvent, typed: Option<char>) {
        let action = match self.screen {
            Screen::Home => self.home.handle_key(event),
            Screen::Colors => self.colors.handle_key(event),
            Screen::Motion => self.motion.handle_key(event),
            Screen::Repl => self.repl.handle_key(event, typed),
        };
        self.apply(action);
    }

    /// Advance animations by one frame. Returns true if the screen needs redrawing.
    fn tick(&mut self) -> bool {
        match self.screen {
            Screen::Colors => {
                self.colors.tick();
                self.colors.animated()
            }
            Screen::Motion => {
                self.motion.tick();
                true
            }
            Screen::Home | Screen::Repl => false,
        }
    }

    fn draw(&self, display: &mut Display) {
        match self.screen {
            Screen::Home => self.home.draw(display),
            Screen::Colors => self.colors.draw(display),
            Screen::Motion => self.motion.draw(display),
            Screen::Repl => self.repl.draw(display),
        }
    }
}

fn run() -> std::io::Result<()> {
    let mut display = Display::open()?;
    let keyboard = Keyboard::open()?;
    let mut typist = Typist::new();
    let mut app = App::new();
    let mut dirty = true;
    while app.running {
        while let Some(event) = keyboard.poll() {
            let typed = typist.char_for(event); // every event, so Shift is tracked
            app.handle_key(event, typed);
            dirty = true;
        }
        if app.tick() || dirty {
            app.draw(&mut display);
            display.present()?;
            dirty = false;
        }
        thread::sleep(FRAME_TIME);
    }
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("hello-cardputer: {error}");
            ExitCode::FAILURE
        }
    }
}
