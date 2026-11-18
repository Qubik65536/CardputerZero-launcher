// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 3, a terminal-style tool: a read-eval-print loop for the `calc` language.
//! Type a line, ENTER runs it; the screen scrolls like a terminal.

use crate::calc::Calculator;
use crate::display::{Display, CHAR_HEIGHT, CHAR_WIDTH};
use crate::input::{keys, KeyEvent};
use crate::ui::{self, Action, BACKGROUND, ERROR, LANGUAGE_COLOR, MUTED, TEXT};

const COLUMNS: usize = 40; // 320 px / 8 px per character
const ROWS: usize = 9; // text rows below the header; the last one is the input line
const TOP: i32 = ui::HEADER_HEIGHT + 2;
const MAX_INPUT: usize = 120;
const MAX_SCROLLBACK: usize = 200;
const PROMPT: &str = "> ";
const HELP: [&str; 4] = [
    "numbers, + - * / % ^ ( )",
    "x = 6 * 7   ans   abs(x) min(a,b) max",
    "commands: help  vars  clear",
    "UP/DOWN history  TAB next  ESC home",
];

pub struct Repl {
    calculator: Calculator,
    scrollback: Vec<(String, u16)>, // line, color
    input: String,
    history: Vec<String>,
    history_index: usize, // == history.len() while editing a new line
}

impl Repl {
    pub fn new() -> Repl {
        let mut repl = Repl {
            calculator: Calculator::new(),
            scrollback: Vec::new(),
            input: String::new(),
            history: Vec::new(),
            history_index: 0,
        };
        repl.print("calc: whole-number calculator", MUTED);
        repl.print("type help and press ENTER", MUTED);
        repl
    }

    /// Add output, wrapped to the screen width.
    fn print(&mut self, text: &str, color: u16) {
        let characters: Vec<char> = text.chars().collect();
        for chunk in characters.chunks(COLUMNS) {
            self.scrollback.push((chunk.iter().collect(), color));
        }
        if characters.is_empty() {
            self.scrollback.push((String::new(), color));
        }
        let excess = self.scrollback.len().saturating_sub(MAX_SCROLLBACK);
        self.scrollback.drain(..excess);
    }

    fn submit(&mut self) {
        let line = std::mem::take(&mut self.input);
        self.print(&format!("{PROMPT}{line}"), TEXT);
        let command = line.trim();
        if command.is_empty() {
            return;
        }
        if self.history.last().map(String::as_str) != Some(command) {
            self.history.push(command.to_string());
        }
        self.history_index = self.history.len();
        match command {
            "help" => HELP.iter().for_each(|line| self.print(line, MUTED)),
            "clear" => self.scrollback.clear(),
            "vars" => {
                let lines: Vec<String> =
                    self.calculator.variables().map(|(name, value)| format!("{name} = {value}")).collect();
                if lines.is_empty() {
                    self.print("no variables yet", MUTED);
                }
                lines.iter().for_each(|line| self.print(line, LANGUAGE_COLOR));
            }
            _ => match self.calculator.run(command) {
                Ok(result) => self.print(&result, LANGUAGE_COLOR),
                Err(message) => self.print(&format!("error: {message}"), ERROR),
            },
        }
    }

    /// Step through earlier lines: -1 = older, +1 = newer.
    fn recall(&mut self, step: isize) {
        let index = self.history_index as isize + step;
        if index < 0 || index > self.history.len() as isize {
            return;
        }
        self.history_index = index as usize;
        self.input = self.history.get(self.history_index).cloned().unwrap_or_default();
    }

    /// `typed` is the character the key produces, if any (see input::Typist).
    pub fn handle_key(&mut self, event: KeyEvent, typed: Option<char>) -> Action {
        if !event.is_down() {
            return Action::Stay;
        }
        match event.code {
            keys::ESC => return Action::Home,
            keys::TAB => return Action::Next,
            keys::ENTER => self.submit(),
            keys::BACKSPACE => {
                self.input.pop();
            }
            // Only the real arrow keys: F/X/Z/C are letters here.
            keys::UP => self.recall(-1),
            keys::DOWN => self.recall(1),
            _ => {
                if let Some(character) = typed.filter(|_| self.input.len() < MAX_INPUT) {
                    self.input.push(character);
                }
            }
        }
        Action::Stay
    }

    pub fn draw(&self, display: &mut Display) {
        display.clear(BACKGROUND);
        ui::draw_header(display, "REPL");
        let visible = &self.scrollback[self.scrollback.len().saturating_sub(ROWS - 1)..];
        for (row, (line, color)) in visible.iter().enumerate() {
            display.draw_text(0, TOP + row as i32 * CHAR_HEIGHT, line, *color, 1);
        }
        // The input line sits under the output; long input scrolls to keep the end visible.
        let y = TOP + visible.len() as i32 * CHAR_HEIGHT;
        let room = COLUMNS - PROMPT.len() - 1;
        let shown = &self.input[self.input.len().saturating_sub(room)..];
        let width = display.draw_text(0, y, PROMPT, LANGUAGE_COLOR, 1);
        let width = width + display.draw_text(width, y, shown, TEXT, 1);
        display.fill_rect(width, y + 2, CHAR_WIDTH, CHAR_HEIGHT - 4, LANGUAGE_COLOR); // cursor
    }
}
