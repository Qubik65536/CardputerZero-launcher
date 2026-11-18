// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! The 320x170 LCD as a Linux framebuffer: an RGB565 canvas you draw into, then
//! `present()` to copy it to the screen.
//!
//! On the device this opens the panel's framebuffer device. Under `fbsim` on a
//! desktop it opens the file named by CARDPUTER_FB instead, so the same code
//! runs on both.

const std = @import("std");
const font = @import("font.zig");

const Io = std.Io;

pub const max_width = 320;
pub const max_height = 170;

/// Pack 8-bit-per-channel red/green/blue into the panel's RGB565 format.
pub fn rgb(red: u8, green: u8, blue: u8) u16 {
    return (@as(u16, red & 0xF8) << 8) | (@as(u16, green & 0xFC) << 3) | (blue >> 3);
}

pub const black = rgb(0, 0, 0);
pub const white = rgb(255, 255, 255);

/// Character cell of the built-in font at scale 1, in pixels.
pub const char_width = 8;
pub const char_height = font.height;

fn mixChannel(under: u16, over: u16, alpha: u32, comptime shift: u4, mask: u32) u16 {
    const below = (@as(u32, under) >> shift) & mask;
    const above = (@as(u32, over) >> shift) & mask;
    return @intCast(((below * (255 - alpha) + above * alpha + 127) / 255) << shift);
}

/// Mix two RGB565 colors: `alpha` 0 = all `under`, 255 = all `over`.
pub fn blend(under: u16, over: u16, alpha: u8) u16 {
    return mixChannel(under, over, alpha, 11, 0x1F) | mixChannel(under, over, alpha, 5, 0x3F) | mixChannel(under, over, alpha, 0, 0x1F);
}

/// Expand RGB565 to XRGB8888, for panels that report a 32 bpp framebuffer.
fn rgb565ToXrgb8888(pixel: u16) u32 {
    const red: u32 = (pixel >> 11) & 0x1F;
    const green: u32 = (pixel >> 5) & 0x3F;
    const blue: u32 = pixel & 0x1F;
    return 0xFF00_0000 | ((red << 3 | red >> 2) << 16) | ((green << 2 | green >> 4) << 8) | (blue << 3 | blue >> 2);
}

const Geometry = struct {
    path: []const u8,
    width: usize = max_width,
    height: usize = max_height,
    stride: usize = max_width * 2, // bytes per row
    bytes_per_pixel: usize = 2, // 2 = RGB565, 4 = XRGB8888
};

fn parsePair(text: []const u8, separator: u8) ?[2]usize {
    const trimmed = std.mem.trim(u8, text, " \n\t");
    const split = std.mem.indexOfScalar(u8, trimmed, separator) orelse return null;
    const first = std.fmt.parseInt(usize, trimmed[0..split], 10) catch return null;
    const second = std.fmt.parseInt(usize, trimmed[split + 1 ..], 10) catch return null;
    return .{ first, second };
}

fn readSysfs(io: Io, path: []const u8, buffer: []u8) ?[]const u8 {
    const text = Io.Dir.cwd().readFile(io, path, buffer) catch return null;
    return std.mem.trim(u8, text, " \n\t");
}

/// The panel's framebuffer device, found the same way APPLaunch finds it:
/// LV_LINUX_FBDEV_DEVICE (APPLaunch exports it to the apps it starts), then
/// /dev/fb_lcd, then the ST7789 entry of /proc/fb, then /dev/fb0.
fn devicePath(io: Io, env: *const std.process.Environ.Map, buffer: []u8) []const u8 {
    for ([_][]const u8{ "LV_LINUX_FBDEV_DEVICE", "APPLAUNCH_LINUX_FBDEV_DEVICE" }) |name| {
        if (env.get(name)) |path| if (path.len > 0) return path;
    }
    if (Io.Dir.cwd().access(io, "/dev/fb_lcd", .{})) |_| return "/dev/fb_lcd" else |_| {}
    var proc_buffer: [512]u8 = undefined;
    const proc_fb = Io.Dir.cwd().readFile(io, "/proc/fb", &proc_buffer) catch "";
    var lines = std.mem.splitScalar(u8, proc_fb, '\n');
    while (lines.next()) |line| {
        if (std.ascii.findIgnoreCase(line, "st7789") == null) continue;
        var fields = std.mem.tokenizeScalar(u8, line, ' ');
        const index = fields.next() orelse continue;
        return std.fmt.bufPrint(buffer, "/dev/fb{s}", .{index}) catch "/dev/fb0";
    }
    return "/dev/fb0";
}

