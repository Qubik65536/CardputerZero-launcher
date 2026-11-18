// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! The home screen: wallpaper, greeting and a menu of the demos.

const std = @import("std");
const display_mod = @import("display.zig");
const input = @import("input.zig");
const ui = @import("ui.zig");

const Display = display_mod.Display;
const keys = input.keys;
const Action = ui.Action;

/// 320x170 RGB565, made with scripts/png_to_rgb565.py. Replace it with your own.
const wallpaper = @embedFile("wallpaper.rgb565");

const Demo = struct { name: []const u8, description: []const u8 };

/// The demos, in menu order: name and a short description.
pub const demos = [_]Demo{
    .{ .name = "Colors", .description = "color triangle and wheel" },
    .{ .name = "Motion", .description = "steer a glowing ball" },
    .{ .name = "REPL", .description = "a tiny calculator language" },
};

const menu_top = 78;
const row_height = 20;

pub const Home = struct {
    selected: usize = 0,

    pub fn handleKey(self: *Home, event: input.KeyEvent) Action {
        if (!event.isDown()) return .stay;
        const count = demos.len;
        if (input.direction(event.code)) |direction| switch (direction) {
            .up, .left => self.selected = (self.selected + count - 1) % count,
            .down, .right => self.selected = (self.selected + 1) % count,
        } else switch (event.code) {
            keys.enter, keys.space => return .{ .open = self.selected },
            keys.digit_1 => return .{ .open = 0 },
            keys.digit_2 => return .{ .open = 1 },
            keys.digit_3 => return .{ .open = 2 },
            // Quit on a short ESC press. (Holding ESC for 3 s makes the launcher kill the app.)
            keys.esc => return .quit,
            else => {},
        }
        return .stay;
    }

    pub fn draw(self: *const Home, display: *Display) void {
        const width: i32 = @intCast(display.width);
        const height: i32 = @intCast(display.height);
        display.drawImage(0, 0, wallpaper);
        ui.drawShadowedText(display, 16, 12, "Hello, " ++ ui.language ++ "!", ui.language_color, 2);
        ui.drawShadowedText(display, 18, 50, "Your CardputerZero app", ui.muted, 1);

        display.shadeRect(8, menu_top - 4, width - 16, row_height * demos.len + 6, 150);
        for (demos, 0..) |demo, index| {
            const y = menu_top + @as(i32, @intCast(index)) * row_height;
            const selected = index == self.selected;
            if (selected) display.fillRect(8, y - 2, 3, row_height - 2, ui.language_color);
            var label_buffer: [32]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buffer, "{d} {s:<7}", .{ index + 1, demo.name }) catch unreachable;
            display.drawText(18, y, label, if (selected) ui.text else ui.muted, 1);
            display.drawText(18 + 10 * 8, y, demo.description, if (selected) ui.language_color else ui.muted, 1);
        }

        display.shadeRect(0, ui.hint_top - 1, width, height - ui.hint_top + 1, 170);
        ui.drawHint(display, "F/X choose  ENTER open  ESC quit");
    }
};
