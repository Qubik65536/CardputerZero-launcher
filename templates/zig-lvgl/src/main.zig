// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Hello Cardputer: a CardputerZero app in Zig, with LVGL widgets.
//!
//! cp0_app_run() (see lvgl.zig) gives the app the launcher's standard page: the 20 px
//! top bar (title, clock, battery) and the 320x150 content area below it, where the
//! app's widgets go. It calls setup() once to build them and onKey() for every key.
//!
//! The home screen greets you and opens four demos: color rendering (colors.zig), an
//! interactive animation with live physics numbers (motion.zig), a terminal-style REPL
//! (repl.zig, running the little language in calc.zig) and a form of real LVGL widgets
//! (widgets.zig). Each is a container in the content area; one shows at a time. TAB
//! moves to the next demo, ESC goes back home, ESC at home quits. Keep what you need
//! and delete the rest.

const std = @import("std");
const c = @import("lvgl.zig");
const colors_mod = @import("colors.zig");
const home_mod = @import("home.zig");
const motion_mod = @import("motion.zig");
const repl_mod = @import("repl.zig");
const ui = @import("ui.zig");
const widgets_mod = @import("widgets.zig");

const Allocator = std.mem.Allocator;
const Action = ui.Action;

/// Which screen is showing; each names a field of App.
const ScreenId = enum { home, colors, motion, repl, widgets };

/// The demos in menu and TAB order (home_mod.demos).
const demo_screens = [_]ScreenId{ .colors, .motion, .repl, .widgets };

const App = struct {
    home: home_mod.Home,
    colors: colors_mod.Colors,
    motion: motion_mod.Motion,
    repl: repl_mod.Repl,
    widgets: widgets_mod.Widgets,
    current: ?ScreenId,

    fn init(self: *App, content: *c.Obj, gpa: Allocator) void {
        self.current = null;
        self.home.init(content);
        self.colors.init(content);
        self.motion.init(content);
        self.repl.init(content, gpa);
        self.widgets.init(content);
    }

    fn deinit(self: *App) void {
        self.repl.deinit();
    }

    fn title(self: *const App) [*:0]const u8 {
        return switch (self.current.?) {
            inline else => |id| @field(self, @tagName(id)).title(),
        };
    }

    /// Hide the current screen and show `id`, calling their onHide/onShow if they have one.
    fn show(self: *App, id: ScreenId) void {
        if (self.current == id) return;
        if (self.current) |current| switch (current) {
            inline else => |shown| {
                const screen = &@field(self, @tagName(shown));
                screen.screen.hide();
                if (@hasDecl(@TypeOf(screen.*), "onHide")) screen.onHide();
            },
        };
        self.current = id;
        switch (id) {
            inline else => |next| {
                const screen = &@field(self, @tagName(next));
                screen.screen.show();
                if (@hasDecl(@TypeOf(screen.*), "onShow")) screen.onShow();
            },
        }
    }

    fn apply(self: *App, action: Action) void {
        switch (action) {
            .stay => {},
            .home => self.show(.home),
            .open => |index| self.show(demo_screens[index]),
            .next => {
                const index = std.mem.indexOfScalar(ScreenId, &demo_screens, self.current.?) orelse 0;
                self.show(demo_screens[(index + 1) % demo_screens.len]);
            },
            .quit => c.cp0_app_quit(),
        }
        // The title follows the screen (and the Colors scene).
        c.cp0_app_set_title(self.title());
    }

    fn handleKey(self: *App, key: *const c.Key) void {
        const action = switch (self.current.?) {
            inline else => |id| @field(self, @tagName(id)).handleKey(key),
        };
        self.apply(action);
    }
};

// The app's state, ~200 KB with the two canvases' pixels: static storage, and it must
// not move, because LVGL callbacks hold pointers into it.
var app: App = undefined;
var app_ready = false;
var app_gpa: Allocator = undefined;

/// cp0_app_run() calls this once, with the content area below the top bar.
fn setup(content: *c.Obj, _: ?*anyopaque) callconv(.c) void {
    // The display exists now and the app's widgets do not yet: set the theme first, so
    // every widget is created with it.
    ui.setTheme(ui.language_color);
    c.lv_obj_set_style_bg_color(content, c.color(ui.background_color), 0);
    c.lv_obj_set_style_bg_opa(content, c.opa_cover, 0);
    app.init(content, app_gpa);
    app_ready = true;
    app.apply(.home);
}

/// cp0_app_run() calls this for every key event: presses, auto-repeats and releases,
/// with the Linux key code and the text the key types (Shift and the keyboard's symbol
/// layer already applied), on the device and on the desktop alike.
fn onKey(key: *const c.Key, _: ?*anyopaque) callconv(.c) void {
    // Releases carry no new input. (Text sent by the automation RPC arrives as released
    // keys without a key code.)
    const injected_text = key.code == 0 and key.text[0] != 0;
    if (key.state == c.Key.released and !injected_text) return;
    if (app_ready) app.handleKey(key);
}

pub fn main(init: std.process.Init) u8 {
    app_gpa = init.gpa;
    // Runs until onKey() calls cp0_app_quit() (ESC on the home screen).
    const status = c.cp0_app_run("Hello Cardputer", setup, onKey, null);
    if (app_ready) app.deinit();
    return std.math.cast(u8, status) orelse 1;
}

test {
    _ = @import("calc.zig");
    _ = @import("lvgl.zig");
    _ = motion_mod;
}