/// Device geometry from /sys/class/graphics/fbN (defaults to 320x170 RGB565).
fn deviceGeometry(io: Io, env: *const std.process.Environ.Map, path_buffer: []u8) !Geometry {
    var geometry: Geometry = .{ .path = devicePath(io, env, path_buffer) };
    var resolved_buffer: [256]u8 = undefined;
    const resolved_len = Io.Dir.cwd().realPathFile(io, geometry.path, &resolved_buffer) catch 0;
    const resolved = if (resolved_len > 0) resolved_buffer[0..resolved_len] else geometry.path; // fb_lcd may be a symlink
    var sysfs_buffer: [128]u8 = undefined;
    const name = std.fs.path.basename(resolved);
    var value_buffer: [64]u8 = undefined;

    const size_path = try std.fmt.bufPrint(&sysfs_buffer, "/sys/class/graphics/{s}/virtual_size", .{name});
    if (readSysfs(io, size_path, &value_buffer)) |text| if (parsePair(text, ',')) |size| {
        geometry.width = @min(size[0], max_width);
        geometry.height = @min(size[1], max_height);
    };
    const bits_path = try std.fmt.bufPrint(&sysfs_buffer, "/sys/class/graphics/{s}/bits_per_pixel", .{name});
    if (readSysfs(io, bits_path, &value_buffer)) |text| {
        const bits = std.fmt.parseInt(usize, text, 10) catch 16;
        if (bits != 16 and bits != 32) return error.UnsupportedPixelFormat;
        geometry.bytes_per_pixel = bits / 8;
    }
    geometry.stride = geometry.width * geometry.bytes_per_pixel;
    const stride_path = try std.fmt.bufPrint(&sysfs_buffer, "/sys/class/graphics/{s}/stride", .{name});
    if (readSysfs(io, stride_path, &value_buffer)) |text| {
        geometry.stride = std.fmt.parseInt(usize, text, 10) catch geometry.stride;
    }
    return geometry;
}

