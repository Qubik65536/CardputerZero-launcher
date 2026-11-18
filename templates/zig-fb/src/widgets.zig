// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 4, widgets: a small form with a text field, a button, a slider, a counter, a
//! chooser and a switch, drawn by hand on the framebuffer. One widget has the focus;
//! F/X move it, Z/C change the value, ENTER presses. The text field takes typing.

const std = @import("std");
const display_mod = @import("display.zig");
const input = @import("input.zig");
const ui = @import("ui.zig");

const Display = display_mod.Display;
const rgb = display_mod.rgb;
const keys = input.keys;
const Action = ui.Action;
const char_width = display_mod.char_width;
const char_height = display_mod.char_height;

const Widget = enum { name, button, volume, count, color, sound };

const Row = struct { widget: Widget, label: []const u8 };

/// The form, top to bottom, with each row's label.
const rows = [_]Row{
    .{ .widget = .name, .label = "Name" },
    .{ .widget = .button, .label = "Button" },
    .{ .widget = .volume, .label = "Volume" },
    .{ .widget = .count, .label = "Count" },
    .{ .widget = .color, .label = "Color" },
    .{ .widget = .sound, .label = "Sound" },
};

const Choice = struct { name: []const u8, color: u16 };

/// The chooser's options: each template language and GitHub's color for it.
const choices = [_]Choice{
    .{ .name = "Rust", .color = rgb(0xDE, 0xA5, 0x84) },
    .{ .name = "Zig", .color = rgb(0xEC, 0x91, 0x5C) },
    .{ .name = "OCaml", .color = rgb(0xEF, 0x7A, 0x08) },
    .{ .name = "C++", .color = rgb(0xF3, 0x4B, 0x7D) },
};

const top = ui.header_height + 2;
const row_height = 18;
const widget_left = 72; // labels on the left, widgets from here
const widget_width = 242;
const max_name = 24;
const slider_width = 176;
const volume_step = 5;
const press_frames = 10; // how long the button shows as pressed
const max_status = 48;
const field = rgb(8, 10, 14);
const border = rgb(60, 70, 82);
const face = rgb(28, 34, 42);

/// The chooser starts on the language this template is written in.
fn languageChoice() usize {
    for (choices, 0..) |choice, index| {
        if (std.mem.eql(u8, choice.name, ui.language)) return index;
    }
    return 0;
}

/// `index + step`, wrapping around within 0..count.
fn wrap(index: usize, step: i32, count: usize) usize {
    return @intCast(@mod(@as(i32, @intCast(index)) + step, @as(i32, @intCast(count))));
}

/// Fixed-size text that `bufPrint` can fill.
fn Text(comptime capacity: usize) type {
    return struct {
        bytes: [capacity]u8 = undefined,
        len: usize = 0,

        fn of(comptime string: []const u8) @This() {
            var text: @This() = .{ .len = string.len };
            @memcpy(text.bytes[0..string.len], string);
            return text;
        }

        fn slice(self: *const @This()) []const u8 {
            return self.bytes[0..self.len];
        }

        fn set(self: *@This(), comptime format: []const u8, args: anytype) void {
            const written = std.fmt.bufPrint(&self.bytes, format, args) catch unreachable;
            self.len = written.len;
        }
    };
}

