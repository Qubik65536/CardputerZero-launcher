// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! The app's look, shared by every screen: colors, the header bar and the hint line.

const display_mod = @import("display.zig");

const Display = display_mod.Display;
const rgb = display_mod.rgb;

/// The language this template is written in, and GitHub's color for it.
pub const language = "Zig";
pub const language_color = rgb(0xEC, 0x91, 0x5C);

pub const background = rgb(14, 18, 23);
pub const header = rgb(28, 34, 42);
pub const text = display_mod.white;
pub const muted = rgb(150, 160, 170);
pub const error_color = rgb(255, 110, 110);

/// Height of the header bar; demo content starts below it.
pub const header_height = 20;
/// Top of the hint line at the bottom of the screen.
pub const hint_top = 170 - display_mod.char_height - 1;

/// What a screen asks the app to do after a key press.
pub const Action = union(enum) {
    stay,
    /// Back to the home screen.
    home,
    /// On to the next demo (TAB).
    next,
    /// Open demo number N (0-based) from the home screen.
    open: usize,
    quit,
};

/// The bar at the top of a demo: its title, and how to leave.
pub fn drawHeader(display: *Display, title: []const u8) void {
    const width: i32 = @intCast(display.width);
    display.fillRect(0, 0, width, header_height, header);
    display.drawText(6, 2, title, language_color, 1);
    const keys = "TAB next  ESC home";
    display.drawText(width - Display.textWidth(keys, 1) - 6, 2, keys, muted, 1);
}

/// One line of key help, centered at the bottom of the screen.
pub fn drawHint(display: *Display, hint: []const u8) void {
    const x = @divTrunc(@as(i32, @intCast(display.width)) - Display.textWidth(hint, 1), 2);
    display.drawText(x, hint_top, hint, muted, 1);
}

/// Text with a dark shadow, readable on top of a picture.
pub fn drawShadowedText(display: *Display, x: i32, y: i32, string: []const u8, color: u16, scale: i32) void {
    display.drawText(x + scale, y + scale, string, rgb(0, 0, 0), scale);
    display.drawText(x, y, string, color, scale);
}
