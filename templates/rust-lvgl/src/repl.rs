// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 3, a terminal-style tool: a read-eval-print loop for the `calc`
//! language (calc.rs). Type a line, ENTER runs it; the screen scrolls like a
//! terminal.

use std::cell::RefCell;

use crate::calc::Calculator;
use crate::lvgl::{self, color_hex, keys, Font, Key, Label, Obj, LV_OBJ_FLAG_HIDDEN, LV_OPA_COVER};
use crate::ui::{
    keep, make_hint, make_label, make_panel, typed_text, Action, Screen, ScreenBase, CONTENT_WIDTH, ERROR_COLOR,
    LANGUAGE_COLOR, MUTED_COLOR, TEXT_COLOR,
};

const LEFT: i32 = 4;
const TOP: i32 = 2;
const LINE_HEIGHT: i32 = 16; // Font::montserrat_14's line height
const TEXT_WIDTH: i32 = CONTENT_WIDTH - 2 * LEFT;
const CURSOR_WIDTH: i32 = 7;
const MAX_INPUT: usize = 120;
const MAX_SCROLLBACK: usize = 200;
/// Text rows above the hint line; the last one is the input line.
const ROWS: usize = 8;
const PROMPT: &str = "> ";
const HELP: [&str; 4] = [
    "numbers, + - * / % ^ ( )",
    "x = 6 * 7   ans   abs(x) min(a,b) max",
    "commands: help  vars  clear",
    "UP/DOWN history  TAB next  ESC home",
];

fn font() -> Font {
    Font::montserrat_14()
}

/// Width of `text` in pixels as a label draws it (the text is ASCII).
fn text_width(text: &str) -> i32 {
    let characters: Vec<char> = text.chars().collect();
    let next = |index: usize| characters.get(index + 1).copied().unwrap_or('\0');
    characters.iter().enumerate().map(|(index, &character)| font().glyph_width(character, next(index))).sum()
}

/// The longest end of `text` that fits in `room` pixels.
fn tail_that_fits(text: &str, room: i32) -> &str {
    let mut start = text.len();
    while start > 0 && text_width(&text[start - 1..]) <= room {
        start -= 1;
    }
    &text[start..]
}

struct Line {
    text: String,
    color: u32,
}

/// What the REPL remembers.
struct Session {
    calculator: Calculator,
    scrollback: Vec<Line>,
    input: String,
    history: Vec<String>,
    history_index: usize, // == history.len() while editing a new line
}

impl Session {
    fn new() -> Session {
        Session {
            calculator: Calculator::new(),
            scrollback: Vec::new(),
            input: String::new(),
            history: Vec::new(),
            history_index: 0,
        }
    }

    /// Add output, wrapped to the screen width.
    fn print(&mut self, text: &str, color: u32) {
        let mut line = String::new();
        for character in text.chars() {
            if !line.is_empty() && text_width(&format!("{line}{character}")) > TEXT_WIDTH {
                self.scrollback.push(Line { text: std::mem::take(&mut line), color });
            }
            line.push(character);
        }
        self.scrollback.push(Line { text: line, color });
        if self.scrollback.len() > MAX_SCROLLBACK {
            let excess = self.scrollback.len() - MAX_SCROLLBACK;
            self.scrollback.drain(..excess);
        }
    }

    fn submit(&mut self) {
        let line = std::mem::take(&mut self.input);
        self.print(&format!("{PROMPT}{line}"), TEXT_COLOR);
        let command = line.trim_matches([' ', '\t']).to_string();
        if command.is_empty() {
            return;
        }
        if self.history.last() != Some(&command) {
            self.history.push(command.clone());
        }
        self.history_index = self.history.len();

        match command.as_str() {
            "help" => HELP.iter().for_each(|help| self.print(help, MUTED_COLOR)),
            "clear" => self.scrollback.clear(),
            "vars" => {
                let variables: Vec<String> =
                    self.calculator.variables().map(|(name, value)| format!("{name} = {value}")).collect();
                if variables.is_empty() {
                    self.print("no variables yet", MUTED_COLOR);
                }
                for variable in variables {
                    self.print(&variable, LANGUAGE_COLOR);
                }
            }
            _ => match self.calculator.run(&command) {
                Ok(result) => self.print(&result, LANGUAGE_COLOR),
                Err(error) => self.print(&format!("error: {error}"), ERROR_COLOR),
            },
        }
    }

