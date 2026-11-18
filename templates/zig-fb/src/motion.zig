// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 2, interactive rendering: push a glowing ball around. It keeps its momentum,
//! leaves a trail and throws sparks when it bounces off the walls.

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

    fn burst(self: *Motion, x: f32, y: f32) void {
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
        ui.drawHeader(display, "Motion");
        ui.drawHint(display, "F/X/Z/C push  ENTER color  SPACE stop");
    }
};
