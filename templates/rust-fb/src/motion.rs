// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 2, interactive rendering: push a glowing ball around. It keeps its momentum,
//! leaves a trail and throws sparks when it bounces off the walls.

use std::collections::VecDeque;

use crate::display::{rgb, Display, WHITE};
use crate::input::{self, keys, Direction, KeyEvent};
use crate::ui::{self, Action, BACKGROUND, LANGUAGE_COLOR};

const RADIUS: f32 = 9.0;
const PUSH: f32 = 1.2; // speed added per key press, pixels per frame
const FRICTION: f32 = 0.99; // speed kept each frame
const BOUNCE: f32 = 0.85; // speed kept when bouncing
const TRAIL_LENGTH: usize = 14;
const SPARKS_PER_BOUNCE: usize = 10;
const SPARK_LIFE: u32 = 30; // frames
const GRID: u16 = rgb(36, 44, 54);
const COLORS: [u16; 4] = [LANGUAGE_COLOR, rgb(79, 195, 247), rgb(129, 199, 132), rgb(240, 98, 146)];

// The area the ball moves in: below the header, above the hint line.
const LEFT: f32 = 0.0;
const RIGHT: f32 = 320.0;
const TOP: f32 = ui::HEADER_HEIGHT as f32;
const BOTTOM: f32 = (ui::HINT_TOP - 2) as f32;

struct Spark {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: u32,
}

/// A small pseudo-random generator (xorshift), so the sparks need no dependencies.
struct Random(u32);

impl Random {
    /// A number from -1 to 1.
    fn next_signed(&mut self) -> f32 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 17;
        self.0 ^= self.0 << 5;
        (self.0 % 2001) as f32 / 1000.0 - 1.0
    }
}

pub struct Motion {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    trail: VecDeque<(f32, f32)>,
    sparks: Vec<Spark>,
    color: usize,
    random: Random,
}

impl Motion {
    pub fn new() -> Motion {
        Motion {
            x: (LEFT + RIGHT) / 2.0,
            y: (TOP + BOTTOM) / 2.0,
            vx: 0.0,
            vy: 0.0,
            trail: VecDeque::new(),
            sparks: Vec::new(),
            color: 0,
            random: Random(0x2545_F491),
        }
    }

    fn burst(&mut self, x: f32, y: f32) {
        for _ in 0..SPARKS_PER_BOUNCE {
            let (vx, vy) = (self.random.next_signed() * 2.5, self.random.next_signed() * 2.5 - 1.0);
            self.sparks.push(Spark { x, y, vx, vy, life: SPARK_LIFE });
        }
    }

    /// Advance one frame: move, bounce, age the trail and the sparks.
    pub fn tick(&mut self) {
        self.x += self.vx;
        self.y += self.vy;
        self.vx *= FRICTION;
        self.vy *= FRICTION;
        if self.x < LEFT + RADIUS || self.x > RIGHT - RADIUS {
            self.x = self.x.clamp(LEFT + RADIUS, RIGHT - RADIUS);
            self.vx = -self.vx * BOUNCE;
            if self.vx.abs() > 0.6 {
                let edge = if self.vx > 0.0 { self.x - RADIUS } else { self.x + RADIUS };
                self.burst(edge, self.y);
            }
        }
        if self.y < TOP + RADIUS || self.y > BOTTOM - RADIUS {
            self.y = self.y.clamp(TOP + RADIUS, BOTTOM - RADIUS);
            self.vy = -self.vy * BOUNCE;
            if self.vy.abs() > 0.6 {
                let edge = if self.vy > 0.0 { self.y - RADIUS } else { self.y + RADIUS };
                self.burst(self.x, edge);
            }
        }
        self.trail.push_front((self.x, self.y));
        self.trail.truncate(TRAIL_LENGTH);
        for spark in &mut self.sparks {
            spark.x += spark.vx;
            spark.y += spark.vy;
            spark.vy += 0.08; // gravity
            spark.life -= 1;
        }
        self.sparks.retain(|spark| spark.life > 0);
    }

    pub fn handle_key(&mut self, event: KeyEvent) -> Action {
        if !event.is_down() {
            return Action::Stay;
        }
        match (input::direction(event.code), event.code) {
            (Some(Direction::Left), _) => self.vx -= PUSH,
            (Some(Direction::Right), _) => self.vx += PUSH,
            (Some(Direction::Up), _) => self.vy -= PUSH,
            (Some(Direction::Down), _) => self.vy += PUSH,
            (None, keys::ENTER) => self.color = (self.color + 1) % COLORS.len(),
            (None, keys::SPACE) => (self.vx, self.vy) = (0.0, 0.0),
            (None, keys::TAB) => return Action::Next,
            (None, keys::ESC) => return Action::Home,
            _ => {}
        }
        Action::Stay
    }

    pub fn draw(&self, display: &mut Display) {
        let color = COLORS[self.color];
        display.clear(BACKGROUND);
        for y in (TOP as i32 + 8..BOTTOM as i32).step_by(16) {
            for x in (8..RIGHT as i32).step_by(16) {
                display.set_pixel(x, y, GRID);
            }
        }
        // Oldest trail first, so newer, brighter circles land on top.
        let length = self.trail.len() as f32;
        for (age, (x, y)) in self.trail.iter().enumerate().rev() {
            let fade = 1.0 - age as f32 / length;
            display.fill_circle(*x as i32, *y as i32, (RADIUS * (0.3 + 0.6 * fade)) as i32, color, (90.0 * fade) as u8);
        }
        for spark in &self.sparks {
            let alpha = (spark.life * 255 / SPARK_LIFE) as u8;
            display.fill_circle(spark.x as i32, spark.y as i32, 1, color, alpha);
        }
        let (x, y, radius) = (self.x as i32, self.y as i32, RADIUS as i32);
        display.fill_circle(x, y, radius + 6, color, 35); // glow
        display.fill_circle(x, y, radius + 3, color, 70);
        display.fill_circle(x, y, radius, color, 255);
        display.fill_circle(x - 3, y - 3, 3, WHITE, 140); // highlight
        ui::draw_header(display, "Motion");
        ui::draw_hint(display, "F/X/Z/C push  ENTER color  SPACE stop");
    }
}
