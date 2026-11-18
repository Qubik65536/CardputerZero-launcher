// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Software rendering into an LVGL canvas: an RGB565 pixel buffer you draw
//! into pixel by pixel, then `present()` so LVGL redraws it.

use std::cell::Cell;

use crate::lvgl::{Canvas, Obj};

/// Pack 0xRRGGBB into the RGB565 format of the canvas (and the panel).
pub const fn rgb565(hex: u32) -> u16 {
    (((hex >> 8) & 0xF800) | ((hex >> 5) & 0x07E0) | ((hex >> 3) & 0x001F)) as u16
}

fn mix_channel(under: u16, over: u16, alpha: u32, shift: u32, mask: u32) -> u16 {
    let below = (u32::from(under) >> shift) & mask;
    let above = (u32::from(over) >> shift) & mask;
    (((below * (255 - alpha) + above * alpha + 127) / 255) << shift) as u16
}

/// Mix two RGB565 colors: `alpha` 0 = all `under`, 255 = all `over`.
pub fn blend565(under: u16, over: u16, alpha: u8) -> u16 {
    let alpha = u32::from(alpha);
    mix_channel(under, over, alpha, 11, 0x1F) | mix_channel(under, over, alpha, 5, 0x3F) | mix_channel(under, over, alpha, 0, 0x1F)
}

pub struct PixelCanvas {
    width: i32,
    height: i32,
    pixels: &'static [Cell<u16>],
    canvas: Canvas,
}

impl PixelCanvas {
    pub fn new(parent: Obj, width: i32, height: i32) -> PixelCanvas {
        let count = (width * height) as usize;
        let pixels: &'static [Cell<u16>] = Box::leak(vec![Cell::new(0); count].into_boxed_slice());
        let canvas = Canvas::create(parent);
        canvas.set_buffer_rgb565(pixels, width, height);
        canvas.set_pos(0, 0);
        PixelCanvas { width, height, pixels, canvas }
    }

    fn pixel(&self, x: i32, y: i32) -> Option<&Cell<u16>> {
        let inside = x >= 0 && y >= 0 && x < self.width && y < self.height;
        inside.then(|| &self.pixels[(y * self.width + x) as usize])
    }

    pub fn clear(&self, color: u16) {
        for pixel in self.pixels {
            pixel.set(color);
        }
    }

    /// Fill a rectangle; parts outside the canvas are clipped.
    pub fn fill_rect(&self, x: i32, y: i32, width: i32, height: i32, color: u16) {
        let left = x.clamp(0, self.width);
        let right = (x + width).clamp(0, self.width);
        let top = y.clamp(0, self.height);
        let bottom = (y + height).clamp(0, self.height);
        for row in top..bottom {
            let start = (row * self.width) as usize;
            for pixel in &self.pixels[start + left as usize..start + right as usize] {
                pixel.set(color);
            }
        }
    }

    /// Set one pixel; coordinates outside the canvas are ignored.
    pub fn set_pixel(&self, x: i32, y: i32, color: u16) {
        if let Some(pixel) = self.pixel(x, y) {
            pixel.set(color);
        }
    }

    /// Mix `color` over the pixel at (x, y); `alpha` 0 = invisible, 255 = opaque.
    pub fn blend_pixel(&self, x: i32, y: i32, color: u16, alpha: u8) {
        if let Some(pixel) = self.pixel(x, y) {
            pixel.set(blend565(pixel.get(), color, alpha));
        }
    }

    /// Darken a rectangle, e.g. behind text drawn over the picture. `alpha` 255 = black.
    pub fn shade_rect(&self, x: i32, y: i32, width: i32, height: i32, alpha: u8) {
        for row in y..y + height {
            for column in x..x + width {
                self.blend_pixel(column, row, 0x0000, alpha);
            }
        }
    }

    /// Fill a circle centered on (cx, cy), mixed in with `alpha`.
    pub fn fill_circle(&self, cx: i32, cy: i32, radius: i32, color: u16, alpha: u8) {
        for dy in -radius..=radius {
            for dx in -radius..=radius {
                if dx * dx + dy * dy <= radius * radius + radius {
                    self.blend_pixel(cx + dx, cy + dy, color, alpha);
                }
            }
        }
    }

    /// Draw a 1-pixel line from (x0, y0) to (x1, y1) (Bresenham's algorithm).
    pub fn draw_line(&self, x0: i32, y0: i32, x1: i32, y1: i32, color: u16) {
        let dx = (x1 - x0).abs();
        let dy = -(y1 - y0).abs();
        let step_x = if x0 < x1 { 1 } else { -1 };
        let step_y = if y0 < y1 { 1 } else { -1 };
        let (mut x, mut y) = (x0, y0);
        let mut error = dx + dy;
        loop {
            self.set_pixel(x, y, color);
            if x == x1 && y == y1 {
                break;
            }
            let doubled = 2 * error;
            if doubled >= dy {
                error += dy;
                x += step_x;
            }
            if doubled <= dx {
                error += dx;
                y += step_y;
            }
        }
    }

    /// Show what was drawn since the last call.
    pub fn present(&self) {
        self.canvas.invalidate();
    }
}