pub const Widgets = struct {
    focus: usize = 0, // index into rows
    name: Text(max_name) = .{},
    volume: i32 = 50, // 0..100
    count: i32 = 0,
    choice: usize = languageChoice(), // index into choices
    sound: bool = true,
    pressed_frames: u32 = 0,
    status: Text(max_status) = .of("Try every widget"), // what the last action did

    /// The accent color is whatever the chooser picked.
    fn accent(self: *const Widgets) u16 {
        return choices[self.choice].color;
    }

    fn focused(self: *const Widgets) Widget {
        return rows[self.focus].widget;
    }

    /// True while the button shows its pressed state.
    pub fn animated(self: *const Widgets) bool {
        return self.pressed_frames > 0;
    }

    pub fn tick(self: *Widgets) void {
        self.pressed_frames -|= 1;
    }

    fn moveFocus(self: *Widgets, step: i32) void {
        self.focus = wrap(self.focus, step, rows.len);
    }

    /// Z/C (or left/right): step the focused widget's value.
    fn change(self: *Widgets, step: i32) void {
        switch (self.focused()) {
            .volume => {
                self.volume = std.math.clamp(self.volume + step * volume_step, 0, 100);
                self.status.set("Volume {d}", .{self.volume});
            },
            .count => {
                self.count += step;
                self.status.set("Count {d}", .{self.count});
            },
            .color => {
                self.choice = wrap(self.choice, step, choices.len);
                self.status.set("Color {s}", .{choices[self.choice].name});
            },
            .sound => {
                self.sound = !self.sound;
                self.status.set("Sound {s}", .{if (self.sound) "on" else "off"});
            },
            .name, .button => {},
        }
    }

    /// ENTER or SPACE on the focused widget.
    fn activate(self: *Widgets) void {
        switch (self.focused()) {
            .button => {
                self.pressed_frames = press_frames;
                const name = std.mem.trim(u8, self.name.slice(), &std.ascii.whitespace);
                self.status.set("Hello, {s}!", .{if (name.len == 0) "stranger" else name});
            },
            .count => {
                self.count = 0;
                self.status.set("Count reset", .{});
            },
            .color, .sound => self.change(1),
            .name => self.moveFocus(1),
            .volume => {},
        }
    }

    /// `typed` is the character the key produces, if any (see input.Typist).
    pub fn handleKey(self: *Widgets, event: input.KeyEvent, typed: ?u8) Action {
        if (!event.isDown()) return .stay;
        switch (event.code) {
            keys.esc => return .home,
            keys.tab => return .next,
            // Real arrow keys always move the focus, even out of the text field.
            keys.up => self.moveFocus(-1),
            keys.down => self.moveFocus(1),
            else => if (self.focused() == .name) switch (event.code) {
                // In the text field F/X/Z/C are letters; ENTER moves on.
                keys.enter => self.moveFocus(1),
                keys.backspace => self.name.len -|= 1,
                else => if (typed) |char| if (self.name.len < max_name) {
                    self.name.bytes[self.name.len] = char;
                    self.name.len += 1;
                },
            } else if (input.direction(event.code)) |direction| switch (direction) {
                .up => self.moveFocus(-1),
                .down => self.moveFocus(1),
                .left => self.change(-1),
                .right => self.change(1),
            } else if (event.code == keys.enter or event.code == keys.space) {
                self.activate();
            },
        }
        return .stay;
    }

    fn drawTextField(self: *const Widgets, display: *Display, y: i32, is_focused: bool) void {
        const color = self.accent();
        display.fillRect(widget_left, y, widget_width, row_height, field);
        display.strokeRect(widget_left, y, widget_width, row_height, if (is_focused) color else border);
        if (self.name.len == 0 and !is_focused) {
            display.drawText(widget_left + 4, y + 1, "your name", ui.muted, 1);
            return;
        }
        display.drawText(widget_left + 4, y + 1, self.name.slice(), ui.text, 1);
        if (is_focused) {
            const width = Display.textWidth(self.name.slice(), 1);
            display.fillRect(widget_left + 4 + width, y + 3, char_width, char_height - 4, color); // cursor
        }
    }

    fn drawButton(self: *const Widgets, display: *Display, y: i32, is_focused: bool) void {
        const color = self.accent();
        const width = 120;
        const label = "Say hello";
        const pressed = self.pressed_frames > 0;
        display.fillRect(widget_left, y, width, row_height, if (pressed) color else face);
        display.strokeRect(widget_left, y, width, row_height, if (is_focused) color else border);
        const x = widget_left + @divTrunc(width - Display.textWidth(label, 1), 2);
        display.drawText(x, y + 1, label, if (pressed) ui.background else ui.text, 1);
    }

    fn drawSlider(self: *const Widgets, display: *Display, y: i32, is_focused: bool) void {
        const color = self.accent();
        const filled = @divTrunc(self.volume * slider_width, 100);
        display.fillRect(widget_left, y + 7, slider_width, 4, border);
        display.fillRect(widget_left, y + 7, filled, 4, color);
        const knob = widget_left + filled - 3;
        display.fillRect(knob, y + 2, 6, row_height - 4, if (is_focused) ui.text else ui.muted);
        var number: [12]u8 = undefined;
        const value = std.fmt.bufPrint(&number, "{d}", .{self.volume}) catch unreachable;
        display.drawText(widget_left + slider_width + 12, y + 1, value, ui.text, 1);
    }

    fn drawCounter(self: *const Widgets, display: *Display, y: i32, is_focused: bool) void {
        const outline = if (is_focused) self.accent() else border;
        const buttons = [_]struct { x: i32, sign: []const u8 }{
            .{ .x = widget_left, .sign = "-" },
            .{ .x = widget_left + 84, .sign = "+" },
        };
        for (buttons) |button| {
            display.fillRect(button.x, y, 24, row_height, face);
            display.strokeRect(button.x, y, 24, row_height, outline);
            display.drawText(button.x + 8, y + 1, button.sign, ui.text, 1);
        }
        var number: [12]u8 = undefined;
        const value = std.fmt.bufPrint(&number, "{d}", .{self.count}) catch unreachable;
        const x = widget_left + 24 + @divTrunc(60 - Display.textWidth(value, 1), 2);
        display.drawText(x, y + 1, value, ui.text, 1);
    }

    fn drawChooser(self: *const Widgets, display: *Display, y: i32, is_focused: bool) void {
        const choice = choices[self.choice];
        const arrows = if (is_focused) self.accent() else ui.muted;
        display.drawText(widget_left, y + 1, "<", arrows, 1);
        display.drawText(widget_left + 16, y + 1, choice.name, choice.color, 1);
        display.drawText(widget_left + 16 + 6 * char_width, y + 1, ">", arrows, 1);
        display.fillRect(widget_left + 16 + 8 * char_width, y + 2, 14, row_height - 4, choice.color); // swatch
    }

    fn drawSwitch(self: *const Widgets, display: *Display, y: i32, is_focused: bool) void {
        const color = self.accent();
        display.fillRect(widget_left, y + 2, 32, row_height - 4, if (self.sound) color else border);
        if (is_focused) display.strokeRect(widget_left - 2, y, 36, row_height, ui.text);
        const knob: i32 = if (self.sound) widget_left + 18 else widget_left + 2;
        display.fillRect(knob, y + 4, 12, row_height - 8, ui.text);
        display.drawText(widget_left + 40, y + 1, if (self.sound) "on" else "off", ui.text, 1);
    }

    pub fn draw(self: *const Widgets, display: *Display) void {
        const color = self.accent();
        display.clear(ui.background);
        for (rows, 0..) |row, index| {
            const y = top + @as(i32, @intCast(index)) * row_height;
            const is_focused = index == self.focus;
            if (is_focused) display.fillRect(0, y, 3, row_height, color);
            display.drawText(8, y + 1, row.label, if (is_focused) color else ui.muted, 1);
            switch (row.widget) {
                .name => self.drawTextField(display, y, is_focused),
                .button => self.drawButton(display, y, is_focused),
                .volume => self.drawSlider(display, y, is_focused),
                .count => self.drawCounter(display, y, is_focused),
                .color => self.drawChooser(display, y, is_focused),
                .sound => self.drawSwitch(display, y, is_focused),
            }
        }
        display.drawText(8, top + rows.len * row_height + 2, self.status.slice(), color, 1);
        ui.drawHeader(display, "Widgets");
        ui.drawHint(display, if (self.focused() == .name) "type a name  ENTER next" else "F/X move  Z/C change  ENTER press");
    }
};
