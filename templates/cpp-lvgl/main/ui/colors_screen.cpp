/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "colors_screen.hpp"

#include "input_keys.h"

#include <algorithm>
#include <cmath>

namespace app {

namespace {

constexpr float kTau = 6.28318530718f;
constexpr float kCenterX = 160.0f;
// Content coordinates, between the "TAB next  ESC home" line (top 18 px) and
// the hint line, so neither covers the picture.
constexpr float kCenterY = 72.0f;
constexpr float kRadius = 54.0f;
constexpr float kSpinPerFrame = 0.02f;  // radians
constexpr float kTurnStep = 0.15f;      // radians per Z/C press

uint16_t rgb(float red, float green, float blue)
{
    const auto channel = [](float value) { return static_cast<uint32_t>(static_cast<uint8_t>(value)); };
    return rgb565(channel(red) << 16 | channel(green) << 8 | channel(blue));
}

// Hue (0..1, wrapping), saturation and value (0..1) to RGB565.
uint16_t hsv(float hue, float saturation, float value)
{
    const float sector = (hue - std::floor(hue)) * 6.0f;
    const float fraction = sector - std::floor(sector);
    const float p = value * (1.0f - saturation);
    const float q = value * (1.0f - saturation * fraction);
    const float t = value * (1.0f - saturation * (1.0f - fraction));
    switch (static_cast<unsigned>(sector)) {
    case 0: return rgb(value * 255, t * 255, p * 255);
    case 1: return rgb(q * 255, value * 255, p * 255);
    case 2: return rgb(p * 255, value * 255, t * 255);
    case 3: return rgb(p * 255, q * 255, value * 255);
    case 4: return rgb(t * 255, p * 255, value * 255);
    default: return rgb(value * 255, p * 255, q * 255);
    }
}

// Gouraud shading: each pixel mixes the corner colors red, green and blue by how
// close it is to each corner (its barycentric weights), scaled so the brightest
// channel is full.
void draw_triangle(PixelCanvas &canvas, float angle)
{
    float xs[3];
    float ys[3];
    for (int index = 0; index < 3; ++index) {
        const float theta = angle + static_cast<float>(index) * kTau / 3.0f;
        xs[index] = kCenterX + kRadius * std::cos(theta);
        ys[index] = kCenterY + kRadius * std::sin(theta);
    }
    const float ax = xs[0], ay = ys[0], bx = xs[1], by = ys[1], cx = xs[2], cy = ys[2];
    const float area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    const int left = static_cast<int>(std::floor(std::min({ax, bx, cx})));
    const int right = static_cast<int>(std::ceil(std::max({ax, bx, cx})));
    const int top = static_cast<int>(std::floor(std::min({ay, by, cy})));
    const int bottom = static_cast<int>(std::ceil(std::max({ay, by, cy})));
    for (int y = top; y <= bottom; ++y) {
        for (int x = left; x <= right; ++x) {
            const float px = static_cast<float>(x) + 0.5f;
            const float py = static_cast<float>(y) + 0.5f;
            const float red = ((cx - bx) * (py - by) - (cy - by) * (px - bx)) / area;
            const float green = ((ax - cx) * (py - cy) - (ay - cy) * (px - cx)) / area;
            const float blue = 1.0f - red - green;
            if (red < 0.0f || green < 0.0f || blue < 0.0f) continue;
            const float brightest = std::max({red, green, blue});
            canvas.set_pixel(x, y, rgb(red / brightest * 255.0f, green / brightest * 255.0f,
                                       blue / brightest * 255.0f));
        }
    }
}

// Hue around the circle, saturation from the center out.
void draw_wheel(PixelCanvas &canvas, float angle)
{
    const int radius = static_cast<int>(kRadius);
    for (int dy = -radius; dy <= radius; ++dy) {
        for (int dx = -radius; dx <= radius; ++dx) {
            const float distance = std::sqrt(static_cast<float>(dx * dx + dy * dy));
            if (distance > kRadius) continue;
            const float hue = (std::atan2(static_cast<float>(dy), static_cast<float>(dx)) + angle) / kTau;
            canvas.set_pixel(static_cast<int>(kCenterX) + dx, static_cast<int>(kCenterY) + dy,
                             hsv(hue, distance / kRadius, 1.0f));
        }
    }
}

} // namespace

void ColorsScreen::draw()
{
    for (int y = 0; y < kContentHeight; ++y) canvas_.fill_rect(0, y, kContentWidth, 1, backdrop_[y]);
    if (scene_ == Scene::Triangle) draw_triangle(canvas_, angle_);
    else draw_wheel(canvas_, angle_);
    canvas_.present();
}

ColorsScreen::ColorsScreen(lv_obj_t *parent) : Screen(parent), canvas_(root(), kContentWidth, kContentHeight)
{
    // Dark vertical gradient behind the picture, worked out once.
    for (int y = 0; y < kContentHeight; ++y)
        backdrop_[y] = blend565(rgb565(0x161C24), rgb565(0x06080B), static_cast<uint8_t>(y * 255 / kContentHeight));

    // Widgets created after the canvas are drawn on top of it.
    make_demo_keys(root());
    make_hint(root(), "Z/C turn  SPACE pause  ENTER switch");
    animate();
    draw();
}

std::string ColorsScreen::title() const
{
    return scene_ == Scene::Triangle ? "Colors: triangle" : "Colors: wheel";
}

void ColorsScreen::on_show()
{
    draw();
}

void ColorsScreen::on_frame()
{
    if (!spinning_) return;
    angle_ = std::fmod(angle_ + kSpinPerFrame, kTau);
    draw();
}

Action ColorsScreen::handle_key(const key_item &key)
{
    switch (direction(key.key_code)) {
    case Direction::Left: angle_ -= kTurnStep; break;
    case Direction::Right: angle_ += kTurnStep; break;
    case Direction::Up:
    case Direction::Down: break;
    case Direction::None:
        switch (key.key_code) {
        case KEY_ENTER: scene_ = scene_ == Scene::Triangle ? Scene::Wheel : Scene::Triangle; break;
        case KEY_SPACE: spinning_ = !spinning_; break;
        case KEY_TAB: return Action::next();
        case KEY_ESC: return Action::home();
        default: break;
        }
        break;
    }
    draw();
    return Action::stay();
}

} // namespace app
