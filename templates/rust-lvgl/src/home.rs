// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! The home screen: wallpaper, greeting and a menu of the demos.

use std::cell::Cell;

use crate::lvgl::{self, color_hex, keys, Font, Image, Key, Label, Obj, LV_OBJ_FLAG_HIDDEN, LV_OPA_COVER};
use crate::ui::{
    direction, keep, make_hint, make_label, make_panel, Action, Direction, Screen, ScreenBase, CONTENT_HEIGHT,
    CONTENT_WIDTH, HINT_TOP, LANGUAGE, LANGUAGE_COLOR, MUTED_COLOR, TEXT_COLOR,
};

pub struct DemoInfo {
    pub name: &'static str,
    pub description: &'static str,
}

/// The demos, in menu order (and TAB order).
pub const DEMOS: [DemoInfo; 4] = [
    DemoInfo { name: "Colors", description: "color triangle and wheel" },
    DemoInfo { name: "Motion", description: "steer a glowing ball" },
    DemoInfo { name: "REPL", description: "a tiny calculator language" },
    DemoInfo { name: "Widgets", description: "text field, slider, more" },
];

const MENU_TOP: i32 = 50;
const ROW_HEIGHT: i32 = 20;
const DESCRIPTION_X: i32 = 98;

/// Text with a dark shadow, readable on top of a picture.
fn make_shadowed_label(parent: Obj, text: &str, font: Font, color: u32, x: i32, y: i32, offset: i32) -> Label {
    let shadow = make_label(parent, text, font, 0x000000);
    shadow.set_pos(x + offset, y + offset);
    let label = make_label(parent, text, font, color);
    label.set_pos(x, y);
    label
}

struct MenuRow {
    accent: Obj,
    name: Label,
    description: Label,
}

pub struct HomeScreen {
    base: ScreenBase,
    rows: Vec<MenuRow>,
    selected: Cell<usize>,
}

impl HomeScreen {
    fn update_selection(&self) {
        for (index, row) in self.rows.iter().enumerate() {
            let selected = index == self.selected.get();
            if selected {
                row.accent.remove_flag(LV_OBJ_FLAG_HIDDEN);
            } else {
                row.accent.add_flag(LV_OBJ_FLAG_HIDDEN);
            }
            row.name.set_style_text_color(color_hex(if selected { TEXT_COLOR } else { MUTED_COLOR }), 0);
            row.description.set_style_text_color(color_hex(if selected { LANGUAGE_COLOR } else { MUTED_COLOR }), 0);
        }
    }

    pub fn new(parent: Obj) -> &'static HomeScreen {
        let base = ScreenBase::new(parent);
        let root = base.root();
        // Images from APPLaunch/share/images/: file_path() resolves the name for
        // both the device (/usr/share/APPLaunch) and the desktop (./APPLaunch).
        let wallpaper = Image::create(root);
        wallpaper.set_src_file(&lvgl::file_path("wallpaper.png"));
        wallpaper.set_pos(0, 0);

        let greeting = format!("Hello, {LANGUAGE}!");
        make_shadowed_label(root, &greeting, Font::montserrat_28(), LANGUAGE_COLOR, 14, -2, 2);
        make_shadowed_label(root, "Your CardputerZero app", Font::montserrat_14(), MUTED_COLOR, 16, 29, 1);

        let menu_height = ROW_HEIGHT * DEMOS.len() as i32 + 6;
        make_panel(root, 8, MENU_TOP - 4, CONTENT_WIDTH - 16, menu_height, 0x000000, 150);
        let mut rows = Vec::new();
        for (index, demo) in DEMOS.iter().enumerate() {
            let y = MENU_TOP + index as i32 * ROW_HEIGHT;
            let accent = make_panel(root, 8, y - 2, 3, ROW_HEIGHT - 2, LANGUAGE_COLOR, LV_OPA_COVER);
            let name = make_label(root, &format!("{} {}", index + 1, demo.name), Font::montserrat_14(), MUTED_COLOR);
            name.set_pos(18, y);
            let description = make_label(root, demo.description, Font::montserrat_14(), MUTED_COLOR);
            description.set_pos(DESCRIPTION_X, y);
            rows.push(MenuRow { accent, name, description });
        }

        make_panel(root, 0, HINT_TOP - 1, CONTENT_WIDTH, CONTENT_HEIGHT - HINT_TOP + 1, 0x000000, 170);
        make_hint(root, "F/X choose  ENTER open  ESC quit");
        let screen = keep(HomeScreen { base, rows, selected: Cell::new(0) });
        screen.update_selection();
        screen
    }
}

impl Screen for HomeScreen {
    fn base(&self) -> &ScreenBase {
        &self.base
    }

    fn title(&self) -> String {
        "Hello Cardputer".to_string()
    }

    fn handle_key(&self, key: &Key) -> Action {
        let count = DEMOS.len();
        let selected = self.selected.get();
        match direction(key.code) {
            Some(Direction::Up | Direction::Left) => self.selected.set((selected + count - 1) % count),
            Some(Direction::Down | Direction::Right) => self.selected.set((selected + 1) % count),
            None => match key.code {
                keys::ENTER | keys::SPACE => return Action::Open(selected),
                keys::DIGIT_1 => return Action::Open(0),
                keys::DIGIT_2 => return Action::Open(1),
                keys::DIGIT_3 => return Action::Open(2),
                keys::DIGIT_4 => return Action::Open(3),
                // Quit on a short ESC press. (Holding ESC for 3 s makes the launcher kill the app.)
                keys::ESC => return Action::Quit,
                _ => {}
            },
        }
        self.update_selection();
        Action::Stay
    }
}
