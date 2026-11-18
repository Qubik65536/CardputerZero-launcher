// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 2, interactive rendering: push a glowing ball around. It keeps its momentum,
//! leaves a trail and throws sparks when it bounces off the walls. A readout shows its
//! physics live: speed, direction, velocity, kinetic energy, wall hits and a speed graph.

const std = @import("std");
const c = @import("lvgl.zig");
const pixel_canvas = @import("pixel_canvas.zig");
const ui = @import("ui.zig");

const Action = ui.Action;
const Canvas = pixel_canvas.PixelCanvas(ui.content_width, ui.content_height);
const rgb565 = pixel_canvas.rgb565;

const ball_radius: f32 = 9.0;
const push: f32 = 1.2; // speed added per key press, pixels per frame
const friction: f32 = 0.99; // speed kept each frame
const bounce: f32 = 0.85; // speed kept when bouncing
const trail_length = 14;
const sparks_per_bounce = 10;
const spark_life: u32 = 30; // frames
// At most two bounces per frame, each spark living spark_life frames.
const max_sparks = 2 * sparks_per_bounce * spark_life;
const grid = rgb565(0x242C36);
const white = rgb565(0xFFFFFF);
const mass: f32 = 1.0; // for the kinetic energy readout
const arrow_scale: f32 = 8.0; // velocity arrow length per pixel/frame of speed
const graph_samples = 96; // one speed sample per frame; also the graph's width in pixels
const graph_height = 36;
const graph_max_speed: f32 = 10.0; // pixels/frame at the top of the graph
const readout_width = 172;
const readout_lines = 3;
const line_height = 16; // lv_font_montserrat_14
const colors = [_]u16{ rgb565(ui.language_color), rgb565(0x4FC3F7), rgb565(0x81C784), rgb565(0xF06292) };

// The area the ball moves in: between the key line at the top and the hint line.
const left: f32 = 0.0;
const right: f32 = ui.content_width;
const top: f32 = 18.0; // below the "TAB next  ESC home" line
const bottom: f32 = ui.hint_top - 2;

const Point = struct {
    x: f32,
    y: f32,
};

const Spark = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: u32,
};

/// `value` with two decimals, written into `buffer`; `plus` adds "+" to non-negative
/// numbers (std.fmt has no "+" flag), like printf's "%+.2f".
fn formatFixed2(buffer: []u8, value: f32, plus: bool) []const u8 {
    const sign = if (plus and !std.math.signbit(value)) "+" else "";
    return std.fmt.bufPrint(buffer, "{s}{d:.2}", .{ sign, value }) catch buffer[0..0];
}

/// Keep the newest `capacity` items of a history, newest first.
fn pushFront(comptime T: type, items: []T, count: *usize, item: T) void {
    count.* = @min(count.* + 1, items.len);
    std.mem.copyBackwards(T, items[1..count.*], items[0 .. count.* - 1]);
    items[0] = item;
}

