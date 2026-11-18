// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! The 320x170 LCD as a Linux framebuffer: an RGB565 canvas you draw into, then
//! `present()` to copy it to the screen.
//!
//! On the device this opens the panel's framebuffer device. Under `fbsim` on a desktop it
//! opens the file named by `CARDPUTER_FB` instead, so the same code runs on both.

use std::env;
use std::fs::{self, File, OpenOptions};
use std::io;
use std::os::unix::fs::FileExt;
use std::path::{Path, PathBuf};

use crate::font;

/// Pack 8-bit-per-channel red/green/blue into the panel's RGB565 format.
pub const fn rgb(red: u8, green: u8, blue: u8) -> u16 {
    ((red as u16 & 0xF8) << 8) | ((green as u16 & 0xFC) << 3) | (blue as u16 >> 3)
}

/// Expand RGB565 to XRGB8888, for panels that report a 32 bpp framebuffer.
const fn rgb565_to_xrgb8888(pixel: u16) -> u32 {
    let red = ((pixel >> 11) & 0x1F) as u32;
    let green = ((pixel >> 5) & 0x3F) as u32;
    let blue = (pixel & 0x1F) as u32;
    0xFF00_0000 | ((red << 3 | red >> 2) << 16) | ((green << 2 | green >> 4) << 8) | (blue << 3 | blue >> 2)
}

pub const BLACK: u16 = rgb(0, 0, 0);
pub const WHITE: u16 = rgb(255, 255, 255);

struct Geometry {
    path: PathBuf,
    width: usize,
    height: usize,
    stride: usize,          // bytes per row in the framebuffer
    bytes_per_pixel: usize, // 2 = RGB565, 4 = XRGB8888
}

fn read_sysfs(dir: &Path, name: &str) -> Option<String> {
    fs::read_to_string(dir.join(name)).ok().map(|text| text.trim().to_string())
}

fn parse_pair(text: &str, separator: char) -> Option<(usize, usize)> {
    let (first, second) = text.split_once(separator)?;
    Some((first.trim().parse().ok()?, second.trim().parse().ok()?))
}

/// The simulated framebuffer created by fbsim (CARDPUTER_FB / CARDPUTER_FB_SIZE).
fn simulated_geometry() -> Option<Geometry> {
    let path = PathBuf::from(env::var_os("CARDPUTER_FB")?);
    let size = env::var("CARDPUTER_FB_SIZE").unwrap_or_else(|_| "320x170".to_string());
    let (width, height) = parse_pair(&size, 'x')?;
    Some(Geometry { path, width, height, stride: width * 2, bytes_per_pixel: 2 })
}

/// The panel's framebuffer device, found the same way APPLaunch finds it:
/// LV_LINUX_FBDEV_DEVICE (APPLaunch exports it to the apps it starts), then
/// /dev/fb_lcd, then the ST7789 entry of /proc/fb, then /dev/fb0.
fn device_path() -> PathBuf {
    for variable in ["LV_LINUX_FBDEV_DEVICE", "APPLAUNCH_LINUX_FBDEV_DEVICE"] {
        if let Some(path) = env::var_os(variable).filter(|path| !path.is_empty()) {
            return PathBuf::from(path);
        }
    }
    if Path::new("/dev/fb_lcd").exists() {
        return PathBuf::from("/dev/fb_lcd");
    }
    let panel = fs::read_to_string("/proc/fb").ok().and_then(|text| {
        text.lines()
            .find(|line| line.to_lowercase().contains("st7789"))
            .and_then(|line| line.split_whitespace().next().map(|index| format!("/dev/fb{index}")))
    });
    PathBuf::from(panel.unwrap_or_else(|| "/dev/fb0".to_string()))
}

