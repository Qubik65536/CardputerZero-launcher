// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Software rendering into an LVGL canvas: an RGB565 pixel buffer you draw into pixel
//! by pixel, then present() so LVGL redraws it.

const std = @import("std");
const c = @import("lvgl.zig");

/// Pack 0xRRGGBB into the RGB565 format of the canvas (and the panel).
pub fn rgb565(hex: u32) u16 {
    return @truncate(((hex >> 8) & 0xF800) | ((hex >> 5) & 0x07E0) | ((hex >> 3) & 0x001F));
}

fn mixChannel(under: u16, over: u16, alpha: u32, comptime shift: u4, comptime mask: u32) u16 {
    const below = (@as(u32, under) >> shift) & mask;
    const above = (@as(u32, over) >> shift) & mask;
    return @intCast(((below * (255 - alpha) + above * alpha + 127) / 255) << shift);
}

/// Mix two RGB565 colors: `alpha` 0 = all `under`, 255 = all `over`.
pub fn blend565(under: u16, over: u16, alpha: u8) u16 {
    return mixChannel(under, over, alpha, 11, 0x1F) | mixChannel(under, over, alpha, 5, 0x3F) |
        mixChannel(under, over, alpha, 0, 0x1F);
}

/// A `width` x `height` canvas. It holds its pixels, so keep it in static storage
/// (as main.zig does with the whole app) and do not move it after init().
pub fn PixelCanvas(comptime width: i32, comptime height: i32) type {
    return struct {
        const Self = @This();

        pixels: [width * height]u16 align(16) = undefined,
        obj: *c.Obj = undefined,

        pub fn init(self: *Self, parent: *c.Obj) void {
            self.obj = c.lv_canvas_create(parent);
            c.lv_canvas_set_buffer(self.obj, &self.pixels, width, height, .rgb565);
            c.lv_obj_set_pos(self.obj, 0, 0);
        }

        pub fn clear(self: *Self, color: u16) void {
            @memset(&self.pixels, color);
        }

        /// Fill a rectangle; parts outside the canvas are clipped.
        pub fn fillRect(self: *Self, x: i32, y: i32, rect_width: i32, rect_height: i32, color: u16) void {
            const left: usize = @intCast(std.math.clamp(x, 0, width));
            const right: usize = @intCast(std.math.clamp(x + rect_width, 0, width));
            const top: usize = @intCast(std.math.clamp(y, 0, height));
            const bottom: usize = @intCast(std.math.clamp(y + rect_height, 0, height));
            if (left >= right) return;
            for (top..bottom) |row| @memset(self.pixels[row * width + left .. row * width + right], color);
        }

        /// Set one pixel; coordinates outside the canvas are ignored.
        pub fn setPixel(self: *Self, x: i32, y: i32, color: u16) void {
            if (x >= 0 and y >= 0 and x < width and y < height) self.pixels[@intCast(y * width + x)] = color;
        }

        /// Mix `color` over the pixel at (x, y); `alpha` 0 = invisible, 255 = opaque.
        pub fn blendPixel(self: *Self, x: i32, y: i32, color: u16, alpha: u8) void {
            if (x >= 0 and y >= 0 and x < width and y < height) {
                const pixel = &self.pixels[@intCast(y * width + x)];
                pixel.* = blend565(pixel.*, color, alpha);
            }
        }

        /// Darken a rectangle, e.g. behind text drawn over the picture. `alpha` 255 = black.
        pub fn shadeRect(self: *Self, x: i32, y: i32, rect_width: i32, rect_height: i32, alpha: u8) void {
            var row = y;
            while (row < y + rect_height) : (row += 1) {
                var column = x;
                while (column < x + rect_width) : (column += 1) self.blendPixel(column, row, 0x0000, alpha);
            }
        }

        /// Fill a circle centered on (cx, cy), mixed in with `alpha`.
        pub fn fillCircle(self: *Self, cx: i32, cy: i32, radius: i32, color: u16, alpha: u8) void {
            var dy = -radius;
            while (dy <= radius) : (dy += 1) {
                var dx = -radius;
                while (dx <= radius) : (dx += 1) {
                    if (dx * dx + dy * dy <= radius * radius + radius) self.blendPixel(cx + dx, cy + dy, color, alpha);
                }
            }
        }

        /// Draw a 1-pixel line from (x0, y0) to (x1, y1) (Bresenham's algorithm).
        pub fn drawLine(self: *Self, x0: i32, y0: i32, x1: i32, y1: i32, color: u16) void {
            const dx: i32 = @intCast(@abs(x1 - x0));
            const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
            const step_x: i32 = if (x0 < x1) 1 else -1;
            const step_y: i32 = if (y0 < y1) 1 else -1;
            var x = x0;
            var y = y0;
            var err = dx + dy;
            while (true) {
                self.setPixel(x, y, color);
                if (x == x1 and y == y1) break;
                const doubled = 2 * err;
                if (doubled >= dy) {
                    err += dy;
                    x += step_x;
                }
                if (doubled <= dx) {
                    err += dx;
                    y += step_y;
                }
            }
        }

        /// Show what was drawn since the last call.
        pub fn present(self: *Self) void {
            c.lv_obj_invalidate(self.obj);
        }
    };
}
