// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! `calc`, the tiny language behind the REPL demo: whole numbers, `+ - * / % ^`,
//! parentheses, variables (`x = 6 * 7`, `ans` is the last result) and the functions
//! `abs`, `min` and `max`. Pure logic, no screen: `zig build test` checks it.

const std = @import("std");

const Allocator = std.mem.Allocator;

const Token = union(enum) {
    number: i64,
    name: []const u8,
    symbol: u8,

    fn isSymbol(self: Token, symbol: u8) bool {
        return self == .symbol and self.symbol == symbol;
    }
};

/// What a line evaluated to: the text to show, or why it failed. Both point into
/// the Calculator and stay valid until its next `run`.
pub const Outcome = union(enum) {
    ok: []const u8,
    err: []const u8,
};

pub const Variable = struct {
    name: []const u8,
    value: i64,
};

/// `error.Invalid` means the line is wrong; the message explaining why is in the
/// Calculator's output.
const Failure = error{ Invalid, OutOfMemory };

/// Collects the message for an `error.Invalid`.
const Messages = struct {
    gpa: Allocator,
    output: *std.ArrayList(u8),

    fn fail(self: Messages, comptime format: []const u8, args: anytype) Failure {
        self.output.clearRetainingCapacity();
        try self.output.print(self.gpa, format, args);
        return error.Invalid;
    }

    fn overflow(self: Messages) Failure {
        return self.fail("overflow", .{});
    }
};

fn tokenize(line: []const u8, gpa: Allocator, tokens: *std.ArrayList(Token), messages: Messages) Failure!void {
    var index: usize = 0;
    while (index < line.len) {
        const char = line[index];
        const start = index;
        if (std.ascii.isWhitespace(char)) {
            index += 1;
        } else if (std.ascii.isDigit(char)) {
            while (index < line.len and std.ascii.isDigit(line[index])) index += 1;
            const value = std.fmt.parseInt(i64, line[start..index], 10) catch return messages.fail("number too large", .{});
            try tokens.append(gpa, .{ .number = value });
        } else if (std.ascii.isAlphabetic(char) or char == '_') {
            while (index < line.len and (std.ascii.isAlphanumeric(line[index]) or line[index] == '_')) index += 1;
            try tokens.append(gpa, .{ .name = line[start..index] });
        } else if (std.mem.indexOfScalar(u8, "+-*/%^()=,", char) != null) {
            try tokens.append(gpa, .{ .symbol = char });
            index += 1;
        } else {
            // Show the whole character, even when it takes several UTF-8 bytes.
            const length = std.unicode.utf8ByteSequenceLength(char) catch 1;
            return messages.fail("unexpected '{s}'", .{line[start..@min(start + length, line.len)]});
        }
    }
}

fn raise(base: i64, exponent: i64, messages: Messages) Failure!i64 {
    if (exponent < 0) return messages.fail("negative exponent", .{});
    if (exponent > std.math.maxInt(u32)) return messages.overflow();
    // Square-and-multiply, skipping the last squaring so that only real overflow fails.
    var remaining: u32 = @intCast(exponent);
    if (remaining == 0) return 1;
    var factor = base;
    var result: i64 = 1;
    while (true) {
        if (remaining & 1 == 1) {
            result = std.math.mul(i64, result, factor) catch return messages.overflow();
            if (remaining == 1) return result;
        }
        remaining /= 2;
        factor = std.math.mul(i64, factor, factor) catch return messages.overflow();
    }
}

/// `values` holds the first two arguments; `count` is how many were given.
fn call(name: []const u8, values: []const i64, count: usize, messages: Messages) Failure!i64 {
    if (std.mem.eql(u8, name, "abs")) {
        if (count != 1) return messages.fail("abs takes 1 argument", .{});
        if (values[0] == std.math.minInt(i64)) return messages.overflow();
        return @intCast(@abs(values[0]));
    }
    if (std.mem.eql(u8, name, "min") or std.mem.eql(u8, name, "max")) {
        if (count != 2) return messages.fail("{s} takes 2 arguments", .{name});
        return if (name[1] == 'i') @min(values[0], values[1]) else @max(values[0], values[1]);
    }
    return messages.fail("unknown function '{s}'", .{name});
}

fn lookup(variables: []const Variable, name: []const u8) ?usize {
    for (variables, 0..) |variable, index| {
        if (std.mem.eql(u8, variable.name, name)) return index;
    }
    return null;
}

