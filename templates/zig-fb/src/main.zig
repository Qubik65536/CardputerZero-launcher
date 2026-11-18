// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Hello Cardputer: a minimal CardputerZero app in Zig.
//!
//! Move the square with F/X/Z/C (or the arrow keys), press ENTER to change its
//! color, ESC to quit. Start editing in `App.handleKey` and `App.draw`.

const std = @import("std");
const display_mod = @import("display.zig");
const input = @import("input.zig");

const Display = display_mod.Display;
const rgb = display_mod.rgb;

const frame_time = std.Io.Duration.fromMilliseconds(16); // ~60 frames per second
const background = rgb(16, 20, 24);
const title_bar = rgb(30, 36, 44);
const muted = rgb(150, 160, 170);
const colors = [_]u16{ rgb(79, 195, 247), rgb(129, 199, 132), rgb(255, 183, 77), rgb(240, 98, 146) };
const square = 24;

const App = struct {
    x: i32,
    y: i32,
    color: usize = 0,
    running: bool = true,

    fn init(display: *const Display) App {
        return .{
            .x = @divTrunc(@as(i32, @intCast(display.width)) - square, 2),
            .y = @divTrunc(@as(i32, @intCast(display.height)) - square, 2),
        };
    }

    fn handleKey(self: *App, event: input.KeyEvent, display: *const Display) void {
        if (!event.isDown()) return;
        const step = 6;
        if (input.direction(event.code)) |direction| switch (direction) {
            .left => self.x -= step,
            .right => self.x += step,
            .up => self.y -= step,
            .down => self.y += step,
        } else switch (event.code) {
            input.keys.enter, input.keys.space => self.color = (self.color + 1) % colors.len,
            // Quit on a short ESC press. (Holding ESC for 3 s makes the launcher kill the app.)
            input.keys.esc => self.running = false,
            else => {},
        }
        self.x = std.math.clamp(self.x, 0, @as(i32, @intCast(display.width)) - square);
        self.y = std.math.clamp(self.y, 20, @as(i32, @intCast(display.height)) - square - 14);
    }

    fn draw(self: *const App, display: *Display) void {
        const width: i32 = @intCast(display.width);
        const height: i32 = @intCast(display.height);
        display.clear(background);
        display.fillRect(0, 0, width, 18, title_bar);
        display.drawText(6, 5, "Hello Cardputer", display_mod.white, 1);
        display.fillRect(self.x, self.y, square, square, colors[self.color]);
        const hint = "F/X/Z/C move  ENTER color  ESC quit";
        display.drawText(@divTrunc(width - Display.textWidth(hint, 1), 2), height - 11, hint, muted, 1);
    }
};

// ~220 KB of pixel buffers: static storage rather than the stack.
var screen: Display = undefined;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    try screen.open(io, init.environ_map);
    defer screen.close();
    var keyboard = try input.Keyboard.open(init.environ_map);
    defer keyboard.close(io);

    var app = App.init(&screen);
    var dirty = true;
    while (app.running) {
        while (try keyboard.poll()) |event| {
            app.handleKey(event, &screen);
            dirty = true;
        }
        if (dirty) {
            app.draw(&screen);
            try screen.present();
            dirty = false;
        }
        try io.sleep(frame_time, .awake);
    }
}
