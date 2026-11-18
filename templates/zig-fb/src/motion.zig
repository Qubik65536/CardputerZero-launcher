// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 2, interactive rendering: push a glowing ball around. It keeps its momentum,
//! leaves a trail and throws sparks when it bounces off the walls. A readout shows its
//! physics live: speed, direction, velocity, kinetic energy, wall hits and a speed graph.

const std = @import("std");
const display_mod = @import("display.zig");
const input = @import("input.zig");
const ui = @import("ui.zig");

const Display = display_mod.Display;
const rgb = display_mod.rgb;
const keys = input.keys;
const Action = ui.Action;

const ball_radius: f32 = 9.0;
const push: f32 = 1.2; // speed added per key press, pixels per frame
const friction: f32 = 0.99; // speed kept each frame
const bounce: f32 = 0.85; // speed kept when bouncing
const trail_length = 14;
const sparks_per_bounce = 10;
const spark_life: u32 = 30; // frames
// At most two bounces per frame, each spark living spark_life frames.
const max_sparks = 2 * sparks_per_bounce * spark_life;
const grid = rgb(36, 44, 54);
const mass: f32 = 1.0; // for the kinetic energy readout
const arrow_scale: f32 = 8.0; // velocity arrow length per pixel/frame of speed
const graph_samples = 96; // one per frame, also the graph's width in pixels
const graph_height = 36;
const graph_max_speed: f32 = 10.0; // pixels/frame at the top of the graph
const colors = [_]u16{ ui.language_color, rgb(79, 195, 247), rgb(129, 199, 132), rgb(240, 98, 146) };

// The area the ball moves in: below the header, above the hint line.
const left: f32 = 0.0;
const right: f32 = 320.0;
const top: f32 = ui.header_height;
const bottom: f32 = ui.hint_top - 2;

const Spark = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: u32,
};

/// A small pseudo-random generator (xorshift), so the sparks need no dependencies.
const Random = struct {
    state: u32,

    /// A number from -1 to 1.
    fn nextSigned(self: *Random) f32 {
        self.state ^= self.state << 13;
        self.state ^= self.state >> 17;
        self.state ^= self.state << 5;
        return @as(f32, @floatFromInt(self.state % 2001)) / 1000.0 - 1.0;
    }
};

/// `value` with two decimals, written into `buffer`; `plus` adds "+" to non-negative
/// numbers (std.fmt has no "+" flag), so the readout matches Rust's `{:+.2}`.
fn formatFixed2(buffer: []u8, value: f32, plus: bool) []const u8 {
    const sign = if (plus and !std.math.signbit(value)) "+" else "";
    return std.fmt.bufPrint(buffer, "{s}{d:.2}", .{ sign, value }) catch buffer[0..0];
}

