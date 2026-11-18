// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 1, color rendering: a spinning RGB triangle and an HSV color wheel, computed
//! pixel by pixel every frame.

const std = @import("std");
const display_mod = @import("display.zig");
const input = @import("input.zig");
const ui = @import("ui.zig");

const Display = display_mod.Display;
const rgb = display_mod.rgb;
const keys = input.keys;
const Action = ui.Action;
const tau = std.math.tau;

const center_x: f32 = 160.0;
const center_y: f32 = 86.0;
const radius: f32 = 60.0;
const spin_per_frame: f32 = 0.02; // radians
const turn_step: f32 = 0.15; // radians per Z/C press

const Scene = enum { triangle, wheel };

/// 0..1 to a color channel, 0..255.
fn channel(level: f32) u8 {
    return @intFromFloat(std.math.clamp(level * 255.0, 0.0, 255.0));
}

/// Hue (0..1, wrapping), saturation and value (0..1) to RGB565.
fn hsv(hue: f32, saturation: f32, value: f32) u16 {
    const sector = @mod(hue, 1.0) * 6.0;
    const fraction = sector - @floor(sector);
    const p = value * (1.0 - saturation);
    const q = value * (1.0 - saturation * fraction);
    const t = value * (1.0 - saturation * (1.0 - fraction));
    const red, const green, const blue = switch (@as(u32, @intFromFloat(sector))) {
        0 => .{ value, t, p },
        1 => .{ q, value, p },
        2 => .{ p, value, t },
        3 => .{ p, q, value },
        4 => .{ t, p, value },
        else => .{ value, p, q },
    };
    return rgb(channel(red), channel(green), channel(blue));
}

/// Dark vertical gradient behind the demo.
fn drawBackdrop(display: *Display) void {
    const width: i32 = @intCast(display.width);
    const height: i32 = @intCast(display.height);
    const top = rgb(22, 28, 36);
    const bottom = rgb(6, 8, 11);
    var y: i32 = ui.header_height;
    while (y < height) : (y += 1) {
        const alpha: u8 = @intCast(@divTrunc((y - ui.header_height) * 255, height - ui.header_height));
        display.fillRect(0, y, width, 1, display_mod.blend(top, bottom, alpha));
    }
}

fn corner(angle: f32, index: usize) [2]f32 {
    const theta = angle + @as(f32, @floatFromInt(index)) * tau / 3.0;
    return .{ center_x + radius * @cos(theta), center_y + radius * @sin(theta) };
}

/// Gouraud shading: each pixel mixes the corner colors red, green and blue by how close
/// it is to each corner (its barycentric weights), scaled so the brightest channel is full.
fn drawTriangle(display: *Display, angle: f32) void {
    const ax, const ay = corner(angle, 0);
    const bx, const by = corner(angle, 1);
    const cx, const cy = corner(angle, 2);
    const area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    const left: i32 = @intFromFloat(@floor(@min(ax, bx, cx)));
    const right: i32 = @intFromFloat(@ceil(@max(ax, bx, cx)));
    const top: i32 = @intFromFloat(@floor(@min(ay, by, cy)));
    const bottom: i32 = @intFromFloat(@ceil(@max(ay, by, cy)));
    var y = top;
    while (y <= bottom) : (y += 1) {
        var x = left;
        while (x <= right) : (x += 1) {
            const px = @as(f32, @floatFromInt(x)) + 0.5;
            const py = @as(f32, @floatFromInt(y)) + 0.5;
            const red = ((cx - bx) * (py - by) - (cy - by) * (px - bx)) / area;
            const green = ((ax - cx) * (py - cy) - (ay - cy) * (px - cx)) / area;
            const blue = 1.0 - red - green;
            if (red < 0.0 or green < 0.0 or blue < 0.0) continue;
            const brightest = @max(red, green, blue);
            display.setPixel(x, y, rgb(channel(red / brightest), channel(green / brightest), channel(blue / brightest)));
        }
    }
}

/// Hue around the circle, saturation from the center out.
fn drawWheel(display: *Display, angle: f32) void {
    const extent: i32 = @intFromFloat(radius);
    var dy = -extent;
    while (dy <= extent) : (dy += 1) {
        var dx = -extent;
        while (dx <= extent) : (dx += 1) {
            const distance = @sqrt(@as(f32, @floatFromInt(dx * dx + dy * dy)));
            if (distance > radius) continue;
            const hue = (std.math.atan2(@as(f32, @floatFromInt(dy)), @as(f32, @floatFromInt(dx))) + angle) / tau;
            display.setPixel(@as(i32, @intFromFloat(center_x)) + dx, @as(i32, @intFromFloat(center_y)) + dy, hsv(hue, distance / radius, 1.0));
        }
    }
}

pub const Colors = struct {
    scene: Scene = .triangle,
    angle: f32 = 0.0,
    spinning: bool = true,

    /// True while the picture changes on its own, so it needs drawing every frame.
    pub fn animated(self: *const Colors) bool {
        return self.spinning;
    }

    pub fn tick(self: *Colors) void {
        if (self.spinning) self.angle = @rem(self.angle + spin_per_frame, tau);
    }

    pub fn handleKey(self: *Colors, event: input.KeyEvent) Action {
        if (!event.isDown()) return .stay;
        if (input.direction(event.code)) |direction| switch (direction) {
            .left => self.angle -= turn_step,
            .right => self.angle += turn_step,
            .up, .down => {},
        } else switch (event.code) {
            keys.enter => self.scene = if (self.scene == .triangle) .wheel else .triangle,
            keys.space => self.spinning = !self.spinning,
            keys.tab => return .next,
            keys.esc => return .home,
            else => {},
        }
        return .stay;
    }

    pub fn draw(self: *const Colors, display: *Display) void {
        drawBackdrop(display);
        switch (self.scene) {
            .triangle => drawTriangle(display, self.angle),
            .wheel => drawWheel(display, self.angle),
        }
        ui.drawHeader(display, if (self.scene == .triangle) "Colors: triangle" else "Colors: wheel");
        ui.drawHint(display, "Z/C turn  SPACE pause  ENTER switch");
    }
};
