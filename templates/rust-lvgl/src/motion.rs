// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 2, interactive rendering: push a glowing ball around. It keeps its
//! momentum, leaves a trail and throws sparks when it bounces off the walls. A
//! readout shows its physics live: speed, direction, velocity, kinetic energy,
//! wall hits and a speed graph.

use std::cell::RefCell;
use std::collections::VecDeque;

use crate::canvas::{rgb565, PixelCanvas};
use crate::lvgl::{keys, Font, Key, Label, Obj};
use crate::ui::{
    direction, keep, make_demo_keys, make_hint, make_label, Action, Direction, Screen, ScreenBase, BACKGROUND_COLOR,
    CONTENT_HEIGHT, CONTENT_WIDTH, HINT_TOP, LANGUAGE_COLOR, TEXT_COLOR,
};

const RADIUS: f32 = 9.0;
const PUSH: f32 = 1.2; // speed added per key press, pixels per frame
const FRICTION: f32 = 0.99; // speed kept each frame
const BOUNCE: f32 = 0.85; // speed kept when bouncing
const TRAIL_LENGTH: usize = 14;
const SPARKS_PER_BOUNCE: usize = 10;
const SPARK_LIFE: u32 = 30; // frames
const GRID: u16 = rgb565(0x242C36);
const WHITE: u16 = rgb565(0xFFFFFF);
const MASS: f32 = 1.0; // for the kinetic energy readout
const ARROW_SCALE: f32 = 8.0; // velocity arrow length per pixel/frame of speed
const GRAPH_SAMPLES: usize = 96; // one speed sample per frame; also the graph's width in pixels
const GRAPH_HEIGHT: i32 = 36;
const GRAPH_MAX_SPEED: f32 = 10.0; // pixels/frame at the top of the graph
const READOUT_WIDTH: i32 = 172;
const READOUT_LINES: i32 = 3;
const LINE_HEIGHT: i32 = 16; // Font::montserrat_14
const COLORS: [u16; 4] = [rgb565(LANGUAGE_COLOR), rgb565(0x4FC3F7), rgb565(0x81C784), rgb565(0xF06292)];

// The area the ball moves in: between the key line at the top and the hint line.
const LEFT: f32 = 0.0;
const RIGHT: f32 = CONTENT_WIDTH as f32;
const TOP: f32 = 18.0; // below the "TAB next  ESC home" line
const BOTTOM: f32 = (HINT_TOP - 2) as f32;

#[derive(Clone, Copy)]
struct Point {
    x: f32,
    y: f32,
}

struct Spark {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: u32,
}

/// Everything that moves; the screen draws it.
struct Ball {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    trail: VecDeque<Point>,
    sparks: Vec<Spark>,
    color: usize,
    random: u32, // xorshift state, so the sparks need no dependencies
    hits: u32,
    speeds: VecDeque<f32>, // newest first
}

impl Ball {
    fn new() -> Ball {
        Ball {
            x: (LEFT + RIGHT) / 2.0,
            y: (TOP + BOTTOM) / 2.0,
            vx: 0.0,
            vy: 0.0,
            trail: VecDeque::new(),
            sparks: Vec::new(),
            color: 0,
            random: 0x2545F491,
            hits: 0,
            speeds: VecDeque::new(),
        }
    }

    /// A number from -1 to 1 (xorshift).
    fn next_random(&mut self) -> f32 {
        self.random ^= self.random << 13;
        self.random ^= self.random >> 17;
        self.random ^= self.random << 5;
        (self.random % 2001) as f32 / 1000.0 - 1.0
    }

    fn speed(&self) -> f32 {
        (self.vx * self.vx + self.vy * self.vy).sqrt()
    }

    /// A wall hit: count it and throw sparks from the contact point.
    fn burst(&mut self, x: f32, y: f32) {
        self.hits += 1;
        for _ in 0..SPARKS_PER_BOUNCE {
            let vx = self.next_random() * 2.5;
            let vy = self.next_random() * 2.5 - 1.0;
            self.sparks.push(Spark { x, y, vx, vy, life: SPARK_LIFE });
        }
    }

    /// Advance one frame: move, bounce, age the trail and the sparks.
    fn tick(&mut self) {
        self.x += self.vx;
        self.y += self.vy;
        self.vx *= FRICTION;
        self.vy *= FRICTION;
        if self.x < LEFT + RADIUS || self.x > RIGHT - RADIUS {
            self.x = self.x.clamp(LEFT + RADIUS, RIGHT - RADIUS);
            self.vx = -self.vx * BOUNCE;
            if self.vx.abs() > 0.6 {
                let contact = if self.vx > 0.0 { self.x - RADIUS } else { self.x + RADIUS };
                self.burst(contact, self.y);
            }
        }
        if self.y < TOP + RADIUS || self.y > BOTTOM - RADIUS {
            self.y = self.y.clamp(TOP + RADIUS, BOTTOM - RADIUS);
            self.vy = -self.vy * BOUNCE;
            if self.vy.abs() > 0.6 {
                let contact = if self.vy > 0.0 { self.y - RADIUS } else { self.y + RADIUS };
                self.burst(self.x, contact);
            }
        }
        self.trail.push_front(Point { x: self.x, y: self.y });
        self.trail.truncate(TRAIL_LENGTH);
        self.speeds.push_front(self.speed());
        self.speeds.truncate(GRAPH_SAMPLES);
        for spark in &mut self.sparks {
            spark.x += spark.vx;
            spark.y += spark.vy;
            spark.vy += 0.08; // gravity
            spark.life -= 1;
        }
        self.sparks.retain(|spark| spark.life > 0);
    }
}