/// Recursive-descent evaluator. Grammar, loosest binding first:
///   expression = term (("+" | "-") term)*
///   term       = unary (("*" | "/" | "%") unary)*
///   unary      = "-" unary | power
///   power      = atom ("^" unary)?          (so 2^3^2 = 2^9 and -2^2 = -4)
///   atom       = number | name | name "(" arguments ")" | "(" expression ")"
const Parser = struct {
    tokens: []const Token,
    position: usize = 0,
    variables: []const Variable,
    messages: Messages,

    fn peek(self: *const Parser) ?Token {
        return if (self.position < self.tokens.len) self.tokens[self.position] else null;
    }

    fn nextIs(self: *const Parser, symbol: u8) bool {
        const token = self.peek() orelse return false;
        return token.isSymbol(symbol);
    }

    fn unexpected(self: *const Parser) Failure {
        const token = self.peek() orelse return self.messages.fail("incomplete expression", .{});
        return switch (token) {
            .number => |value| self.messages.fail("unexpected '{d}'", .{value}),
            .name => |name| self.messages.fail("unexpected '{s}'", .{name}),
            .symbol => |symbol| self.messages.fail("unexpected '{c}'", .{symbol}),
        };
    }

    fn expect(self: *Parser, symbol: u8) Failure!void {
        if (!self.nextIs(symbol)) return self.messages.fail("expected '{c}'", .{symbol});
        self.position += 1;
    }

    fn callFunction(self: *Parser, name: []const u8) Failure!i64 {
        var values: [2]i64 = undefined;
        var count: usize = 0;
        if (!self.nextIs(')')) {
            while (true) {
                const value = try self.expression();
                if (count < values.len) values[count] = value;
                count += 1;
                if (!self.nextIs(',')) break;
                self.position += 1;
            }
        }
        try self.expect(')');
        return call(name, values[0..@min(count, values.len)], count, self.messages);
    }

    fn atom(self: *Parser) Failure!i64 {
        const token = self.peek() orelse return self.unexpected();
        switch (token) {
            .number => |value| {
                self.position += 1;
                return value;
            },
            .name => |name| {
                self.position += 1;
                if (self.nextIs('(')) {
                    self.position += 1;
                    return self.callFunction(name);
                }
                const index = lookup(self.variables, name) orelse return self.messages.fail("unknown name '{s}'", .{name});
                return self.variables[index].value;
            },
            .symbol => |symbol| {
                if (symbol != '(') return self.unexpected();
                self.position += 1;
                const value = try self.expression();
                try self.expect(')');
                return value;
            },
        }
    }

    fn power(self: *Parser) Failure!i64 {
        const base = try self.atom();
        if (!self.nextIs('^')) return base;
        self.position += 1;
        const exponent = try self.unary();
        return raise(base, exponent, self.messages);
    }

    fn unary(self: *Parser) Failure!i64 {
        if (self.nextIs('-')) {
            self.position += 1;
            const value = try self.unary();
            return std.math.negate(value) catch self.messages.overflow();
        }
        return self.power();
    }

    fn term(self: *Parser) Failure!i64 {
        var value = try self.unary();
        while (self.peek()) |token| {
            if (!(token.isSymbol('*') or token.isSymbol('/') or token.isSymbol('%'))) break;
            const operator = token.symbol;
            self.position += 1;
            const right = try self.unary();
            if (operator != '*' and right == 0) return self.messages.fail("division by zero", .{});
            // MIN / -1 and MIN % -1 do not fit in an i64.
            if (operator != '*' and right == -1 and value == std.math.minInt(i64)) return self.messages.overflow();
            value = switch (operator) {
                '*' => std.math.mul(i64, value, right) catch return self.messages.overflow(),
                '/' => @divTrunc(value, right),
                else => @rem(value, right),
            };
        }
        return value;
    }

    fn expression(self: *Parser) Failure!i64 {
        var value = try self.term();
        while (self.peek()) |token| {
            if (!(token.isSymbol('+') or token.isSymbol('-'))) break;
            self.position += 1;
            const right = try self.term();
            const result = if (token.symbol == '+') std.math.add(i64, value, right) else std.math.sub(i64, value, right);
            value = result catch return self.messages.overflow();
        }
        return value;
    }
};

const functions = [_][]const u8{ "abs", "min", "max" };

