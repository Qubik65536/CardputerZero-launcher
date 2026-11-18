// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! The home screen: wallpaper, greeting and a menu of the demos.

const std = @import("std");
const c = @import("lvgl.zig");
const ui = @import("ui.zig");

const Action = ui.Action;

pub const DemoInfo = struct {
    name: []const u8,
    description: [*:0]const u8,
};

/// The demos, in menu order (and TAB order).
pub const demos = [_]DemoInfo{
    .{ .name = "Colors", .description = "color triangle and wheel" },
    .{ .name = "Motion", .description = "steer a glowing ball" },
    .{ .name = "REPL", .description = "a tiny calculator language" },
    .{ .name = "Widgets", .description = "text field, slider, more" },
};

const menu_top = 50;
const row_height = 20;
const description_x = 98;

/// Text with a dark shadow, readable on top of a picture.
fn makeShadowedLabel(parent: *c.Obj, text: [*:0]const u8, font: *const c.Font, color: u32, x: i32, y: i32, offset: i32) *c.Obj {
    const shadow = ui.makeLabel(parent, text, font, 0x000000);
    c.lv_obj_set_pos(shadow, x + offset, y + offset);
    const label = ui.makeLabel(parent, text, font, color);
    c.lv_obj_set_pos(label, x, y);
    return label;
}

const MenuRow = struct {
    accent: *c.Obj,
    name: *c.Obj,
    description: *c.Obj,
};

pub const Home = struct {
    screen: ui.Screen,
    selected: usize = 0,
    rows: [demos.len]MenuRow,

    pub fn title(_: *const Home) [*:0]const u8 {
        return "Hello Cardputer";
    }

    fn updateSelection(self: *Home) void {
        for (&self.rows, 0..) |row, index| {
            const selected = index == self.selected;
            c.setHidden(row.accent, !selected);
            c.lv_obj_set_style_text_color(row.name, c.color(if (selected) ui.text_color else ui.muted_color), 0);
            c.lv_obj_set_style_text_color(row.description, c.color(if (selected) ui.language_color else ui.muted_color), 0);
        }
    }

    pub fn init(self: *Home, parent: *c.Obj) void {
        self.* = .{ .screen = .init(parent), .rows = undefined };
        const root = self.screen.root;

        // Images from APPLaunch/share/images/: cp0_app_file_path() finds them both on the
        // device (/usr/share/APPLaunch) and on the desktop (./APPLaunch).
        var path_buffer: [512]u8 = undefined;
        if (c.filePath(&path_buffer, "wallpaper.png")) |path| {
            const wallpaper = c.lv_image_create(root);
            c.lv_image_set_src(wallpaper, path.ptr);
            c.lv_obj_set_pos(wallpaper, 0, 0);
        }

        _ = makeShadowedLabel(root, "Hello, " ++ ui.language ++ "!", &c.lv_font_montserrat_28, ui.language_color, 14, -2, 2);
        _ = makeShadowedLabel(root, "Your CardputerZero app", &c.lv_font_montserrat_14, ui.muted_color, 16, 29, 1);

        _ = ui.makePanel(root, 8, menu_top - 4, ui.content_width - 16, row_height * demos.len + 6, 0x000000, 150);
        inline for (demos, 0..) |demo, index| {
            const y: i32 = menu_top + index * row_height;
            const row = &self.rows[index];
            row.accent = ui.makePanel(root, 8, y - 2, 3, row_height - 2, ui.language_color, c.opa_cover);
            const name = std.fmt.comptimePrint("{d} {s}", .{ index + 1, demo.name });
            row.name = ui.makeLabel(root, name, &c.lv_font_montserrat_14, ui.muted_color);
            c.lv_obj_set_pos(row.name, 18, y);
            row.description = ui.makeLabel(root, demo.description, &c.lv_font_montserrat_14, ui.muted_color);
            c.lv_obj_set_pos(row.description, description_x, y);
        }

        _ = ui.makePanel(root, 0, ui.hint_top - 1, ui.content_width, ui.content_height - ui.hint_top + 1, 0x000000, 170);
        _ = ui.makeHint(root, "F/X choose  ENTER open  ESC quit");
        self.updateSelection();
    }

    pub fn handleKey(self: *Home, key: *const c.Key) Action {
        if (ui.direction(key.code)) |direction| {
            switch (direction) {
                .up, .left => self.selected = (self.selected + demos.len - 1) % demos.len,
                .down, .right => self.selected = (self.selected + 1) % demos.len,
            }
            self.updateSelection();
            return .stay;
        }
        return switch (key.code) {
            ui.keys.enter, ui.keys.space => .{ .open = self.selected },
            ui.keys.digit_1 => .{ .open = 0 },
            ui.keys.digit_2 => .{ .open = 1 },
            ui.keys.digit_3 => .{ .open = 2 },
            ui.keys.digit_4 => .{ .open = 3 },
            // Quit on a short ESC press. (Holding ESC for 3 s makes the launcher kill the app.)
            ui.keys.esc => .quit,
            else => .stay,
        };
    }
};