pub struct MotionScreen {
    base: ScreenBase,
    canvas: PixelCanvas,
    readout: Label,
    ball: RefCell<Ball>,
}

impl MotionScreen {
    /// Numbers about the ball's motion, top left: a shaded panel on the canvas, text in a label.
    fn draw_readout(&self, ball: &Ball) {
        let speed = ball.speed();
        // Screen y grows downwards; flip it so 90 degrees points up, as in math.
        let mut degrees = (-ball.vy).atan2(ball.vx).to_degrees() % 360.0;
        if degrees < 0.0 {
            degrees += 360.0;
        }
        let direction = degrees.round() as i32 % 360;
        let energy = 0.5 * MASS * speed * speed;
        self.readout.set_text(&format!(
            "speed {speed:.2}  dir {direction}\nvx {:+.2}  vy {:+.2}\nenergy {energy:.2}  hits {}",
            ball.vx, ball.vy, ball.hits
        ));
        self.canvas.shade_rect(0, TOP as i32 + 2, READOUT_WIDTH, READOUT_LINES * LINE_HEIGHT + 4, 150);
    }

    /// Speed over the last GRAPH_SAMPLES frames, top right, newest on the right.
    fn draw_graph(&self, ball: &Ball, color: u16) {
        let samples = GRAPH_SAMPLES as i32;
        let left = RIGHT as i32 - samples - 4;
        let top = TOP as i32 + 2;
        let bottom = top + GRAPH_HEIGHT - 1;
        self.canvas.shade_rect(left - 2, top, samples + 4, GRAPH_HEIGHT + 2, 150);
        let height_of = |value: f32| ((value / GRAPH_MAX_SPEED).min(1.0) * (GRAPH_HEIGHT - 2) as f32) as i32;
        for age in 1..ball.speeds.len() {
            let x = left + samples - 1 - age as i32;
            let newer = bottom - height_of(ball.speeds[age - 1]);
            self.canvas.draw_line(x + 1, newer, x, bottom - height_of(ball.speeds[age]), color);
        }
    }

    fn draw(&self) {
        let ball = self.ball.borrow();
        let canvas = &self.canvas;
        let color = COLORS[ball.color];
        canvas.clear(rgb565(BACKGROUND_COLOR));
        for y in (TOP as i32 + 8..BOTTOM as i32).step_by(16) {
            for x in (8..RIGHT as i32).step_by(16) {
                canvas.set_pixel(x, y, GRID);
            }
        }
        // Oldest trail first, so newer, brighter circles land on top.
        let length = ball.trail.len() as f32;
        for (age, point) in ball.trail.iter().enumerate().rev() {
            let fade = 1.0 - age as f32 / length;
            let radius = (RADIUS * (0.3 + 0.6 * fade)) as i32;
            canvas.fill_circle(point.x as i32, point.y as i32, radius, color, (90.0 * fade) as u8);
        }
        for spark in &ball.sparks {
            canvas.fill_circle(spark.x as i32, spark.y as i32, 1, color, (spark.life * 255 / SPARK_LIFE) as u8);
        }
        let (x, y, radius) = (ball.x as i32, ball.y as i32, RADIUS as i32);
        canvas.fill_circle(x, y, radius + 6, color, 35); // glow
        canvas.fill_circle(x, y, radius + 3, color, 70);
        canvas.fill_circle(x, y, radius, color, 255);
        canvas.fill_circle(x - 3, y - 3, 3, WHITE, 140); // highlight
        if ball.speed() > 0.05 {
            // Velocity arrow: where the ball is heading, and how fast.
            let tip_x = (ball.x + ball.vx * ARROW_SCALE) as i32;
            let tip_y = (ball.y + ball.vy * ARROW_SCALE) as i32;
            canvas.draw_line(x, y, tip_x, tip_y, WHITE);
            canvas.fill_circle(tip_x, tip_y, 2, WHITE, 255);
        }
        self.draw_readout(&ball);
        self.draw_graph(&ball, color);
        canvas.present();
    }

    pub fn new(parent: Obj) -> &'static MotionScreen {
        let base = ScreenBase::new(parent);
        let canvas = PixelCanvas::new(base.root(), CONTENT_WIDTH, CONTENT_HEIGHT);
        // Widgets created after the canvas are drawn on top of it.
        let readout = make_label(base.root(), "", Font::montserrat_14(), TEXT_COLOR);
        readout.set_pos(4, TOP as i32 + 4);
        make_demo_keys(base.root());
        make_hint(base.root(), "F/X/Z/C push  ENTER color  SPACE stop");
        let screen = keep(MotionScreen { base, canvas, readout, ball: RefCell::new(Ball::new()) });
        screen.base.animate(screen);
        screen
    }
}

impl Screen for MotionScreen {
    fn base(&self) -> &ScreenBase {
        &self.base
    }

    fn title(&self) -> String {
        "Motion".to_string()
    }

    fn on_frame(&self) {
        self.ball.borrow_mut().tick();
        self.draw();
    }

    fn handle_key(&self, key: &Key) -> Action {
        let mut ball = self.ball.borrow_mut();
        match direction(key.code) {
            Some(Direction::Left) => ball.vx -= PUSH,
            Some(Direction::Right) => ball.vx += PUSH,
            Some(Direction::Up) => ball.vy -= PUSH,
            Some(Direction::Down) => ball.vy += PUSH,
            None => match key.code {
                keys::ENTER => ball.color = (ball.color + 1) % COLORS.len(),
                keys::SPACE => (ball.vx, ball.vy) = (0.0, 0.0),
                keys::TAB => return Action::Next,
                keys::ESC => return Action::Home,
                _ => {}
            },
        }
        Action::Stay
    }
}
