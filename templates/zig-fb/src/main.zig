// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Hello Cardputer: a CardputerZero app in Zig.
//!
//! The home screen greets you and opens three demos: color rendering (`colors.zig`),
//! an interactive animation (`motion.zig`) and a terminal-style REPL (`repl.zig`, running
//! the little language in `calc.zig`). TAB moves to the next demo, ESC goes back home,
//! ESC at home quits. Keep what you need and delete the rest.

const std = @import("std");
const colors_mod = @import("colors.zig");
const display_mod = @import("display.zig");
const home_mod = @import("home.zig");
const input = @import("input.zig");
const motion_mod = @import("motion.zig");
const repl_mod = @import("repl.zig");
const ui = @import("ui.zig");

const Allocator = std.mem.Allocator;
const Display = display_mod.Display;
const Action = ui.Action;

const frame_time = std.Io.Duration.fromMilliseconds(16); // ~60 frames per second

/// Which screen is showing. The demos are in home.demos order.
const Screen = enum { home, colors, motion, repl };

const demo_screens = [_]Screen{ .colors, .motion, .repl };

const App = struct {
    screen: Screen = .home,
    home: home_mod.Home = .{},
    colors: colors_mod.Colors = .{},
    motion: motion_mod.Motion = .{},
    repl: repl_mod.Repl = undefined,
    running: bool = true,

    fn init(self: *App, gpa: Allocator) void {
        self.* = .{};
        self.repl.init(gpa);
    }

    fn deinit(self: *App) void {
        self.repl.deinit();
    }

    fn apply(self: *App, action: Action) void {
        switch (action) {
            .stay => {},
            .home => self.screen = .home,
            .open => |index| self.screen = demo_screens[index],
            .next => {
                const index = std.mem.indexOfScalar(Screen, &demo_screens, self.screen) orelse 0;
                self.screen = demo_screens[(index + 1) % demo_screens.len];
            },
            .quit => self.running = false,
        }
    }

    fn handleKey(self: *App, event: input.KeyEvent, typed: ?u8) Allocator.Error!void {
        const action = switch (self.screen) {
            .home => self.home.handleKey(event),
            .colors => self.colors.handleKey(event),
            .motion => self.motion.handleKey(event),
            .repl => try self.repl.handleKey(event, typed),
        };
        self.apply(action);
    }

    /// Advance animations by one frame. Returns true if the screen needs redrawing.
    fn tick(self: *App) bool {
        switch (self.screen) {
            .colors => {
                self.colors.tick();
                return self.colors.animated();
            },
            .motion => {
                self.motion.tick();
                return true;
            },
            .home, .repl => return false,
        }
    }

    fn draw(self: *const App, display: *Display) void {
        switch (self.screen) {
            .home => self.home.draw(display),
            .colors => self.colors.draw(display),
            .motion => self.motion.draw(display),
            .repl => self.repl.draw(display),
        }
    }
};

// ~220 KB of pixel buffers and the app's state: static storage rather than the stack.
var screen: Display = undefined;
var app: App = undefined;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    try screen.open(io, init.environ_map);
    defer screen.close();
    var keyboard = try input.Keyboard.open(init.environ_map);
    defer keyboard.close(io);
    var typist = input.Typist.init(init.environ_map);

    app.init(init.gpa);
    defer app.deinit();
    var dirty = true;
    while (app.running) {
        while (try keyboard.poll()) |event| {
            const typed = typist.charFor(event); // every event, so Shift is tracked
            try app.handleKey(event, typed);
            dirty = true;
        }
        if (app.tick() or dirty) {
            app.draw(&screen);
            try screen.present();
            dirty = false;
        }
        try io.sleep(frame_time, .awake);
    }
}
