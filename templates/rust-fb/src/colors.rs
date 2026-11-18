// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 1, color rendering: a spinning RGB triangle and an HSV color wheel, computed
//! pixel by pixel every frame.

use std::f32::consts::TAU;

use crate::display::{blend, rgb, Display};
use crate::input::{self, keys, Direction, KeyEvent};
use crate::ui::{self, Action};

const CENTER_X: f32 = 160.0;
const CENTER_Y: f32 = 86.0;
const RADIUS: f32 = 60.0;
const SPIN_PER_FRAME: f32 = 0.02; // radians
const TURN_STEP: f32 = 0.15; // radians per Z/C press

#[derive(Clone, Copy, PartialEq, Eq)]
enum Scene {
    Triangle,
    Wheel,
}

/// Hue (0..1, wrapping), saturation and value (0..1) to RGB565.
fn hsv(hue: f32, saturation: f32, value: f32) -> u16 {
    let sector = hue.rem_euclid(1.0) * 6.0;
    let fraction = sector - sector.floor();
    let (p, q, t) = (value * (1.0 - saturation), value * (1.0 - saturation * fraction), value * (1.0 - saturation * (1.0 - fraction)));
    let (red, green, blue) = match sector as u32 {
        0 => (value, t, p),
        1 => (q, value, p),
        2 => (p, value, t),
        3 => (p, q, value),
        4 => (t, p, value),
        _ => (value, p, q),
    };
    rgb((red * 255.0) as u8, (green * 255.0) as u8, (blue * 255.0) as u8)
}

/// Dark vertical gradient behind the demo.
fn draw_backdrop(display: &mut Display) {
    let width = display.width() as i32;
    let (top, bottom) = (rgb(22, 28, 36), rgb(6, 8, 11));
    for y in ui::HEADER_HEIGHT..display.height() as i32 {
        let alpha = ((y - ui::HEADER_HEIGHT) * 255 / (display.height() as i32 - ui::HEADER_HEIGHT)) as u8;
        display.fill_rect(0, y, width, 1, blend(top, bottom, alpha));
    }
}

/// Gouraud shading: each pixel mixes the corner colors red, green and blue by how close
/// it is to each corner (its barycentric weights), scaled so the brightest channel is full.
fn draw_triangle(display: &mut Display, angle: f32) {
    let corner = |index: usize| {
        let theta = angle + index as f32 * TAU / 3.0;
        (CENTER_X + RADIUS * theta.cos(), CENTER_Y + RADIUS * theta.sin())
    };
    let [(ax, ay), (bx, by), (cx, cy)] = [corner(0), corner(1), corner(2)];
    let area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    let (left, right) = (ax.min(bx).min(cx).floor() as i32, ax.max(bx).max(cx).ceil() as i32);
    let (top, bottom) = (ay.min(by).min(cy).floor() as i32, ay.max(by).max(cy).ceil() as i32);
    for y in top..=bottom {
        for x in left..=right {
            let (px, py) = (x as f32 + 0.5, y as f32 + 0.5);
            let red = ((cx - bx) * (py - by) - (cy - by) * (px - bx)) / area;
            let green = ((ax - cx) * (py - cy) - (ay - cy) * (px - cx)) / area;
            let blue = 1.0 - red - green;
            if red < 0.0 || green < 0.0 || blue < 0.0 {
                continue;
            }
            let brightest = red.max(green).max(blue);
            let channel = |weight: f32| (weight / brightest * 255.0) as u8;
            display.set_pixel(x, y, rgb(channel(red), channel(green), channel(blue)));
        }
    }
}

/// Hue around the circle, saturation from the center out.
fn draw_wheel(display: &mut Display, angle: f32) {
    let radius = RADIUS as i32;
    for dy in -radius..=radius {
        for dx in -radius..=radius {
            let distance = ((dx * dx + dy * dy) as f32).sqrt();
            if distance > RADIUS {
                continue;
            }
            let hue = ((dy as f32).atan2(dx as f32) + angle) / TAU;
            display.set_pixel(CENTER_X as i32 + dx, CENTER_Y as i32 + dy, hsv(hue, distance / RADIUS, 1.0));
        }
    }
}

pub struct Colors {
    scene: Scene,
    angle: f32,
    spinning: bool,
}

impl Colors {
    pub fn new() -> Colors {
        Colors { scene: Scene::Triangle, angle: 0.0, spinning: true }
    }

    /// True while the picture changes on its own, so it needs drawing every frame.
    pub fn animated(&self) -> bool {
        self.spinning
    }

    pub fn tick(&mut self) {
        if self.spinning {
            self.angle = (self.angle + SPIN_PER_FRAME) % TAU;
        }
    }

    pub fn handle_key(&mut self, event: KeyEvent) -> Action {
        if !event.is_down() {
            return Action::Stay;
        }
        match (input::direction(event.code), event.code) {
            (Some(Direction::Left), _) => self.angle -= TURN_STEP,
            (Some(Direction::Right), _) => self.angle += TURN_STEP,
            (None, keys::ENTER) => {
                self.scene = if self.scene == Scene::Triangle { Scene::Wheel } else { Scene::Triangle };
            }
            (None, keys::SPACE) => self.spinning = !self.spinning,
            (None, keys::TAB) => return Action::Next,
            (None, keys::ESC) => return Action::Home,
            _ => {}
        }
        Action::Stay
    }

    pub fn draw(&self, display: &mut Display) {
        draw_backdrop(display);
        match self.scene {
            Scene::Triangle => draw_triangle(display, self.angle),
            Scene::Wheel => draw_wheel(display, self.angle),
        }
        let title = if self.scene == Scene::Triangle { "Colors: triangle" } else { "Colors: wheel" };
        ui::draw_header(display, title);
        ui::draw_hint(display, "Z/C turn  SPACE pause  ENTER switch");
    }
}
