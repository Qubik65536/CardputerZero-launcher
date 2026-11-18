// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 3, a terminal-style tool: a read-eval-print loop for the `calc` language
//! (calc.zig). Type a line, ENTER runs it; the screen scrolls like a terminal.

const std = @import("std");
const c = @import("lvgl.zig");
const calc = @import("calc.zig");
const ui = @import("ui.zig");

const Allocator = std.mem.Allocator;
const Action = ui.Action;

const font = &c.lv_font_montserrat_14;
const text_left = 4;
const text_top = 2;
const line_height = 16; // lv_font_montserrat_14's line height
const text_width = ui.content_width - 2 * text_left;
const cursor_width = 7;
/// Text rows above the hint line; the last one is the input line.
const rows = 8;
const max_input = 120;
const max_scrollback = 200;
/// Longest output line: text_width is reached long before this many characters.
const max_line = 160;
const prompt = "> ";
const help = [_][]const u8{
    "numbers, + - * / % ^ ( )",
    "x = 6 * 7   ans   abs(x) min(a,b) max",
    "commands: help  vars  clear",
    "UP/DOWN history  TAB next  ESC home",
};

/// Width of `text` in pixels as a label draws it (the text is ASCII).
fn textWidth(text: []const u8) i32 {
    var width: i32 = 0;
    for (text, 0..) |char, index| {
        const next: u32 = if (index + 1 < text.len) text[index + 1] else 0;
        width += c.lv_font_get_glyph_width(font, char, next);
    }
    return width;
}

/// The longest end of `text` that fits in `room` pixels.
fn tailThatFits(text: []const u8, room: i32) []const u8 {
    var start = text.len;
    while (start > 0 and textWidth(text[start - 1 ..]) <= room) start -= 1;
    return text[start..];
}

/// One row of output.
const Line = struct {
    text: [max_line]u8 = undefined,
    len: usize = 0,
    color: u32,

    fn slice(self: *const Line) []const u8 {
        return self.text[0..self.len];
    }
};