/// Device geometry from /sys/class/graphics/fbN (falls back to 320x170 RGB565).
fn device_geometry() -> io::Result<Geometry> {
    let path = device_path();
    let resolved = fs::canonicalize(&path).unwrap_or_else(|_| path.clone()); // /dev/fb_lcd may be a symlink
    let sysfs = Path::new("/sys/class/graphics").join(resolved.file_name().unwrap_or_default());
    let (width, height) = read_sysfs(&sysfs, "virtual_size")
        .and_then(|size| parse_pair(&size, ','))
        .unwrap_or((320, 170));
    let bits = read_sysfs(&sysfs, "bits_per_pixel").and_then(|bits| bits.parse().ok()).unwrap_or(16);
    if bits != 16 && bits != 32 {
        return Err(io::Error::new(io::ErrorKind::Unsupported, format!("{bits} bpp framebuffer")));
    }
    let bytes_per_pixel = bits / 8;
    let stride = read_sysfs(&sysfs, "stride")
        .and_then(|stride| stride.parse().ok())
        .unwrap_or(width * bytes_per_pixel);
    Ok(Geometry { path, width, height, stride, bytes_per_pixel })
}

pub struct Display {
    file: File,
    width: usize,
    height: usize,
    stride: usize,
    bytes_per_pixel: usize,
    pixels: Vec<u16>,
    bytes: Vec<u8>,
}

impl Display {
    pub fn open() -> io::Result<Display> {
        let geometry = match simulated_geometry() {
            Some(geometry) => geometry,
            None => device_geometry()?,
        };
        let file = OpenOptions::new().read(true).write(true).open(&geometry.path).map_err(|error| {
            io::Error::new(error.kind(), format!("{}: {error}", geometry.path.display()))
        })?;
        Ok(Display {
            file,
            width: geometry.width,
            height: geometry.height,
            stride: geometry.stride,
            bytes_per_pixel: geometry.bytes_per_pixel,
            pixels: vec![BLACK; geometry.width * geometry.height],
            bytes: vec![0; geometry.stride * geometry.height],
        })
    }

    pub fn width(&self) -> usize {
        self.width
    }

    pub fn height(&self) -> usize {
        self.height
    }

    pub fn clear(&mut self, color: u16) {
        self.pixels.fill(color);
    }

    /// Fill a rectangle; parts outside the screen are clipped.
    pub fn fill_rect(&mut self, x: i32, y: i32, width: i32, height: i32, color: u16) {
        let clamp = |value: i32, limit: usize| (value.max(0) as usize).min(limit);
        let (left, right) = (clamp(x, self.width), clamp(x + width, self.width));
        let (top, bottom) = (clamp(y, self.height), clamp(y + height, self.height));
        if left >= right {
            return;
        }
        for row in top..bottom {
            self.pixels[row * self.width + left..row * self.width + right].fill(color);
        }
    }

    /// Draw ASCII text with the built-in 8x8 font, enlarged `scale` times
    /// (scale 1 = 8px tall, 2 = 16px). Returns the width drawn, in pixels.
    pub fn draw_text(&mut self, x: i32, y: i32, text: &str, color: u16, scale: i32) -> i32 {
        let mut cursor = x;
        for byte in text.bytes() {
            let index = byte.wrapping_sub(font::FIRST) as usize;
            let glyph = font::GLYPHS.get(index).unwrap_or(&font::GLYPHS[(b'?' - font::FIRST) as usize]);
            for (row, bits) in glyph.iter().enumerate() {
                for column in 0..8 {
                    if bits & (0x80 >> column) != 0 {
                        self.fill_rect(cursor + column * scale, y + row as i32 * scale, scale, scale, color);
                    }
                }
            }
            cursor += 8 * scale;
        }
        cursor - x
    }

    /// Width in pixels that `draw_text` would use, e.g. for centering.
    pub fn text_width(text: &str, scale: i32) -> i32 {
        text.len() as i32 * 8 * scale
    }

    /// Copy the canvas to the screen.
    pub fn present(&mut self) -> io::Result<()> {
        for row in 0..self.height {
            let source = &self.pixels[row * self.width..(row + 1) * self.width];
            let start = row * self.stride;
            let target = &mut self.bytes[start..start + self.width * self.bytes_per_pixel];
            if self.bytes_per_pixel == 2 {
                for (pixel, out) in source.iter().zip(target.chunks_exact_mut(2)) {
                    out.copy_from_slice(&pixel.to_le_bytes());
                }
            } else {
                for (pixel, out) in source.iter().zip(target.chunks_exact_mut(4)) {
                    out.copy_from_slice(&rgb565_to_xrgb8888(*pixel).to_le_bytes());
                }
            }
        }
        self.file.write_all_at(&self.bytes, 0)
    }
}
