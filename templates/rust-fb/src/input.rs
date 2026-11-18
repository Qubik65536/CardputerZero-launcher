// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Keyboard input as Linux evdev events.
//!
//! On the device this reads the built-in keyboard's evdev device. Keys report
//! Linux key codes; note that the keyboard's symbol layer uses its own codes
//! (see docs/app-development/device-reference.md) - letters, digits, ENTER,
//! ESC, BACKSPACE, TAB and SPACE are standard. Under
//! `fbsim` it reads the FIFO named by `CARDPUTER_INPUT`, which carries the same
//! 24-byte `struct input_event` records. A background thread does the blocking
//! reads; the app polls without blocking.

use std::env;
use std::fs::File;
use std::io::{self, Read};
use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver};
use std::thread;

/// Linux key codes (linux/input-event-codes.h) that apps commonly need.
#[allow(dead_code)] // a reference table: not every app uses every key
pub mod keys {
    pub const ESC: u16 = 1;
    pub const BACKSPACE: u16 = 14;
    pub const TAB: u16 = 15;
    pub const LEFTSHIFT: u16 = 42;
    pub const RIGHTSHIFT: u16 = 54;
    pub const DIGIT_1: u16 = 2;
    pub const DIGIT_2: u16 = 3;
    pub const DIGIT_3: u16 = 4;
    pub const ENTER: u16 = 28;
    pub const SPACE: u16 = 57;
    pub const UP: u16 = 103;
    pub const LEFT: u16 = 105;
    pub const RIGHT: u16 = 106;
    pub const DOWN: u16 = 108;
    pub const Q: u16 = 16;
    pub const F: u16 = 33;
    pub const Z: u16 = 44;
    pub const X: u16 = 45;
    pub const C: u16 = 46;
}

/// Direction of a navigation key. The CardputerZero keyboard has no arrow keys:
/// like the launcher, treat F/X/Z/C as up/down/left/right. Real arrow keys
/// (desktop simulator, external keyboards) work too.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Direction {
    Up,
    Down,
    Left,
    Right,
}

pub fn direction(code: u16) -> Option<Direction> {
    match code {
        keys::UP | keys::F => Some(Direction::Up),
        keys::DOWN | keys::X => Some(Direction::Down),
        keys::LEFT | keys::Z => Some(Direction::Left),
        keys::RIGHT | keys::C => Some(Direction::Right),
        _ => None,
    }
}

const EV_KEY: u16 = 1;
const INPUT_EVENT_SIZE: usize = 24; // struct input_event on 64-bit Linux

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyState {
    Released,
    Pressed,
    /// Auto-repeat while the key is held down.
    Repeated,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct KeyEvent {
    pub code: u16,
    pub state: KeyState,
}

impl KeyEvent {
    /// True for a fresh press or an auto-repeat: what most UIs act on.
    pub fn is_down(&self) -> bool {
        self.state != KeyState::Released
    }
}

fn parse_event(record: &[u8; INPUT_EVENT_SIZE]) -> Option<KeyEvent> {
    let kind = u16::from_le_bytes([record[16], record[17]]);
    let code = u16::from_le_bytes([record[18], record[19]]);
    let value = i32::from_le_bytes([record[20], record[21], record[22], record[23]]);
    if kind != EV_KEY {
        return None;
    }
    let state = match value {
        0 => KeyState::Released,
        1 => KeyState::Pressed,
        _ => KeyState::Repeated,
    };
    Some(KeyEvent { code, state })
}

/// US desktop keyboard rows: key code of the first key, unshifted and shifted characters.
const DESKTOP_ROWS: [(u16, &str, &str); 4] = [
    (2, "1234567890-=", "!@#$%^&*()_+"),
    (16, "qwertyuiop[]", "QWERTYUIOP{}"),
    (30, "asdfghjkl;'`", "ASDFGHJKL:\"~"),
    (43, "\\zxcvbnm,./", "|ZXCVBNM<>?"),
];

/// The CardputerZero's symbol layer (SYM + key) sends these codes; the table is the
/// launcher's default keymap (ext_components/cp0_lvgl/src/cp0/cp0_keyboard_keymap.c).
const DEVICE_SYMBOLS: [(u16, char); 32] = [
    (26, '!'), (27, '@'), (39, '#'), (40, '$'), (41, '%'), (43, '^'), (51, '&'), (52, '*'),
    (53, '('), (94, ')'), (55, '~'), (69, '`'), (70, '_'), (71, '-'), (72, '+'), (73, '='),
    (74, '['), (75, ']'), (76, '{'), (77, '}'), (79, ';'), (80, ':'), (81, '\''), (82, '"'),
    (83, '<'), (85, '>'), (86, '\\'), (89, '|'), (90, ','), (91, '.'), (92, '/'), (93, '?'),
];

fn desktop_char(code: u16, shift: bool) -> Option<char> {
    if code == keys::SPACE {
        return Some(' ');
    }
    DESKTOP_ROWS.iter().find_map(|(first, plain, shifted)| {
        let index = code.checked_sub(*first)? as usize;
        let row = if shift { shifted } else { plain };
        row.chars().nth(index)
    })
}

fn device_char(code: u16, shift: bool) -> Option<char> {
    if let Some((_, symbol)) = DEVICE_SYMBOLS.iter().find(|(symbol_code, _)| *symbol_code == code) {
        return Some(*symbol);
    }
    // Letters, digits and space are where a PC keyboard has them; Shift makes capitals.
    let character = desktop_char(code, false)?;
    if character.is_ascii_alphabetic() {
        Some(if shift { character.to_ascii_uppercase() } else { character })
    } else {
        Some(character).filter(|character| character.is_ascii_digit() || *character == ' ')
    }
}

/// Which characters keys type: the CardputerZero's own keyboard, or a US desktop
/// keyboard (fbsim and the emulator, which set CARDPUTER_INPUT).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Layout {
    Device,
    Desktop,
}