pub const Repl = struct {
    screen: ui.Screen,
    gpa: Allocator,
    calculator: calc.Calculator,
    scrollback: [max_scrollback]Line = undefined,
    scrollback_len: usize = 0,
    input: [max_input]u8 = undefined,
    input_len: usize = 0,
    history: std.ArrayList([]u8) = .empty,
    history_index: usize = 0, // == history.items.len while editing a new line

    line_labels: [rows - 1]*c.Obj = undefined,
    prompt_label: *c.Obj = undefined,
    input_label: *c.Obj = undefined,
    cursor: *c.Obj = undefined,

    pub fn title(_: *const Repl) [*:0]const u8 {
        return "REPL";
    }

    fn pushLine(self: *Repl, line: Line) void {
        if (self.scrollback_len == max_scrollback) {
            std.mem.copyForwards(Line, self.scrollback[0 .. max_scrollback - 1], self.scrollback[1..]);
            self.scrollback_len -= 1;
        }
        self.scrollback[self.scrollback_len] = line;
        self.scrollback_len += 1;
    }

    /// Add output made of `parts` joined together, wrapped to the screen width.
    fn printParts(self: *Repl, parts: []const []const u8, color: u32) void {
        var line: Line = .{ .color = color };
        for (parts) |part| {
            for (part) |char| {
                line.text[line.len] = char;
                if (line.len > 0 and (line.len + 1 == max_line or textWidth(line.text[0 .. line.len + 1]) > text_width)) {
                    self.pushLine(line);
                    line = .{ .color = color };
                    line.text[0] = char;
                }
                line.len += 1;
            }
        }
        self.pushLine(line);
    }

    /// Add output, wrapped to the screen width.
    fn print(self: *Repl, text: []const u8, color: u32) void {
        self.printParts(&.{text}, color);
    }

    fn submit(self: *Repl) Allocator.Error!void {
        const line = self.input[0..self.input_len];
        self.input_len = 0; // `line` stays readable until the next key is typed
        self.printParts(&.{ prompt, line }, ui.text_color);
        const command = std.mem.trim(u8, line, " \t");
        if (command.len == 0) return;
        const items = self.history.items;
        if (items.len == 0 or !std.mem.eql(u8, items[items.len - 1], command)) {
            const copy = try self.gpa.dupe(u8, command);
            errdefer self.gpa.free(copy);
            try self.history.append(self.gpa, copy);
        }
        self.history_index = self.history.items.len;

        if (std.mem.eql(u8, command, "help")) {
            for (help) |text| self.print(text, ui.muted_color);
        } else if (std.mem.eql(u8, command, "clear")) {
            self.scrollback_len = 0;
        } else if (std.mem.eql(u8, command, "vars")) {
            const variables = self.calculator.list();
            if (variables.len == 0) self.print("no variables yet", ui.muted_color);
            for (variables) |variable| {
                var number: [24]u8 = undefined;
                const value = std.fmt.bufPrint(&number, "{d}", .{variable.value}) catch unreachable;
                self.printParts(&.{ variable.name, " = ", value }, ui.language_color);
            }
        } else switch (try self.calculator.run(command)) {
            .ok => |result| self.print(result, ui.language_color),
            .err => |message| self.printParts(&.{ "error: ", message }, ui.error_color),
        }
    }

    /// Step through earlier lines: -1 = older, +1 = newer.
    fn recall(self: *Repl, step: isize) void {
        const index = @as(isize, @intCast(self.history_index)) + step;
        if (index < 0 or index > self.history.items.len) return;
        self.history_index = @intCast(index);
        const line: []const u8 = if (self.history_index < self.history.items.len) self.history.items[self.history_index] else "";
        const length = @min(line.len, max_input);
        @memcpy(self.input[0..length], line[0..length]);
        self.input_len = length;
    }

    fn refresh(self: *Repl) void {
        const visible = @min(self.scrollback_len, self.line_labels.len);
        const first = self.scrollback_len - visible;
        for (self.line_labels, 0..) |label, row| {
            if (row >= visible) {
                c.setHidden(label, true);
                continue;
            }
            const line = &self.scrollback[first + row];
            c.setText(label, line.slice());
            c.lv_obj_set_style_text_color(label, c.color(line.color), 0);
            c.setHidden(label, false);
        }

        // The input line sits under the output; long input scrolls to keep the end visible.
        const y = text_top + @as(i32, @intCast(visible)) * line_height;
        const prompt_width = textWidth(prompt);
        const shown = tailThatFits(self.input[0..self.input_len], text_width - prompt_width - cursor_width - 1);
        c.setText(self.input_label, shown);
        c.lv_obj_set_pos(self.prompt_label, text_left, y);
        c.lv_obj_set_pos(self.input_label, text_left + prompt_width, y);
        c.lv_obj_set_pos(self.cursor, text_left + prompt_width + textWidth(shown) + 1, y + 2);
    }

    pub fn init(self: *Repl, parent: *c.Obj, gpa: Allocator) void {
        self.* = .{ .screen = .init(parent), .gpa = gpa, .calculator = .init(gpa) };
        const root = self.screen.root;
        for (&self.line_labels, 0..) |*label, row| {
            label.* = ui.makeLabel(root, "", font, ui.text_color);
            c.lv_obj_set_pos(label.*, text_left, text_top + @as(i32, @intCast(row)) * line_height);
        }
        self.prompt_label = ui.makeLabel(root, prompt, font, ui.language_color);
        self.input_label = ui.makeLabel(root, "", font, ui.text_color);
        self.cursor = ui.makePanel(root, 0, 0, cursor_width, line_height - 4, ui.language_color, c.opa_cover);
        _ = ui.makeHint(root, "UP/DOWN history  TAB next  ESC home");

        self.print("calc: whole-number calculator", ui.muted_color);
        self.print("type help and press ENTER", ui.muted_color);
        self.refresh();
    }

    pub fn deinit(self: *Repl) void {
        for (self.history.items) |line| self.gpa.free(line);
        self.history.deinit(self.gpa);
        self.calculator.deinit();
    }

    pub fn onShow(_: *Repl) void {
        // F/X/Z/C type letters here instead of acting as arrows.
        c.cp0_app_set_text_input(1);
    }

    pub fn onHide(_: *Repl) void {
        c.cp0_app_set_text_input(0);
    }

    pub fn handleKey(self: *Repl, key: *const c.Key) Action {
        switch (key.code) {
            ui.keys.esc => return .home,
            ui.keys.tab => return .next,
            ui.keys.enter => self.submit() catch self.print("error: out of memory", ui.error_color),
            ui.keys.backspace => self.input_len -|= 1,
            // Only the real arrow keys: F/X/Z/C are letters here.
            ui.keys.up => self.recall(-1),
            ui.keys.down => self.recall(1),
            else => if (ui.typedText(key)) |text| {
                if (self.input_len < max_input) {
                    self.input[self.input_len] = text[0];
                    self.input_len += 1;
                }
            },
        }
        self.refresh();
        return .stay;
    }
};
