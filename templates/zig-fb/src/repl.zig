// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 3, a terminal-style tool: a read-eval-print loop for the `calc` language.
//! Type a line, ENTER runs it; the screen scrolls like a terminal.

const std = @import("std");
const calc = @import("calc.zig");
const display_mod = @import("display.zig");
const input = @import("input.zig");
const ui = @import("ui.zig");

const Allocator = std.mem.Allocator;
const Display = display_mod.Display;
const keys = input.keys;
const Action = ui.Action;

const columns = 40; // 320 px / 8 px per character
const rows = 9; // text rows below the header; the last one is the input line
const top = ui.header_height + 2;
const max_input = 120;
const max_scrollback = 200;
const prompt = "> ";
const help = [_][]const u8{
    "numbers, + - * / % ^ ( )",
    "x = 6 * 7   ans   abs(x) min(a,b) max",
    "commands: help  vars  clear",
    "UP/DOWN history  TAB next  ESC home",
};

/// One screen row of output.
const Line = struct {
    text: [columns]u8 = undefined,
    len: usize = 0,
    color: u16,
};

pub const Repl = struct {
    gpa: Allocator,
    calculator: calc.Calculator,
    scrollback: [max_scrollback]Line = undefined,
    scrollback_len: usize = 0,
    input: [max_input]u8 = undefined,
    input_len: usize = 0,
    history: std.ArrayList([]u8) = .empty,
    history_index: usize = 0, // == history.items.len while editing a new line

    pub fn init(self: *Repl, gpa: Allocator) void {
        self.* = .{ .gpa = gpa, .calculator = .init(gpa) };
        self.print("calc: whole-number calculator", ui.muted);
        self.print("type help and press ENTER", ui.muted);
    }

    pub fn deinit(self: *Repl) void {
        for (self.history.items) |line| self.gpa.free(line);
        self.history.deinit(self.gpa);
        self.calculator.deinit();
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
    fn printParts(self: *Repl, parts: []const []const u8, color: u16) void {
        var line: Line = .{ .color = color };
        var empty = true;
        for (parts) |part| {
            for (part) |char| {
                if (line.len == columns) {
                    self.pushLine(line);
                    line = .{ .color = color };
                }
                line.text[line.len] = char;
                line.len += 1;
                empty = false;
            }
        }
        if (line.len > 0 or empty) self.pushLine(line);
    }

    /// Add output, wrapped to the screen width.
    fn print(self: *Repl, text: []const u8, color: u16) void {
        self.printParts(&.{text}, color);
    }

    fn submit(self: *Repl) Allocator.Error!void {
        const line = self.input[0..self.input_len];
        self.input_len = 0; // `line` stays readable until the next key is typed
        self.printParts(&.{ prompt, line }, ui.text);
        const command = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (command.len == 0) return;
        const items = self.history.items;
        if (items.len == 0 or !std.mem.eql(u8, items[items.len - 1], command)) {
            const copy = try self.gpa.dupe(u8, command);
            errdefer self.gpa.free(copy);
            try self.history.append(self.gpa, copy);
        }
        self.history_index = self.history.items.len;
        if (std.mem.eql(u8, command, "help")) {
            for (help) |text| self.print(text, ui.muted);
        } else if (std.mem.eql(u8, command, "clear")) {
            self.scrollback_len = 0;
        } else if (std.mem.eql(u8, command, "vars")) {
            const variables = self.calculator.list();
            if (variables.len == 0) self.print("no variables yet", ui.muted);
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
        @memcpy(self.input[0..line.len], line);
        self.input_len = line.len;
    }

    /// `typed` is the character the key produces, if any (see input.Typist).
    pub fn handleKey(self: *Repl, event: input.KeyEvent, typed: ?u8) Allocator.Error!Action {
        if (!event.isDown()) return .stay;
        switch (event.code) {
            keys.esc => return .home,
            keys.tab => return .next,
            keys.enter => try self.submit(),
            keys.backspace => self.input_len -|= 1,
            // Only the real arrow keys: F/X/Z/C are letters here.
            keys.up => self.recall(-1),
            keys.down => self.recall(1),
            else => if (typed) |char| if (self.input_len < max_input) {
                self.input[self.input_len] = char;
                self.input_len += 1;
            },
        }
        return .stay;
    }

    pub fn draw(self: *const Repl, display: *Display) void {
        display.clear(ui.background);
        ui.drawHeader(display, "REPL");
        const visible = self.scrollback[self.scrollback_len -| (rows - 1)..self.scrollback_len];
        for (visible, 0..) |*line, row| {
            display.drawText(0, top + @as(i32, @intCast(row)) * display_mod.char_height, line.text[0..line.len], line.color, 1);
        }
        // The input line sits under the output; long input scrolls to keep the end visible.
        const y = top + @as(i32, @intCast(visible.len)) * display_mod.char_height;
        const room = columns - prompt.len - 1;
        const shown = self.input[self.input_len -| room..self.input_len];
        const prompt_width = Display.textWidth(prompt, 1);
        display.drawText(0, y, prompt, ui.language_color, 1);
        display.drawText(prompt_width, y, shown, ui.text, 1);
        const cursor = prompt_width + Display.textWidth(shown, 1);
        display.fillRect(cursor, y + 2, display_mod.char_width, display_mod.char_height - 4, ui.language_color); // cursor
    }
};