/// Turns key events into typed characters, keeping track of Shift.
pub struct Typist {
    layout: Layout,
    shift: bool,
}

impl Typist {
    pub fn new() -> Typist {
        let layout = if env::var_os("CARDPUTER_INPUT").is_some() { Layout::Desktop } else { Layout::Device };
        Typist { layout, shift: false }
    }

    /// The character a key press types, if any. Feed it every event, releases
    /// included, so it sees Shift go up and down.
    pub fn char_for(&mut self, event: KeyEvent) -> Option<char> {
        if event.code == keys::LEFTSHIFT || event.code == keys::RIGHTSHIFT {
            self.shift = event.is_down();
            return None;
        }
        if !event.is_down() {
            return None;
        }
        match self.layout {
            Layout::Device => device_char(event.code, self.shift),
            Layout::Desktop => desktop_char(event.code, self.shift),
        }
    }
}

/// The built-in keyboard's event device. APPLaunch exports its path to the apps
/// it starts; the fixed by-path name is the same device when run another way.
fn device_keyboard() -> PathBuf {
    ["LV_LINUX_KEYBOARD_DEVICE", "APPLAUNCH_LINUX_KEYBOARD_DEVICE"]
        .iter()
        .filter_map(|variable| env::var_os(variable).filter(|path| !path.is_empty()))
        .map(PathBuf::from)
        .next()
        .unwrap_or_else(|| PathBuf::from("/dev/input/by-path/platform-3f804000.i2c-event"))
}

pub struct Keyboard {
    events: Receiver<KeyEvent>,
}

impl Keyboard {
    pub fn open() -> io::Result<Keyboard> {
        let path = env::var_os("CARDPUTER_INPUT").map(PathBuf::from).unwrap_or_else(device_keyboard);
        let mut file = File::open(&path)
            .map_err(|error| io::Error::new(error.kind(), format!("{}: {error}", path.display())))?;
        let (sender, events) = mpsc::channel();
        thread::spawn(move || {
            let mut record = [0u8; INPUT_EVENT_SIZE];
            while file.read_exact(&mut record).is_ok() {
                if let Some(event) = parse_event(&record) {
                    if sender.send(event).is_err() {
                        break; // the app dropped the Keyboard
                    }
                }
            }
        });
        Ok(Keyboard { events })
    }

    /// The next pending key event, if any. Never blocks.
    pub fn poll(&self) -> Option<KeyEvent> {
        self.events.try_recv().ok()
    }
}