pub const Motion = struct {
    x: f32 = (left + right) / 2.0,
    y: f32 = (top + bottom) / 2.0,
    vx: f32 = 0.0,
    vy: f32 = 0.0,
    trail: [trail_length][2]f32 = undefined, // newest first
    trail_len: usize = 0,
    sparks: [max_sparks]Spark = undefined,
    spark_count: usize = 0,
    color: usize = 0,
    random: Random = .{ .state = 0x2545_F491 },
    hits: u32 = 0,
    speeds: [graph_samples]f32 = undefined, // newest first
    speed_count: usize = 0,

    fn speed(self: *const Motion) f32 {
        return @sqrt(self.vx * self.vx + self.vy * self.vy);
    }

    /// A wall hit: count it and throw sparks from the contact point.
    fn burst(self: *Motion, x: f32, y: f32) void {
        self.hits += 1;
        for (0..sparks_per_bounce) |_| {
            const vx = self.random.nextSigned() * 2.5;
            const vy = self.random.nextSigned() * 2.5 - 1.0;
            if (self.spark_count == max_sparks) continue;
            self.sparks[self.spark_count] = .{ .x = x, .y = y, .vx = vx, .vy = vy, .life = spark_life };
            self.spark_count += 1;
        }
    }

    /// Advance one frame: move, bounce, age the trail and the sparks.
    pub fn tick(self: *Motion) void {
        self.x += self.vx;
        self.y += self.vy;
        self.vx *= friction;
        self.vy *= friction;
        if (self.x < left + ball_radius or self.x > right - ball_radius) {
            self.x = std.math.clamp(self.x, left + ball_radius, right - ball_radius);
            self.vx = -self.vx * bounce;
            if (@abs(self.vx) > 0.6) {
                const edge = if (self.vx > 0.0) self.x - ball_radius else self.x + ball_radius;
                self.burst(edge, self.y);
            }
        }
        if (self.y < top + ball_radius or self.y > bottom - ball_radius) {
            self.y = std.math.clamp(self.y, top + ball_radius, bottom - ball_radius);
            self.vy = -self.vy * bounce;
            if (@abs(self.vy) > 0.6) {
                const edge = if (self.vy > 0.0) self.y - ball_radius else self.y + ball_radius;
                self.burst(self.x, edge);
            }
        }
        self.trail_len = @min(self.trail_len + 1, trail_length);
        std.mem.copyBackwards([2]f32, self.trail[1..self.trail_len], self.trail[0 .. self.trail_len - 1]);
        self.trail[0] = .{ self.x, self.y };
        self.speed_count = @min(self.speed_count + 1, graph_samples);
        std.mem.copyBackwards(f32, self.speeds[1..self.speed_count], self.speeds[0 .. self.speed_count - 1]);
        self.speeds[0] = self.speed();
        var kept: usize = 0;
        for (self.sparks[0..self.spark_count]) |spark| {
            var moved = spark;
            moved.x += moved.vx;
            moved.y += moved.vy;
            moved.vy += 0.08; // gravity
            moved.life -= 1;
            if (moved.life == 0) continue;
            self.sparks[kept] = moved;
            kept += 1;
        }
        self.spark_count = kept;
    }

    pub fn handleKey(self: *Motion, event: input.KeyEvent) Action {
        if (!event.isDown()) return .stay;
        if (input.direction(event.code)) |direction| switch (direction) {
            .left => self.vx -= push,
            .right => self.vx += push,
            .up => self.vy -= push,
            .down => self.vy += push,
        } else switch (event.code) {
            keys.enter => self.color = (self.color + 1) % colors.len,
            keys.space => {
                self.vx = 0.0;
                self.vy = 0.0;
            },
            keys.tab => return .next,
            keys.esc => return .home,
            else => {},
        }
        return .stay;
    }

    /// Numbers about the ball's motion, top left.
    fn drawReadout(self: *const Motion, display: *Display) void {
        const current = self.speed();
        // Screen y grows downwards; flip it so 90 degrees points up, as in math.
        var degrees = @rem(std.math.radiansToDegrees(std.math.atan2(-self.vy, self.vx)), 360.0);
        if (degrees < 0.0) degrees += 360.0;
        const direction = @rem(@as(i32, @intFromFloat(@round(degrees))), 360);
        const energy = 0.5 * mass * current * current;
        var numbers: [4][48]u8 = undefined;
        var buffers: [3][112]u8 = undefined;
        const lines = [_][]const u8{
            std.fmt.bufPrint(&buffers[0], "speed {s}  dir {d}", .{ formatFixed2(&numbers[0], current, false), direction }) catch unreachable,
            std.fmt.bufPrint(&buffers[1], "vx {s}  vy {s}", .{ formatFixed2(&numbers[1], self.vx, true), formatFixed2(&numbers[2], self.vy, true) }) catch unreachable,
            std.fmt.bufPrint(&buffers[2], "energy {s}  hits {d}", .{ formatFixed2(&numbers[3], energy, false), self.hits }) catch unreachable,
        };
        const panel_top: i32 = @as(i32, @intFromFloat(top)) + 2;
        display.shadeRect(0, panel_top, 172, lines.len * display_mod.char_height + 4, 150);
        for (lines, 0..) |line, row| {
            display.drawText(4, panel_top + 2 + @as(i32, @intCast(row)) * display_mod.char_height, line, ui.text, 1);
        }
    }

    /// Speed over the last graph_samples frames, top right, newest on the right.
    fn drawGraph(self: *const Motion, display: *Display, color: u16) void {
        const graph_left: i32 = @as(i32, @intFromFloat(right)) - graph_samples - 4;
        const graph_top: i32 = @as(i32, @intFromFloat(top)) + 2;
        const graph_bottom = graph_top + graph_height - 1;
        display.shadeRect(graph_left - 2, graph_top, graph_samples + 4, graph_height + 2, 150);
        var previous: ?[2]i32 = null;
        for (self.speeds[0..self.speed_count], 0..) |sample, age| {
            const height: i32 = @intFromFloat(@min(sample / graph_max_speed, 1.0) * (graph_height - 2));
            const point = [2]i32{ graph_left + graph_samples - 1 - @as(i32, @intCast(age)), graph_bottom - height };
            if (previous) |from| display.drawLine(from[0], from[1], point[0], point[1], color);
            previous = point;
        }
    }

    pub fn draw(self: *const Motion, display: *Display) void {
        const color = colors[self.color];
        display.clear(ui.background);
        var grid_y: i32 = @as(i32, @intFromFloat(top)) + 8;
        while (grid_y < @as(i32, @intFromFloat(bottom))) : (grid_y += 16) {
            var grid_x: i32 = 8;
            while (grid_x < @as(i32, @intFromFloat(right))) : (grid_x += 16) display.setPixel(grid_x, grid_y, grid);
        }
        // Oldest trail first, so newer, brighter circles land on top.
        const length: f32 = @floatFromInt(self.trail_len);
        var age = self.trail_len;
        while (age > 0) {
            age -= 1;
            const x, const y = self.trail[age];
            const fade = 1.0 - @as(f32, @floatFromInt(age)) / length;
            const size: i32 = @intFromFloat(ball_radius * (0.3 + 0.6 * fade));
            display.fillCircle(@intFromFloat(x), @intFromFloat(y), size, color, @intFromFloat(90.0 * fade));
        }
        for (self.sparks[0..self.spark_count]) |spark| {
            const alpha: u8 = @intCast(spark.life * 255 / spark_life);
            display.fillCircle(@intFromFloat(spark.x), @intFromFloat(spark.y), 1, color, alpha);
        }
        const x: i32 = @intFromFloat(self.x);
        const y: i32 = @intFromFloat(self.y);
        const size: i32 = @intFromFloat(ball_radius);
        display.fillCircle(x, y, size + 6, color, 35); // glow
        display.fillCircle(x, y, size + 3, color, 70);
        display.fillCircle(x, y, size, color, 255);
        display.fillCircle(x - 3, y - 3, 3, display_mod.white, 140); // highlight
        if (self.speed() > 0.05) {
            // Velocity arrow: where the ball is heading, and how fast.
            const tip_x: i32 = @intFromFloat(self.x + self.vx * arrow_scale);
            const tip_y: i32 = @intFromFloat(self.y + self.vy * arrow_scale);
            display.drawLine(x, y, tip_x, tip_y, display_mod.white);
            display.fillCircle(tip_x, tip_y, 2, display_mod.white, 255);
        }
        self.drawReadout(display);
        self.drawGraph(display, color);
        ui.drawHeader(display, "Motion");
        ui.drawHint(display, "F/X/Z/C push  ENTER color  SPACE stop");
    }
};

test "readout numbers have two decimals and a sign when asked" {
    var buffer: [48]u8 = undefined;
    try std.testing.expectEqualStrings("4.37", formatFixed2(&buffer, 4.371, false));
    try std.testing.expectEqualStrings("-3.30", formatFixed2(&buffer, -3.3, true));
    try std.testing.expectEqualStrings("+2.86", formatFixed2(&buffer, 2.861, true));
    try std.testing.expectEqualStrings("+0.00", formatFixed2(&buffer, 0.0, true));
}