pub const Display = struct {
    io: Io,
    file: Io.File,
    width: usize,
    height: usize,
    stride: usize,
    bytes_per_pixel: usize,
    pixels: [max_width * max_height]u16 = undefined,
    bytes: [max_width * 4 * max_height]u8 = undefined,

    /// Opens the simulated framebuffer (CARDPUTER_FB from fbsim) or the device's.
    /// Display is large; keep it in static or heap memory, not on the stack.
    pub fn open(self: *Display, io: Io, env: *const std.process.Environ.Map) !void {
        var path_buffer: [64]u8 = undefined;
        var geometry: Geometry = undefined;
        if (env.get("CARDPUTER_FB")) |path| {
            geometry = .{ .path = path };
            if (env.get("CARDPUTER_FB_SIZE")) |size| if (parsePair(size, 'x')) |pair| {
                geometry.width = @min(pair[0], max_width);
                geometry.height = @min(pair[1], max_height);
                geometry.stride = geometry.width * 2;
            };
        } else {
            geometry = try deviceGeometry(io, env, &path_buffer);
        }
        self.* = .{
            .io = io,
            .file = try Io.Dir.openFileAbsolute(io, geometry.path, .{ .mode = .read_write }),
            .width = geometry.width,
            .height = geometry.height,
            .stride = geometry.stride,
            .bytes_per_pixel = geometry.bytes_per_pixel,
        };
        if (self.stride * self.height > self.bytes.len) return error.FramebufferTooLarge;
        self.clear(black);
    }

    pub fn close(self: *Display) void {
        self.file.close(self.io);
    }

    pub fn clear(self: *Display, color: u16) void {
        @memset(self.pixels[0 .. self.width * self.height], color);
    }

    /// Fill a rectangle; parts outside the screen are clipped.
    pub fn fillRect(self: *Display, x: i32, y: i32, width: i32, height: i32, color: u16) void {
        const left: usize = @intCast(std.math.clamp(x, 0, @as(i32, @intCast(self.width))));
        const right: usize = @intCast(std.math.clamp(x + width, 0, @as(i32, @intCast(self.width))));
        const top: usize = @intCast(std.math.clamp(y, 0, @as(i32, @intCast(self.height))));
        const bottom: usize = @intCast(std.math.clamp(y + height, 0, @as(i32, @intCast(self.height))));
        if (left >= right) return;
        for (top..bottom) |row| @memset(self.pixels[row * self.width + left .. row * self.width + right], color);
    }

    /// Set one pixel; coordinates outside the screen are ignored.
    pub fn setPixel(self: *Display, x: i32, y: i32, color: u16) void {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) return;
        self.pixels[@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))] = color;
    }

    /// Mix `color` over the pixel at (x, y); `alpha` 0 = invisible, 255 = opaque.
    pub fn blendPixel(self: *Display, x: i32, y: i32, color: u16, alpha: u8) void {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) return;
        const pixel = &self.pixels[@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))];
        pixel.* = blend(pixel.*, color, alpha);
    }

    /// Darken a rectangle, e.g. behind text drawn over a picture. `alpha` 255 = black.
    pub fn shadeRect(self: *Display, x: i32, y: i32, width: i32, height: i32, alpha: u8) void {
        var row = y;
        while (row < y + height) : (row += 1) {
            var column = x;
            while (column < x + width) : (column += 1) self.blendPixel(column, row, black, alpha);
        }
    }

    /// Fill a circle centered on (cx, cy), mixed in with `alpha` (255 = opaque).
    pub fn fillCircle(self: *Display, cx: i32, cy: i32, radius: i32, color: u16, alpha: u8) void {
        var dy = -radius;
        while (dy <= radius) : (dy += 1) {
            var dx = -radius;
            while (dx <= radius) : (dx += 1) {
                if (dx * dx + dy * dy <= radius * radius + radius) self.blendPixel(cx + dx, cy + dy, color, alpha);
            }
        }
    }

    /// Draw an image made by scripts/png_to_rgb565.py (with or without --alpha),
    /// e.g. `display.drawImage(0, 0, @embedFile("wallpaper.rgb565"))`.
    pub fn drawImage(self: *Display, x: i32, y: i32, image: []const u8) void {
        const width: usize = std.mem.readInt(u16, image[0..2], .little);
        const height: usize = std.mem.readInt(u16, image[2..4], .little);
        const pixels = image[4..][0 .. width * height * 2];
        const rest = image[4 + width * height * 2 ..];
        const alpha: ?[]const u8 = if (rest.len >= width * height) rest else null;
        for (0..height) |row| {
            for (0..width) |column| {
                const index = row * width + column;
                const color = std.mem.readInt(u16, pixels[index * 2 ..][0..2], .little);
                const opacity: u8 = if (alpha) |values| values[index] else 255;
                self.blendPixel(x + @as(i32, @intCast(column)), y + @as(i32, @intCast(row)), color, opacity);
            }
        }
    }

    /// Draw ASCII text with the built-in 8x16 font, enlarged `scale` times
    /// (scale 1 = 8x16 pixels per character, 2 = 16x32).
    pub fn drawText(self: *Display, x: i32, y: i32, text: []const u8, color: u16, scale: i32) void {
        var cursor = x;
        for (text) |char| {
            const index = if (char >= font.first and char - font.first < font.glyphs.len) char - font.first else '?' - font.first;
            for (font.glyphs[index], 0..) |bits, row| {
                for (0..8) |column| {
                    if (bits & (@as(u8, 0x80) >> @intCast(column)) != 0) {
                        self.fillRect(cursor + @as(i32, @intCast(column)) * scale, y + @as(i32, @intCast(row)) * scale, scale, scale, color);
                    }
                }
            }
            cursor += char_width * scale;
        }
    }

    /// Width in pixels that drawText would use, e.g. for centering.
    pub fn textWidth(text: []const u8, scale: i32) i32 {
        return @as(i32, @intCast(text.len)) * char_width * scale;
    }

    /// Copy the canvas to the screen.
    pub fn present(self: *Display) !void {
        for (0..self.height) |row| {
            const source = self.pixels[row * self.width .. (row + 1) * self.width];
            const target = self.bytes[row * self.stride ..][0 .. self.width * self.bytes_per_pixel];
            for (source, 0..) |pixel, column| {
                if (self.bytes_per_pixel == 2) {
                    std.mem.writeInt(u16, target[column * 2 ..][0..2], pixel, .little);
                } else {
                    std.mem.writeInt(u32, target[column * 4 ..][0..4], rgb565ToXrgb8888(pixel), .little);
                }
            }
        }
        try self.file.writePositionalAll(self.io, self.bytes[0 .. self.stride * self.height], 0);
    }
};
