// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! The home screen: wallpaper, greeting and a menu of the demos.

use crate::display::Display;
use crate::input::{self, keys, Direction, KeyEvent};
use crate::ui::{self, Action, LANGUAGE, LANGUAGE_COLOR, MUTED, TEXT};

/// 320x170 RGB565, made with scripts/png_to_rgb565.py. Replace it with your own.
const WALLPAPER: &[u8] = include_bytes!("../assets/wallpaper.rgb565");

/// The demos, in menu order: name and a short description.
pub const DEMOS: [(&str, &str); 3] = [
    ("Colors", "color triangle and wheel"),
    ("Motion", "steer a glowing ball"),
    ("REPL", "a tiny calculator language"),
];

const MENU_TOP: i32 = 78;
const ROW_HEIGHT: i32 = 20;

pub struct Home {
    selected: usize,
}

impl Home {
    pub fn new() -> Home {
        Home { selected: 0 }
    }

    pub fn handle_key(&mut self, event: KeyEvent) -> Action {
        if !event.is_down() {
            return Action::Stay;
        }
        let count = DEMOS.len();
        match (input::direction(event.code), event.code) {
            (Some(Direction::Up | Direction::Left), _) => self.selected = (self.selected + count - 1) % count,
            (Some(Direction::Down | Direction::Right), _) => self.selected = (self.selected + 1) % count,
            (None, keys::ENTER | keys::SPACE) => return Action::Open(self.selected),
            (None, keys::DIGIT_1) => return Action::Open(0),
            (None, keys::DIGIT_2) => return Action::Open(1),
            (None, keys::DIGIT_3) => return Action::Open(2),
            // Quit on a short ESC press. (Holding ESC for 3 s makes the launcher kill the app.)
            (None, keys::ESC) => return Action::Quit,
            _ => {}
        }
        Action::Stay
    }

    pub fn draw(&self, display: &mut Display) {
        let width = display.width() as i32;
        display.draw_image(0, 0, WALLPAPER);
        ui::draw_shadowed_text(display, 16, 12, &format!("Hello, {LANGUAGE}!"), LANGUAGE_COLOR, 2);
        ui::draw_shadowed_text(display, 18, 50, "Your CardputerZero app", MUTED, 1);

        display.shade_rect(8, MENU_TOP - 4, width - 16, ROW_HEIGHT * DEMOS.len() as i32 + 6, 150);
        for (index, (name, description)) in DEMOS.iter().enumerate() {
            let y = MENU_TOP + index as i32 * ROW_HEIGHT;
            let selected = index == self.selected;
            if selected {
                display.fill_rect(8, y - 2, 3, ROW_HEIGHT - 2, LANGUAGE_COLOR);
            }
            let color = if selected { TEXT } else { MUTED };
            display.draw_text(18, y, &format!("{} {:<7}", index + 1, name), color, 1);
            display.draw_text(18 + 10 * 8, y, description, if selected { LANGUAGE_COLOR } else { MUTED }, 1);
        }

        display.shade_rect(0, ui::HINT_TOP - 1, width, display.height() as i32 - ui::HINT_TOP + 1, 170);
        ui::draw_hint(display, "F/X choose  ENTER open  ESC quit");
    }
}
