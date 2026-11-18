// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! The app: owns the screens, shows one at a time and routes keys.
//!
//! The home screen greets you and opens four demos: color rendering
//! (colors.rs), an interactive animation with live physics numbers
//! (motion.rs), a terminal-style REPL (repl.rs, running the little language in
//! calc.rs) and a form of real LVGL widgets (widgets.rs). Each is a `Screen`
//! inside the content area below the top bar; one shows at a time. TAB moves to
//! the next demo, ESC goes back home, ESC at home quits. Keep what you need and
//! delete the rest.

use std::cell::Cell;

use crate::colors::ColorsScreen;
use crate::home::HomeScreen;
use crate::lvgl::{self, color_hex, App, Key, KeyState, Obj, LV_OPA_COVER};
use crate::motion::MotionScreen;
use crate::repl::ReplScreen;
use crate::ui::{Action, Screen, BACKGROUND_COLOR};
use crate::widgets::WidgetsScreen;

/// Which screen is showing.
#[derive(Clone, Copy, PartialEq, Eq)]
enum ScreenId {
    Home,
    Colors,
    Motion,
    Repl,
    Widgets,
}

/// The demos in menu and TAB order (home::DEMOS).
const DEMOS: [ScreenId; 4] = [ScreenId::Colors, ScreenId::Motion, ScreenId::Repl, ScreenId::Widgets];

pub struct HelloCardputer {
    home: &'static HomeScreen,
    colors: &'static ColorsScreen,
    motion: &'static MotionScreen,
    repl: &'static ReplScreen,
    widgets: &'static WidgetsScreen,
    current: Cell<ScreenId>,
}

impl HelloCardputer {
    fn screen(&self, id: ScreenId) -> &'static dyn Screen {
        match id {
            ScreenId::Home => self.home,
            ScreenId::Colors => self.colors,
            ScreenId::Motion => self.motion,
            ScreenId::Repl => self.repl,
            ScreenId::Widgets => self.widgets,
        }
    }

    fn show(&self, id: ScreenId) {
        if self.current.get() == id {
            return;
        }
        self.screen(self.current.get()).hide();
        self.current.set(id);
        self.screen(id).show();
    }

    fn apply(&self, action: Action) {
        match action {
            Action::Stay => {}
            Action::Home => self.show(ScreenId::Home),
            Action::Open(demo) => self.show(DEMOS[demo]),
            Action::Next => {
                let index = DEMOS.iter().position(|id| *id == self.current.get()).unwrap_or(0);
                self.show(DEMOS[(index + 1) % DEMOS.len()]);
            }
            Action::Quit => lvgl::quit(),
        }
        // The title follows the screen (and the Colors scene).
        lvgl::set_title(&self.screen(self.current.get()).title());
    }

    /// Build the UI on `content`, the 320x150 area below the top bar.
    pub fn new(content: Obj) -> &'static HelloCardputer {
        content.set_style_bg_color(color_hex(BACKGROUND_COLOR), 0);
        content.set_style_bg_opa(LV_OPA_COVER, 0);
        let app: &'static HelloCardputer = Box::leak(Box::new(HelloCardputer {
            home: HomeScreen::new(content),
            colors: ColorsScreen::new(content),
            motion: MotionScreen::new(content),
            repl: ReplScreen::new(content),
            widgets: WidgetsScreen::new(content),
            current: Cell::new(ScreenId::Home),
        }));
        app.home.show();
        app.apply(Action::Stay);
        app
    }
}

impl App for HelloCardputer {
    /// cp0_lvgl sends every key here, with the Linux key code, modifiers and the
    /// text it types (Shift and the keyboard's symbol layer already applied), on
    /// the device and on the desktop alike.
    fn on_key(&self, key: &Key) {
        // Key presses and auto-repeats; releases carry no new input. (Text sent by
        // the automation RPC arrives as released items without a key code.)
        let injected_text = key.code == 0 && !key.text.is_empty();
        if key.state == KeyState::Released && !injected_text {
            return;
        }
        self.apply(self.screen(self.current.get()).handle_key(key));
    }
}