pub const Motion = struct {
    screen: ui.Screen,
    canvas: Canvas = .{},
    x: f32 = (left + right) / 2.0,
    y: f32 = (top + bottom) / 2.0,
    vx: f32 = 0.0,
    vy: f32 = 0.0,
    trail: [trail_length]Point = undefined, // newest first
    trail_count: usize = 0,
    sparks: [max_sparks]Spark = undefined,
    spark_count: usize = 0,
    color: usize = 0,
    random: u32 = 0x2545F491, // xorshift state, so the sparks need no dependencies
    hits: u32 = 0,
    speeds: [graph_samples]f32 = undefined, // newest first
    speed_count: usize = 0,
    readout: *c.Obj = undefined,

    pub fn init(self: *Motion, parent: *c.Obj) void {
        self.* = .{ .screen = .init(parent) };
        self.canvas.init(self.screen.root);
        // Widgets created after the canvas are drawn on top of it.
        self.readout = ui.makeLabel(self.screen.root, "", &c.lv_font_montserrat_14, ui.text_color);
        c.lv_obj_set_pos(self.readout, 4, @as(i32, @intFromFloat(top)) + 4);
        _ = ui.makeDemoKeys(self.screen.root);
        _ = ui.makeHint(self.screen.root, "F/X/Z/C push  ENTER color  SPACE stop");
        self.screen.animate(Motion, self);
    }

    pub fn title(_: *const Motion) [*:0]const u8 {
        return "Motion";
    }

    /// A number from -1 to 1 (xorshift).
    fn nextRandom(self: *Motion) f32 {
        self.random ^= self.random << 13;
        self.random ^= self.random >> 17;
        self.random ^= self.random << 5;
        return @as(f32, @floatFromInt(self.random % 2001)) / 1000.0 - 1.0;
    }

    fn speed(self: *const Motion) f32 {
        return @sqrt(self.vx * self.vx + self.vy * self.vy);
    }

    /// A wall hit: count it and throw sparks from the contact point.
    fn burst(self: *Motion, x: f32, y: f32) void {
        self.hits += 1;
        for (0..sparks_per_bounce) |_| {
            const vx = self.nextRandom() * 2.5;
            const vy = self.nextRandom() * 2.5 - 1.0;
            if (self.spark_count == max_sparks) continue;
            self.sparks[self.spark_count] = .{ .x = x, .y = y, .vx = vx, .vy = vy, .life = spark_life };
            self.spark_count += 1;
        }
    }

    /// Advance one frame: move, bounce, age the trail and the sparks.
    fn tick(self: *Motion) void {
        self.x += self.vx;
        self.y += self.vy;
        self.vx *= friction;
        self.vy *= friction;
        if (self.x < left + ball_radius or self.x > right - ball_radius) {
            self.x = std.math.clamp(self.x, left + ball_radius, right - ball_radius);
            self.vx = -self.vx * bounce;
            if (@abs(self.vx) > 0.6) self.burst(if (self.vx > 0.0) self.x - ball_radius else self.x + ball_radius, self.y);
        }
        if (self.y < top + ball_radius or self.y > bottom - ball_radius) {
            self.y = std.math.clamp(self.y, top + ball_radius, bottom - ball_radius);
            self.vy = -self.vy * bounce;
            if (@abs(self.vy) > 0.6) self.burst(self.x, if (self.vy > 0.0) self.y - ball_radius else self.y + ball_radius);
        }
        pushFront(Point, &self.trail, &self.trail_count, .{ .x = self.x, .y = self.y });
        pushFront(f32, &self.speeds, &self.speed_count, self.speed());
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

    /// Numbers about the ball's motion, top left: a shaded panel on the canvas, text in a label.
    fn drawReadout(self: *Motion) void {
        const current = self.speed();
        // Screen y grows downwards; flip it so 90 degrees points up, as in math.
        var degrees = @rem(std.math.radiansToDegrees(std.math.atan2(-self.vy, self.vx)), 360.0);
        if (degrees < 0.0) degrees += 360.0;
        const heading = @rem(@as(i32, @intFromFloat(@round(degrees))), 360);
        const energy = 0.5 * mass * current * current;
        var numbers: [4][48]u8 = undefined;
        var text: [160]u8 = undefined;
        const readout = std.fmt.bufPrint(&text, "speed {s}  dir {d}\nvx {s}  vy {s}\nenergy {s}  hits {d}", .{
            formatFixed2(&numbers[0], current, false),
            heading,
            formatFixed2(&numbers[1], self.vx, true),
            formatFixed2(&numbers[2], self.vy, true),
            formatFixed2(&numbers[3], energy, false),
            self.hits,
        }) catch unreachable;
        c.setText(self.readout, readout);
        self.canvas.shadeRect(0, @as(i32, @intFromFloat(top)) + 2, readout_width, readout_lines * line_height + 4, 150);
    }

    fn graphHeight(value: f32) i32 {
        return @intFromFloat(@min(value / graph_max_speed, 1.0) * (graph_height - 2));
    }

    /// Speed over the last graph_samples frames, top right, newest on the right.
    fn drawGraph(self: *Motion, color: u16) void {
        const graph_left: i32 = @as(i32, @intFromFloat(right)) - graph_samples - 4;
        const graph_top: i32 = @as(i32, @intFromFloat(top)) + 2;
        const graph_bottom = graph_top + graph_height - 1;
        self.canvas.shadeRect(graph_left - 2, graph_top, graph_samples + 4, graph_height + 2, 150);
        for (1..self.speed_count) |age| {
            const x = graph_left + graph_samples - 1 - @as(i32, @intCast(age));
            const newer = graph_bottom - graphHeight(self.speeds[age - 1]);
            const older = graph_bottom - graphHeight(self.speeds[age]);
            self.canvas.drawLine(x + 1, newer, x, older, color);
        }
    }

    fn draw(self: *Motion) void {
        const color = colors[self.color];
        self.canvas.clear(rgb565(ui.background_color));
        var grid_y: i32 = @as(i32, @intFromFloat(top)) + 8;
        while (grid_y < @as(i32, @intFromFloat(bottom))) : (grid_y += 16) {
            var grid_x: i32 = 8;
            while (grid_x < @as(i32, @intFromFloat(right))) : (grid_x += 16) self.canvas.setPixel(grid_x, grid_y, grid);
        }
        // Oldest trail first, so newer, brighter circles land on top.
        const length: f32 = @floatFromInt(self.trail_count);
        var age = self.trail_count;
        while (age > 0) {
            age -= 1;
            const point = self.trail[age];
            const fade = 1.0 - @as(f32, @floatFromInt(age)) / length;
            const size: i32 = @intFromFloat(ball_radius * (0.3 + 0.6 * fade));
            self.canvas.fillCircle(@intFromFloat(point.x), @intFromFloat(point.y), size, color, @intFromFloat(90.0 * fade));
        }
        for (self.sparks[0..self.spark_count]) |spark| {
            const alpha: u8 = @intCast(spark.life * 255 / spark_life);
            self.canvas.fillCircle(@intFromFloat(spark.x), @intFromFloat(spark.y), 1, color, alpha);
        }
        const x: i32 = @intFromFloat(self.x);
        const y: i32 = @intFromFloat(self.y);
        const size: i32 = @intFromFloat(ball_radius);
        self.canvas.fillCircle(x, y, size + 6, color, 35); // glow
        self.canvas.fillCircle(x, y, size + 3, color, 70);
        self.canvas.fillCircle(x, y, size, color, 255);
        self.canvas.fillCircle(x - 3, y - 3, 3, white, 140); // highlight
        if (self.speed() > 0.05) {
            // Velocity arrow: where the ball is heading, and how fast.
            const tip_x: i32 = @intFromFloat(self.x + self.vx * arrow_scale);
            const tip_y: i32 = @intFromFloat(self.y + self.vy * arrow_scale);
            self.canvas.drawLine(x, y, tip_x, tip_y, white);
            self.canvas.fillCircle(tip_x, tip_y, 2, white, 255);
        }
        self.drawReadout();
        self.drawGraph(color);
        self.canvas.present();
    }

    pub fn onFrame(self: *Motion) void {
        self.tick();
        self.draw();
    }

    pub fn handleKey(self: *Motion, key: *const c.Key) Action {
        if (ui.direction(key.code)) |direction| switch (direction) {
            .left => self.vx -= push,
            .right => self.vx += push,
            .up => self.vy -= push,
            .down => self.vy += push,
        } else switch (key.code) {
            ui.keys.enter => self.color = (self.color + 1) % colors.len,
            ui.keys.space => {
                self.vx = 0.0;
                self.vy = 0.0;
            },
            ui.keys.tab => return .next,
            ui.keys.esc => return .home,
            else => {},
        }
        return .stay;
    }
};

test "readout numbers have two decimals and a sign when asked" {
    var buffer: [48]u8 = undefined;
    try std.testing.expectEqualStrings("4.37", formatFixed2(&buffer, 4.371, false));
    try std.testing.expectEqualStrings("-3.30", formatFixed2(&buffer, -3.3, true));
    try std.testing.expectEqualStrings("+2.86", formatFixed2(&buffer, 2.861, true));
    try std.testing.expectEqualStrings("+0.00", formatFixed2(&buffer, 0.0, true));
}