/// The interpreter: variables live as long as it does.
pub const Calculator = struct {
    gpa: Allocator,
    variables: std.ArrayList(Variable) = .empty, // sorted by name
    output: std.ArrayList(u8) = .empty,

    pub fn init(gpa: Allocator) Calculator {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Calculator) void {
        for (self.variables.items) |variable| self.gpa.free(variable.name);
        self.variables.deinit(self.gpa);
        self.output.deinit(self.gpa);
    }

    fn set(self: *Calculator, name: []const u8, value: i64) Allocator.Error!void {
        if (lookup(self.variables.items, name)) |index| {
            self.variables.items[index].value = value;
            return;
        }
        var index: usize = 0;
        while (index < self.variables.items.len and std.mem.order(u8, self.variables.items[index].name, name) == .lt) index += 1;
        const owned = try self.gpa.dupe(u8, name);
        errdefer self.gpa.free(owned);
        try self.variables.insert(self.gpa, index, .{ .name = owned, .value = value });
    }

    fn evaluate(self: *Calculator, line: []const u8, tokens: *std.ArrayList(Token)) Failure![]const u8 {
        const messages: Messages = .{ .gpa = self.gpa, .output = &self.output };
        try tokenize(line, self.gpa, tokens, messages);
        const all = tokens.items;
        const target: ?[]const u8 = if (all.len >= 2 and all[0] == .name and all[1].isSymbol('=')) all[0].name else null;
        if (target) |name| {
            for (functions) |function| {
                if (std.mem.eql(u8, name, function)) return messages.fail("{s} is a function", .{name});
            }
        }
        var parser: Parser = .{
            .tokens = all[if (target != null) 2 else 0..],
            .variables = self.variables.items,
            .messages = messages,
        };
        const value = try parser.expression();
        if (parser.peek() != null) return parser.unexpected();
        try self.set("ans", value);
        self.output.clearRetainingCapacity();
        if (target) |name| {
            try self.set(name, value);
            try self.output.print(self.gpa, "{s} = {d}", .{ name, value });
        } else {
            try self.output.print(self.gpa, "{d}", .{value});
        }
        return self.output.items;
    }

    /// Run one line: an expression (`1 + 2`) or an assignment (`x = 1 + 2`).
    /// The result is the text to show, `3` or `x = 3`.
    pub fn run(self: *Calculator, line: []const u8) Allocator.Error!Outcome {
        var tokens: std.ArrayList(Token) = .empty;
        defer tokens.deinit(self.gpa);
        const text = self.evaluate(line, &tokens) catch |failure| switch (failure) {
            error.Invalid => return .{ .err = self.output.items },
            error.OutOfMemory => return error.OutOfMemory,
        };
        return .{ .ok = text };
    }

    /// Every variable and its value, in name order.
    pub fn list(self: *const Calculator) []const Variable {
        return self.variables.items;
    }
};

fn expectOutcome(calculator: *Calculator, line: []const u8, expected: Outcome) !void {
    const outcome = try calculator.run(line);
    try std.testing.expectEqual(std.meta.activeTag(expected), std.meta.activeTag(outcome));
    switch (expected) {
        inline else => |text, tag| try std.testing.expectEqualStrings(text, @field(outcome, @tagName(tag))),
    }
}

/// Run one line on a fresh Calculator.
fn expectRun(line: []const u8, expected: Outcome) !void {
    var calculator = Calculator.init(std.testing.allocator);
    defer calculator.deinit();
    try expectOutcome(&calculator, line, expected);
}

test "arithmetic follows the usual rules" {
    try expectRun("1 + 2 * 3", .{ .ok = "7" });
    try expectRun("(1 + 2) * 3", .{ .ok = "9" });
    try expectRun("7 / 2", .{ .ok = "3" });
    try expectRun("-7 / 2", .{ .ok = "-3" });
    try expectRun("-7 % 3", .{ .ok = "-1" });
    try expectRun("2 ^ 3 ^ 2", .{ .ok = "512" });
    try expectRun("-2 ^ 2", .{ .ok = "-4" });
    try expectRun("10 - 4 - 3", .{ .ok = "3" });
    try expectRun("max(3, abs(-8)) + min(1, 2)", .{ .ok = "9" });
}

test "variables and ans persist" {
    var calculator = Calculator.init(std.testing.allocator);
    defer calculator.deinit();
    try expectOutcome(&calculator, "x = 6 * 7", .{ .ok = "x = 42" });
    try expectOutcome(&calculator, "x + 1", .{ .ok = "43" });
    try expectOutcome(&calculator, "ans * 2", .{ .ok = "86" });
    const variables = calculator.list();
    try std.testing.expectEqual(2, variables.len);
    try std.testing.expectEqualStrings("ans", variables[0].name);
    try std.testing.expectEqual(86, variables[0].value);
    try std.testing.expectEqualStrings("x", variables[1].name);
    try std.testing.expectEqual(42, variables[1].value);
}

test "mistakes are explained" {
    try expectRun("1 / 0", .{ .err = "division by zero" });
    try expectRun("y + 1", .{ .err = "unknown name 'y'" });
    try expectRun("(1 + 2", .{ .err = "expected ')'" });
    try expectRun("1 +", .{ .err = "incomplete expression" });
    try expectRun("1 2", .{ .err = "unexpected '2'" });
    try expectRun("2 $ 3", .{ .err = "unexpected '$'" });
    try expectRun("2 ^ -1", .{ .err = "negative exponent" });
    try expectRun("2 ^ 64", .{ .err = "overflow" });
    try expectRun("abs(1, 2)", .{ .err = "abs takes 1 argument" });
    try expectRun("sqrt(4)", .{ .err = "unknown function 'sqrt'" });
    try expectRun("max = 3", .{ .err = "max is a function" });
    try expectRun("99999999999999999999", .{ .err = "number too large" });
}
