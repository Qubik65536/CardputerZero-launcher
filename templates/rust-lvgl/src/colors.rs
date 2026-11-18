// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 1, color rendering: a spinning RGB triangle and an HSV color wheel,
//! computed pixel by pixel every frame into an LVGL canvas.

use std::cell::Cell;
use std::f32::consts::TAU;

use crate::canvas::{blend565, rgb565, PixelCanvas};
use crate::lvgl::{keys, Key, Obj};
use crate::ui::{
    direction, keep, make_demo_keys, make_hint, Action, Direction, Screen, ScreenBase, CONTENT_HEIGHT, CONTENT_WIDTH,
};

const CENTER_X: f32 = 160.0;
// Content coordinates, between the "TAB next  ESC home" line (top 18 px) and
// the hint line, so neither covers the picture.
const CENTER_Y: f32 = 72.0;
const RADIUS: f32 = 54.0;
const SPIN_PER_FRAME: f32 = 0.02; // radians
const TURN_STEP: f32 = 0.15; // radians per Z/C press

fn rgb(red: f32, green: f32, blue: f32) -> u16 {
    // `as u8` saturates: values past 255 stay 255.
    let channel = |value: f32| u32::from(value as u8);
    rgb565(channel(red) << 16 | channel(green) << 8 | channel(blue))
}

/// Hue (0..1, wrapping), saturation and value (0..1) to RGB565.
fn hsv(hue: f32, saturation: f32, value: f32) -> u16 {
    let sector = (hue - hue.floor()) * 6.0;
    let fraction = sector - sector.floor();
    let p = value * (1.0 - saturation);
    let q = value * (1.0 - saturation * fraction);
    let t = value * (1.0 - saturation * (1.0 - fraction));
    match sector as u32 {
        0 => rgb(value * 255.0, t * 255.0, p * 255.0),
        1 => rgb(q * 255.0, value * 255.0, p * 255.0),
        2 => rgb(p * 255.0, value * 255.0, t * 255.0),
        3 => rgb(p * 255.0, q * 255.0, value * 255.0),
        4 => rgb(t * 255.0, p * 255.0, value * 255.0),
        _ => rgb(value * 255.0, p * 255.0, q * 255.0),
    }
}

/// Gouraud shading: each pixel mixes the corner colors red, green and blue by
/// how close it is to each corner (its barycentric weights), scaled so the
/// brightest channel is full.
fn draw_triangle(canvas: &PixelCanvas, angle: f32) {
    let corner = |index: usize| {
        let theta = angle + index as f32 * TAU / 3.0;
        (CENTER_X + RADIUS * theta.cos(), CENTER_Y + RADIUS * theta.sin())
    };
    let ((ax, ay), (bx, by), (cx, cy)) = (corner(0), corner(1), corner(2));
    let area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    let left = ax.min(bx).min(cx).floor() as i32;
    let right = ax.max(bx).max(cx).ceil() as i32;
    let top = ay.min(by).min(cy).floor() as i32;
    let bottom = ay.max(by).max(cy).ceil() as i32;
    for y in top..=bottom {
        for x in left..=right {
            let px = x as f32 + 0.5;
            let py = y as f32 + 0.5;
            let red = ((cx - bx) * (py - by) - (cy - by) * (px - bx)) / area;
            let green = ((ax - cx) * (py - cy) - (ay - cy) * (px - cx)) / area;
            let blue = 1.0 - red - green;
            if red < 0.0 || green < 0.0 || blue < 0.0 {
                continue;
            }
            let brightest = red.max(green).max(blue);
            canvas.set_pixel(x, y, rgb(red / brightest * 255.0, green / brightest * 255.0, blue / brightest * 255.0));
        }
    }
}

/// Hue around the circle, saturation from the center out.
fn draw_wheel(canvas: &PixelCanvas, angle: f32) {
    let radius = RADIUS as i32;
    for dy in -radius..=radius {
        for dx in -radius..=radius {
            let distance = ((dx * dx + dy * dy) as f32).sqrt();
            if distance > RADIUS {
                continue;
            }
            let hue = ((dy as f32).atan2(dx as f32) + angle) / TAU;
            canvas.set_pixel(CENTER_X as i32 + dx, CENTER_Y as i32 + dy, hsv(hue, distance / RADIUS, 1.0));
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Scene {
    Triangle,
    Wheel,
}

pub struct ColorsScreen {
    base: ScreenBase,
    canvas: PixelCanvas,
    backdrop: Vec<u16>, // one color per row
    scene: Cell<Scene>,
    angle: Cell<f32>,
    spinning: Cell<bool>,
}

impl ColorsScreen {
    fn draw(&self) {
        for (y, color) in self.backdrop.iter().enumerate() {
            self.canvas.fill_rect(0, y as i32, CONTENT_WIDTH, 1, *color);
        }
        match self.scene.get() {
            Scene::Triangle => draw_triangle(&self.canvas, self.angle.get()),
            Scene::Wheel => draw_wheel(&self.canvas, self.angle.get()),
        }
        self.canvas.present();
    }

    pub fn new(parent: Obj) -> &'static ColorsScreen {
        let base = ScreenBase::new(parent);
        let canvas = PixelCanvas::new(base.root(), CONTENT_WIDTH, CONTENT_HEIGHT);
        // Dark vertical gradient behind the picture, worked out once.
        let backdrop = (0..CONTENT_HEIGHT)
            .map(|y| blend565(rgb565(0x161C24), rgb565(0x06080B), (y * 255 / CONTENT_HEIGHT) as u8))
            .collect();

        // Widgets created after the canvas are drawn on top of it.
        make_demo_keys(base.root());
        make_hint(base.root(), "Z/C turn  SPACE pause  ENTER switch");
        let screen = keep(ColorsScreen {
            base,
            canvas,
            backdrop,
            scene: Cell::new(Scene::Triangle),
            angle: Cell::new(0.0),
            spinning: Cell::new(true),
        });
        screen.base.animate(screen);
        screen.draw();
        screen
    }
}

impl Screen for ColorsScreen {
    fn base(&self) -> &ScreenBase {
        &self.base
    }

    fn title(&self) -> String {
        match self.scene.get() {
            Scene::Triangle => "Colors: triangle",
            Scene::Wheel => "Colors: wheel",
        }
        .to_string()
    }

    fn on_show(&self) {
        self.draw();
    }

    fn on_frame(&self) {
        if !self.spinning.get() {
            return;
        }
        self.angle.set((self.angle.get() + SPIN_PER_FRAME) % TAU);
        self.draw();
    }

    fn handle_key(&self, key: &Key) -> Action {
        match direction(key.code) {
            Some(Direction::Left) => self.angle.set(self.angle.get() - TURN_STEP),
            Some(Direction::Right) => self.angle.set(self.angle.get() + TURN_STEP),
            Some(Direction::Up | Direction::Down) => {}
            None => match key.code {
                keys::ENTER => self.scene.set(match self.scene.get() {
                    Scene::Triangle => Scene::Wheel,
                    Scene::Wheel => Scene::Triangle,
                }),
                keys::SPACE => self.spinning.set(!self.spinning.get()),
                keys::TAB => return Action::Next,
                keys::ESC => return Action::Home,
                _ => {}
            },
        }
        self.draw();
        Action::Stay
    }
}