    /// Step through earlier lines: -1 = older, +1 = newer.
    fn recall(&mut self, step: isize) {
        let Some(index) = self.history_index.checked_add_signed(step) else {
            return;
        };
        if index > self.history.len() {
            return;
        }
        self.history_index = index;
        self.input = self.history.get(index).cloned().unwrap_or_default();
    }
}

pub struct ReplScreen {
    base: ScreenBase,
    line_labels: Vec<Label>,
    prompt_label: Label,
    input_label: Label,
    cursor: Obj,
    session: RefCell<Session>,
}

impl ReplScreen {
    fn refresh(&self) {
        let session = self.session.borrow();
        let visible = session.scrollback.len().min(self.line_labels.len());
        let first = session.scrollback.len() - visible;
        for (row, label) in self.line_labels.iter().enumerate() {
            if row >= visible {
                label.add_flag(LV_OBJ_FLAG_HIDDEN);
                continue;
            }
            let line = &session.scrollback[first + row];
            label.set_text(&line.text);
            label.set_style_text_color(color_hex(line.color), 0);
            label.remove_flag(LV_OBJ_FLAG_HIDDEN);
        }

        // The input line sits under the output; long input scrolls to keep the end visible.
        let y = TOP + visible as i32 * LINE_HEIGHT;
        let prompt_width = text_width(PROMPT);
        let shown = tail_that_fits(&session.input, TEXT_WIDTH - prompt_width - CURSOR_WIDTH - 1);
        self.input_label.set_text(shown);
        self.prompt_label.set_pos(LEFT, y);
        self.input_label.set_pos(LEFT + prompt_width, y);
        self.cursor.set_pos(LEFT + prompt_width + text_width(shown) + 1, y + 2);
    }

    pub fn new(parent: Obj) -> &'static ReplScreen {
        let base = ScreenBase::new(parent);
        let root = base.root();
        let line_labels = (0..ROWS - 1)
            .map(|row| {
                let label = make_label(root, "", font(), TEXT_COLOR);
                label.set_pos(LEFT, TOP + row as i32 * LINE_HEIGHT);
                label
            })
            .collect();
        let prompt_label = make_label(root, PROMPT, font(), LANGUAGE_COLOR);
        let input_label = make_label(root, "", font(), TEXT_COLOR);
        let cursor = make_panel(root, 0, 0, CURSOR_WIDTH, LINE_HEIGHT - 4, LANGUAGE_COLOR, LV_OPA_COVER);
        make_hint(root, "UP/DOWN history  TAB next  ESC home");

        let mut session = Session::new();
        session.print("calc: whole-number calculator", MUTED_COLOR);
        session.print("type help and press ENTER", MUTED_COLOR);
        let screen =
            keep(ReplScreen { base, line_labels, prompt_label, input_label, cursor, session: RefCell::new(session) });
        screen.refresh();
        screen
    }
}

impl Screen for ReplScreen {
    fn base(&self) -> &ScreenBase {
        &self.base
    }

    fn title(&self) -> String {
        "REPL".to_string()
    }

    fn on_show(&self) {
        // F/X/Z/C type letters here instead of acting as arrows.
        lvgl::set_text_input(true);
    }

    fn on_hide(&self) {
        lvgl::set_text_input(false);
    }

    fn handle_key(&self, key: &Key) -> Action {
        {
            let mut session = self.session.borrow_mut();
            match key.code {
                keys::ESC => return Action::Home,
                keys::TAB => return Action::Next,
                keys::ENTER => session.submit(),
                keys::BACKSPACE => {
                    session.input.pop();
                }
                // Only the real arrow keys: F/X/Z/C are letters here.
                keys::UP => session.recall(-1),
                keys::DOWN => session.recall(1),
                _ => {
                    if let Some(text) = typed_text(key) {
                        if session.input.len() < MAX_INPUT {
                            session.input.push_str(text);
                        }
                    }
                }
            }
        }
        self.refresh();
        Action::Stay
    }
}
