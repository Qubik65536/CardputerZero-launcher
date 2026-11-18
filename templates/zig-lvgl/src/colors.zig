// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 1, color rendering: a spinning RGB triangle and an HSV color wheel, computed
//! pixel by pixel every frame into an LVGL canvas.

const std = @import("std");
const c = @import("lvgl.zig");
const pixel_canvas = @import("pixel_canvas.zig");
const ui = @import("ui.zig");

const Action = ui.Action;
const Canvas = pixel_canvas.PixelCanvas(ui.content_width, ui.content_height);
const rgb565 = pixel_canvas.rgb565;

const tau: f32 = 6.28318530718;
const center_x: f32 = 160.0;
// Content coordinates, between the "TAB next  ESC home" line (top 18 px) and the hint
// line, so neither covers the picture.
const center_y: f32 = 72.0;
const radius: f32 = 54.0;
const spin_per_frame: f32 = 0.02; // radians
const turn_step: f32 = 0.15; // radians per Z/C press

fn channel(value: f32) u32 {
    return @intFromFloat(std.math.clamp(value, 0.0, 255.0));
}

fn rgb(red: f32, green: f32, blue: f32) u16 {
    return rgb565(channel(red) << 16 | channel(green) << 8 | channel(blue));
}

/// Hue (0..1, wrapping), saturation and value (0..1) to RGB565.
fn hsv(hue: f32, saturation: f32, value: f32) u16 {
    const sector = (hue - @floor(hue)) * 6.0;
    const fraction = sector - @floor(sector);
    const p = value * (1.0 - saturation);
    const q = value * (1.0 - saturation * fraction);
    const t = value * (1.0 - saturation * (1.0 - fraction));
    return switch (@as(u32, @intFromFloat(sector))) {
        0 => rgb(value * 255, t * 255, p * 255),
        1 => rgb(q * 255, value * 255, p * 255),
        2 => rgb(p * 255, value * 255, t * 255),
        3 => rgb(p * 255, q * 255, value * 255),
        4 => rgb(t * 255, p * 255, value * 255),
        else => rgb(value * 255, p * 255, q * 255),
    };
}

/// Gouraud shading: each pixel mixes the corner colors red, green and blue by how close
/// it is to each corner (its barycentric weights), scaled so the brightest channel is full.
fn drawTriangle(canvas: *Canvas, angle: f32) void {
    var xs: [3]f32 = undefined;
    var ys: [3]f32 = undefined;
    for (0..3) |index| {
        const theta = angle + @as(f32, @floatFromInt(index)) * tau / 3.0;
        xs[index] = center_x + radius * @cos(theta);
        ys[index] = center_y + radius * @sin(theta);
    }
    const ax = xs[0];
    const ay = ys[0];
    const bx = xs[1];
    const by = ys[1];
    const cx = xs[2];
    const cy = ys[2];
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
            canvas.setPixel(x, y, rgb(red / brightest * 255.0, green / brightest * 255.0, blue / brightest * 255.0));
        }
    }
}

/// Hue around the circle, saturation from the center out.
fn drawWheel(canvas: *Canvas, angle: f32) void {
    const size: i32 = @intFromFloat(radius);
    var dy = -size;
    while (dy <= size) : (dy += 1) {
        var dx = -size;
        while (dx <= size) : (dx += 1) {
            const distance = @sqrt(@as(f32, @floatFromInt(dx * dx + dy * dy)));
            if (distance > radius) continue;
            const hue = (std.math.atan2(@as(f32, @floatFromInt(dy)), @as(f32, @floatFromInt(dx))) + angle) / tau;
            canvas.setPixel(@as(i32, @intFromFloat(center_x)) + dx, @as(i32, @intFromFloat(center_y)) + dy, hsv(hue, distance / radius, 1.0));
        }
    }
}

const Scene = enum { triangle, wheel };

pub const Colors = struct {
    screen: ui.Screen,
    canvas: Canvas = .{},
    backdrop: [ui.content_height]u16 = undefined, // one color per row
    scene: Scene = .triangle,
    angle: f32 = 0.0,
    spinning: bool = true,

    fn draw(self: *Colors) void {
        for (self.backdrop, 0..) |color, y| self.canvas.fillRect(0, @intCast(y), ui.content_width, 1, color);
        switch (self.scene) {
            .triangle => drawTriangle(&self.canvas, self.angle),
            .wheel => drawWheel(&self.canvas, self.angle),
        }
        self.canvas.present();
    }

    pub fn init(self: *Colors, parent: *c.Obj) void {
        self.* = .{ .screen = .init(parent) };
        self.canvas.init(self.screen.root);
        // Dark vertical gradient behind the picture, worked out once.
        for (&self.backdrop, 0..) |*color, y| {
            color.* = pixel_canvas.blend565(rgb565(0x161C24), rgb565(0x06080B), @intCast(y * 255 / ui.content_height));
        }
        // Widgets created after the canvas are drawn on top of it.
        _ = ui.makeDemoKeys(self.screen.root);
        _ = ui.makeHint(self.screen.root, "Z/C turn  SPACE pause  ENTER switch");
        self.screen.animate(Colors, self);
        self.draw();
    }

    pub fn title(self: *const Colors) [*:0]const u8 {
        return switch (self.scene) {
            .triangle => "Colors: triangle",
            .wheel => "Colors: wheel",
        };
    }

    pub fn onShow(self: *Colors) void {
        self.draw();
    }

    pub fn onFrame(self: *Colors) void {
        if (!self.spinning) return;
        self.angle = @rem(self.angle + spin_per_frame, tau);
        self.draw();
    }

    pub fn handleKey(self: *Colors, key: *const c.Key) Action {
        if (ui.direction(key.code)) |direction| switch (direction) {
            .left => self.angle -= turn_step,
            .right => self.angle += turn_step,
            .up, .down => {},
        } else switch (key.code) {
            ui.keys.enter => self.scene = if (self.scene == .triangle) .wheel else .triangle,
            ui.keys.space => self.spinning = !self.spinning,
            ui.keys.tab => return .next,
            ui.keys.esc => return .home,
            else => {},
        }
        self.draw();
        return .stay;
    }
};
