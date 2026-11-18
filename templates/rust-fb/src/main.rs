// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Hello Cardputer: a minimal CardputerZero app in Rust.
//!
//! Move the square with F/X/Z/C (or the arrow keys), press ENTER to change its color, ESC
//! to quit. Start editing in `App::handle_key` and `App::draw`.

mod display;
mod font;
mod input;

use std::process::ExitCode;
use std::thread;
use std::time::Duration;

use display::{rgb, Display, WHITE};
use input::{keys, Direction, KeyEvent, Keyboard};

const FRAME_TIME: Duration = Duration::from_millis(16); // ~60 frames per second
const BACKGROUND: u16 = rgb(16, 20, 24);
const TITLE_BAR: u16 = rgb(30, 36, 44);
const MUTED: u16 = rgb(150, 160, 170);
const COLORS: [u16; 4] = [rgb(79, 195, 247), rgb(129, 199, 132), rgb(255, 183, 77), rgb(240, 98, 146)];
const SQUARE: i32 = 24;

struct App {
    x: i32,
    y: i32,
    color: usize,
    running: bool,
}

impl App {
    fn new(display: &Display) -> App {
        App {
            x: (display.width() as i32 - SQUARE) / 2,
            y: (display.height() as i32 - SQUARE) / 2,
            color: 0,
            running: true,
        }
    }

    fn handle_key(&mut self, event: KeyEvent, display: &Display) {
        if !event.is_down() {
            return;
        }
        let step = 6;
        match (input::direction(event.code), event.code) {
            (Some(Direction::Left), _) => self.x -= step,
            (Some(Direction::Right), _) => self.x += step,
            (Some(Direction::Up), _) => self.y -= step,
            (Some(Direction::Down), _) => self.y += step,
            (None, keys::ENTER | keys::SPACE) => self.color = (self.color + 1) % COLORS.len(),
            // Quit on a short ESC press. (Holding ESC for 3 s makes the launcher kill the app.)
            (None, keys::ESC) => self.running = false,
            _ => {}
        }
        self.x = self.x.clamp(0, display.width() as i32 - SQUARE);
        self.y = self.y.clamp(20, display.height() as i32 - SQUARE - 14);
    }

    fn draw(&self, display: &mut Display) {
        let width = display.width() as i32;
        let height = display.height() as i32;
        display.clear(BACKGROUND);
        display.fill_rect(0, 0, width, 18, TITLE_BAR);
        display.draw_text(6, 5, "Hello Cardputer", WHITE, 1);
        display.fill_rect(self.x, self.y, SQUARE, SQUARE, COLORS[self.color]);
        let hint = "F/X/Z/C move  ENTER color  ESC quit";
        display.draw_text((width - Display::text_width(hint, 1)) / 2, height - 11, hint, MUTED, 1);
    }
}

fn run() -> std::io::Result<()> {
    let mut display = Display::open()?;
    let keyboard = Keyboard::open()?;
    let mut app = App::new(&display);
    let mut dirty = true;
    while app.running {
        while let Some(event) = keyboard.poll() {
            app.handle_key(event, &display);
            dirty = true;
        }
        if dirty {
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
